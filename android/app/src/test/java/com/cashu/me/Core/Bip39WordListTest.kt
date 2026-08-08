package com.cashu.me.Core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class Bip39WordListTest {

    @Test
    fun wordListHasExactly2048UniqueWords() {
        assertEquals(2048, Bip39WordList.words.size)
    }

    @Test
    fun wordListSpansAbandonToZoo() {
        assertTrue("abandon" in Bip39WordList.words)
        assertTrue("zoo" in Bip39WordList.words)
        assertTrue("cashu" !in Bip39WordList.words)
    }

    @Test
    fun normalizeCollapsesWhitespaceAndLowercases() {
        assertEquals(
            "abandon ability able",
            Bip39WordList.normalize("  Abandon\n ABILITY\t able  "),
        )
    }

    @Test
    fun validPhraseHasNoInvalidIndices() {
        val phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        assertEquals(emptyList<Int>(), Bip39WordList.invalidWordIndices(phrase))
    }

    @Test
    fun invalidWordsAreReportedByNormalizedIndex() {
        // "cashu" (index 1) and "zzz" (index 3) are not BIP-39 words.
        assertEquals(
            listOf(1, 3),
            Bip39WordList.invalidWordIndices("abandon cashu zoo zzz"),
        )
    }

    @Test
    fun casingAndSpacingDoNotFlagValidWords() {
        assertEquals(
            emptyList<Int>(),
            Bip39WordList.invalidWordIndices("  ZOO   Wolf\nabandon "),
        )
    }

    @Test
    fun emptyInputHasNoInvalidIndices() {
        assertEquals(emptyList<Int>(), Bip39WordList.invalidWordIndices("   "))
    }

    // -- completions ---------------------------------------------------------

    /**
     * [Bip39WordList.completions] binary-searches, so lexicographic order is a
     * correctness precondition, not a nicety. Pinned here because the list is
     * generated from the iOS file and a regeneration could silently reorder it.
     */
    @Test
    fun sortedListIsLexicographicAndComplete() {
        assertEquals(2048, Bip39WordList.sorted.size)
        assertEquals(Bip39WordList.sorted.sorted(), Bip39WordList.sorted)
        assertEquals(Bip39WordList.words, Bip39WordList.sorted.toSet())
    }

    @Test
    fun completionsReturnPrefixMatchesInWordlistOrder() {
        assertEquals(listOf("add", "addict", "address"), Bip39WordList.completions("add"))
    }

    /**
     * The reason seed entry never auto-advances on an exact match: "add" is a
     * whole word *and* a prefix of two others, so a match-advance would strand
     * anyone typing "address".
     */
    @Test
    fun anExactWordCanAlsoBeAPrefixOfLongerWords() {
        assertTrue("add" in Bip39WordList.words)
        assertEquals(listOf("add", "addict", "address"), Bip39WordList.completions("add"))
    }

    @Test
    fun completionsRespectTheLimit() {
        assertEquals(listOf("add", "addict"), Bip39WordList.completions("add", limit = 2))
        assertEquals(emptyList<String>(), Bip39WordList.completions("add", limit = 0))
    }

    /** A single letter matches ~130 words — noise, not help. */
    @Test
    fun completionsNeedTwoCharacters() {
        assertEquals(emptyList<String>(), Bip39WordList.completions("a"))
        assertTrue(Bip39WordList.completions("ab").isNotEmpty())
    }

    @Test
    fun completionsIgnoreCasingAndSurroundingSpace() {
        assertEquals(listOf("zebra", "zero"), Bip39WordList.completions("  ZE  ", limit = 2))
    }

    @Test
    fun unknownPrefixCompletesToNothing() {
        assertEquals(emptyList<String>(), Bip39WordList.completions("zzz"))
        assertEquals(emptyList<String>(), Bip39WordList.completions("qx"))
    }

    /** The binary search must not walk off either end of the list. */
    @Test
    fun completionsHandleTheListEdges() {
        assertEquals(listOf("abandon"), Bip39WordList.completions("abandon"))
        assertEquals(listOf("zoo"), Bip39WordList.completions("zoo"))
    }
}
