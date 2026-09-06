package com.cashu.me.Core

import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.Models.MintQuoteState
import com.cashu.me.Models.PaymentMethodKind
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class FocusedMintQuoteMonitorTest {
    @Test
    fun `checks only displayed invoice immediately and stops after issuance`() = runBlocking {
        val monitor = FocusedMintQuoteMonitor()
        val ids = mutableListOf<String>()
        val intervals = mutableListOf<Long>()
        monitor.monitor("displayed", refresh = { id ->
            assertTrue(monitor.isActive)
            ids += id
            quote(PaymentMethodKind.Bolt11, paid = 21, issued = if (ids.size == 1) 0 else 21)
        }, sleep = { intervals += it })

        assertEquals(listOf("displayed", "displayed"), ids)
        assertEquals(listOf(2_000L), intervals)
        assertFalse(monitor.isActive)
    }

    @Test
    fun `previously paid reusable offer keeps checking for later payments`() = runBlocking {
        val monitor = FocusedMintQuoteMonitor()
        var checks = 0
        val intervals = mutableListOf<Long>()
        try {
            monitor.monitor("displayed", refresh = {
                checks++
                val amount = if (checks == 1) 10L else 31L
                quote(PaymentMethodKind.Bolt12, paid = amount, issued = amount)
            }, sleep = {
                intervals += it
                if (intervals.size == 2) throw CancellationException()
            })
        } catch (_: CancellationException) {
            // The screen closes after observing the second payment.
        }
        assertEquals(2, checks)
        assertEquals(listOf(2_000L, 2_000L), intervals)
        assertFalse(monitor.isActive)
    }

    @Test
    fun `cancellation releases focus and reopening checks immediately`() = runBlocking {
        val monitor = FocusedMintQuoteMonitor()
        val sleeping = CompletableDeferred<Unit>()
        val ids = mutableListOf<String>()
        val job = launch {
            monitor.monitor("first", refresh = { id ->
                ids += id
                null // Missing or temporarily unavailable quotes keep retrying.
            }, sleep = {
                sleeping.complete(Unit)
                awaitCancellation()
            })
        }
        withTimeout(2_000) { sleeping.await() }
        assertTrue(monitor.isActive)
        job.cancelAndJoin()
        assertFalse(monitor.isActive)

        monitor.monitor("second", refresh = { id ->
            ids += id
            quote(PaymentMethodKind.Bolt11, paid = 21, issued = 21)
        }, sleep = { fail("Settled invoice must stop") })
        assertEquals(listOf("first", "second"), ids)
        assertFalse(monitor.isActive)
    }

    @Test
    fun `expired unpaid invoice stops but paid unissued invoice keeps retrying`() = runBlocking {
        val monitor = FocusedMintQuoteMonitor()
        monitor.monitor("displayed", refresh = {
            quote(PaymentMethodKind.Bolt11, expiry = 1)
        }, sleep = { fail("Expired unpaid invoice must stop") })

        var checks = 0
        monitor.monitor("displayed", refresh = {
            checks++
            quote(PaymentMethodKind.Bolt11, paid = 21, issued = if (checks == 1) 0 else 21, expiry = 1)
        }, sleep = {})
        assertEquals(2, checks)
    }

    @Test
    fun `onchain deposit keeps checking after expiry`() = runBlocking {
        val monitor = FocusedMintQuoteMonitor()
        var checks = 0
        monitor.monitor("displayed", refresh = {
            checks++
            val amount = if (checks == 1) 0L else 21L
            quote(PaymentMethodKind.Onchain, paid = amount, issued = amount, expiry = 1)
        }, sleep = { assertEquals(10_000L, it) })
        assertEquals(2, checks)
        assertFalse(monitor.isActive)
    }

    private fun quote(
        method: PaymentMethodKind,
        paid: Long = 0,
        issued: Long = 0,
        expiry: Long? = null,
    ) = MintQuoteInfo(
        id = "displayed", request = "request", amount = null, paymentMethod = method,
        state = if (paid > issued) MintQuoteState.Paid else if (paid > 0) MintQuoteState.Issued else MintQuoteState.Pending,
        expiryEpochSeconds = expiry, amountPaid = paid, amountIssued = issued,
    )
}
