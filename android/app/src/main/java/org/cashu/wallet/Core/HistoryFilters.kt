package org.cashu.wallet.Core

import kotlin.math.ceil
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.WeekFields
import java.util.Locale
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.WalletTransaction

enum class HistoryFilter(val label: String) {
    All("All"),
    Pending("Pending"),
    Completed("Completed"),
}

const val HistoryPageSize = 10

data class HistorySection(
    val title: String,
    val transactions: List<WalletTransaction>,
)

fun filterTransactions(
    transactions: List<WalletTransaction>,
    filter: HistoryFilter,
): List<WalletTransaction> = when (filter) {
    HistoryFilter.All -> transactions
    HistoryFilter.Pending -> transactions.filter { it.status == TransactionStatus.Pending }
    HistoryFilter.Completed -> transactions.filter { it.status == TransactionStatus.Completed }
}

fun maxHistoryPages(count: Int, pageSize: Int = HistoryPageSize): Int =
    maxOf(1, ceil(count.toDouble() / pageSize.toDouble()).toInt())

fun paginateTransactions(
    transactions: List<WalletTransaction>,
    page: Int,
    pageSize: Int = HistoryPageSize,
): List<WalletTransaction> {
    val safePage = page.coerceAtLeast(1)
    val start = (safePage - 1) * pageSize
    if (start >= transactions.size) return emptyList()
    return transactions.subList(start, minOf(start + pageSize, transactions.size))
}

fun pendingTokenRefreshMessage(claimedCount: Int): String =
    if (claimedCount == 1) {
        "1 pending token was claimed."
    } else if (claimedCount > 1) {
        "$claimedCount pending tokens were claimed."
    } else {
        "No pending token changes."
    }

fun pendingMintQuoteRefreshMessage(mintedCount: Int): String =
    if (mintedCount == 1) {
        "1 paid quote was minted."
    } else if (mintedCount > 1) {
        "$mintedCount paid quotes were minted."
    } else {
        "No pending quote changes."
    }

fun groupTransactionsByDate(
    transactions: List<WalletTransaction>,
    nowEpochMillis: Long,
    zoneId: ZoneId = ZoneId.systemDefault(),
): List<HistorySection> {
    if (transactions.isEmpty()) return emptyList()

    val now = Instant.ofEpochMilli(nowEpochMillis).atZone(zoneId).toLocalDate()
    val yesterday = now.minusDays(1)
    val currentWeek = weekKey(now)
    val currentMonth = now.withDayOfMonth(1)

    val buckets = linkedMapOf(
        "Today" to mutableListOf<WalletTransaction>(),
        "Yesterday" to mutableListOf(),
        "This Week" to mutableListOf(),
        "This Month" to mutableListOf(),
        "Earlier" to mutableListOf(),
    )

    transactions.forEach { transaction ->
        val date = Instant.ofEpochMilli(transaction.dateEpochMillis).atZone(zoneId).toLocalDate()
        val bucket = when {
            date == now -> "Today"
            date == yesterday -> "Yesterday"
            weekKey(date) == currentWeek -> "This Week"
            date.withDayOfMonth(1) == currentMonth -> "This Month"
            else -> "Earlier"
        }
        buckets.getValue(bucket).add(transaction)
    }

    return buckets.mapNotNull { (title, items) ->
        items.takeIf { it.isNotEmpty() }?.let { HistorySection(title, it) }
    }
}

private fun weekKey(date: LocalDate): Pair<Int, Int> {
    val weekFields = WeekFields.of(Locale.getDefault())
    return date.get(weekFields.weekBasedYear()) to date.get(weekFields.weekOfWeekBasedYear())
}
