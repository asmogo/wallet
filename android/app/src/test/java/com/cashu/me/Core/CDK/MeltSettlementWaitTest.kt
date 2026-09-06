package com.cashu.me.Core.CDK

import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.cashudevkit.Amount as CdkAmount
import org.cashudevkit.FinalizedMelt as CdkFinalizedMelt
import org.cashudevkit.PaymentMethod as CdkPaymentMethod
import org.cashudevkit.QuoteState as CdkQuoteState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The in-lane settlement wait for async (NUT-05) lightning melts: CDK's
 * `wait()` does the polling; the gateway only gates by method and bounds the
 * wait with a fallback cap. Driven with plain closures — `FinalizedMelt` is a
 * data class, no CDK runtime needed (iOS `MeltSettlementWaitTests` parity).
 */
class MeltSettlementWaitTest {

    private fun finalized(state: CdkQuoteState = CdkQuoteState.PAID) = CdkFinalizedMelt(
        quoteId = "quote",
        state = state,
        preimage = "preimage",
        change = null,
        amount = CdkAmount(10uL),
        feePaid = CdkAmount(2uL),
    )

    @Test
    fun `fast settlement returns the finalized melt`() = runBlocking {
        val result = awaitLightningSettlementOrNull(method = CdkPaymentMethod.Bolt11) {
            finalized()
        }
        assertEquals("preimage", result?.preimage)
        assertEquals(2uL, result?.feePaid?.value)
    }

    @Test
    fun `bolt12 waits too`() = runBlocking {
        val result = awaitLightningSettlementOrNull(method = CdkPaymentMethod.Bolt12) {
            finalized(CdkQuoteState.ISSUED)
        }
        assertEquals(CdkQuoteState.ISSUED, result?.state)
    }

    @Test
    fun `onchain and unknown methods never wait`() = runBlocking {
        assertNull(
            awaitLightningSettlementOrNull(method = CdkPaymentMethod.Onchain) {
                error("must not be invoked for on-chain")
            },
        )
        assertNull(
            awaitLightningSettlementOrNull(method = null) {
                error("must not be invoked without a method")
            },
        )
    }

    @Test
    fun `cap expiry falls back to pending`() = runBlocking {
        val result = awaitLightningSettlementOrNull(
            method = CdkPaymentMethod.Bolt11,
            waitMs = 50,
        ) {
            delay(5_000)
            finalized()
        }
        assertNull(result)
    }

    @Test
    fun `an ambiguous wait failure reaches status recovery`() = runBlocking {
        try {
            awaitLightningSettlementOrNull(method = CdkPaymentMethod.Bolt11) {
                throw IllegalStateException("transport died")
            }
            org.junit.Assert.fail("The caller must reconcile an ambiguous failure")
        } catch (error: IllegalStateException) {
            assertEquals("transport died", error.message)
        }
    }
}
