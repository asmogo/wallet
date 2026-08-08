import XCTest
@testable import CashuWallet

/// The advance rule is the subtle part of word-by-word seed entry, so it is
/// pinned here rather than left to the view. Android twin:
/// `android/app/src/test/java/com/cashu/me/Core/SeedPhraseEntryTest.kt`.
final class SeedPhraseEntryTests: XCTestCase {

    private let vector = Array(repeating: "abandon", count: 11) + ["about"]

    private func entry(typing words: [String]) -> SeedPhraseEntry {
        var entry = SeedPhraseEntry()
        for word in words { entry.typed("\(word) ") }
        return entry
    }

    // MARK: - Committing

    func testSpaceCommitsTheWordAndAdvances() {
        var entry = SeedPhraseEntry()
        XCTAssertEqual(entry.typed("abandon "), .advanced)
        XCTAssertEqual(entry.words[0], "abandon")
        XCTAssertEqual(entry.index, 1)
        XCTAssertEqual(entry.draft, "")
    }

    func testTypingWithoutASpaceCommitsNothing() {
        var entry = SeedPhraseEntry()
        XCTAssertEqual(entry.typed("abando"), SeedCommitOutcome.none)
        XCTAssertEqual(entry.index, 0)
        XCTAssertEqual(entry.draft, "abando")
    }

    func testTheNextKeyCommitsWhatIsInTheField() {
        var entry = SeedPhraseEntry()
        entry.typed("abandon")
        XCTAssertEqual(entry.commit(), .advanced)
        XCTAssertEqual(entry.words[0], "abandon")
    }

    func testCommittingAnEmptyFieldIsIgnored() {
        var entry = SeedPhraseEntry()
        XCTAssertEqual(entry.commit(), .ignored)
    }

    /// The whole reason exact matches never auto-advance: "add" is a word *and*
    /// a prefix of "addict" and "address". Committing it must yield "add".
    func testAnExactWordCommitsAsItselfEvenWhenLongerWordsSharePrefix() {
        var entry = SeedPhraseEntry()
        XCTAssertEqual(entry.typed("add "), .advanced)
        XCTAssertEqual(entry.words[0], "add")
    }

    func testAUniquePrefixCompletesOnCommit() {
        var entry = SeedPhraseEntry()
        XCTAssertEqual(entry.typed("abando "), .advanced)
        XCTAssertEqual(entry.words[0], "abandon")
    }

    func testAnAmbiguousPrefixIsRejectedAndNothingMoves() {
        var entry = SeedPhraseEntry()
        XCTAssertEqual(entry.typed("ad "), .rejected)
        XCTAssertEqual(entry.index, 0)
        XCTAssertEqual(entry.draft, "ad")
        // The rejected text does sit in slot 0 — the live slot *is* the draft —
        // but it is neither settled nor complete.
        XCTAssertFalse(entry.isSettled(0))
        XCTAssertFalse(entry.isComplete)
    }

    func testANonWordIsRejectedAndStaysInTheFieldToBeFixed() {
        var entry = SeedPhraseEntry()
        XCTAssertEqual(entry.typed("zzzz "), .rejected)
        XCTAssertEqual(entry.draft, "zzzz")
        XCTAssertEqual(entry.index, 0)
    }

    func testCasingIsNormalisedOnTheWayIn() {
        var entry = SeedPhraseEntry()
        entry.typed("ABANDON ")
        XCTAssertEqual(entry.words[0], "abandon")
    }

    // MARK: - Multi-word input

    func testAMultiWordBurstCommitsEachWordAndKeepsTheTail() {
        var entry = SeedPhraseEntry()
        entry.typed("abandon ability abl")
        XCTAssertEqual(entry.words[0], "abandon")
        XCTAssertEqual(entry.words[1], "ability")
        XCTAssertEqual(entry.index, 2)
        XCTAssertEqual(entry.draft, "abl")
    }

    func testARejectedWordHaltsTheBurstSoNothingLandsInTheWrongSlot() {
        var entry = SeedPhraseEntry()
        XCTAssertEqual(entry.typed("abandon zzzz ability"), .rejected)
        XCTAssertEqual(entry.words[0], "abandon")
        XCTAssertEqual(entry.index, 1)
        XCTAssertEqual(entry.draft, "zzzz")
        XCTAssertEqual(entry.words[2], "")
    }

    // MARK: - Completion

    func testTheTwelfthWordCompletesRatherThanAdvancing() {
        var entry = self.entry(typing: Array(vector.dropLast()))
        XCTAssertEqual(entry.index, 11)
        XCTAssertEqual(entry.typed("about "), .completed)
        XCTAssertTrue(entry.isComplete)
        XCTAssertEqual(entry.phrase, vector.joined(separator: " "))
    }

    /// The CTA arms on a valid but uncommitted last word — the user should not
    /// have to press space after the twelfth. This falls out of the live slot
    /// being part of `words`.
    func testTheLastWordCountsBeforeItIsCommitted() {
        var entry = self.entry(typing: Array(vector.dropLast()))
        entry.typed("about")
        XCTAssertTrue(entry.isComplete)
        XCTAssertEqual(entry.phrase, vector.joined(separator: " "))
    }

    func testAPartialLastWordDoesNotArmTheCta() {
        var entry = self.entry(typing: Array(vector.dropLast()))
        entry.typed("abou")
        XCTAssertFalse(entry.isComplete)
    }

    func testCommittingAnEditedWordJumpsToWhateverIsStillEmpty() {
        var entry = self.entry(typing: ["abandon", "ability", "able"])
        entry.jump(to: 1)
        entry.typed("about ")
        XCTAssertEqual(entry.words[1], "about")
        XCTAssertEqual(entry.index, 3, "The next empty slot, not slot 2")
    }

    // MARK: - Stepping back

    func testBackspaceOnAnEmptyFieldStepsBackAndRestoresTheWord() {
        var entry = self.entry(typing: ["abandon", "ability"])
        XCTAssertEqual(entry.index, 2)
        XCTAssertTrue(entry.stepBack())
        XCTAssertEqual(entry.index, 1)
        XCTAssertEqual(entry.draft, "ability")
    }

    func testBackspaceAtTheFirstWordDoesNothing() {
        var entry = SeedPhraseEntry()
        XCTAssertFalse(entry.stepBack())
    }

    // MARK: - The rail

    func testTheLiveSlotIsNeverDrawnAsSettled() {
        var entry = self.entry(typing: ["abandon"])
        entry.typed("abil")
        XCTAssertTrue(entry.isSettled(0))
        XCTAssertFalse(entry.isSettled(1), "Slot 1 is being edited right now")
        XCTAssertFalse(entry.isSettled(2))
    }

    func testJumpingBackLeavesThatSlotUnsettled() {
        var entry = self.entry(typing: ["abandon", "ability"])
        entry.jump(to: 0)
        XCTAssertFalse(entry.isSettled(0))
        XCTAssertTrue(entry.isSettled(1))
    }

    // MARK: - Pasting

    func testPastingTwelveValidWordsFillsEverySlot() {
        var entry = SeedPhraseEntry()
        XCTAssertEqual(entry.fill(from: vector.joined(separator: " ")), .filled)
        XCTAssertTrue(entry.isComplete)
        XCTAssertEqual(entry.index, 11)
    }

    func testPastingToleratesMessyWhitespaceAndCasing() {
        var entry = SeedPhraseEntry()
        let messy = "  ABANDON\n abandon\tabandon abandon abandon abandon "
            + "abandon abandon abandon abandon abandon   ABOUT  "
        XCTAssertEqual(entry.fill(from: messy), .filled)
        XCTAssertEqual(entry.phrase, vector.joined(separator: " "))
    }

    func testPastingFewerThanTwelveLandsOnTheNextWordToType() {
        var entry = SeedPhraseEntry()
        XCTAssertEqual(entry.fill(from: "abandon ability able about"), .partial(4))
        XCTAssertEqual(entry.index, 4)
        XCTAssertFalse(entry.isComplete)
    }

    func testPastingTwelveWithOneBadWordLandsOnThatWord() {
        var broken = vector
        broken[3] = "zzzz"
        var entry = SeedPhraseEntry()
        XCTAssertEqual(entry.fill(from: broken.joined(separator: " ")), .invalid(3))
        XCTAssertEqual(entry.index, 3)
        XCTAssertEqual(entry.draft, "zzzz")
    }

    /// A 24-word phrase is dropped to 12 rather than half-filled silently — the
    /// wallet only restores 12 words, and the caller says so.
    func testPastingTwentyFourWordsKeepsTwelveAndReportsThem() {
        var entry = SeedPhraseEntry()
        XCTAssertEqual(entry.fill(from: (vector + vector).joined(separator: " ")), .filled)
        XCTAssertEqual(entry.words.count, 12)
        XCTAssertEqual(entry.phrase, vector.joined(separator: " "))
    }

    func testPastingSomethingThatIsNotAPhraseIsRefused() {
        var entry = SeedPhraseEntry()
        XCTAssertEqual(entry.fill(from: "https://mint.example"), .unusable)
        XCTAssertEqual(entry.fill(from: "   "), .unusable)
    }

    func testEditingAnyWordLeavesTheReviewGrid() {
        var entry = SeedPhraseEntry()
        entry.fill(from: vector.joined(separator: " "))
        entry.markReviewing()
        XCTAssertTrue(entry.isReviewing)
        entry.jump(to: 2)
        XCTAssertFalse(entry.isReviewing)
    }

    // MARK: - Suggestions

    func testTheFieldOffersCompletionsForWhatIsTyped() {
        var entry = SeedPhraseEntry()
        entry.typed("add")
        XCTAssertEqual(entry.completions, ["add", "addict", "address"])
        XCTAssertEqual(SeedPhraseEntry().completions, [])
    }

    // MARK: - Wordlist completions

    /// `bip39Completions` binary-searches, so lexicographic order is a
    /// correctness precondition, not a nicety.
    func testSortedWordListIsLexicographicAndComplete() {
        XCTAssertEqual(bip39SortedWords.count, 2048)
        XCTAssertEqual(bip39SortedWords, bip39SortedWords.sorted())
        XCTAssertEqual(Set(bip39SortedWords), bip39WordList)
    }

    func testCompletionsRespectTheLimitAndNeedTwoCharacters() {
        XCTAssertEqual(bip39Completions(prefix: "add"), ["add", "addict", "address"])
        XCTAssertEqual(bip39Completions(prefix: "add", limit: 2), ["add", "addict"])
        XCTAssertEqual(bip39Completions(prefix: "a"), [])
        XCTAssertEqual(bip39Completions(prefix: "zzz"), [])
    }

    /// The binary search must not walk off either end of the list.
    func testCompletionsHandleTheListEdges() {
        XCTAssertEqual(bip39Completions(prefix: "abandon"), ["abandon"])
        XCTAssertEqual(bip39Completions(prefix: "zoo"), ["zoo"])
    }
}
