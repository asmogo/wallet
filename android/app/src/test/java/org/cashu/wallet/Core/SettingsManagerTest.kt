package org.cashu.wallet.Core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class SettingsManagerTest {
    @Test
    fun p2pkSendNormalizationAcceptsXOnlyHex() {
        val xOnly = "a".repeat(64)

        assertEquals(
            "02$xOnly",
            SettingsManager.normalizeP2PKPublicKeyForSend(xOnly),
        )
    }

    @Test
    fun p2pkSendNormalizationAcceptsCompressedHex() {
        val compressed = "03${"b".repeat(64)}"

        assertEquals(
            compressed,
            SettingsManager.normalizeP2PKPublicKeyForSend(" $compressed "),
        )
    }

    @Test
    fun p2pkSendNormalizationRejectsInvalidKeys() {
        assertThrows(IllegalArgumentException::class.java) {
            SettingsManager.normalizeP2PKPublicKeyForSend("04${"c".repeat(64)}")
        }
    }

    @Test
    fun p2pkSendNormalizationTreatsBlankAsAbsent() {
        assertNull(SettingsManager.normalizeP2PKPublicKeyForSend(" "))
    }

    @Test
    fun p2pkComparisonNormalizationDropsCompressedPrefix() {
        val xOnly = "d".repeat(64)

        assertEquals(
            xOnly,
            SettingsManager.normalizeP2PKPublicKeyForComparison("02$xOnly"),
        )
    }
}
