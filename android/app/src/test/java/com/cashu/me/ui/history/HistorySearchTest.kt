package com.cashu.me.ui.history

import com.cashu.me.Core.HistoryFilter
import com.cashu.me.Models.CashuRequest
import com.cashu.me.Models.CashuRequestPayment
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HistorySearchTest {
    @Test
    fun `request search matches the requested amount`() {
        val request = request(amount = 100, received = emptyList())

        assertEquals(listOf(request), matchingRequests("100", request))
        assertTrue(matchingRequests("95", request).isEmpty())
    }

    @Test
    fun `request search matches the total received amount`() {
        // iOS HistoryView.matchesSearch parity: once payments land, the
        // aggregate received total is searchable with the same raw-digit
        // normalization as every other History amount.
        val request = request(
            amount = 100,
            received = listOf(
                CashuRequestPayment("tx-1", amount = 60, receivedAtEpochMillis = 2),
                CashuRequestPayment("tx-2", amount = 36, receivedAtEpochMillis = 3),
            ),
        )

        assertEquals(listOf(request), matchingRequests("96", request))
        // The configured amount stays searchable too.
        assertEquals(listOf(request), matchingRequests("100", request))
        assertTrue(matchingRequests("95", request).isEmpty())
    }

    @Test
    fun `request search ignores a zero total received`() {
        // Legacy rows carry payments with unknown (zero) amounts — a "0" query
        // must not match a request that shows no received total.
        val request = request(
            amount = 5,
            received = listOf(
                CashuRequestPayment("tx-1", amount = 0, receivedAtEpochMillis = 2),
            ),
        )

        assertTrue(matchingRequests("0", request).isEmpty())
    }

    @Test
    fun `request search matches title and memo case-insensitively`() {
        val request = request(amount = null, received = emptyList(), memo = "Coffee money")

        assertEquals(listOf(request), matchingRequests("cashu request", request))
        assertEquals(listOf(request), matchingRequests("COFFEE", request))
    }

    @Test
    fun `transaction search matches title amount and memo`() {
        val transaction = WalletTransaction(
            id = "tx",
            amount = 250,
            type = TransactionType.Outgoing,
            kind = TransactionKind.Lightning,
            dateEpochMillis = 1,
            status = TransactionStatus.Completed,
            memo = "dinner split",
        )

        assertEquals(1, matchingTransactions("lightning paid", transaction).size)
        assertEquals(1, matchingTransactions("250", transaction).size)
        assertEquals(1, matchingTransactions("DINNER", transaction).size)
        assertTrue(matchingTransactions("251", transaction).isEmpty())
    }

    private fun matchingRequests(query: String, vararg requests: CashuRequest): List<CashuRequest> =
        unifiedFiltered(
            transactions = emptyList(),
            requests = requests.toList(),
            filter = HistoryFilter.All,
            query = query,
        ).mapNotNull { (it as? HistoryItem.Req)?.request }

    private fun matchingTransactions(
        query: String,
        vararg transactions: WalletTransaction,
    ): List<WalletTransaction> =
        unifiedFiltered(
            transactions = transactions.toList(),
            requests = emptyList(),
            filter = HistoryFilter.All,
            query = query,
        ).mapNotNull { (it as? HistoryItem.Tx)?.transaction }

    private fun request(
        amount: Long?,
        received: List<CashuRequestPayment>,
        memo: String? = null,
    ) = CashuRequest(
        id = "request",
        encoded = "creqA",
        amount = amount,
        memo = memo,
        createdAtEpochMillis = 1,
        receivedPayments = received,
    )
}
