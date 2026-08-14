import Foundation

/// What a commit attempt did, so the caller can fire haptics and notices.
enum SeedCommitOutcome: Equatable {
    /// Text changed but nothing was committed.
    case none
    /// Nothing to commit — the field was empty.
    case ignored
    /// Committed and moved to the next empty slot.
    case advanced
    /// Committed the last empty slot; the caller should run the checksum.
    case completed
    /// Not a word and not a unique prefix. Nothing moved.
    case rejected
}

/// What a pasted phrase turned out to be.
enum SeedPasteOutcome: Equatable {
    /// All 12 landed and every one is a real word.
    case filled
    /// Fewer than 12 words; this many landed and the rest are still to type.
    case partial(Int)
    /// 12 landed but the word at this index is not in the list.
    case invalid(Int)
    /// Nothing in there looked like a seed phrase.
    case unusable
}

/// The word-by-word seed-entry state machine, as a value type so the advance
/// rule is testable without a view. Android twin:
/// `android/app/src/main/java/com/cashu/me/Core/SeedPhraseEntry.kt`.
///
/// `words` is the whole phrase, one slot per position, `""` for a slot not yet
/// filled. The slot at `index` is *also* the live text in the field — there is
/// no separate draft. That single source of truth is what makes the CTA arm on
/// a valid but uncommitted last word without any extra bookkeeping.
///
/// BIP-39 checksum validation lives outside this type: it needs the CDK, and
/// this type stays pure. Callers run the checksum once `isComplete` turns true
/// and call `markReviewing()` when it fails.
struct SeedPhraseEntry: Equatable {
    static let wordCount = 12

    private(set) var words: [String] = Array(repeating: "", count: SeedPhraseEntry.wordCount)
    private(set) var index: Int = 0
    private(set) var isReviewing: Bool = false

    /// The live field text — the slot the user is editing.
    var draft: String { words[index] }

    /// Slots filled so far, whether or not they are real words.
    var enteredCount: Int { words.filter { !$0.isEmpty }.count }

    /// Every slot filled with a word that is actually in the list.
    var isComplete: Bool { words.allSatisfy { bip39WordList.contains($0) } }

    /// Space-joined, for the checksum and for `initializeRestoredWallet`.
    var phrase: String { words.filter { !$0.isEmpty }.joined(separator: " ") }

    /// Up to three completions for what is currently in the field.
    var completions: [String] { bip39Completions(prefix: draft) }

    /// Slots the rail draws as filled. The live slot is never one of them.
    func isSettled(_ slot: Int) -> Bool {
        slot != index && !words[slot].isEmpty
    }

    // MARK: - Editing

    private mutating func setDraft(_ text: String) {
        words[index] = text
        isReviewing = false
    }

    /// Feed the field's new text.
    ///
    /// Whitespace is the commit key: everything before it is a finished word
    /// and the remainder stays in the field. That also makes a multi-word paste
    /// *into* the field behave exactly like typing it.
    @discardableResult
    mutating func typed(_ text: String) -> SeedCommitOutcome {
        let lowered = text.lowercased()
        guard lowered.contains(where: { $0.isWhitespace }) else {
            setDraft(lowered)
            return .none
        }

        let chunks = lowered.components(separatedBy: .whitespacesAndNewlines)
        var outcome: SeedCommitOutcome = .none
        for (offset, chunk) in chunks.enumerated() {
            if offset == chunks.count - 1 {
                // The tail after the final separator is still being typed. An
                // empty tail is written nowhere: after an advance the new slot
                // is already empty, and after a *completion* the index has
                // nowhere to go, so writing "" would wipe the word just
                // committed.
                if !chunk.isEmpty { setDraft(chunk) }
            } else if !chunk.isEmpty {
                setDraft(chunk)
                outcome = commit()
                // A rejected chunk stays in the field to be corrected; anything
                // after it would land in the wrong slot.
                if outcome == .rejected { return .rejected }
            }
        }
        return outcome
    }

    /// Commit whatever is in the field — the space key, the Next key, or a
    /// suggestion tap that has already been written into the draft.
    ///
    /// An exact wordlist match never advances on its own elsewhere, because
    /// `add` is both a word and a prefix of `addict` and `address`. Here, where
    /// the user has explicitly asked to commit, an exact match wins outright
    /// and a unique prefix completes; anything ambiguous is refused.
    @discardableResult
    mutating func commit() -> SeedCommitOutcome {
        let candidate = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !candidate.isEmpty else { return .ignored }

        let resolved: String
        if bip39WordList.contains(candidate) {
            resolved = candidate
        } else {
            let matches = bip39Completions(prefix: candidate, limit: 2)
            guard matches.count == 1 else { return .rejected }
            resolved = matches[0]
        }

        words[index] = resolved
        isReviewing = false
        if let next = words.firstIndex(where: { $0.isEmpty }) {
            index = next
            return .advanced
        }
        // Nothing left empty — stay put and let the caller run the checksum.
        return .completed
    }

    /// Backspace on an already-empty field steps back a word and loads it for
    /// editing. Inside a non-empty draft, backspace is an ordinary delete and
    /// this is never called.
    @discardableResult
    mutating func stepBack() -> Bool {
        guard index > 0 else { return false }
        index -= 1
        isReviewing = false
        return true
    }

    /// Rail tick or review-grid cell: edit a specific word.
    mutating func jump(to slot: Int) {
        guard words.indices.contains(slot) else { return }
        index = slot
        isReviewing = false
    }

    /// The checksum failed, so show all 12 — no single word can be blamed.
    mutating func markReviewing() {
        isReviewing = true
    }

    /// Fill from a pasted phrase. Extra words past the twelfth are dropped: the
    /// wallet only restores 12-word phrases, and silently keeping a 24-word
    /// prefix would be worse than saying so.
    @discardableResult
    mutating func fill(from pasted: String) -> SeedPasteOutcome {
        let tokens = pasted.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard tokens.contains(where: { bip39WordList.contains($0) }) else { return .unusable }

        let kept = Array(tokens.prefix(Self.wordCount))
        words = (0..<Self.wordCount).map { kept.indices.contains($0) ? kept[$0] : "" }
        isReviewing = false

        if kept.count < Self.wordCount {
            index = kept.count
            return .partial(kept.count)
        }
        if let bad = words.firstIndex(where: { !bip39WordList.contains($0) }) {
            index = bad
            return .invalid(bad)
        }
        index = Self.wordCount - 1
        return .filled
    }

    mutating func reset() {
        self = SeedPhraseEntry()
    }
}
