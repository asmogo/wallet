package com.cashu.me.ui.receive

import com.cashu.me.Core.NfcReceive.NfcReceivePhase
import com.cashu.me.Models.CashuRequestPayment
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CashuRequestPaymentObservationTest {
    @Test
    fun `existing payments establish baseline without replaying success`() {
        assertNull(newestUnseenPayment(null, listOf(payment("existing"))))
    }

    @Test
    fun `new payment is returned after baseline`() {
        val received = newestUnseenPayment(
            observedPaymentIds = listOf("existing"),
            currentPayments = listOf(payment("existing"), payment("new", amount = 19)),
        )

        assertEquals("new", received?.transactionId)
        assertEquals(19L, received?.amount)
    }

    @Test
    fun `first payment is returned after an empty request baseline`() {
        val received = newestUnseenPayment(
            observedPaymentIds = emptyList(),
            currentPayments = listOf(payment("first", amount = 19)),
        )

        assertEquals("first", received?.transactionId)
    }

    @Test
    fun `unchanged payment snapshot does not replay success`() {
        assertNull(
            newestUnseenPayment(
                observedPaymentIds = listOf("existing"),
                currentPayments = listOf(payment("existing")),
            ),
        )
    }

    @Test
    fun `newest unseen payment wins when updates arrive together`() {
        val received = newestUnseenPayment(
            observedPaymentIds = listOf("existing"),
            currentPayments = listOf(
                payment("existing"),
                payment("new-1"),
                payment("new-2"),
            ),
        )

        assertEquals("new-2", received?.transactionId)
    }

    @Test
    fun `same request can present a second payment without replaying the first`() {
        val first = payment("first", amount = 21)
        val second = payment("second", amount = 21)
        assertEquals(first, newestUnseenPayment(emptyList(), listOf(first)))
        assertNull(newestUnseenPayment(listOf(first.transactionId), listOf(first)))
        assertEquals(second, newestUnseenPayment(listOf(first.transactionId), listOf(first, second)))
        assertNull(newestUnseenPayment(listOf("first", "second"), listOf(first, second)))
    }

    @Test
    fun `NFC session stays mounted while payment record and success state hand off`() {
        assertTrue(shouldKeepNfcSessionMounted(false, NfcReceivePhase.Redeeming))
        assertTrue(shouldKeepNfcSessionMounted(false, NfcReceivePhase.Success))
        assertFalse(shouldKeepNfcSessionMounted(false, NfcReceivePhase.Inactive))
        assertTrue(shouldKeepNfcSessionMounted(true, NfcReceivePhase.Waiting))
    }

    private fun payment(id: String, amount: Long = 1) = CashuRequestPayment(
        transactionId = id,
        amount = amount,
        receivedAtEpochMillis = 1,
    )
}
