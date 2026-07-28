package com.cashu.me.Core

import com.cashu.me.Models.CashuRequest
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CashuRequestStoreTest {
    @Test
    fun quoteIntentAttachmentUsesQuoteIdAndSuppressesDuplicatePayments() {
        val persistence = MemoryCashuRequestPersistence()
        val store = CashuRequestStore(persistence)

        store.upsertQuoteIntent(
            id = "request-a",
            quoteId = "quote-a",
            quoteKind = "bolt11",
            amount = 21,
            unit = "sat",
            mints = listOf("https://mint.example"),
            memo = "coffee",
            encoded = "creq-a",
        )
        store.attachPaymentByQuoteId("quote-a", transactionId = "tx-a", amount = 21)
        store.attachPaymentByQuoteId("quote-a", transactionId = "tx-a", amount = 21)

        val request = store.request("request-a")!!
        assertEquals("request-a", store.state.value.currentRequestId)
        assertEquals("quote-a", request.quoteId)
        assertEquals("bolt11", request.quoteKind)
        assertEquals(1, request.receivedPayments.size)
        assertEquals("tx-a", request.receivedPayments.single().transactionId)
        assertEquals(21L, request.totalReceived)
        assertEquals(request, persistence.requests.single())
    }

    @Test
    fun reopeningReusableQuotePreservesItsHistoryRowAndPayments() {
        val persistence = MemoryCashuRequestPersistence()
        val store = CashuRequestStore(persistence)

        val original = store.upsertQuoteIntent(
            id = "request-a",
            quoteId = "quote-a",
            quoteKind = "bolt12",
            amount = null,
            unit = "sat",
            mints = listOf("https://mint.example"),
            encoded = "lno-original",
        )
        store.attachPaymentByQuoteId("quote-a", transactionId = "tx-a", amount = 21)

        val reopened = store.upsertQuoteIntent(
            id = "request-b",
            quoteId = "quote-a",
            quoteKind = "bolt12",
            amount = null,
            unit = "sat",
            mints = listOf("https://mint.example"),
            encoded = "lno-current",
        )

        assertEquals(original.id, reopened.id)
        assertEquals(original.createdAtEpochMillis, reopened.createdAtEpochMillis)
        assertEquals("lno-current", reopened.encoded)
        assertEquals(1, store.state.value.requests.size)
        assertEquals(21L, reopened.totalReceived)
    }

    @Test
    fun reconciliationAggregatesIncomingTransactionsForQuoteIntent() {
        val persistence = MemoryCashuRequestPersistence()
        val store = CashuRequestStore(persistence)
        store.upsertQuoteIntent(
            id = "request-a",
            quoteId = "quote-a",
            quoteKind = "bolt12",
            amount = null,
            encoded = "lno-a",
        )

        store.reconcileIncomingQuotePayments(
            listOf(
                quoteTransaction(id = "tx-a", amount = 21, date = 100, quoteId = "quote-a"),
                quoteTransaction(id = "tx-b", amount = 34, date = 200, quoteId = "quote-a"),
                quoteTransaction(id = "tx-b", amount = 34, date = 200, quoteId = "quote-a"),
                quoteTransaction(id = "tx-c", amount = 55, date = 300, quoteId = "other-quote"),
            ),
        )

        val request = store.request("request-a")!!
        assertEquals(listOf("tx-a", "tx-b"), request.receivedPayments.map { it.transactionId })
        assertEquals(listOf(100L, 200L), request.receivedPayments.map { it.receivedAtEpochMillis })
        assertEquals(55L, request.totalReceived)
    }

    @Test
    fun reconciliationRefreshesTheSyntheticQuotePaymentInsteadOfDoubleCounting() {
        val persistence = MemoryCashuRequestPersistence()
        val store = CashuRequestStore(persistence)
        store.upsertQuoteIntent(
            id = "request-a",
            quoteId = "quote-a",
            quoteKind = "bolt12",
            amount = null,
            encoded = "lno-a",
        )

        store.reconcileIncomingQuotePayments(
            listOf(quoteTransaction(id = "quote-a", amount = 21, date = 100, quoteId = "quote-a")),
        )
        store.reconcileIncomingQuotePayments(
            listOf(quoteTransaction(id = "quote-a", amount = 55, date = 200, quoteId = "quote-a")),
        )

        val request = store.request("request-a")!!
        assertEquals(1, request.receivedPayments.size)
        assertEquals(55L, request.totalReceived)
        assertEquals(200L, request.receivedPayments.single().receivedAtEpochMillis)
    }

    @Test
    fun reusableBolt12TransactionsKeepEachPaymentDuringHistoryMerge() {
        val transactions = listOf(
            quoteTransaction(id = "tx-a", amount = 21, date = 100, quoteId = "quote-a"),
            quoteTransaction(id = "tx-b", amount = 34, date = 200, quoteId = "quote-a"),
            quoteTransaction(id = "tx-a", amount = 21, date = 100, quoteId = "quote-a"),
        )

        val merged = deduplicateWalletTransactions(
            transactions = transactions,
            reusableBolt12QuoteIds = setOf("quote-a"),
        )

        assertEquals(listOf("tx-a", "tx-b"), merged.map { it.id })
    }

    @Test
    fun oneShotQuoteTransactionsRemainDeduplicatedByQuoteId() {
        val transactions = listOf(
            quoteTransaction(id = "tx-a", amount = 21, date = 100, quoteId = "quote-a"),
            quoteTransaction(id = "tx-b", amount = 34, date = 200, quoteId = "quote-a"),
        )

        val merged = deduplicateWalletTransactions(
            transactions = transactions,
            reusableBolt12QuoteIds = emptySet(),
        )

        assertEquals(listOf("tx-a"), merged.map { it.id })
    }

    @Test
    fun updateDeleteResetAndReloadPersistConsistentState() {
        val persistence = MemoryCashuRequestPersistence()
        val store = CashuRequestStore(persistence)

        store.createNew(
            id = "request-a",
            amount = 10,
            unit = "sat",
            mints = listOf("https://mint-a.example"),
            memo = "first",
            encoded = "creq-a",
        )
        val updated = store.update(
            id = "request-a",
            amount = 12,
            unit = "usd",
            mints = listOf("https://mint-b.example"),
            memo = " ",
            encoded = "creq-updated",
        )!!

        assertEquals(12L, updated.amount)
        assertEquals("usd", updated.unit)
        assertEquals(listOf("https://mint-b.example"), updated.mints)
        assertNull(updated.memo)
        assertEquals("creq-updated", updated.encoded)
        assertEquals("request-a", persistence.currentCashuRequestId)

        store.delete("request-a")
        assertTrue(store.state.value.requests.isEmpty())
        assertNull(store.state.value.currentRequestId)

        persistence.requests = listOf(
            CashuRequest(id = "old", encoded = "creq-old", createdAtEpochMillis = 1),
            CashuRequest(id = "new", encoded = "creq-new", createdAtEpochMillis = 2),
        )
        persistence.currentCashuRequestId = "missing"
        store.reload()

        assertEquals(listOf("new", "old"), store.state.value.requests.map { it.id })
        assertNull(store.state.value.currentRequestId)
        assertNull(persistence.currentCashuRequestId)

        store.resetForWalletBoundary()
        assertTrue(persistence.requests.isEmpty())
        assertNull(persistence.currentCashuRequestId)
        assertTrue(store.state.value.requests.isEmpty())
        assertNull(store.state.value.currentRequestId)
    }

    @Test
    fun legacyPaymentIdsAreNormalizedWhenPersisting() {
        val persistence = MemoryCashuRequestPersistence()
        val store = CashuRequestStore(persistence)

        store.upsert(
            CashuRequest(
                id = "legacy",
                encoded = "creq-legacy",
                createdAtEpochMillis = 42,
                receivedPaymentIds = listOf("tx-legacy"),
            ),
        )

        val stored = persistence.requests.single()
        assertTrue(stored.receivedPaymentIds.isEmpty())
        assertEquals(1, stored.receivedPayments.size)
        assertEquals("tx-legacy", stored.receivedPayments.single().transactionId)
        assertEquals(0L, stored.receivedPayments.single().amount)
        assertEquals(42L, stored.receivedPayments.single().receivedAtEpochMillis)
    }
}

private fun quoteTransaction(
    id: String,
    amount: Long,
    date: Long,
    quoteId: String,
): WalletTransaction = WalletTransaction(
    id = id,
    amount = amount,
    type = TransactionType.Incoming,
    kind = TransactionKind.Lightning,
    dateEpochMillis = date,
    status = TransactionStatus.Completed,
    quoteId = quoteId,
)

private class MemoryCashuRequestPersistence : CashuRequestPersistence {
    var requests: List<CashuRequest> = emptyList()
    override var currentCashuRequestId: String? = null

    override fun loadCashuRequests(): List<CashuRequest> = requests

    override fun saveCashuRequests(requests: List<CashuRequest>) {
        this.requests = requests
    }
}
