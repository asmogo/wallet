package com.cashu.me.Core

import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.Models.MintQuoteRetryState
import com.cashu.me.Models.MintQuoteScheduleRecord
import com.cashu.me.Models.MintQuoteState
import com.cashu.me.Models.PaymentMethodKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WalletMintQuoteSyncServiceTest {
    @Test
    fun `focused monitoring respects failure backoff and settles without manual refresh`() = runBlocking {
        val ledger = QuoteLedger(paid = 8, issued = 0).apply {
            quote = quote.copy(paymentMethod = PaymentMethodKind.Bolt11)
            failuresBeforeIssuance = 1
        }
        val service = ledger.service()
        val monitor = FocusedMintQuoteMonitor()
        val credits = mutableListOf<Long>()
        var refreshes = 0
        monitor.monitor(ledger.quote.id, refresh = { id ->
            refreshes++
            val result = service.syncPendingMintQuote(id)
            result.receivedAmount?.let { credits += it }
            result.quote
        }, sleep = { ledger.now += 2_000 })

        assertEquals(4, refreshes) // Immediate, 2s, 4s, 6s (retry is due at 5s).
        assertEquals(2, ledger.mintCalls)
        assertEquals(listOf(8L), credits)
        assertEquals(8L, ledger.quote.amountIssued)
        assertFalse(monitor.isActive)
    }

    @Test
    fun `recovery during the first check reports the issuance delta once`() = runBlocking {
        val ledger = QuoteLedger(paid = 21, issued = 0).apply { recoverOnNextCheck = 21 }
        val service = ledger.service()

        val recovered = service.syncPendingMintQuote(ledger.quote.id)
        val duplicate = service.syncPendingMintQuote(ledger.quote.id)

        assertEquals(21L, recovered.newlyIssued)
        assertTrue(recovered.minted)
        assertEquals(0L, duplicate.newlyIssued)
        assertEquals(0, ledger.mintCalls)
    }

    @Test
    fun `first check recovery and a later payment report the combined delta`() = runBlocking {
        val ledger = QuoteLedger(paid = 34, issued = 0).apply { recoverOnNextCheck = 21 }
        val result = ledger.service().syncPendingMintQuote(ledger.quote.id)

        assertEquals(34L, result.newlyIssued)
        assertEquals(1, ledger.mintCalls)
        assertTrue(result.hasSettledPayment)
    }

    @Test
    fun `automatic retries respect persisted deadlines and manual retries bypass them`() = runBlocking {
        val ledger = QuoteLedger(paid = 8, issued = 0).apply { failuresBeforeIssuance = 5 }
        val first = ledger.service().syncPendingMintQuote(ledger.quote.id)
        val checkCalls = ledger.checkCalls
        val record = ledger.schedules[ledger.quote.id]

        // Recreate the service over the same durable state, as on relaunch.
        val reopened = ledger.service()
        val deferred = reopened.syncPendingMintQuote(ledger.quote.id)
        assertEquals(first.retryStatus, deferred.retryStatus)
        assertEquals(checkCalls, ledger.checkCalls)
        assertEquals(1, ledger.mintCalls)
        assertEquals(record, ledger.schedules[ledger.quote.id])

        ledger.now = checkNotNull(first.retryStatus.nextRetryAtEpochMillis)
        reopened.syncPendingMintQuote(ledger.quote.id)
        assertEquals(2, ledger.mintCalls)

        ledger.failuresBeforeIssuance = 0
        val manual = reopened.syncPendingMintQuote(ledger.quote.id, force = true)
        assertEquals(8L, manual.newlyIssued)
        assertEquals(3, ledger.mintCalls)
        assertEquals(MintQuoteRetryState.None, manual.retryStatus.state)
    }

    @Test
    fun `onchain payment confirmed after expiry is issued on the next sweep`() = runBlocking {
        val ledger = QuoteLedger(paid = 0, issued = 0).apply {
            quote = quote.copy(paymentMethod = PaymentMethodKind.Onchain, expiryEpochSeconds = 1)
        }
        val service = ledger.service()
        service.syncPendingMintQuote(ledger.quote.id)
        assertFalse(checkNotNull(ledger.schedules[ledger.quote.id]).isComplete)

        ledger.addPayment(21)
        ledger.now += 60_000
        val selected = service.selectQuoteIdsForSync(listOf(ledger.quote.id), force = false)
        assertEquals(listOf(ledger.quote.id), selected)
        val result = service.syncPendingMintQuote(selected.single())
        assertEquals(21L, result.newlyIssued)
        assertTrue(result.hasSettledPayment)
    }

    @Test
    fun `paid quote is only complete after issued counter catches up`() = runBlocking {
        val ledger = QuoteLedger(paid = 21, issued = 0)
        val result = ledger.service().syncPendingMintQuote(ledger.quote.id)

        assertEquals(21L, result.newlyIssued)
        assertEquals(21L, result.quote?.amountIssued)
        assertEquals(0L, result.remainingAmount)
        assertTrue(result.hasSettledPayment)
        assertEquals(1, ledger.mintCalls)
    }

    @Test
    fun `same reusable offer settles every later payment exactly once`() = runBlocking {
        val ledger = QuoteLedger(paid = 10, issued = 0)
        val service = ledger.service()

        val first = service.syncPendingMintQuote(ledger.quote.id)
        ledger.addPayment(11)
        val second = service.syncPendingMintQuote(ledger.quote.id)
        val duplicateCheck = service.syncPendingMintQuote(ledger.quote.id)

        assertEquals(10L, first.newlyIssued)
        assertEquals(11L, second.newlyIssued)
        assertEquals(0L, duplicateCheck.newlyIssued)
        assertEquals(21L, duplicateCheck.quote?.amountPaid)
        assertEquals(21L, duplicateCheck.quote?.amountIssued)
        assertEquals(2, ledger.mintCalls)
    }

    @Test
    fun `ambiguous mint response is resolved by verified issued counter`() = runBlocking {
        val ledger = QuoteLedger(paid = 13, issued = 0).apply {
            throwAfterNextIssuance = true
        }

        val result = ledger.service().syncPendingMintQuote(ledger.quote.id)

        assertEquals(13L, result.newlyIssued)
        assertTrue(result.hasSettledPayment)
        assertEquals(13L, result.quote?.amountIssued)
    }

    @Test
    fun `failed issuance remains tracked and succeeds on a later pass`() = runBlocking {
        val ledger = QuoteLedger(paid = 8, issued = 0).apply {
            failuresBeforeIssuance = 1
        }
        val service = ledger.service()

        val failed = service.syncPendingMintQuote(ledger.quote.id)
        val recovered = service.syncPendingMintQuote(ledger.quote.id, force = true)

        assertFalse(failed.hasSettledPayment)
        assertEquals(8L, failed.remainingAmount)
        assertEquals(MintQuoteRetryState.RetryScheduled, failed.retryStatus.state)
        assertEquals(8L, recovered.newlyIssued)
        assertTrue(recovered.hasSettledPayment)
        assertEquals(MintQuoteRetryState.None, recovered.retryStatus.state)
        assertEquals(2, ledger.mintCalls)
    }

    @Test
    fun `check failure uses durable paid snapshot and reports a scheduled retry`() = runBlocking {
        val cached = MintQuoteInfo(
            id = "reusable-quote",
            request = "lno1test",
            amount = null,
            isAmountless = true,
            paymentMethod = PaymentMethodKind.Bolt12,
            state = MintQuoteState.Paid,
            expiryEpochSeconds = null,
            mintUrl = "https://mint.example",
            amountPaid = 5,
            amountIssued = 0,
        )
        val service = WalletMintQuoteSyncService(
            checkQuote = { error("mint temporarily unavailable") },
            storedQuote = { cached },
            mintQuote = { error("must not mint without a status check") },
            nowEpochMillis = { 10_000 },
        )

        val result = service.syncPendingMintQuote(cached.id)

        assertEquals(cached, result.quote)
        assertEquals(5L, result.remainingAmount)
        assertEquals(MintQuoteRetryState.RetryScheduled, result.retryStatus.state)
        assertEquals(15_000L, result.retryStatus.nextRetryAtEpochMillis)
    }

    @Test
    fun `wallet boundary storage reset clears retry state immediately`() {
        var schedules = mapOf(
            "old-quote" to MintQuoteScheduleRecord(
                firstObservedAtEpochMillis = 1_000,
                consecutiveFailures = 4,
                hadOutstandingPayment = true,
                isReusable = true,
            ),
        )
        val service = WalletMintQuoteSyncService(
            checkQuote = { error("unused") },
            mintQuote = { error("unused") },
            loadSchedules = { schedules },
            saveSchedules = { schedules = it },
        )

        assertEquals(
            MintQuoteRetryState.NeedsAttention,
            service.retryStatus("old-quote").state,
        )

        // WalletStore.removeAllWalletData() changes the durable source while
        // WalletManager remains alive. The service must not retain the old
        // wallet's retry metadata in memory.
        schedules = emptyMap()

        assertEquals(MintQuoteRetryState.None, service.retryStatus("old-quote").state)
    }

    @Test
    fun `concurrent triggers share one check mint verify lane`() = runBlocking {
        val ledger = QuoteLedger(paid = 31, issued = 0)
        val service = ledger.service()

        val results = listOf(
            async(Dispatchers.Default) { service.syncPendingMintQuote(ledger.quote.id) },
            async(Dispatchers.Default) { service.syncPendingMintQuote(ledger.quote.id) },
        ).awaitAll()

        assertEquals(1, ledger.mintCalls)
        assertEquals(31L, results.sumOf { it.newlyIssued })
        assertTrue(results.all { it.hasSettledPayment })
    }

    private class QuoteLedger(paid: Long, issued: Long) {
        var quote = MintQuoteInfo(
            id = "reusable-quote",
            request = "lno1test",
            amount = null,
            isAmountless = true,
            paymentMethod = PaymentMethodKind.Bolt12,
            state = if (paid > issued) MintQuoteState.Paid else if (paid > 0) MintQuoteState.Issued else MintQuoteState.Pending,
            expiryEpochSeconds = null,
            mintUrl = "https://mint.example",
            amountPaid = paid,
            amountIssued = issued,
        )
        var mintCalls = 0
        var checkCalls = 0
        var now = 10_000L
        var schedules: Map<String, MintQuoteScheduleRecord> = emptyMap()
        var recoverOnNextCheck = 0L
        var failuresBeforeIssuance = 0
        var throwAfterNextIssuance = false

        fun service() = WalletMintQuoteSyncService(
            storedQuote = { quote },
            checkQuote = {
                checkCalls += 1
                if (recoverOnNextCheck > 0) {
                    quote = quote.copy(amountIssued = quote.amountIssued + recoverOnNextCheck)
                    recoverOnNextCheck = 0
                }
                quote
            },
            loadSchedules = { schedules },
            saveSchedules = { schedules = it },
            nowEpochMillis = { now },
            mintQuote = {
                mintCalls += 1
                if (failuresBeforeIssuance > 0) {
                    failuresBeforeIssuance -= 1
                    error("temporary mint failure")
                }
                val issuedNow = quote.mintableAmount
                quote = quote.copy(
                    amountIssued = quote.amountPaid,
                    state = MintQuoteState.Issued,
                )
                if (throwAfterNextIssuance) {
                    throwAfterNextIssuance = false
                    error("response lost after issuance")
                }
                issuedNow
            },
        )

        fun addPayment(amount: Long) {
            quote = quote.copy(
                amountPaid = quote.amountPaid + amount,
                state = MintQuoteState.Paid,
            )
        }
    }
}
