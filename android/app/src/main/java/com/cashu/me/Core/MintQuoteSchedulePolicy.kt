package com.cashu.me.Core

import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.Models.MintQuoteRetryState
import com.cashu.me.Models.MintQuoteRetryStatus
import com.cashu.me.Models.MintQuoteScheduleRecord
import com.cashu.me.Models.MintQuoteState
import com.cashu.me.Models.PaymentMethodKind

/**
 * Pure policy for the app-wide mint-quote sweeper. It deliberately separates
 * scheduling from CDK's quote ledger: losing or corrupting this metadata may
 * cause an early check, but can never change how much ecash may be issued.
 */
internal object MintQuoteSchedulePolicy {
    const val PASSIVE_BATCH_LIMIT = 2
    const val FORCED_BATCH_LIMIT = 20
    private const val RECENT_QUOTE_WINDOW_MS = 2 * 60_000L
    private const val RECENT_QUOTE_INTERVAL_MS = 10_000L
    private const val IDLE_QUOTE_INTERVAL_MS = 60_000L
    private const val NEEDS_ATTENTION_FAILURE_COUNT = 4
    private val FAILURE_DELAYS_MS = longArrayOf(
        5_000L,
        15_000L,
        30_000L,
        60_000L,
        5 * 60_000L,
    )

    data class Selection(
        val quoteIds: List<String>,
        val records: Map<String, MintQuoteScheduleRecord>,
    )

    fun select(
        quoteIds: Collection<String>,
        existing: Map<String, MintQuoteScheduleRecord>,
        nowEpochMillis: Long,
        force: Boolean,
        unsettledOnchainQuoteIds: Set<String> = emptySet(),
    ): Selection {
        val uniqueIds = quoteIds.asSequence().filter(String::isNotBlank).toSet()
        val records = existing
            .filterKeys { it in uniqueIds }
            .toMutableMap()

        uniqueIds.forEach { quoteId ->
            records.putIfAbsent(
                quoteId,
                MintQuoteScheduleRecord(firstObservedAtEpochMillis = nowEpochMillis),
            )
        }
        // Reopen schedules created by the old expiry policy while a deposit
        // was still waiting for confirmations. CDK remains the source of truth.
        unsettledOnchainQuoteIds.forEach { quoteId ->
            records[quoteId]?.takeIf { it.isComplete }?.let { record ->
                records[quoteId] = record.copy(isComplete = false, nextAttemptAtEpochMillis = 0)
            }
        }

        val limit = if (force) FORCED_BATCH_LIMIT else PASSIVE_BATCH_LIMIT
        val selected = uniqueIds.asSequence()
            .filter { quoteId ->
                val record = checkNotNull(records[quoteId])
                !record.isComplete && (force || record.nextAttemptAtEpochMillis <= nowEpochMillis)
            }
            .sortedWith(
                compareBy<String> { records[it]?.lastAttemptAtEpochMillis ?: Long.MIN_VALUE }
                    .thenBy { records[it]?.nextAttemptAtEpochMillis ?: Long.MIN_VALUE }
                    .thenBy { it },
            )
            .take(limit)
            .toList()

        // Reserve the selected slice before network work. If the coroutine is
        // cancelled halfway through, the same first row cannot starve all
        // later rows on the next foreground tick.
        selected.forEach { quoteId ->
            val record = checkNotNull(records[quoteId])
            records[quoteId] = record.copy(
                lastAttemptAtEpochMillis = nowEpochMillis,
                nextAttemptAtEpochMillis = if (record.consecutiveFailures == 0) {
                    nowEpochMillis + FAILURE_DELAYS_MS.first()
                } else {
                    record.nextAttemptAtEpochMillis
                },
            )
        }
        return Selection(selected, records)
    }

    fun observed(
        previous: MintQuoteScheduleRecord?,
        quote: MintQuoteInfo,
        nowEpochMillis: Long,
    ): MintQuoteScheduleRecord {
        val record = previous ?: MintQuoteScheduleRecord(
            firstObservedAtEpochMillis = nowEpochMillis,
        )
        val reusable = quote.paymentMethod == PaymentMethodKind.Bolt12
        val expired = quote.expiryEpochSeconds
            ?.takeIf { it > 0 }
            ?.let { nowEpochMillis / 1_000 >= it }
            ?: false
        // Deposits seen before an on-chain quote expires can confirm later.
        val expiredInvoice = quote.paymentMethod == PaymentMethodKind.Bolt11 && expired
        val complete = !reusable && (
            expiredInvoice || quote.state == MintQuoteState.Issued || quote.hasSettledPayment
        )
        val age = (nowEpochMillis - record.firstObservedAtEpochMillis).coerceAtLeast(0)
        val nextInterval = if (age < RECENT_QUOTE_WINDOW_MS) {
            RECENT_QUOTE_INTERVAL_MS
        } else {
            IDLE_QUOTE_INTERVAL_MS
        }
        return record.copy(
            lastAttemptAtEpochMillis = nowEpochMillis,
            nextAttemptAtEpochMillis = if (complete) Long.MAX_VALUE else nowEpochMillis + nextInterval,
            consecutiveFailures = 0,
            hadOutstandingPayment = false,
            isReusable = reusable,
            isComplete = complete,
        )
    }

    fun failed(
        previous: MintQuoteScheduleRecord?,
        nowEpochMillis: Long,
        hadOutstandingPayment: Boolean,
        isReusable: Boolean,
    ): MintQuoteScheduleRecord {
        val record = previous ?: MintQuoteScheduleRecord(
            firstObservedAtEpochMillis = nowEpochMillis,
        )
        val failures = if (record.consecutiveFailures == Int.MAX_VALUE) {
            Int.MAX_VALUE
        } else {
            record.consecutiveFailures + 1
        }
        val delay = FAILURE_DELAYS_MS[(failures - 1).coerceAtMost(FAILURE_DELAYS_MS.lastIndex)]
        return record.copy(
            lastAttemptAtEpochMillis = nowEpochMillis,
            nextAttemptAtEpochMillis = nowEpochMillis + delay,
            consecutiveFailures = failures,
            hadOutstandingPayment = hadOutstandingPayment || record.hadOutstandingPayment,
            isReusable = isReusable || record.isReusable,
            isComplete = false,
        )
    }

    fun shouldAttempt(record: MintQuoteScheduleRecord?, nowEpochMillis: Long, force: Boolean): Boolean =
        force || record == null || record.consecutiveFailures == 0 ||
            record.nextAttemptAtEpochMillis <= nowEpochMillis

    fun retryStatus(record: MintQuoteScheduleRecord): MintQuoteRetryStatus {
        if (!record.hadOutstandingPayment || record.consecutiveFailures == 0) {
            return MintQuoteRetryStatus()
        }
        return MintQuoteRetryStatus(
            state = if (record.consecutiveFailures >= NEEDS_ATTENTION_FAILURE_COUNT) {
                MintQuoteRetryState.NeedsAttention
            } else {
                MintQuoteRetryState.RetryScheduled
            },
            nextRetryAtEpochMillis = record.nextAttemptAtEpochMillis,
            failureCount = record.consecutiveFailures,
        )
    }
}
