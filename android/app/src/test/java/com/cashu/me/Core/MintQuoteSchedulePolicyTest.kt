package com.cashu.me.Core

import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.Models.MintQuoteRetryState
import com.cashu.me.Models.MintQuoteScheduleRecord
import com.cashu.me.Models.MintQuoteState
import com.cashu.me.Models.PaymentMethodKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MintQuoteSchedulePolicyTest {
    @Test
    fun `passive sweeps are bounded and rotate fairly`() {
        val ids = (1..5).map { "quote-$it" }
        val first = MintQuoteSchedulePolicy.select(ids, emptyMap(), nowEpochMillis = 1_000, force = false)

        assertEquals(MintQuoteSchedulePolicy.PASSIVE_BATCH_LIMIT, first.quoteIds.size)

        val second = MintQuoteSchedulePolicy.select(ids, first.records, nowEpochMillis = 1_000, force = false)
        assertEquals(MintQuoteSchedulePolicy.PASSIVE_BATCH_LIMIT, second.quoteIds.size)
        assertTrue(first.quoteIds.intersect(second.quoteIds.toSet()).isEmpty())
    }

    @Test
    fun `forced sweep bypasses due time but stays bounded`() {
        val ids = (1..30).map { "quote-$it" }
        val future = ids.associateWith {
            MintQuoteScheduleRecord(
                firstObservedAtEpochMillis = 1,
                nextAttemptAtEpochMillis = Long.MAX_VALUE - 1,
            )
        }

        assertTrue(
            MintQuoteSchedulePolicy.select(ids, future, 2_000, force = false).quoteIds.isEmpty(),
        )
        assertEquals(
            MintQuoteSchedulePolicy.FORCED_BATCH_LIMIT,
            MintQuoteSchedulePolicy.select(ids, future, 2_000, force = true).quoteIds.size,
        )
    }

    @Test
    fun `paid issuance failures become truthful needs-attention state`() {
        var record: MintQuoteScheduleRecord? = null
        repeat(3) {
            record = MintQuoteSchedulePolicy.failed(
                previous = record,
                nowEpochMillis = it * 10_000L,
                hadOutstandingPayment = true,
                isReusable = true,
            )
        }
        assertEquals(
            MintQuoteRetryState.RetryScheduled,
            MintQuoteSchedulePolicy.retryStatus(checkNotNull(record)).state,
        )

        record = MintQuoteSchedulePolicy.failed(
            previous = record,
            nowEpochMillis = 40_000,
            hadOutstandingPayment = true,
            isReusable = true,
        )
        assertEquals(
            MintQuoteRetryState.NeedsAttention,
            MintQuoteSchedulePolicy.retryStatus(checkNotNull(record)).state,
        )
        assertEquals(4, record!!.consecutiveFailures)
    }

    @Test
    fun `waiting failures back off without claiming a payment needs attention`() {
        val record = MintQuoteSchedulePolicy.failed(
            previous = null,
            nowEpochMillis = 10_000,
            hadOutstandingPayment = false,
            isReusable = true,
        )

        assertEquals(MintQuoteRetryState.None, MintQuoteSchedulePolicy.retryStatus(record).state)
        assertTrue(record.nextAttemptAtEpochMillis > 10_000)
    }

    @Test
    fun `failure counter saturates without overflowing`() {
        val saturated = MintQuoteSchedulePolicy.failed(
            previous = MintQuoteScheduleRecord(
                firstObservedAtEpochMillis = 1,
                consecutiveFailures = Int.MAX_VALUE,
                hadOutstandingPayment = true,
            ),
            nowEpochMillis = 10_000,
            hadOutstandingPayment = true,
            isReusable = true,
        )

        assertEquals(Int.MAX_VALUE, saturated.consecutiveFailures)
        assertEquals(
            MintQuoteRetryState.NeedsAttention,
            MintQuoteSchedulePolicy.retryStatus(saturated).state,
        )
    }

    @Test
    fun `reusable quote remains scheduled after issuance catches up`() {
        val record = MintQuoteSchedulePolicy.observed(
            previous = null,
            quote = quote(
                method = PaymentMethodKind.Bolt12,
                state = MintQuoteState.Issued,
                paid = 21,
                issued = 21,
            ),
            nowEpochMillis = 1_000,
        )

        assertTrue(record.isReusable)
        assertFalse(record.isComplete)
        assertTrue(record.nextAttemptAtEpochMillis > 1_000)
    }

    @Test
    fun `settled one-shot quote leaves the scheduler`() {
        val record = MintQuoteSchedulePolicy.observed(
            previous = null,
            quote = quote(
                method = PaymentMethodKind.Bolt11,
                state = MintQuoteState.Issued,
                paid = 21,
                issued = 21,
            ),
            nowEpochMillis = 1_000,
        )

        assertTrue(record.isComplete)
        assertEquals(
            emptyList<String>(),
            MintQuoteSchedulePolicy.select(
                quoteIds = listOf("quote"),
                existing = mapOf("quote" to record),
                nowEpochMillis = Long.MAX_VALUE,
                force = true,
            ).quoteIds,
        )
    }

    private fun quote(
        method: PaymentMethodKind,
        state: MintQuoteState,
        paid: Long,
        issued: Long,
    ) = MintQuoteInfo(
        id = "quote",
        request = "request",
        amount = paid,
        paymentMethod = method,
        state = state,
        expiryEpochSeconds = null,
        amountPaid = paid,
        amountIssued = issued,
    )
}
