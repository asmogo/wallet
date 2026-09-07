package com.cashu.me.Core

import com.cashu.me.Core.CDK.WalletAccountReference
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class StoredAccountProjectionTest {
    private val a = WalletAccountReference("https://a.example", "usd")
    private val b = WalletAccountReference("https://b.example", "usd")
    private val sat = WalletAccountReference(a.mintUrl, "sat")

    @Test fun failedAccountKeepsTheWholePreviousCurrencyTotal() = runBlocking {
        val result = projectStoredBalances(listOf(a, b, sat), mapOf("usd" to 500L, "sat" to 1L)) {
            when (it) { a -> 200L; b -> error("Storage unavailable"); else -> 30L }
        }
        assertEquals(mapOf("usd" to 500L, "sat" to 30L), result.totals)
        assertEquals(200L, result.balances[a])
    }

    @Test fun successfulRetryReplacesPreviousTotalAndDeduplicatesAccounts() = runBlocking {
        val result = projectStoredBalances(listOf(a, b, a), mapOf("usd" to 500L)) { 200L }
        assertEquals(mapOf("usd" to 400L), result.totals)
    }

    @Test fun zeroBalanceHistoricalAccountRemainsRepresented() = runBlocking {
        val result = projectStoredBalances(listOf(a), mapOf("usd" to 500L)) { 0L }
        assertEquals(mapOf("usd" to 0L), result.totals)
    }

    @Test(expected = CancellationException::class)
    fun cancellationDoesNotPublishAPartialRefresh() = runBlocking {
        projectStoredBalances(listOf(a), emptyMap()) { throw CancellationException() }
        Unit
    }
}
