package org.cashu.wallet.Core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MnemonicInputTest {
    @Test
    fun normalizesWhitespaceAndCase() {
        assertEquals(
            "abandon ability able",
            MnemonicInput.normalize("  Abandon\nABILITY   able  "),
        )
    }

    @Test
    fun detectsSupportedWordCounts() {
        assertTrue(MnemonicInput.hasSupportedWordCount((1..12).joinToString(" ") { "word" }))
        assertTrue(MnemonicInput.hasSupportedWordCount((1..24).joinToString(" ") { "word" }))
        assertFalse(MnemonicInput.hasSupportedWordCount((1..15).joinToString(" ") { "word" }))
        assertFalse(MnemonicInput.hasSupportedWordCount((1..18).joinToString(" ") { "word" }))
        assertFalse(MnemonicInput.hasSupportedWordCount((1..21).joinToString(" ") { "word" }))
        assertFalse(MnemonicInput.hasSupportedWordCount((1..13).joinToString(" ") { "word" }))
    }

    @Test
    fun exposesSwiftCompatibleWordCountLabel() {
        assertEquals("12 or 24", MnemonicInput.supportedWordCountLabel)
    }

    @Test
    fun matchesNormalizedPhrases() {
        assertTrue(MnemonicInput.matches("Abandon  ability", "abandon ability"))
        assertFalse(MnemonicInput.matches("abandon ability", "abandon able"))
    }
}
