package com.cashu.me.ui.send

import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class CashuRequestFeeEstimateTest {
    private val key = CashuRequestFeeEstimateKey(
        request = "creqA",
        amountSats = 21L,
        mintUrl = "https://mint.example",
    )

    @Test
    fun loadingReservesEstimateForTheCurrentPayment() {
        assertEquals(
            CashuRequestFeePresentation(
                value = "",
                loading = true,
                valueMonospaced = true,
            ),
            CashuRequestFeeEstimate.Loading(key).presentation { "$it sat" },
        )
    }

    @Test
    fun zeroFeeIsPresentedAsNoFee() = runBlocking {
        val result = resolveCashuRequestFeeEstimate(key) { _, _ -> 0L }

        assertEquals(CashuRequestFeeEstimate.NoFee(key), result)
        assertEquals("No fee", result.presentation { "$it sat" }.value)
    }

    @Test
    fun nonzeroFeePreservesTheEstimatedAmount() = runBlocking {
        val result = resolveCashuRequestFeeEstimate(key) { amount, mintUrl ->
            assertEquals(21L, amount)
            assertEquals("https://mint.example", mintUrl)
            3L
        }

        assertEquals(CashuRequestFeeEstimate.Amount(key, 3L), result)
        assertEquals("3 sat", result.presentation { "$it sat" }.value)
    }

    @Test
    fun estimationFailureIsUnavailableAndNeverZero() = runBlocking {
        val result = resolveCashuRequestFeeEstimate(key) { _, _ ->
            throw IOException("mint unavailable")
        }

        assertEquals(CashuRequestFeeEstimate.Unavailable(key), result)
        assertEquals("Unavailable", result.presentation { "$it sat" }.value)
    }

    @Test
    fun staleResultCannotReplaceNewRequestLoadingState() {
        val nextKey = key.copy(request = "creqB", amountSats = 34L)
        val current = CashuRequestFeeEstimate.Loading(nextKey)
        val stale = CashuRequestFeeEstimate.Amount(key, 3L)

        assertEquals(current, current.acceptIfCurrent(stale))
    }

    @Test
    fun cancellationIsPropagatedInsteadOfBecomingUnavailable() {
        try {
            runBlocking {
                resolveCashuRequestFeeEstimate(key) { _, _ ->
                    throw CancellationException("route changed")
                }
            }
            fail("Expected cancellation")
        } catch (_: CancellationException) {
            // Expected: LaunchedEffect owns cancellation and starts the new key.
        }
    }
}
