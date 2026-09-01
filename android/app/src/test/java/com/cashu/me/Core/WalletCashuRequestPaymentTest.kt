package com.cashu.me.Core

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class WalletCashuRequestPaymentTest {
    @Test
    fun payCashuPaymentRequestPaysThenRefreshesBalanceAndTransactions() = runBlocking {
        val events = mutableListOf<String>()

        payCashuPaymentRequestAndRefresh(
            encoded = "creq1payment",
            customAmountSats = 21,
            preferredMintURL = "https://mint.example",
            payCashuPaymentRequest = { encoded, amount, mintUrl ->
                events += "pay:$encoded:$amount:$mintUrl"
            },
            refreshBalance = { events += "refreshBalance" },
            loadTransactions = { events += "loadTransactions" },
        )

        assertEquals(
            listOf(
                "pay:creq1payment:21:https://mint.example",
                "refreshBalance",
                "loadTransactions",
            ),
            events,
        )
    }

    @Test
    fun paymentFailureDoesNotRefreshBalanceOrTransactions() {
        val events = mutableListOf<String>()

        val result = runCatching {
            runBlocking {
                payCashuPaymentRequestAndRefresh(
                    encoded = "creq1payment",
                    customAmountSats = 21,
                    preferredMintURL = "https://mint.example",
                    payCashuPaymentRequest = { _, _, _ ->
                        events += "pay"
                        error("payment failed")
                    },
                    refreshBalance = { events += "refreshBalance" },
                    loadTransactions = { events += "loadTransactions" },
                )
            }
        }

        assertEquals("payment failed", result.exceptionOrNull()?.message)
        assertEquals(listOf("pay"), events)
    }
}
