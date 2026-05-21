package org.cashu.wallet.Core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class QuoteExpiryFormatterTest {
    @Test
    fun nullOrZeroExpiryIsHidden() {
        assertNull(quoteExpiryText(null, nowEpochSeconds = 100))
        assertNull(quoteExpiryText(0, nowEpochSeconds = 100))
        assertNull(quoteExpiryText(LOCAL_NEVER_EXPIRES_EPOCH_SECONDS, nowEpochSeconds = 100))
    }

    @Test
    fun expiredQuoteIsMarkedExpired() {
        assertEquals("Expired", quoteExpiryText(99, nowEpochSeconds = 100))
    }

    @Test
    fun formatsSecondsMinutesAndHours() {
        assertEquals("45s", quoteExpiryText(145, nowEpochSeconds = 100))
        assertEquals("2m 5s", quoteExpiryText(225, nowEpochSeconds = 100))
        assertEquals("1h 1m", quoteExpiryText(3_760, nowEpochSeconds = 100))
    }
}
