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
    fun clearingDescriptionRestoresLastUsedOfferWithoutChangingHistory() {
        val persistence = MemoryCashuRequestPersistence()
        val store = CashuRequestStore(persistence)
        val plain = CashuRequest(id = "plain", quoteId = "plain", quoteKind = "bolt12",
            encoded = "lno-plain", mints = listOf("https://mint.example"), createdAtEpochMillis = 1)
        store.upsert(plain)
        store.upsert(plain.copy(id = "described", quoteId = "described", memo = "Coffee", createdAtEpochMillis = 2))
        store.upsert(plain.copy(id = "other-unit", quoteId = "other-unit", unit = "usd", memo = "USD", createdAtEpochMillis = 3))
        store.upsert(plain.copy(id = "fixed", quoteId = "fixed", amount = 21, memo = "Fixed", createdAtEpochMillis = 4))
        assertEquals("described", store.lastPresentedAmountlessOffer("https://mint.example", "sat")?.id)
        store.attachPaymentByQuoteId("plain", "payment", 21)
        store.markQuotePresented("plain")
        val reloaded = CashuRequestStore(persistence)
        val restored = reloaded.lastPresentedAmountlessOffer("https://mint.example", "SAT")!!
        assertNull(restored.memo)
        assertEquals(plain.createdAtEpochMillis, restored.createdAtEpochMillis)
        assertEquals(21L, restored.totalReceived)
        assertEquals("other-unit", reloaded.lastPresentedAmountlessOffer("https://mint.example", "usd")?.id)
        assertNull(reloaded.lastPresentedAmountlessOffer("https://other.example", "sat"))
    }

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
            unit = "sat",
            mints = listOf("https://mint-b.example"),
            memo = " ",
            encoded = { id ->
                assertEquals("request-a", id)
                "creq-updated"
            },
        )!!

        assertEquals(12L, updated.amount)
        assertEquals("sat", updated.unit)
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
    fun currencyChangeKeepsOriginalAndLatePaymentsInTheirOwnIntent() {
        for (alreadyPaid in listOf(false, true)) {
            val persistence = MemoryCashuRequestPersistence()
            val store = CashuRequestStore(persistence)
            val original = store.createNew(id = "sat-request", amount = 500, unit = "sat",
                mints = listOf("https://sat.example"), memo = "Coffee", encoded = "old-code")
            if (alreadyPaid) {
                store.attachPayment(original.id, "first", 1200)
                store.attachPayment(original.id, "second", 34)
            }
            val prior = store.request(original.id)
            val updated = store.update(id = original.id, amount = null, unit = "usd",
                mints = listOf("https://usd.example"), memo = original.memo) { id -> "code-$id" }!!
            assertTrue(updated.id != original.id)
            assertEquals("code-${updated.id}", updated.encoded)
            assertNull(updated.amount)
            assertEquals("usd", updated.unit)
            assertEquals(original.memo, updated.memo)
            assertEquals(0L, updated.totalReceived)
            assertEquals(prior, store.request(original.id))
            assertEquals(updated.id, store.state.value.currentRequestId)

            // Codes shared before the edit still belong to the sat intent.
            store.attachPayment(original.id, "late", 10)
            store.attachPayment(updated.id, "usd-payment", 99)
            val reloaded = CashuRequestStore(persistence)
            assertEquals(2, reloaded.state.value.requests.size)
            assertEquals("sat", reloaded.request(original.id)?.unit)
            assertEquals(if (alreadyPaid) 1244L else 10L, reloaded.request(original.id)?.totalReceived)
            assertEquals(99L, reloaded.request(updated.id)?.totalReceived)
            assertEquals(updated.id, reloaded.state.value.currentRequestId)
        }
    }

    @Test
    fun failedCurrencyEncodingLeavesRequestAndCurrentPointerUntouched() {
        val persistence = MemoryCashuRequestPersistence()
        val store = CashuRequestStore(persistence)
        val original = store.createNew(id = "original", encoded = "old-code")
        val result = runCatching {
            store.update(id = original.id, amount = null, unit = "usd", mints = emptyList(), memo = null) {
                error("Encoding failed")
            }
        }
        assertTrue(result.isFailure)
        assertEquals(listOf(original), store.state.value.requests)
        assertEquals(original.id, store.state.value.currentRequestId)
        assertEquals(listOf(original), CashuRequestStore(persistence).state.value.requests)
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
