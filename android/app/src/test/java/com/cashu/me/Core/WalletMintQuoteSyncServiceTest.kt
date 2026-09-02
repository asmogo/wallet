package com.cashu.me.Core

import com.cashu.me.Models.MintQuoteInfo
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
        val recovered = service.syncPendingMintQuote(ledger.quote.id)

        assertFalse(failed.hasSettledPayment)
        assertEquals(8L, failed.remainingAmount)
        assertEquals(8L, recovered.newlyIssued)
        assertTrue(recovered.hasSettledPayment)
        assertEquals(2, ledger.mintCalls)
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
            state = if (paid > issued) MintQuoteState.Paid else MintQuoteState.Issued,
            expiryEpochSeconds = null,
            mintUrl = "https://mint.example",
            amountPaid = paid,
            amountIssued = issued,
        )
        var mintCalls = 0
        var failuresBeforeIssuance = 0
        var throwAfterNextIssuance = false

        fun service() = WalletMintQuoteSyncService(
            checkQuote = { quote },
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
