package com.cashu.me.Core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReceivedPaymentEventTest {
    @Test
    fun onlyPositiveConfirmedCreditsCreateAReceiveBeat() {
        assertNull(
            confirmedReceivedPaymentEvent(
                amount = 0,
                unit = "sat",
                confirmationOwner = ReceiveConfirmationOwner.Home,
            ),
        )
        assertNull(
            confirmedReceivedPaymentEvent(
                amount = -21,
                unit = "sat",
                confirmationOwner = ReceiveConfirmationOwner.Home,
            ),
        )

        val event = confirmedReceivedPaymentEvent(
            amount = 21,
            unit = "SAT",
            confirmationOwner = ReceiveConfirmationOwner.Home,
        )
        assertEquals(21L, event?.amount)
        assertEquals("sat", event?.unit)
    }

    @Test
    fun homeOwnsHapticOnlyWhenNoReceiveFlowOwnsConfirmation() {
        val inFlow = confirmedReceivedPaymentEvent(
            amount = 21,
            unit = "sat",
            confirmationOwner = ReceiveConfirmationOwner.InFlow,
        )
        val background = confirmedReceivedPaymentEvent(
            amount = 21,
            unit = "sat",
            confirmationOwner = ReceiveConfirmationOwner.Home,
        )

        assertFalse(checkNotNull(inFlow).homeOwnsSuccessHaptic)
        assertTrue(checkNotNull(background).homeOwnsSuccessHaptic)
    }
}
