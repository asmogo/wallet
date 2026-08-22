package com.cashu.me.Core

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Whole-number-first entry. These vectors are mirrored verbatim in the iOS
 * suite (CashuWalletTests/MintServiceTests + CI/IntegrationTests) — the raw
 * string is the contract between the two platforms, so they must agree.
 */
class UnitAmountEntryTest {
    @Test
    fun zeroDecimalEntryMatchesPlainIntegerBehavior() {
        assertEquals("5", UnitAmountEntry.append("5", "", 0))
        assertEquals("5", UnitAmountEntry.append("5", "0", 0))
        assertEquals("50", UnitAmountEntry.append("0", "5", 0))
        assertEquals("5", UnitAmountEntry.backspace("50"))
        assertEquals(500L, UnitAmountEntry.baseUnits("500", 0))
    }

    /** The regression this whole change exists for: "21" is $21, not $0.21. */
    @Test
    fun digitsBuildTheIntegerPartLeftToRight() {
        var raw = ""
        raw = UnitAmountEntry.append("2", raw, 2)
        assertEquals("2", raw)
        raw = UnitAmountEntry.append("1", raw, 2)
        assertEquals("21", raw)
        assertEquals(2_100L, UnitAmountEntry.baseUnits(raw, 2))
    }

    @Test
    fun separatorArmsTheFraction() {
        var raw = UnitAmountEntry.append("2", "", 2)
        raw = UnitAmountEntry.append("1", raw, 2)
        raw = UnitAmountEntry.appendSeparator(raw, 2)
        assertEquals("21.", raw)
        assertEquals(2_100L, UnitAmountEntry.baseUnits(raw, 2))
        raw = UnitAmountEntry.append("5", raw, 2)
        assertEquals("21.5", raw)
        assertEquals(2_150L, UnitAmountEntry.baseUnits(raw, 2))
        raw = UnitAmountEntry.append("0", raw, 2)
        assertEquals("21.50", raw)
        assertEquals(2_150L, UnitAmountEntry.baseUnits(raw, 2))
    }

    @Test
    fun separatorOnAnEmptyPadOpensWithALeadingZero() {
        val raw = UnitAmountEntry.appendSeparator("", 2)
        assertEquals("0.", raw)
        assertEquals(0L, UnitAmountEntry.baseUnits(raw, 2))
        assertEquals(50L, UnitAmountEntry.baseUnits(UnitAmountEntry.append("5", raw, 2), 2))
    }

    @Test
    fun separatorIsInertWhenItCannotApply() {
        // Already armed.
        assertEquals("21.5", UnitAmountEntry.appendSeparator("21.5", 2))
        // No fraction exists for a 0-decimal unit, and no key is rendered for it.
        assertEquals("21", UnitAmountEntry.appendSeparator("21", 0))
    }

    @Test
    fun fractionStopsAtTheUnitsPrecision() {
        assertEquals("21.50", UnitAmountEntry.append("7", "21.50", 2))
        assertEquals(2_150L, UnitAmountEntry.baseUnits("21.50", 2))
    }

    @Test
    fun backspaceDropsCharactersIncludingTheSeparator() {
        assertEquals("21.5", UnitAmountEntry.backspace("21.50"))
        assertEquals("21.", UnitAmountEntry.backspace("21.5"))
        assertEquals("21", UnitAmountEntry.backspace("21."))
        assertEquals("2", UnitAmountEntry.backspace("21"))
        assertEquals("", UnitAmountEntry.backspace("2"))
    }

    @Test
    fun entryStringSeedsInMinimalForm() {
        assertEquals("", UnitAmountEntry.entryString(0, 2))
        assertEquals("6", UnitAmountEntry.entryString(600, 2))
        assertEquals("6.10", UnitAmountEntry.entryString(610, 2))
        assertEquals("6.17", UnitAmountEntry.entryString(617, 2))
        assertEquals("0.09", UnitAmountEntry.entryString(9, 2))
        assertEquals("1234", UnitAmountEntry.entryString(1_234, 0))
    }

    @Test
    fun seededStringsRoundTripThroughBaseUnits() {
        for (value in listOf(1L, 9L, 600L, 610L, 617L, 2_150L, 99_999_999_999L)) {
            assertEquals(value, UnitAmountEntry.baseUnits(UnitAmountEntry.entryString(value, 2), 2))
        }
        // A seeded whole and its padded twin are the same amount.
        assertEquals(600L, UnitAmountEntry.baseUnits("6", 2))
        assertEquals(600L, UnitAmountEntry.baseUnits("6.00", 2))
    }

    @Test
    fun integerPartStopsAtTwelveDigits() {
        val maxed = "999999999999"
        assertEquals(maxed, UnitAmountEntry.append("9", maxed, 2))
        assertEquals(maxed, UnitAmountEntry.append("9", maxed, 0))
        // Still extendable into the fraction.
        assertEquals("999999999999.9", UnitAmountEntry.append("9", "999999999999.", 2))
    }

    /**
     * An over-long raw can only arrive pre-seeded; it must clamp rather than
     * parse-fail into a silent zero.
     */
    @Test
    fun oversizedRawClampsInsteadOfCollapsingToZero() {
        assertEquals(99_999_999_999_999L, UnitAmountEntry.baseUnits("99999999999999999999", 2))
        assertEquals(999_999_999_999L, UnitAmountEntry.baseUnits("99999999999999999999", 0))
    }

    @Test
    fun nonDigitKeysAreIgnored() {
        assertEquals("5.00", UnitAmountEntry.append("x", "5.00", 2))
        assertEquals("500", UnitAmountEntry.append("x", "500", 0))
        // The separator has its own entry point; it is not a digit.
        assertEquals("500", UnitAmountEntry.append(".", "500", 2))
    }
}
