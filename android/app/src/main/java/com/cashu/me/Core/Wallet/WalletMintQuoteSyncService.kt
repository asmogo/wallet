package com.cashu.me.Core

import com.cashu.me.Core.CDK.CdkWalletGateway
import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.Models.MintQuoteRetryStatus
import com.cashu.me.Models.MintQuoteScheduleRecord
import com.cashu.me.Models.PaymentMethodKind
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal data class MintQuoteSyncResult(
    val quote: MintQuoteInfo? = null,
    val newlyIssued: Long = 0,
    val hadOutstandingPayment: Boolean = false,
    val retryStatus: MintQuoteRetryStatus = MintQuoteRetryStatus(),
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
    issuedBeforeCheck: Long? = null,
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
    val verifiedAdvance = (issued - (issuedBeforeCheck ?: observed.amountIssued)).coerceAtLeast(0)
    return MintQuoteSyncResult(
        quote = quote,
        newlyIssued = maxOf(nonNegativeMinted, verifiedAdvance),
        hadOutstandingPayment = observed.amountPaid > observed.amountIssued,
    )
}

internal class WalletMintQuoteSyncService private constructor(
    private val checkQuote: suspend (String) -> MintQuoteInfo,
    private val storedQuote: suspend (String) -> MintQuoteInfo?,
    private val mintQuote: suspend (String) -> Long,
    private val quoteObserved: (String) -> Unit,
    private val loadSchedules: () -> Map<String, MintQuoteScheduleRecord>,
    private val saveSchedules: (Map<String, MintQuoteScheduleRecord>) -> Unit,
    private val nowEpochMillis: () -> Long,
    private val logFailure: (String, Throwable) -> Unit,
) {
    /**
     * One reconciliation lane covers foreground polling, receive screens, and
     * History refresh. Keeping check → mint → verify atomic at this layer avoids
     * duplicate issuance attempts and duplicate receipt events.
     */
    private val reconciliationMutex = Mutex()
    private val scheduleMonitor = Any()

    constructor(
        gateway: CdkWalletGateway,
        walletStore: WalletStore,
    ) : this(
        checkQuote = gateway::checkMintQuote,
        storedQuote = gateway::storedMintQuote,
        mintQuote = gateway::mintTokens,
        quoteObserved = { quoteId ->
            val current = walletStore.loadMintQuoteTimestamps()
            if (quoteId !in current) {
                walletStore.saveMintQuoteTimestamps(current + (quoteId to System.currentTimeMillis()))
            }
        },
        loadSchedules = walletStore::loadMintQuoteSchedules,
        saveSchedules = walletStore::saveMintQuoteSchedules,
        nowEpochMillis = System::currentTimeMillis,
        logFailure = { message, error -> AppLogger.wallet.error(message, error) },
    )

    /** Test seam for the counter state machine; production uses CDK above. */
    internal constructor(
        checkQuote: suspend (String) -> MintQuoteInfo,
        mintQuote: suspend (String) -> Long,
        storedQuote: suspend (String) -> MintQuoteInfo? = { null },
        loadSchedules: () -> Map<String, MintQuoteScheduleRecord> = { emptyMap() },
        saveSchedules: (Map<String, MintQuoteScheduleRecord>) -> Unit = {},
        nowEpochMillis: () -> Long = System::currentTimeMillis,
    ) : this(
        checkQuote = checkQuote,
        storedQuote = storedQuote,
        mintQuote = mintQuote,
        quoteObserved = {},
        loadSchedules = loadSchedules,
        saveSchedules = saveSchedules,
        nowEpochMillis = nowEpochMillis,
        logFailure = { _, _ -> },
    )

    /**
     * Select a fair, bounded slice for one sweep and reserve it before any
     * network suspension. Explicit refresh bypasses due times but remains
     * bounded so a large historical ledger cannot monopolize the wallet.
     */
    fun selectQuoteIdsForSync(
        quoteIds: Collection<String>,
        force: Boolean,
        unsettledOnchainQuoteIds: Set<String> = emptySet(),
    ): List<String> =
        synchronized(scheduleMonitor) {
            val selection = MintQuoteSchedulePolicy.select(
                quoteIds = quoteIds,
                existing = schedulesLocked(),
                nowEpochMillis = nowEpochMillis(),
                force = force,
                unsettledOnchainQuoteIds = unsettledOnchainQuoteIds,
            )
            persistSchedulesLocked(selection.records)
            selection.quoteIds
        }

    /** Rehydrate a paid-but-unissued status when its receive screen reopens. */
    fun retryStatus(quoteId: String): MintQuoteRetryStatus = synchronized(scheduleMonitor) {
        schedulesLocked()[quoteId]
            ?.let(MintQuoteSchedulePolicy::retryStatus)
            ?: MintQuoteRetryStatus()
    }

    fun shouldAttempt(quoteId: String, force: Boolean = false): Boolean = synchronized(scheduleMonitor) {
        MintQuoteSchedulePolicy.shouldAttempt(schedulesLocked()[quoteId], nowEpochMillis(), force)
    }

    /**
     * Check -> mint -> verify one persisted quote. The quote stays unresolved
     * when any paid amount remains, so the next foreground/startup pass retries
     * it. Reusable BOLT12 quotes can run through this method indefinitely.
     */
    suspend fun syncPendingMintQuote(quoteId: String, force: Boolean = false): MintQuoteSyncResult =
        reconciliationMutex.withLock {
            val cached = storedQuoteOrNull(quoteId)
            if (!shouldAttempt(quoteId, force)) {
                return@withLock MintQuoteSyncResult(quote = cached, retryStatus = retryStatus(quoteId))
            }
            val observed = try {
                checkQuote(quoteId).also { rememberMintQuoteTimestamp(it.id) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (!isMissingQuoteError(error)) {
                    logFailure("Failed to refresh pending quote $quoteId", error)
                }
                val local = storedQuoteOrNull(quoteId) ?: cached
                val retryStatus = recordFailure(quoteId, local)
                return@withLock MintQuoteSyncResult(
                    quote = local,
                    hadOutstandingPayment = local?.mintableAmount?.let { it > 0 } == true,
                    retryStatus = retryStatus,
                )
            }

            if (observed.mintableAmount == 0L) {
                recordObservation(observed)
                return@withLock reconciledMintQuoteResult(observed, issuedBeforeCheck = cached?.amountIssued)
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
            val result = reconciledMintQuoteResult(observed, mintedAmount, verified, cached?.amountIssued)

            if (result.remainingAmount > 0L) {
                val failure = mintError ?: IllegalStateException(
                    "Mint quote made no verified issuance progress.",
                )
                logFailure(
                    "Paid mint quote remains unissued: $quoteId remaining=${result.remainingAmount}",
                    failure,
                )
                return@withLock result.copy(retryStatus = recordFailure(quoteId, result.quote))
            }
            recordObservation(checkNotNull(result.quote))
            result
        }

    private suspend fun storedQuoteOrNull(quoteId: String): MintQuoteInfo? = try {
        storedQuote(quoteId)
    } catch (error: CancellationException) {
        throw error
    } catch (_: Throwable) {
        null
    }

    fun rememberMintQuoteTimestamp(quoteId: String) {
        quoteObserved(quoteId)
        synchronized(scheduleMonitor) {
            val schedules = schedulesLocked().toMutableMap()
            schedules.putIfAbsent(
                quoteId,
                MintQuoteScheduleRecord(firstObservedAtEpochMillis = nowEpochMillis()),
            )
            persistSchedulesLocked(schedules)
        }
    }

    private fun recordObservation(quote: MintQuoteInfo) {
        synchronized(scheduleMonitor) {
            val schedules = schedulesLocked().toMutableMap()
            schedules[quote.id] = MintQuoteSchedulePolicy.observed(
                previous = schedules[quote.id],
                quote = quote,
                nowEpochMillis = nowEpochMillis(),
            )
            persistSchedulesLocked(schedules)
        }
    }

    private fun recordFailure(quoteId: String, quote: MintQuoteInfo?): MintQuoteRetryStatus =
        synchronized(scheduleMonitor) {
            val schedules = schedulesLocked().toMutableMap()
            val record = MintQuoteSchedulePolicy.failed(
                previous = schedules[quoteId],
                nowEpochMillis = nowEpochMillis(),
                hadOutstandingPayment = quote?.mintableAmount?.let { it > 0 } == true,
                isReusable = quote?.paymentMethod == PaymentMethodKind.Bolt12,
            )
            schedules[quoteId] = record
            persistSchedulesLocked(schedules)
            MintQuoteSchedulePolicy.retryStatus(record)
        }

    // Always reload at the wallet boundary. Wallet replacement clears or
    // restores this store while the manager remains alive; retaining a process
    // cache here could otherwise resurrect retry metadata from the old wallet.
    private fun schedulesLocked(): Map<String, MintQuoteScheduleRecord> = loadSchedules()

    private fun persistSchedulesLocked(schedules: Map<String, MintQuoteScheduleRecord>) {
        saveSchedules(schedules)
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
