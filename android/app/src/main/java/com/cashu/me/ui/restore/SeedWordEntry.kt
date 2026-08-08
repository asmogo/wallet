package com.cashu.me.ui.restore

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cashu.me.Core.CommitOutcome
import kotlinx.coroutines.delay
import com.cashu.me.Core.SeedPhraseEntry
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.testing.UiTestTags
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.atSize
import com.cashu.me.ui.theme.withSlashedZero

// ---------------------------------------------------------------------------
// Copy
// ---------------------------------------------------------------------------

/**
 * The seed-entry message set, in one place because both hosts render it and the
 * strings on the old screen had already drifted. iOS twin: `SeedEntryCopy` in
 * `ios/CashuWallet/Views/Main/SeedWordEntry.swift`.
 */
object SeedEntryCopy {
    const val SUBHEAD = "Enter your 12 words, one at a time."
    const val HELPER = "Press space after each word."
    const val COMPLETE = "All 12 words check out."
    const val REJECTED = "Not a seed word. Check the spelling."
    const val CHECKSUM =
        "That's not a valid seed phrase. One of the words is probably mistyped. " +
            "Tap any word below to fix it."
    const val PASTE_LINK = "Paste seed phrase"
    const val PASTE_UNUSABLE = "Nothing in the clipboard looked like a seed phrase."

    fun pastePartial(count: Int): String =
        "Pasted $count ${if (count == 1) "word" else "words"}. Enter the rest."

    fun pasteInvalid(index: Int): String =
        "Pasted 12 words, but word ${index + 1} isn't in the list."
}

/** A host-supplied message that replaces the default helper line. */
data class SeedEntryNotice(val text: String, val severity: NoticeSeverity)

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/**
 * Compose holder around the immutable [SeedPhraseEntry], following this file
 * family's existing idiom (`RestoreMintsStagingState`, `RestoreProgressState`).
 * The BIP-39 checksum is deliberately not in here: it needs the CDK, and the
 * host owns that.
 */
@Stable
class SeedPhraseEntryState(initial: SeedPhraseEntry = SeedPhraseEntry()) {
    var entry by mutableStateOf(initial)
    var notice by mutableStateOf<SeedEntryNotice?>(null)

    val phrase: String get() = entry.phrase
    val isComplete: Boolean get() = entry.isComplete
    val isReviewing: Boolean get() = entry.isReviewing
    val enteredCount: Int get() = entry.enteredCount

    fun reset() {
        entry = SeedPhraseEntry()
        notice = null
    }

    fun markReviewing() {
        entry = entry.reviewing()
    }
}

/** [initial] exists so screenshot baselines can compose a mid-entry state. */
@Composable
fun rememberSeedPhraseEntryState(
    initial: SeedPhraseEntry = SeedPhraseEntry(),
): SeedPhraseEntryState = remember { SeedPhraseEntryState(initial) }

// ---------------------------------------------------------------------------
// Metrics
// ---------------------------------------------------------------------------

private val RailSlot: Dp = 10.dp
private val RailWidth: Dp = 2.dp
private val TickCurrent: Dp = 10.dp
private val TickResting: Dp = 3.dp
private val RailHitWidth: Dp = 24.dp
private val RailToCard: Dp = 20.dp
private val CardRadius: Dp = 14.dp
private val CardPadding: Dp = 20.dp
private val OrdinalWidth: Dp = 22.dp
private val ChipRadius: Dp = 12.dp

/** Matches the restore chips' glyph box in RestoreWalletFlow.kt. */
private val ChipGlyphSize: Dp = 18.dp

/** Ghost cards are alpha and scale only — a static blur can never match across
 *  screenshot-golden hosts, and iOS has to draw the identical thing. */
private val GhostScales = listOf(0.96f, 0.92f)
private val GhostOffsets = listOf((-8).dp, (-16).dp)
private val GhostAlphas = listOf(0.55f, 0.30f)

// ---------------------------------------------------------------------------
// The field
// ---------------------------------------------------------------------------

/**
 * Word-by-word seed entry: a progress rail, a card holding one word, ghost
 * cards for the words still to come, and up to three wordlist completions.
 *
 * The text field is a *single persistent* [BasicTextField] that never leaves
 * the composition — advancing changes the ordinal and the ghosts around it, so
 * the keyboard never dismisses and re-presents between words. Everything that
 * animates is therefore a sibling of the field, never an ancestor.
 */
@Composable
fun SeedWordEntryField(
    state: SeedPhraseEntryState,
    onOutcome: (CommitOutcome) -> Unit,
    modifier: Modifier = Modifier,
    autoFocus: Boolean = true,
    onPaste: (() -> Unit)? = null,
) {
    val haptics = LocalHapticFeedback.current
    val keyboard = LocalSoftwareKeyboardController.current
    val focusRequester = remember { FocusRequester() }
    var rejected by remember { mutableStateOf(false) }

    fun apply(outcome: CommitOutcome) {
        when (outcome) {
            CommitOutcome.Advanced -> {
                rejected = false
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            }
            CommitOutcome.Completed -> {
                rejected = false
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            }
            CommitOutcome.Rejected -> {
                rejected = true
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            }
            CommitOutcome.None -> rejected = false
            CommitOutcome.Ignored -> Unit
        }
        onOutcome(outcome)
    }

    var hasAutoFocused by remember { mutableStateOf(false) }
    LaunchedEffect(autoFocus, state.isReviewing) {
        // Word-by-word entry is keyboard-driven, so the field autofocuses — a
        // deliberate exception to the "land calm" rule the mint step keeps.
        // But not on the first frame: the IME's own animation overlapping the
        // stage swap read as two fighting motions (device review 2026-08-08).
        // Let the swap land, then the keyboard rises as its own clean motion.
        // Later refocuses (leaving the review grid) are within-stage and stay
        // immediate.
        if (autoFocus && !state.isReviewing) {
            if (!hasAutoFocused) {
                hasAutoFocused = true
                delay(350)
            }
            focusRequester.requestFocus()
            keyboard?.show()
        }
    }

    Column(modifier = modifier.fillMaxWidth()) {
        if (state.isReviewing) {
            SeedWordReviewGrid(words = state.entry.words) { slot ->
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                state.entry = state.entry.jump(slot)
                state.notice = null
            }
            Box(modifier = Modifier.padding(top = CashuTheme.spacing.default)) {
                HelperLine(state = state, rejected = rejected)
            }
        } else {
            // The rail sizes this row, but chips and helper belong to the
            // card's own column — hung below the rail's extent they landed in
            // the scroll fade on iOS and left dead space on both platforms
            // (device review 2026-08-08).
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(RailToCard),
            ) {
                // The rail owns its haptics — touch acknowledgment and
                // per-word ticks are its voice, not the host's.
                SeedWordProgressRail(entry = state.entry) { slot ->
                    state.entry = state.entry.jump(slot)
                }
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
                ) {
                    SeedWordCard(
                        state = state,
                        rejected = rejected,
                        focusRequester = focusRequester,
                        onTyped = { text -> state.entry.typed(text).let { state.entry = it.entry; apply(it.outcome) } },
                        onCommit = { state.entry.commit().let { state.entry = it.entry; apply(it.outcome) } },
                        onBackspaceOnEmpty = {
                            state.entry.stepBack()?.let {
                                state.entry = it
                                rejected = false
                                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            }
                        },
                    )
                    SeedWordChipRow(
                        words = state.entry.completions,
                        onPaste = if (state.enteredCount == 0) onPaste else null,
                        onSelect = { word ->
                            // A chip goes through the same commit path as
                            // typing it, rather than being a second way to
                            // advance.
                            val typed = state.entry.typed(word)
                            val committed = typed.entry.commit()
                            state.entry = committed.entry
                            apply(committed.outcome)
                        },
                    )
                    HelperLine(state = state, rejected = rejected)
                }
            }
        }
    }
}

@Composable
private fun HelperLine(state: SeedPhraseEntryState, rejected: Boolean) {
    val notice = state.notice
    when {
        notice != null -> InlineNotice(text = notice.text, severity = notice.severity)
        rejected -> InlineNotice(text = SeedEntryCopy.REJECTED, severity = NoticeSeverity.Caution)
        else -> Text(
            text = if (state.isComplete) SeedEntryCopy.COMPLETE else SeedEntryCopy.HELPER,
            style = MaterialTheme.typography.bodyMedium,
            color = if (state.isComplete) {
                CashuTheme.colors.received
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
        )
    }
}

// ---------------------------------------------------------------------------
// Card + ghosts
// ---------------------------------------------------------------------------

@Composable
private fun SeedWordCard(
    state: SeedPhraseEntryState,
    rejected: Boolean,
    focusRequester: FocusRequester,
    onTyped: (String) -> Unit,
    onCommit: () -> Unit,
    onBackspaceOnEmpty: () -> Unit,
) {
    val entry = state.entry
    val isLast = entry.index == SeedPhraseEntry.WORD_COUNT - 1
    val remaining = SeedPhraseEntry.WORD_COUNT - (entry.index + 1)
    val cardColor by animateColorAsState(
        targetValue = if (rejected) {
            MaterialTheme.colorScheme.errorContainer
        } else {
            MaterialTheme.colorScheme.surfaceContainerHighest
        },
        label = "seed-card",
    )

    // BottomCenter matches the ghosts' transform origin; BottomStart would
    // shear the stack sideways as it scales.
    Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.BottomCenter) {
        // One empty surface per word still to come, capped at two. They carry
        // no content — they are the shape of what is left, not a container.
        GhostScales.indices.reversed().forEach { depth ->
            if (remaining > depth) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(CardHeight())
                        .graphicsLayer {
                            scaleX = GhostScales[depth]
                            scaleY = GhostScales[depth]
                            translationY = GhostOffsets[depth].toPx()
                            alpha = GhostAlphas[depth]
                            transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.5f, 1f)
                        }
                        .clip(RoundedCornerShape(CardRadius))
                        .background(MaterialTheme.colorScheme.surfaceContainerHighest)
                        .clearAndSetSemantics {},
                )
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(CardHeight())
                .clip(RoundedCornerShape(CardRadius))
                .background(cardColor)
                .padding(horizontal = CardPadding),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
        ) {
            // Only the ordinal morphs on advance — the field beside it must keep
            // its identity or the keyboard drops.
            AnimatedContent(
                targetState = entry.index,
                transitionSpec = { fadeIn() togetherWith fadeOut() },
                label = "seed-ordinal",
            ) { index ->
                Text(
                    text = "${index + 1}",
                    style = CashuTheme.type.monoCaption,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.width(OrdinalWidth),
                )
            }

            BasicTextField(
                value = entry.draft,
                onValueChange = onTyped,
                modifier = Modifier
                    .weight(1f)
                    .testTag(UiTestTags.SeedWordField)
                    .focusRequester(focusRequester)
                    .onPreviewKeyEvent { event ->
                        // Backspace on an already-empty field steps back a word.
                        // Inside a non-empty draft it stays an ordinary delete.
                        if (event.type == KeyEventType.KeyDown &&
                            event.key == Key.Backspace &&
                            entry.draft.isEmpty()
                        ) {
                            onBackspaceOnEmpty()
                            true
                        } else {
                            false
                        }
                    },
                textStyle = CashuTheme.type.monoBody.atSize(20.sp).withSlashedZero()
                    .copy(color = MaterialTheme.colorScheme.onSurface),
                singleLine = true,
                cursorBrush = SolidColor(MaterialTheme.colorScheme.onSurface),
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                    imeAction = if (isLast) ImeAction.Done else ImeAction.Next,
                ),
                keyboardActions = KeyboardActions(
                    onNext = { onCommit() },
                    onDone = { onCommit() },
                ),
                decorationBox = { inner ->
                    if (entry.draft.isEmpty()) {
                        Text(
                            text = "word ${entry.index + 1}",
                            style = CashuTheme.type.monoBody.atSize(20.sp),
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f),
                        )
                    }
                    inner()
                },
            )
        }
    }
}

/** Derived from the text style's line box, so the card grows with the font
 *  scale instead of clipping. */
@Composable
private fun CardHeight(): Dp {
    val lineHeight = CashuTheme.type.monoBody.atSize(20.sp).lineHeight
    return with(androidx.compose.ui.platform.LocalDensity.current) { lineHeight.toDp() } +
        CardPadding * 2
}

// ---------------------------------------------------------------------------
// Rail
// ---------------------------------------------------------------------------

/** Twelve ticks, one per word. Length carries the emphasis, never colour —
 *  green appears only once the whole phrase is in. */
@Composable
private fun SeedWordProgressRail(entry: SeedPhraseEntry, onSelect: (Int) -> Unit) {
    // Two haptic voices, deliberately distinct: ContextClick when the finger
    // engages the rail (tap or hold) — the "you've grabbed a control" cue —
    // and SegmentTick for each word change while scrubbing, which is exactly
    // the discrete-segment scrub that constant was designed for.
    val haptics = LocalHapticFeedback.current
    val jumpActions = remember(entry.index) {
        listOf(
            CustomAccessibilityAction("Previous word") {
                onSelect((entry.index - 1).coerceAtLeast(0)); true
            },
            CustomAccessibilityAction("Next word") {
                onSelect((entry.index + 1).coerceAtMost(SeedPhraseEntry.WORD_COUNT - 1)); true
            },
        )
    }

    Column(
        modifier = Modifier
            .testTag(UiTestTags.SeedWordRail)
            // Tap jumps; press-and-hold then drag scrubs through the words,
            // the focused word updating live (jumps are live, so release
            // needs no handler). Container-level gestures rather than
            // per-tick clickables: the long-press gate keeps the scrub out of
            // the way of both quick taps and the enclosing scroll, and a
            // merged semantics node full of child click actions was mud.
            .pointerInput(Unit) {
                detectTapGestures { offset ->
                    // The engage cue fires on every touch — the hint that this
                    // is a control, even tapping the tick already focused.
                    haptics.performHapticFeedback(HapticFeedbackType.ContextClick)
                    onSelect(slotAt(offset.y))
                }
            }
            .pointerInput(Unit) {
                var last = -1
                detectDragGesturesAfterLongPress(
                    onDragStart = { offset ->
                        haptics.performHapticFeedback(HapticFeedbackType.ContextClick)
                        last = slotAt(offset.y)
                        onSelect(last)
                    },
                    onDrag = { change, _ ->
                        change.consume()
                        val slot = slotAt(change.position.y)
                        // One tick per *word change*, not per drag sample.
                        if (slot != last) {
                            last = slot
                            haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
                            onSelect(slot)
                        }
                    },
                )
            }
            // One element with custom actions: twelve 10dp ticks can never be
            // 48dp targets, so assistive navigation goes through the value.
            .semantics(mergeDescendants = true) {
                contentDescription = "Seed word progress"
                stateDescription = "Word ${entry.index + 1} of ${SeedPhraseEntry.WORD_COUNT}"
                customActions = jumpActions
            },
    ) {
        repeat(SeedPhraseEntry.WORD_COUNT) { slot ->
            val height by animateDpAsState(
                targetValue = if (slot == entry.index) TickCurrent else TickResting,
                label = "seed-tick",
            )
            val tint by animateColorAsState(
                targetValue = tickTint(entry, slot),
                label = "seed-tick-tint",
            )
            Box(
                modifier = Modifier
                    .width(RailHitWidth)
                    .height(RailSlot),
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    modifier = Modifier
                        .width(RailWidth)
                        .height(height)
                        .clip(RoundedCornerShape(percent = 50))
                        .background(tint),
                )
            }
        }
    }
}

/** The tick under a y-position, clamped to the rail. */
private fun Density.slotAt(y: Float): Int =
    (y / RailSlot.toPx()).toInt().coerceIn(0, SeedPhraseEntry.WORD_COUNT - 1)

@Composable
private fun tickTint(entry: SeedPhraseEntry, slot: Int): Color = when {
    entry.isComplete -> CashuTheme.colors.received
    slot == entry.index -> MaterialTheme.colorScheme.onSurface
    entry.isSettled(slot) -> MaterialTheme.colorScheme.onSurfaceVariant
    else -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.20f)
}

// ---------------------------------------------------------------------------
// Suggestions
// ---------------------------------------------------------------------------

/**
 * The row under the card, three-state: the paste chip while nothing is entered,
 * wordlist completions while typing, reserved space otherwise. One row, one
 * height — a hidden chip pins it in every state so the card never reflows.
 */
@Composable
private fun SeedWordChipRow(
    words: List<String>,
    onPaste: (() -> Unit)?,
    onSelect: (String) -> Unit,
) {
    Box(contentAlignment = Alignment.CenterStart) {
        // A hidden chip reserves the real row height without stating one.
        ChipLabel(word = "placeholder", modifier = Modifier.alpha(0f).clearAndSetSemantics {})

        Row(horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug)) {
            when {
                // Pasting is the most common way in, so it takes the spot the
                // eye is already on — directly under the card — rather than a
                // ghost link under a disabled CTA. It yields this row to the
                // suggestions the moment typing starts.
                onPaste != null -> PasteChip(onPaste)
                words.isNotEmpty() -> words.forEachIndexed { index, word ->
                    ChipLabel(
                        word = word,
                        modifier = Modifier
                            .testTag(UiTestTags.seedSuggestion(index))
                            .clip(RoundedCornerShape(ChipRadius))
                            .clickable { onSelect(word) },
                    )
                }
            }
        }
    }
}

@Composable
private fun PasteChip(onPaste: () -> Unit) {
    Row(
        modifier = Modifier
            .testTag(UiTestTags.SeedPaste)
            .clip(RoundedCornerShape(ChipRadius))
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .clickable(onClick = onPaste)
            .padding(horizontal = CashuTheme.spacing.default, vertical = CashuTheme.spacing.snug),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
    ) {
        Icon(
            imageVector = Icons.Outlined.ContentPaste,
            contentDescription = null,
            modifier = Modifier.size(ChipGlyphSize),
            tint = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            // A control, not a wordlist word — regular UI type, mono stays
            // reserved for the words themselves.
            text = SeedEntryCopy.PASTE_LINK,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
private fun ChipLabel(word: String, modifier: Modifier = Modifier) {
    Text(
        text = word,
        style = CashuTheme.type.monoBody,
        color = MaterialTheme.colorScheme.onSurface,
        modifier = modifier
            .clip(RoundedCornerShape(ChipRadius))
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .padding(horizontal = CashuTheme.spacing.default, vertical = CashuTheme.spacing.snug),
    )
}

// ---------------------------------------------------------------------------
// Review grid
// ---------------------------------------------------------------------------

/**
 * Where a checksum failure lands. The checksum says one of the twelve is wrong
 * but never which, so the only honest recovery is to show all of them. Mirrors
 * `SeedGrid`'s geometry so the two seed surfaces read alike, but is a separate
 * composable on purpose — `SeedPhraseAccessibilityComposeTest` pins the reveal
 * card's semantics and this must not be able to disturb them.
 */
@Composable
private fun SeedWordReviewGrid(words: List<String>, onSelect: (Int) -> Unit) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(3),
        modifier = Modifier
            .fillMaxWidth()
            .testTag(UiTestTags.SeedWordReview)
            .clip(RoundedCornerShape(CardRadius))
            .background(MaterialTheme.colorScheme.surfaceContainerHighest)
            .padding(CardPadding),
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
    ) {
        itemsIndexed(words) { index, word ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onSelect(index) }
                    .semantics { contentDescription = "Word ${index + 1}, $word" },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
            ) {
                Text(
                    text = "%02d".format(index + 1),
                    style = CashuTheme.type.monoCaption,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = word,
                    style = CashuTheme.type.monoBody.withSlashedZero(),
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}
