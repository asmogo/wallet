package com.cashu.me.Core

import java.util.concurrent.ConcurrentHashMap
import com.cashu.me.Core.CDK.CdkWalletGateway
import com.cashu.me.Models.MintQuoteState
import com.cashu.me.Models.PaymentMethodKind
import kotlinx.coroutines.CancellationException

internal data class MintQuoteSyncResult(
    val minted: Boolean,
    val receivedAmount: Long? = null,
    val unit: String = "sat",
)

internal class WalletMintQuoteSyncService(
    private val gateway: CdkWalletGateway,
    private val walletStore: WalletStore,
) {
    private val mintQuoteSyncsInFlight = mutableSetOf<String>()
    /** Session throttle state — reset on process death (cold start re-checks once). */
    private val checkThrottle = ConcurrentHashMap<String, MintQuoteCheckBackoff.Entry>()

    fun throttleEntry(quoteId: String): MintQuoteCheckBackoff.Entry? = checkThrottle[quoteId]

    /**
     * @param force skip exponential unpaid backoff (detail open / pull-to-refresh).
     * Still debounced briefly so rapid taps cannot spam the mint.
     */
    suspend fun syncPendingMintQuote(
        quoteId: String,
        allowPendingOnchainMintAttempt: Boolean,
        force: Boolean = false,
    ): MintQuoteSyncResult {
        val now = System.currentTimeMillis()
        val prior = checkThrottle[quoteId]
        if (!MintQuoteCheckBackoff.shouldCheck(prior, now, force)) return MintQuoteSyncResult(minted = false)

        if (!mintQuoteSyncsInFlight.add(quoteId)) return MintQuoteSyncResult(minted = false)
        return try {
            val updatedQuote = try {
                gateway.checkMintQuote(quoteId).also { rememberMintQuoteTimestamp(it.id) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                checkThrottle[quoteId] = MintQuoteCheckBackoff.afterUnpaidOrError(prior, now)
                if (!isMissingQuoteError(error)) {
                    AppLogger.wallet.error("Failed to refresh pending quote $quoteId", error)
                }
                return MintQuoteSyncResult(minted = false)
            }

            val shouldAttemptMint = updatedQuote.state == MintQuoteState.Paid ||
                updatedQuote.state == MintQuoteState.Issued ||
                (allowPendingOnchainMintAttempt && updatedQuote.paymentMethod == PaymentMethodKind.Onchain)
            if (!shouldAttemptMint) {
                checkThrottle[quoteId] = MintQuoteCheckBackoff.afterUnpaidOrError(prior, now)
                return MintQuoteSyncResult(minted = false)
            }

            if (updatedQuote.paymentMethod == PaymentMethodKind.Bolt12 &&
                updatedQuote.amountPaid > 0 &&
                updatedQuote.amountIssued >= updatedQuote.amountPaid
            ) {
                // Still fully caught up — treat as a quiet miss so passive
                // polling backs off instead of re-hitting every 30s.
                checkThrottle[quoteId] = MintQuoteCheckBackoff.afterUnpaidOrError(prior, now)
                return MintQuoteSyncResult(minted = false)
            }

            var receivedAmount: Long? = null
            val minted = try {
                receivedAmount = gateway.mintTokens(quoteId)
                true
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                when {
                    isAlreadyIssuedMintError(error) -> true
                    updatedQuote.paymentMethod == PaymentMethodKind.Onchain &&
                        updatedQuote.state == MintQuoteState.Pending -> {
                        false
                    }
                    else -> {
                        AppLogger.wallet.error("Failed to mint pending quote $quoteId", error)
                        false
                    }
                }
            }

            checkThrottle[quoteId] = if (minted) {
                MintQuoteCheckBackoff.afterMintedOrSettled(now)
            } else {
                MintQuoteCheckBackoff.afterUnpaidOrError(prior, now)
            }
            MintQuoteSyncResult(
                minted = minted,
                receivedAmount = receivedAmount?.takeIf { minted },
                unit = updatedQuote.unit,
            )
        } finally {
            mintQuoteSyncsInFlight.remove(quoteId)
        }
    }

    fun rememberMintQuoteTimestamp(quoteId: String) {
        val current = walletStore.loadMintQuoteTimestamps()
        if (quoteId !in current) {
            walletStore.saveMintQuoteTimestamps(current + (quoteId to System.currentTimeMillis()))
        }
    }

    fun isAlreadyIssuedMintError(error: Throwable): Boolean {
        val message = "${error.message.orEmpty()} ${error}".lowercase()
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
        val message = "${error.message.orEmpty()} ${error}".lowercase()
        return message.contains("not found") ||
            message.contains("no stored mint quote") ||
            message.contains("missing quote")
    }
}
