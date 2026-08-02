package com.cashu.me.ui.home

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeRuntimeReadinessTest {
    @Test
    fun paymentActionsStayDisabledWhileRuntimeIsPreparing() {
        val availability = homePaymentActionAvailability(isRuntimeReady = false)

        assertTrue(availability.isPreparingWallet)
        assertFalse(availability.receiveEnabled)
        assertFalse(availability.sendEnabled)
    }

    @Test
    fun paymentActionsUseExistingPrerequisitesAfterRuntimeIsReady() {
        val availability = homePaymentActionAvailability(isRuntimeReady = true)

        assertFalse(availability.isPreparingWallet)
        assertTrue(availability.receiveEnabled)
        assertTrue(availability.sendEnabled)
    }

    @Test
    fun bothActionsStayAvailableWithoutMintOnceRuntimeIsReady() {
        // Readiness is the only gate: with no mint, Send opens the connect-a-mint
        // surface rather than sitting disabled (iOS parity).
        val availability = homePaymentActionAvailability(isRuntimeReady = true)

        assertFalse(availability.isPreparingWallet)
        assertTrue(availability.receiveEnabled)
        assertTrue(availability.sendEnabled)
    }
}
