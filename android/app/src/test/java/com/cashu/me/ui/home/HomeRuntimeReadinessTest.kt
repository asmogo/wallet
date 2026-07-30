package com.cashu.me.ui.home

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeRuntimeReadinessTest {
    @Test
    fun paymentActionsStayDisabledWhileRuntimeIsPreparing() {
        val availability = homePaymentActionAvailability(
            isRuntimeReady = false,
            hasActiveMint = true,
        )

        assertTrue(availability.isPreparingWallet)
        assertFalse(availability.receiveEnabled)
        assertFalse(availability.sendEnabled)
    }

    @Test
    fun paymentActionsUseExistingPrerequisitesAfterRuntimeIsReady() {
        val availability = homePaymentActionAvailability(
            isRuntimeReady = true,
            hasActiveMint = true,
        )

        assertFalse(availability.isPreparingWallet)
        assertTrue(availability.receiveEnabled)
        assertTrue(availability.sendEnabled)
    }

    @Test
    fun receiveStaysAvailableWithoutMintOnceRuntimeIsReady() {
        val availability = homePaymentActionAvailability(
            isRuntimeReady = true,
            hasActiveMint = false,
        )

        assertFalse(availability.isPreparingWallet)
        assertTrue(availability.receiveEnabled)
        assertFalse(availability.sendEnabled)
    }
}
