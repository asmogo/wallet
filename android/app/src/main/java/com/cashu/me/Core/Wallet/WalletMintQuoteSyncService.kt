package com.cashu.me.Core

import com.cashu.me.Core.CDK.CdkWalletGateway
import com.cashu.me.Models.MintQuoteInfo
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal data class MintQuoteSyncResult(
    val quote: MintQuoteInfo? = null,
    val newlyIssued: Long = 0,
    val hadOutstandingPayment: Boolean = false,
) {
    val minted: Boolean get() = newlyIssued > 0
    val receivedAmount: Long? get() = newlyIssued.takeIf { it > 0 }
    val unit: String get() = quote?.unit ?: "sat"
    val remainingAmount: Long get() = quote?.mintableAmount ?: 0
    val hasSettledPayment: Boolean get() = quote?.hasSettledPayment == true
}

/**
 * Merge a mint response and its verification check without ever moving either
 * NUT-25 counter backwards. A successful mint response is enough to infer a
 * local advance when the follow-up GET is temporarily unavailable; conversely,
 * a verified counter advance resolves a lost/ambiguous mint response.
 */
internal fun reconciledMintQuoteResult(
    observed: MintQuoteInfo,
    mintedAmount: Long = 0,
    verified: MintQuoteInfo? = null,
): MintQuoteSyncResult {
    val nonNegativeMinted = mintedAmount.coerceAtLeast(0)
    val inferredIssued = if (nonNegativeMinted > Long.MAX_VALUE - observed.amountIssued) {
        Long.MAX_VALUE
    } else {
        observed.amountIssued + nonNegativeMinted
    }
    val base = verified ?: observed
    val paid = maxOf(base.amountPaid, observed.amountPaid)
    val issued = maxOf(base.amountIssued, inferredIssued)
    val quote = base.copy(
        amountPaid = paid,
        amountIssued = issued,
        state = mintQuoteStateForDomain(base.paymentMethod, base.state, paid, issued),
    )
    val verifiedAdvance = (issued - observed.amountIssued).coerceAtLeast(0)
    return MintQuoteSyncResult(
        quote = quote,
        newlyIssued = maxOf(nonNegativeMinted, verifiedAdvance),
        hadOutstandingPayment = observed.amountPaid > observed.amountIssued,
    )
}

internal class WalletMintQuoteSyncService private constructor(
    private val checkQuote: suspend (String) -> MintQuoteInfo,
    private val mintQuote: suspend (String) -> Long,
    private val quoteObserved: (String) -> Unit,
    private val logFailure: (String, Throwable) -> Unit,
) {
    /**
     * One reconciliation lane covers foreground polling, receive screens, and
     * History refresh. Keeping check → mint → verify atomic at this layer avoids
     * duplicate issuance attempts and duplicate receipt events.
     */
    private val reconciliationMutex = Mutex()

    constructor(
        gateway: CdkWalletGateway,
        walletStore: WalletStore,
    ) : this(
        checkQuote = gateway::checkMintQuote,
        mintQuote = gateway::mintTokens,
        quoteObserved = { quoteId ->
            val current = walletStore.loadMintQuoteTimestamps()
            if (quoteId !in current) {
                walletStore.saveMintQuoteTimestamps(current + (quoteId to System.currentTimeMillis()))
            }
        },
        logFailure = { message, error -> AppLogger.wallet.error(message, error) },
    )

    /** Test seam for the counter state machine; production uses CDK above. */
    internal constructor(
        checkQuote: suspend (String) -> MintQuoteInfo,
        mintQuote: suspend (String) -> Long,
    ) : this(checkQuote, mintQuote, {}, { _, _ -> })

    /**
     * Check -> mint -> verify one persisted quote. The quote stays unresolved
     * when any paid amount remains, so the next foreground/startup pass retries
     * it. Reusable BOLT12 quotes can run through this method indefinitely.
     */
    suspend fun syncPendingMintQuote(quoteId: String): MintQuoteSyncResult =
        reconciliationMutex.withLock {
            val observed = try {
                checkQuote(quoteId).also { rememberMintQuoteTimestamp(it.id) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (!isMissingQuoteError(error)) {
                    logFailure("Failed to refresh pending quote $quoteId", error)
                }
                return@withLock MintQuoteSyncResult()
            }

            if (observed.mintableAmount == 0L) {
                return@withLock reconciledMintQuoteResult(observed)
            }

            var mintedAmount = 0L
            var mintError: Throwable? = null
            try {
                mintedAmount = mintQuote(quoteId)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                mintError = error
            }

            // Always ask again. If POST /mint succeeded but its response was
            // lost, amount_issued is the durable proof that issuance happened.
            val verified = try {
                checkQuote(quoteId).also { rememberMintQuoteTimestamp(it.id) }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                null
            }
            val result = reconciledMintQuoteResult(observed, mintedAmount, verified)

            if (result.remainingAmount > 0L && mintError != null) {
                logFailure(
                    "Paid mint quote remains unissued: $quoteId " +
                        "remaining=${result.remainingAmount}",
                    mintError,
                )
            }
            result
        }

    fun rememberMintQuoteTimestamp(quoteId: String) {
        quoteObserved(quoteId)
    }

    fun isAlreadyIssuedMintError(error: Throwable): Boolean {
        val message = "${error.message.orEmpty()} $error".lowercase()
        if (
            message.contains("already being minted") ||
            message.contains("not issued") ||
            message.contains("not yet") ||
            message.contains("unissued")
        ) {
            return false
        }
        return message.contains("already issued") ||
            message.contains("already minted") ||
            message.contains("quote is issued") ||
            message.contains("state=issued") ||
            message.contains("tokens already issued")
    }

    private fun isMissingQuoteError(error: Throwable): Boolean {
        val message = "${error.message.orEmpty()} $error".lowercase()
        return message.contains("not found") ||
            message.contains("no stored mint quote") ||
            message.contains("missing quote")
    }
}
