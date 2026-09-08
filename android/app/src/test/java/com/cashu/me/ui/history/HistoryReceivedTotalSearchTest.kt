package com.cashu.me.ui.history

import com.cashu.me.Core.HistoryFilter
import com.cashu.me.Models.CashuRequest
import com.cashu.me.Models.CashuRequestPayment
import org.junit.Assert.*
import org.junit.Test

class HistoryReceivedTotalSearchTest {
    private val request = CashuRequest(
        id = "request", encoded = "", amount = 25L, memo = "Coffee",
        createdAtEpochMillis = 1L,
        receivedPayments = listOf(
            CashuRequestPayment("one", 30L, 2L), CashuRequestPayment("two", 45L, 3L),
        ),
    )

    @Test fun searchesPersistedTotalWithoutLoadedTransactions() {
        assertEquals(1, search(" 75 ").size)
        assertEquals(1, search("25").size)
        assertEquals(1, search(" coffee ").size)
        assertEquals(0, search("30").size)
    }

    @Test fun preservesFilterAndDoesNotMatchAnUnreceivedZeroTotal() {
        assertEquals(0, search("75", HistoryFilter.Pending).size)
        assertEquals(1, search("75", HistoryFilter.Completed).size)
        assertEquals(1, search("  ").size)
        val unpaid = request.copy(amount = null, memo = null, receivedPayments = emptyList())
        assertTrue(unifiedFiltered(emptyList(), listOf(unpaid), HistoryFilter.All, "0").isEmpty())
    }

    private fun search(query: String, filter: HistoryFilter = HistoryFilter.All) =
        unifiedFiltered(emptyList(), listOf(request), filter, query)
}
