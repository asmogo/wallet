package com.cashu.me.Core

/**
 * The word-by-word seed-entry state machine, as an immutable value so the
 * advance rule is testable without a composition. The Compose holder wraps it;
 * the iOS twin is `SeedPhraseEntry` in `ios/CashuWallet/Core/SeedPhraseEntry.swift`.
 *
 * [words] is the whole phrase, one slot per position, `""` for a slot not yet
 * filled. The slot at [index] is *also* the live text in the field — there is no
 * separate draft. That single source of truth is what makes the CTA arm on a
 * valid but uncommitted last word without any extra bookkeeping.
 *
 * BIP-39 checksum validation lives outside this type: it needs the CDK, and this
 * type stays pure. Callers run the checksum once [isComplete] turns true and
 * call [reviewing] when it fails.
 */
data class SeedPhraseEntry(
    val words: List<String> = List(WORD_COUNT) { "" },
    val index: Int = 0,
    val isReviewing: Boolean = false,
) {
    companion object {
        const val WORD_COUNT = 12
        private val WHITESPACE = Regex("\\s+")
    }

    /** The live field text — the slot the user is editing. */
    val draft: String get() = words[index]

    /** Slots filled so far, whether or not they are real words. */
    val enteredCount: Int get() = words.count { it.isNotBlank() }

    /** Every slot filled with a word that is actually in the list. */
    val isComplete: Boolean get() = words.all { it in Bip39WordList.words }

    /** Space-joined, for the checksum and for `initializeRestoredWallet`. */
    val phrase: String get() = words.filter { it.isNotBlank() }.joinToString(" ")

    /** Up to three completions for what is currently in the field. */
    val completions: List<String> get() = Bip39WordList.completions(draft)

    /** Slots the rail draws as filled. The live slot is never one of them. */
    fun isSettled(slot: Int): Boolean = slot != index && words[slot].isNotBlank()

    // -- editing -------------------------------------------------------------

    private fun withDraft(text: String): SeedPhraseEntry =
        copy(words = words.toMutableList().also { it[index] = text }, isReviewing = false)

    /**
     * Feed the field's new text.
     *
     * Whitespace is the commit key: everything before it is a finished word and
     * the remainder stays in the field. That also makes a multi-word paste
     * *into* the field behave exactly like typing it.
     */
    fun typed(text: String): CommitResult {
        if (text.none { it.isWhitespace() }) {
            return CommitResult(withDraft(text.lowercase()), CommitOutcome.None)
        }
        val chunks = text.lowercase().split(WHITESPACE)
        var entry = this
        var outcome = CommitOutcome.None
        chunks.forEachIndexed { i, chunk ->
            if (i == chunks.lastIndex) {
                // The tail after the final separator is still being typed. An
                // empty tail is written nowhere: after an advance the new slot
                // is already empty, and after a *completion* the index has
                // nowhere to go, so writing "" would wipe the word just
                // committed.
                if (chunk.isNotEmpty()) entry = entry.withDraft(chunk)
            } else if (chunk.isNotBlank()) {
                val result = entry.withDraft(chunk).commit()
                entry = result.entry
                outcome = result.outcome
                // A rejected chunk stays in the field to be corrected; anything
                // after it would land in the wrong slot.
                if (result.outcome == CommitOutcome.Rejected) return CommitResult(entry, outcome)
            }
        }
        return CommitResult(entry, outcome)
    }

    /**
     * Commit whatever is in the field — the space key, the Next key, or a
     * suggestion tap that has already been written into the draft.
     *
     * An exact wordlist match never advances on its own elsewhere, because
     * `add` is both a word and a prefix of `addict` and `address`. Here, where
     * the user has explicitly asked to commit, an exact match wins outright and
     * a unique prefix completes; anything ambiguous is refused.
     */
    fun commit(): CommitResult {
        val candidate = draft.trim().lowercase()
        if (candidate.isEmpty()) return CommitResult(this, CommitOutcome.Ignored)

        val resolved = when {
            candidate in Bip39WordList.words -> candidate
            else -> Bip39WordList.completions(candidate, limit = 2)
                .singleOrNull() ?: return CommitResult(this, CommitOutcome.Rejected)
        }

        val filled = words.toMutableList().also { it[index] = resolved }
        val next = filled.indexOfFirst { it.isBlank() }
        return if (next == -1) {
            // Nothing left empty — stay put and let the caller run the checksum.
            CommitResult(copy(words = filled, isReviewing = false), CommitOutcome.Completed)
        } else {
            CommitResult(copy(words = filled, index = next, isReviewing = false), CommitOutcome.Advanced)
        }
    }

    /**
     * Backspace on an already-empty field steps back a word and loads it for
     * editing. Inside a non-empty draft, backspace is an ordinary delete and
     * this is never called.
     */
    fun stepBack(): SeedPhraseEntry? =
        if (index == 0) null else copy(index = index - 1, isReviewing = false)

    /** Rail tick or review-grid cell: edit a specific word. */
    fun jump(to: Int): SeedPhraseEntry =
        if (to in words.indices) copy(index = to, isReviewing = false) else this

    /** The checksum failed, so show all 12 — no single word can be blamed. */
    fun reviewing(): SeedPhraseEntry = copy(isReviewing = true)

    /**
     * Fill from a pasted phrase. Extra words past the twelfth are dropped: the
     * wallet only restores 12-word phrases, and silently keeping a 24-word
     * prefix would be worse than saying so.
     */
    fun fill(pasted: String): PasteResult {
        val tokens = pasted.trim().lowercase().split(WHITESPACE).filter { it.isNotBlank() }
        if (tokens.none { it in Bip39WordList.words }) {
            return PasteResult(this, PasteOutcome.Unusable)
        }
        val kept = tokens.take(WORD_COUNT)
        val filled = List(WORD_COUNT) { kept.getOrElse(it) { "" } }

        if (kept.size < WORD_COUNT) {
            return PasteResult(
                SeedPhraseEntry(filled, kept.size),
                PasteOutcome.Partial(kept.size),
            )
        }
        val bad = filled.indexOfFirst { it !in Bip39WordList.words }
        return if (bad == -1) {
            PasteResult(SeedPhraseEntry(filled, WORD_COUNT - 1), PasteOutcome.Filled)
        } else {
            PasteResult(SeedPhraseEntry(filled, bad), PasteOutcome.Invalid(bad))
        }
    }
}

data class CommitResult(val entry: SeedPhraseEntry, val outcome: CommitOutcome)

enum class CommitOutcome {
    /** Text changed but nothing was committed. */
    None,

    /** Nothing to commit — the field was empty. */
    Ignored,

    /** Committed and moved to the next empty slot. */
    Advanced,

    /** Committed the last empty slot; the caller should run the checksum. */
    Completed,

    /** Not a word and not a unique prefix. Nothing moved. */
    Rejected,
}

data class PasteResult(val entry: SeedPhraseEntry, val outcome: PasteOutcome)

sealed interface PasteOutcome {
    /** All 12 landed and every one is a real word. */
    data object Filled : PasteOutcome

    /** Fewer than 12 words; [count] landed and the rest are still to type. */
    data class Partial(val count: Int) : PasteOutcome

    /** 12 landed but the word at [index] is not in the list. */
    data class Invalid(val index: Int) : PasteOutcome

    /** Nothing in there looked like a seed phrase. */
    data object Unusable : PasteOutcome
}
