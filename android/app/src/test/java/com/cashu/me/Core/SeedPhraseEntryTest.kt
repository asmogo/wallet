package com.cashu.me.Core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The advance rule is the subtle part of word-by-word seed entry, so it is
 * pinned here rather than left to the UI. iOS twin: `SeedPhraseEntryTests`.
 */
class SeedPhraseEntryTest {

    private val vector = List(11) { "abandon" } + "about"

    private fun entryWith(vararg typed: String): SeedPhraseEntry {
        var entry = SeedPhraseEntry()
        typed.forEach { entry = entry.typed("$it ").entry }
        return entry
    }

    // -- committing ----------------------------------------------------------

    @Test
    fun spaceCommitsTheWordAndAdvances() {
        val result = SeedPhraseEntry().typed("abandon ")
        assertEquals(CommitOutcome.Advanced, result.outcome)
        assertEquals("abandon", result.entry.words[0])
        assertEquals(1, result.entry.index)
        assertEquals("", result.entry.draft)
    }

    @Test
    fun typingWithoutASpaceCommitsNothing() {
        val result = SeedPhraseEntry().typed("abando")
        assertEquals(CommitOutcome.None, result.outcome)
        assertEquals(0, result.entry.index)
        assertEquals("abando", result.entry.draft)
    }

    @Test
    fun theNextKeyCommitsWhatIsInTheField() {
        val result = SeedPhraseEntry().typed("abandon").entry.commit()
        assertEquals(CommitOutcome.Advanced, result.outcome)
        assertEquals("abandon", result.entry.words[0])
    }

    @Test
    fun committingAnEmptyFieldIsIgnored() {
        assertEquals(CommitOutcome.Ignored, SeedPhraseEntry().commit().outcome)
    }

    /**
     * The whole reason exact matches never auto-advance: "add" is a word *and*
     * a prefix of "addict" and "address". Committing it must yield "add".
     */
    @Test
    fun anExactWordCommitsAsItselfEvenWhenLongerWordsShareThePrefix() {
        val result = SeedPhraseEntry().typed("add ")
        assertEquals(CommitOutcome.Advanced, result.outcome)
        assertEquals("add", result.entry.words[0])
    }

    @Test
    fun aUniquePrefixCompletesOnCommit() {
        val result = SeedPhraseEntry().typed("abando ")
        assertEquals(CommitOutcome.Advanced, result.outcome)
        assertEquals("abandon", result.entry.words[0])
    }

    @Test
    fun anAmbiguousPrefixIsRejectedAndNothingMoves() {
        val result = SeedPhraseEntry().typed("ad ")
        assertEquals(CommitOutcome.Rejected, result.outcome)
        assertEquals(0, result.entry.index)
        assertEquals("ad", result.entry.draft)
        // The rejected text does sit in slot 0 — the live slot *is* the draft —
        // but it is neither settled nor complete.
        assertFalse(result.entry.isSettled(0))
        assertFalse(result.entry.isComplete)
    }

    @Test
    fun aNonWordIsRejectedAndStaysInTheFieldToBeFixed() {
        val result = SeedPhraseEntry().typed("zzzz ")
        assertEquals(CommitOutcome.Rejected, result.outcome)
        assertEquals("zzzz", result.entry.draft)
        assertEquals(0, result.entry.index)
    }

    @Test
    fun casingIsNormalisedOnTheWayIn() {
        val result = SeedPhraseEntry().typed("ABANDON ")
        assertEquals("abandon", result.entry.words[0])
    }

    // -- multi-word input ----------------------------------------------------

    @Test
    fun aMultiWordBurstCommitsEachWordAndKeepsTheTail() {
        val result = SeedPhraseEntry().typed("abandon ability abl")
        assertEquals("abandon", result.entry.words[0])
        assertEquals("ability", result.entry.words[1])
        assertEquals(2, result.entry.index)
        assertEquals("abl", result.entry.draft)
    }

    @Test
    fun aRejectedWordHaltsTheBurstSoNothingLandsInTheWrongSlot() {
        val result = SeedPhraseEntry().typed("abandon zzzz ability")
        assertEquals(CommitOutcome.Rejected, result.outcome)
        assertEquals("abandon", result.entry.words[0])
        assertEquals(1, result.entry.index)
        assertEquals("zzzz", result.entry.draft)
        assertEquals("", result.entry.words[2])
    }

    // -- completion ----------------------------------------------------------

    @Test
    fun theTwelfthWordCompletesRatherThanAdvancing() {
        var entry = entryWith(*vector.dropLast(1).toTypedArray())
        assertEquals(11, entry.index)
        val result = entry.typed("about ")
        assertEquals(CommitOutcome.Completed, result.outcome)
        assertTrue(result.entry.isComplete)
        assertEquals(vector.joinToString(" "), result.entry.phrase)
    }

    /**
     * The CTA arms on a valid but uncommitted last word — the user should not
     * have to press space after the twelfth. This falls out of the live slot
     * being part of [SeedPhraseEntry.words].
     */
    @Test
    fun theLastWordCountsBeforeItIsCommitted() {
        val entry = entryWith(*vector.dropLast(1).toTypedArray()).typed("about").entry
        assertTrue(entry.isComplete)
        assertEquals(vector.joinToString(" "), entry.phrase)
    }

    @Test
    fun aPartialLastWordDoesNotArmTheCta() {
        val entry = entryWith(*vector.dropLast(1).toTypedArray()).typed("abou").entry
        assertFalse(entry.isComplete)
    }

    @Test
    fun committingAnEditedWordJumpsToWhateverIsStillEmpty() {
        var entry = entryWith("abandon", "ability", "able")
        entry = entry.jump(to = 1).typed("about ").entry
        assertEquals("about", entry.words[1])
        assertEquals("The next empty slot, not slot 2", 3, entry.index)
    }

    // -- stepping back -------------------------------------------------------

    @Test
    fun backspaceOnAnEmptyFieldStepsBackAndRestoresTheWord() {
        val entry = entryWith("abandon", "ability")
        assertEquals(2, entry.index)
        val stepped = entry.stepBack()!!
        assertEquals(1, stepped.index)
        assertEquals("ability", stepped.draft)
    }

    @Test
    fun backspaceAtTheFirstWordDoesNothing() {
        assertNull(SeedPhraseEntry().stepBack())
    }

    // -- the rail ------------------------------------------------------------

    @Test
    fun theLiveSlotIsNeverDrawnAsSettled() {
        val entry = entryWith("abandon").typed("abil").entry
        assertTrue(entry.isSettled(0))
        assertFalse("Slot 1 is being edited right now", entry.isSettled(1))
        assertFalse(entry.isSettled(2))
    }

    @Test
    fun jumpingBackLeavesThatSlotUnsettled() {
        val entry = entryWith("abandon", "ability").jump(to = 0)
        assertFalse(entry.isSettled(0))
        assertTrue(entry.isSettled(1))
    }

    // -- pasting -------------------------------------------------------------

    @Test
    fun pastingTwelveValidWordsFillsEverySlot() {
        val result = SeedPhraseEntry().fill(vector.joinToString(" "))
        assertEquals(PasteOutcome.Filled, result.outcome)
        assertTrue(result.entry.isComplete)
        assertEquals(11, result.entry.index)
    }

    @Test
    fun pastingToleratesMessyWhitespaceAndCasing() {
        val messy = "  ABANDON\n abandon\tabandon abandon abandon abandon " +
            "abandon abandon abandon abandon abandon   ABOUT  "
        val result = SeedPhraseEntry().fill(messy)
        assertEquals(PasteOutcome.Filled, result.outcome)
        assertEquals(vector.joinToString(" "), result.entry.phrase)
    }

    @Test
    fun pastingFewerThanTwelveLandsOnTheNextWordToType() {
        val result = SeedPhraseEntry().fill("abandon ability able about")
        assertEquals(PasteOutcome.Partial(4), result.outcome)
        assertEquals(4, result.entry.index)
        assertFalse(result.entry.isComplete)
    }

    @Test
    fun pastingTwelveWithOneBadWordLandsOnThatWord() {
        val broken = vector.toMutableList().also { it[3] = "zzzz" }
        val result = SeedPhraseEntry().fill(broken.joinToString(" "))
        assertEquals(PasteOutcome.Invalid(3), result.outcome)
        assertEquals(3, result.entry.index)
        assertEquals("zzzz", result.entry.draft)
    }

    /**
     * A 24-word phrase is dropped to 12 rather than half-filled silently — the
     * wallet only restores 12 words, and the caller says so.
     */
    @Test
    fun pastingTwentyFourWordsKeepsTwelveAndReportsThem() {
        val result = SeedPhraseEntry().fill((vector + vector).joinToString(" "))
        assertEquals(PasteOutcome.Filled, result.outcome)
        assertEquals(12, result.entry.words.size)
        assertEquals(vector.joinToString(" "), result.entry.phrase)
    }

    @Test
    fun pastingSomethingThatIsNotAPhraseIsRefused() {
        assertEquals(PasteOutcome.Unusable, SeedPhraseEntry().fill("https://mint.example").outcome)
        assertEquals(PasteOutcome.Unusable, SeedPhraseEntry().fill("   ").outcome)
    }

    @Test
    fun pastingDoesNotStrandTheReviewGrid() {
        val entry = SeedPhraseEntry().fill(vector.joinToString(" ")).entry.reviewing()
        assertTrue(entry.isReviewing)
        assertFalse("Editing any word leaves the grid", entry.jump(to = 2).isReviewing)
    }

    // -- suggestions ---------------------------------------------------------

    @Test
    fun theFieldOffersCompletionsForWhatIsTyped() {
        assertEquals(listOf("add", "addict", "address"), SeedPhraseEntry().typed("add").entry.completions)
        assertEquals(emptyList<String>(), SeedPhraseEntry().completions)
    }
}
