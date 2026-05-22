package org.cashu.wallet.Core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class AppLoggerTest {
    @Test
    fun privacySafeMessageRedactsNostrPrivateKeys() {
        val message = AppLogger.privacySafeMessage(
            "imported nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq",
        )

        assertEquals("imported <redacted-nsec>", message)
    }

    @Test
    fun privacySafeMessageRedactsLabeledSecrets() {
        val message = AppLogger.privacySafeMessage(
            "seed phrase: abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
        )

        assertFalse(message.contains("abandon"))
        assertEquals("seed phrase=<redacted>", message)
    }
}
