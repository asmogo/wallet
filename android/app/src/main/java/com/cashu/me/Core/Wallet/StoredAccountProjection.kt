package com.cashu.me.Core

import com.cashu.me.Core.CDK.WalletAccountReference
import kotlinx.coroutines.CancellationException

internal data class StoredBalanceProjection(
    val totals: Map<String, Long>,
    val balances: Map<WalletAccountReference, Long>,
)

/** Commit each currency only when every contributing account was read. */
internal suspend fun projectStoredBalances(
    accounts: List<WalletAccountReference>,
    previousTotals: Map<String, Long>,
    read: suspend (WalletAccountReference) -> Long,
): StoredBalanceProjection {
    val balances = mutableMapOf<WalletAccountReference, Long>()
    val totals = mutableMapOf<String, Long>()
    for ((unit, group) in accounts.distinct().groupBy { it.unit }) {
        var complete = true
        var total = 0L
        for (account in group) {
            try {
                val amount = read(account)
                balances[account] = amount
                total += amount
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                complete = false
            }
        }
        if (complete) totals[unit] = total
        else previousTotals[unit]?.let { totals[unit] = it }
    }
    return StoredBalanceProjection(totals, balances)
}
