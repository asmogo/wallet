package org.cashu.wallet.Core

import java.time.LocalDateTime
import java.time.ZoneId
import org.cashu.wallet.Models.TransactionKind
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.TransactionType
import org.cashu.wallet.Models.WalletTransaction
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HistoryFiltersTest {
    @Test
    fun filtersPendingAndCompletedTransactions() {
        val pending = transaction("pending", TransactionStatus.Pending)
        val completed = transaction("completed", TransactionStatus.Completed)
        val failed = transaction("failed", TransactionStatus.Failed)
        val transactions = listOf(pending, completed, failed)

        assertEquals(transactions, filterTransactions(transactions, HistoryFilter.All))
        assertEquals(listOf(pending), filterTransactions(transactions, HistoryFilter.Pending))
        assertEquals(listOf(completed), filterTransactions(transactions, HistoryFilter.Completed))
    }

    @Test
    fun maxPagesNeverDropsBelowOne() {
        assertEquals(1, maxHistoryPages(0))
        assertEquals(1, maxHistoryPages(10))
        assertEquals(2, maxHistoryPages(11))
    }

    @Test
    fun paginatesTransactionsByPageSize() {
        val transactions = (1..12).map { transaction(it.toString(), TransactionStatus.Completed) }

        assertEquals((1..10).map { it.toString() }, paginateTransactions(transactions, page = 1).map { it.id })
        assertEquals(listOf("11", "12"), paginateTransactions(transactions, page = 2).map { it.id })
        assertTrue(paginateTransactions(transactions, page = 3).isEmpty())
    }

    @Test
    fun formatsPendingTokenRefreshMessages() {
        assertEquals("No pending token changes.", pendingTokenRefreshMessage(0))
        assertEquals("1 pending token was claimed.", pendingTokenRefreshMessage(1))
        assertEquals("2 pending tokens were claimed.", pendingTokenRefreshMessage(2))
    }

    @Test
    fun formatsPendingMintQuoteRefreshMessages() {
        assertEquals("No pending quote changes.", pendingMintQuoteRefreshMessage(0))
        assertEquals("1 paid quote was minted.", pendingMintQuoteRefreshMessage(1))
        assertEquals("2 paid quotes were minted.", pendingMintQuoteRefreshMessage(2))
    }

    @Test
    fun groupsTransactionsIntoSwiftStyleDateBuckets() {
        val zone = ZoneId.of("UTC")
        val now = LocalDateTime.of(2026, 5, 21, 12, 0).atZone(zone).toInstant().toEpochMilli()
        val transactions = listOf(
            transaction("today", TransactionStatus.Completed, epochMillis(2026, 5, 21, zone)),
            transaction("yesterday", TransactionStatus.Completed, epochMillis(2026, 5, 20, zone)),
            transaction("week", TransactionStatus.Completed, epochMillis(2026, 5, 18, zone)),
            transaction("month", TransactionStatus.Completed, epochMillis(2026, 5, 2, zone)),
            transaction("earlier", TransactionStatus.Completed, epochMillis(2026, 4, 30, zone)),
        )

        val groups = groupTransactionsByDate(transactions, nowEpochMillis = now, zoneId = zone)

        assertEquals(listOf("Today", "Yesterday", "This Week", "This Month", "Earlier"), groups.map { it.title })
        assertEquals(listOf("today"), groups[0].transactions.map { it.id })
        assertEquals(listOf("yesterday"), groups[1].transactions.map { it.id })
        assertEquals(listOf("week"), groups[2].transactions.map { it.id })
        assertEquals(listOf("month"), groups[3].transactions.map { it.id })
        assertEquals(listOf("earlier"), groups[4].transactions.map { it.id })
    }

    private fun transaction(
        id: String,
        status: TransactionStatus,
        dateEpochMillis: Long = 1_700_000_000,
    ) = WalletTransaction(
        id = id,
        amount = 1,
        type = TransactionType.Incoming,
        kind = TransactionKind.Ecash,
        dateEpochMillis = dateEpochMillis,
        status = status,
    )

    private fun epochMillis(year: Int, month: Int, day: Int, zone: ZoneId): Long =
        LocalDateTime.of(year, month, day, 12, 0).atZone(zone).toInstant().toEpochMilli()
}
