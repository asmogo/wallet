package com.cashu.me.Core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WalletStartupFailureTest {
    @Test
    fun freshWalletFailureUsesUserFacingCopyAndRetry() {
        val failure = walletStartupFailure(hasStoredWallet = false)

        assertEquals("The wallet couldn't start. Try again in a moment.", failure.message)
        assertEquals("Try Again", failure.recoveryActionLabel)
    }

    @Test
    fun storedWalletFailureOffersSeedRecoveryWithoutTechnicalDetails() {
        val failure = walletStartupFailure(hasStoredWallet = true)

        assertTrue(failure.message.contains("restore it from your seed phrase"))
        assertEquals("Try Again", failure.recoveryActionLabel)
        assertFalse(failure.message.contains("CDK", ignoreCase = true))
        assertFalse(failure.message.contains("FFI", ignoreCase = true))
        assertFalse(failure.message.contains("SQLite", ignoreCase = true))
    }
}
