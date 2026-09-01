package com.cashu.me.ui.restore

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cashu.me.Core.Bip39WordList
import com.cashu.me.Core.CommitOutcome
import com.cashu.me.Core.NostrMintBackupService
import com.cashu.me.Core.PasteOutcome
import com.cashu.me.Core.Wallet.userFacingWalletMessage
import com.cashu.me.Core.WalletManager
import com.cashu.me.Core.mintUrlCandidates
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.RestoreMintResult
import com.cashu.me.ui.components.CashuTextField
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.IconSwap
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.MintAvatar
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.ScrollFadeBand
import com.cashu.me.ui.components.ghostButtonUnderCtaTextStyle
import com.cashu.me.ui.components.scrollEdgeFade
import com.cashu.me.ui.testing.UiTestTags
import com.cashu.me.ui.theme.CapsuleShape
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withMonoDigits
import com.cashu.me.ui.theme.withSlashedZero
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

// iOS restore twin: OnboardingView seed branch + Settings RestoreWalletView.
// Shared seed → mints → progress phases with quiet crossfades owned by callers.
//
// Each step is split into a stateless stage body (*StageContent / *Rows) plus a
// state holder (remember*State), so the onboarding chassis can host the
// headline/subhead/CTAs while Settings → Restore keeps the classic inline
// header+footer layout through the unchanged *Step wrappers below.

private val HeaderPadding = 28.dp
private val CtaPadding = 24.dp
private val BottomPadding = 24.dp
private val MintAvatarSize = 36.dp
private val ProgressSpinnerSize = 18.dp
private val ChipGlyphSize = 18.dp

// Mint-staging copy. Hoisted because the subhead alone had four call sites
// (both hosts here, the onboarding stage, and the screenshot baseline) and they
// had already started drifting. iOS twin: OnboardingView.restoreMintsStage.
//
// Name the reason this step exists at all. Without it the screen reads as
// busywork, and the user has no way to know the seed alone can't find their
// money. The second sentence names both routes forward, because the backup
// lookup no longer runs itself.
internal const val RestoreMintsTitleOnboarding = "Add your mints."
internal const val RestoreMintsTitleInApp = "Add your mints"
internal const val RestoreMintsSubhead =
    "Your seed phrase doesn't record which mints you used. " +
        "Find them from a backup, or add them yourself."

// The list is empty far more often than not, and the disabled primary never
// says why. These three lines are the only place that explains the wait and the
// way out. The landing line carries the most weight: it is where everyone now
// arrives, so it has to name the button rather than describe the situation.
internal const val RestoreMintsEmptyLanding =
    "Tap Find my mints to look for a backup of your mint list, or add them above."
internal const val RestoreMintsEmptySearching = "Checking for a backup of your mint list…"
internal const val RestoreMintsEmptyNoBackup =
    "No backup found. Add the mints you used before, then restore."

/** Layout chrome for onboarding (large heavy titles) vs in-app settings. */
enum class RestorePresentation {
    Onboarding,
    InApp,
}

sealed interface RestoreMintPhase {
    data object Pending : RestoreMintPhase
    data object Restoring : RestoreMintPhase
    data class Recovered(val result: RestoreMintResult) : RestoreMintPhase
    data class Failed(val message: String) : RestoreMintPhase
}

internal fun restoreMintFailurePhase(error: Throwable): RestoreMintPhase.Failed =
    RestoreMintPhase.Failed(error.userFacingWalletMessage)

@Composable
fun restoreOnboardingTitleStyle(): TextStyle =
    CashuTheme.type.title

// Single-line onboarding titles render at full display size and step down only
// when the line would overflow (narrow devices / large font scales).
private val OnboardingTitleAutoSize = TextAutoSize.StepBased(
    minFontSize = 26.sp,
    maxFontSize = 36.sp,
    stepSize = 1.sp,
)

@Composable
private fun restoreInAppTitleStyle(): TextStyle =
    MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.SemiBold)

@Composable
private fun restoreTitleStyle(presentation: RestorePresentation): TextStyle =
    when (presentation) {
        RestorePresentation.Onboarding -> restoreOnboardingTitleStyle()
        RestorePresentation.InApp -> restoreInAppTitleStyle()
    }

// ---------------------------------------------------------------------------
// Seed
// ---------------------------------------------------------------------------

/**
 * The BIP-39 checksum, run at the only moment it can be: once all twelve words
 * are in. It says one of them is wrong but never which, so a failure hands the
 * whole phrase back on the review grid. iOS twin: `runSeedChecksum`.
 */
internal suspend fun runSeedChecksum(
    state: SeedPhraseEntryState,
    validate: suspend (String) -> Boolean,
) {
    if (!state.isComplete) return
    if (validate(state.phrase)) {
        state.notice = null
        return
    }
    state.markReviewing()
    state.notice = SeedEntryNotice(SeedEntryCopy.CHECKSUM, NoticeSeverity.Error)
}

/** Fill every slot from the clipboard. iOS twin: `pasteMnemonicFromClipboard`. */
internal suspend fun pasteSeedPhrase(
    state: SeedPhraseEntryState,
    clipboardText: String?,
    validate: suspend (String) -> Boolean,
) {
    if (clipboardText.isNullOrBlank()) {
        state.notice = SeedEntryNotice(SeedEntryCopy.PASTE_UNUSABLE, NoticeSeverity.Caution)
        return
    }
    val result = state.entry.fill(clipboardText)
    state.entry = result.entry
    when (val outcome = result.outcome) {
        PasteOutcome.Filled -> {
            state.notice = null
            runSeedChecksum(state, validate)
        }
        is PasteOutcome.Partial ->
            state.notice = SeedEntryNotice(
                SeedEntryCopy.pastePartial(outcome.count),
                NoticeSeverity.Caution,
            )
        is PasteOutcome.Invalid ->
            state.notice = SeedEntryNotice(
                SeedEntryCopy.pasteInvalid(outcome.index),
                NoticeSeverity.Caution,
            )
        PasteOutcome.Unusable ->
            state.notice = SeedEntryNotice(SeedEntryCopy.PASTE_UNUSABLE, NoticeSeverity.Caution)
    }
}

/**
 * The live seed-entry stage: one word at a time, validated as it lands, with a
 * progress rail and wordlist completions. Stateless — the caller owns the
 * [SeedPhraseEntryState]. Shared by the onboarding chassis host and the
 * Settings wrapper, because both ask for exactly the same thing.
 */
@Composable
fun RestoreSeedStageContent(
    state: SeedPhraseEntryState,
    onOutcome: (CommitOutcome) -> Unit,
    errorText: String?,
    modifier: Modifier = Modifier,
    autoFocus: Boolean = true,
    onPaste: (() -> Unit)? = null,
) {
    Column(
        modifier = modifier
            .padding(horizontal = HeaderPadding)
            // iOS restore-input twin (`.scrollEdgeFade(bottom: 0)`): the
            // keyboard is up for this whole step, so content dissolves into
            // the chassis edge instead of cutting against it. Before the
            // scroll modifier so the layer wraps the scroll clip.
            .scrollEdgeFade(bottom = 0.dp)
            .verticalScroll(rememberScrollState())
            // Inside the scroll, not outside: verticalScroll clips, and the
            // ghost cards peek ~11dp above the card's top edge — which is the
            // content's top edge now that the card leads its column. Padding
            // placed after the scroll modifier becomes scrolled content and
            // gives the ghosts headroom inside the clip. The bottom band lets
            // the last row scroll clear of the fade.
            .padding(top = CashuTheme.spacing.section, bottom = ScrollFadeBand),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
    ) {
        SeedWordEntryField(
            state = state,
            onOutcome = onOutcome,
            autoFocus = autoFocus,
            onPaste = onPaste,
            modifier = Modifier.fillMaxWidth(),
        )
        // The install failure is a different problem from a mistyped word and
        // keeps its own channel.
        if (errorText != null) {
            InlineNotice(text = errorText, severity = NoticeSeverity.Error)
        }
    }
}

/**
 * Seed-entry step shared by onboarding and Settings → Restore.
 *
 * iOS: monospaced editor, paste/clear corner control, live word counter,
 * CTA **Next** once 12 words are present. Full BIP-39 validation runs on submit.
 */
@Composable
fun RestoreSeedStep(
    presentation: RestorePresentation,
    restoring: Boolean,
    errorText: String?,
    onClearError: () -> Unit,
    onBack: (() -> Unit)?,
    onNext: (String) -> Unit,
    onValidateChecksum: suspend (String) -> Boolean,
) {
    val seedState = rememberSeedPhraseEntryState()
    val clipboard = LocalClipboardManager.current
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    // Per-word validity is structural now — a word cannot be committed unless it
    // is in the list — so the old `requireValidWords` switch has nothing left to
    // choose between. What remains is the checksum, which both hosts enforce.
    val canContinue = seedState.isComplete && !seedState.isReviewing && !restoring

    val titleAlign = if (presentation == RestorePresentation.InApp) {
        Alignment.CenterHorizontally
    } else {
        Alignment.Start
    }
    val titleTextAlign = if (presentation == RestorePresentation.InApp) {
        TextAlign.Center
    } else {
        TextAlign.Start
    }
    val title = if (presentation == RestorePresentation.InApp) {
        "Restore Wallet"
    } else {
        "Restore wallet."
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = HeaderPadding)
                .padding(top = CashuTheme.spacing.snug),
            horizontalAlignment = titleAlign,
            verticalArrangement = Arrangement.spacedBy(
                if (presentation == RestorePresentation.InApp) {
                    CashuTheme.spacing.micro
                } else {
                    CashuTheme.spacing.snug
                },
            ),
        ) {
            Text(
                text = title,
                style = restoreTitleStyle(presentation),
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = titleTextAlign,
                maxLines = if (presentation == RestorePresentation.Onboarding) 1 else Int.MAX_VALUE,
                autoSize = if (presentation == RestorePresentation.Onboarding) OnboardingTitleAutoSize else null,
            )
            Text(
                text = "Enter your 12 words in order.",
                style = if (presentation == RestorePresentation.InApp) {
                    MaterialTheme.typography.bodyMedium
                } else {
                    MaterialTheme.typography.bodyLarge
                },
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = titleTextAlign,
            )
        }

        RestoreSeedStageContent(
            state = seedState,
            onOutcome = { outcome ->
                if (outcome != CommitOutcome.Ignored) {
                    seedState.notice = null
                    onClearError()
                }
                if (outcome == CommitOutcome.Completed) {
                    scope.launch { runSeedChecksum(seedState, onValidateChecksum) }
                }
            },
            onPaste = {
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                scope.launch {
                    pasteSeedPhrase(seedState, clipboard.getText()?.text, onValidateChecksum)
                }
            },
            errorText = errorText,
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
        )

        Column(
            modifier = Modifier
                .padding(horizontal = CtaPadding)
                .padding(top = CashuTheme.spacing.comfortable)
                .padding(bottom = BottomPadding),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            PrimaryButton(
                text = "Next",
                onClick = { onNext(seedState.phrase) },
                enabled = canContinue,
                loading = restoring,
            )
            if (onBack != null) {
                GhostButton(
                    text = "Back",
                    onClick = onBack,
                    enabled = !restoring,
                    textStyle = ghostButtonUnderCtaTextStyle,
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Mints
// ---------------------------------------------------------------------------

/**
 * The mint-staging state machine — input parsing, dedupe, previews, clipboard
 * and Nostr-backup ingestion — shared by the onboarding chassis host and the
 * Settings → Restore wrapper.
 */
@Stable
class RestoreMintsStagingState internal constructor(
    private val scope: CoroutineScope,
    private val walletManager: WalletManager,
    private val nostrMintBackupService: NostrMintBackupService,
    private val clipboard: ClipboardManager,
    private val haptics: HapticFeedback,
) {
    var input by mutableStateOf("")
        private set
    var staged by mutableStateOf<List<String>>(emptyList())
        private set
    val previews = mutableStateMapOf<String, MintInfo>()
    var notice by mutableStateOf<String?>(null)
        private set
    var noticeSeverity by mutableStateOf(NoticeSeverity.Info)
        private set

    fun updateInput(value: String) {
        input = value
        notice = null
    }

    private fun setNotice(message: String?, severity: NoticeSeverity = NoticeSeverity.Info) {
        notice = message
        noticeSeverity = severity
    }

    private fun stageUrl(raw: String, showDuplicate: Boolean, showInvalid: Boolean): Boolean {
        val normalized = normalizeMintUrl(raw) ?: run {
            if (showInvalid) setNotice("That doesn't look like a mint URL.", NoticeSeverity.Caution)
            return false
        }
        if (staged.any { it.equals(normalized, ignoreCase = true) }) {
            // "staged" is our word, not the user's.
            if (showDuplicate) setNotice("This mint is already in the list.", NoticeSeverity.Caution)
            return false
        }
        staged = staged + normalized
        setNotice(null)
        scope.launch {
            runCatching { walletManager.fetchLiveMintInfo(normalized) }
                .getOrNull()
                ?.let { previews[normalized] = it }
        }
        return true
    }

    fun addInput() {
        val candidates = mintUrlCandidates(input).ifEmpty {
            listOfNotNull(normalizeMintUrl(input))
        }
        if (candidates.isEmpty()) {
            setNotice("Paste one or more mint URLs.", NoticeSeverity.Error)
            return
        }
        var added = 0
        for (candidate in candidates) {
            if (stageUrl(candidate, showDuplicate = false, showInvalid = false)) added++
        }
        when {
            added == 0 -> setNotice("No new mints to add.")
            added == 1 -> {
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                setNotice(null)
            }
            else -> {
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                setNotice("Added $added mints.")
            }
        }
        if (added > 0) input = ""
    }

    fun pasteFromClipboard() {
        val content = clipboard.getText()?.text
        if (content.isNullOrBlank()) {
            setNotice("Clipboard is empty.")
            return
        }
        val candidates = mintUrlCandidates(content)
        var added = 0
        var invalid = 0
        if (candidates.isEmpty()) {
            val single = normalizeMintUrl(content)
            if (single != null) {
                if (stageUrl(single, showDuplicate = false, showInvalid = false)) added++
            } else {
                invalid++
            }
        } else {
            for (candidate in candidates) {
                if (stageUrl(candidate, showDuplicate = false, showInvalid = false)) {
                    added++
                }
            }
            val tokens = content.split(Regex("[\\s,;]+")).filter { it.isNotBlank() }
            invalid = (tokens.size - candidates.size).coerceAtLeast(0)
        }
        when {
            added == 0 && invalid > 0 ->
                setNotice("Nothing in the clipboard looked like a mint URL.", NoticeSeverity.Error)
            added == 0 -> setNotice("No new mints to add.")
            invalid > 0 -> {
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                setNotice(
                    "Added $added mint${if (added == 1) "" else "s"}. " +
                        "Skipped $invalid that didn't look like a mint URL.",
                )
            }
            else -> {
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                setNotice("Added $added mint${if (added == 1) "" else "s"}.")
            }
        }
    }

    /// True once a lookup has finished, however it finished — drives the
    /// empty-state line's "no backup found" wording.
    var backupSearchCompleted by mutableStateOf(false)
        private set

    /**
     * Look up the encrypted mint-list backup for this seed on the user's relays
     * and stage every mint it contains.
     *
     * Only ever runs from an explicit tap. It used to fire on arrival, on the
     * grounds that publishing is on by default so most people have a list
     * waiting — but the step opens by telling the user their seed phrase doesn't
     * record which mints they used, and then a dozen of their mints appeared
     * anyway. The user has no way to see the lookup happen, so the screen read
     * as contradicting itself, or as the wallet knowing more about them than
     * they agreed to. The lookup is still one tap away; the tap is now theirs,
     * which is what makes the result explicable.
     */
    fun searchNostrBackup() {
        // The chip stops taking taps while a lookup is in flight, but that is a
        // view-layer courtesy; refuse re-entry here so a second call can never
        // double-stage the same backup.
        if (nostrMintBackupService.state.value.isSearching) return
        scope.launch {
            runCatching { nostrMintBackupService.fetchBackedUpMintUrls() }
                .onSuccess { urls ->
                    val normalized = urls.mapNotNull(::normalizeMintUrl)
                    var added = 0
                    for (url in normalized) {
                        if (stageUrl(url, showDuplicate = false, showInvalid = false)) added++
                    }
                    when {
                        added > 0 ->
                            setNotice("Added $added mint${if (added == 1) "" else "s"} from your backup.")
                        // When the list is empty the empty-state line is on
                        // screen already saying this — speak here only when it
                        // isn't.
                        normalized.isEmpty() ->
                            if (staged.isNotEmpty()) {
                                setNotice("No backup of your mint list found.", NoticeSeverity.Caution)
                            }
                        else -> setNotice("Backup found. Its mints are already in the list.")
                    }
                    backupSearchCompleted = true
                }
                .onFailure {
                    backupSearchCompleted = true
                    // Through the shared mapper, never the raw message — a
                    // relay failure here surfaced as a raw CDK FFI dump.
                    setNotice(it.userFacingWalletMessage, NoticeSeverity.Error)
                }
        }
    }

    fun remove(url: String) {
        staged = staged.filterNot { it == url }
        previews.remove(url)
    }

    fun reset() {
        input = ""
        staged = emptyList()
        previews.clear()
        notice = null
        noticeSeverity = NoticeSeverity.Info
        // Clear the searched flag too, or returning to this step lands on "No
        // backup found" instead of the line that names the button — a dead
        // screen with no way forward.
        backupSearchCompleted = false
    }
}

@Composable
fun rememberRestoreMintsStagingState(
    walletManager: WalletManager,
    nostrMintBackupService: NostrMintBackupService,
): RestoreMintsStagingState {
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current
    val haptics = LocalHapticFeedback.current
    return remember(walletManager, nostrMintBackupService) {
        RestoreMintsStagingState(scope, walletManager, nostrMintBackupService, clipboard, haptics)
    }
}

/**
 * The live mint-staging stage: URL field, Add/Paste/Nostr capsule chips, notice,
 * and the staged-mint rows, in one scrolling column. Stateless — pair it with
 * [RestoreMintsStagingState] (or preview it with plain values).
 */
@Composable
fun RestoreMintsStageContent(
    input: String,
    staged: List<String>,
    previews: Map<String, MintInfo>,
    notice: String?,
    noticeSeverity: NoticeSeverity,
    searching: Boolean,
    onInputChange: (String) -> Unit,
    onAdd: () -> Unit,
    onPaste: () -> Unit,
    onNostr: () -> Unit,
    onRemove: (String) -> Unit,
    modifier: Modifier = Modifier,
    backupSearchCompleted: Boolean = false,
) {
    Column(
        modifier = modifier
            // The chassis is a sibling below this stage rather than an overlay,
            // so the stage's own bottom edge is the clip line — hence a zero
            // inset, not a chassis-height one. iOS insets by the chassis
            // because its content really does run underneath. No top fade: the
            // whole stage scrolls as one unit, so the first thing in the
            // container is the URL field sitting flush at the top edge, and a
            // top mask would permanently dim it.
            .scrollEdgeFade(bottom = 0.dp)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = HeaderPadding)
            // Bottom clearance equal to the fade band, so scrolling to the end
            // parks the last row clear of the gradient instead of leaving it
            // permanently dimmed.
            .padding(bottom = ScrollFadeBand),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        CashuTextField(
            value = input,
            onValueChange = onInputChange,
            modifier = Modifier.fillMaxWidth(),
            placeholder = "mint.example.com",
            textStyle = MaterialTheme.typography.bodyMedium,
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None,
                keyboardType = KeyboardType.Uri,
                imeAction = ImeAction.Done,
            ),
            keyboardActions = KeyboardActions(onDone = { onAdd() }),
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
        ) {
            RestoreCapsuleChip(
                text = "Add",
                icon = Icons.Outlined.Add,
                onClick = onAdd,
                enabled = input.isNotBlank(),
                modifier = Modifier.weight(1f),
            )
            RestoreCapsuleChip(
                text = "Paste",
                icon = Icons.Outlined.ContentPaste,
                onClick = onPaste,
                modifier = Modifier.weight(1f),
            )
        }

        // "Nostr" named the transport, not the outcome. The user doesn't need
        // to know where their mint list is kept — only that we can go and look
        // for it. It gets its own row because it is the way through this step
        // for anyone who can't recite their mint URLs, which is most people;
        // third-of-a-row next to Add and Paste both buried it and truncated it.
        RestoreCapsuleChip(
            text = "Find my mints",
            busyText = "Checking for your mints…",
            icon = Icons.Outlined.Search,
            onClick = onNostr,
            loading = searching,
            modifier = Modifier.fillMaxWidth(),
        )

        if (notice != null) {
            InlineNotice(text = notice, severity = noticeSeverity)
        }

        if (staged.isNotEmpty()) {
            Column(modifier = Modifier.fillMaxWidth()) {
                staged.forEach { url ->
                    StagedMintRow(
                        url = url,
                        preview = previews[url],
                        onRemove = { onRemove(url) },
                    )
                }
            }
        } else {
            Text(
                text = when {
                    searching -> RestoreMintsEmptySearching
                    backupSearchCompleted -> RestoreMintsEmptyNoBackup
                    else -> RestoreMintsEmptyLanding
                },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = CashuTheme.spacing.default),
            )
        }
    }
}

/**
 * Mint staging step — Add / Paste / Nostr capsule chips; CTA requires ≥1 mint
 * (iOS both onboarding and Settings restore).
 */
@Composable
fun RestoreMintsStep(
    presentation: RestorePresentation,
    walletManager: WalletManager,
    nostrMintBackupService: NostrMintBackupService,
    onBack: () -> Unit,
    onRestore: (List<String>, Map<String, MintInfo>) -> Unit,
    showBottomBack: Boolean = presentation == RestorePresentation.Onboarding,
) {
    val staging = rememberRestoreMintsStagingState(walletManager, nostrMintBackupService)
    val backupState by nostrMintBackupService.state.collectAsState()

    val titleAlign = if (presentation == RestorePresentation.InApp) {
        Alignment.CenterHorizontally
    } else {
        Alignment.Start
    }
    val titleTextAlign = if (presentation == RestorePresentation.InApp) {
        TextAlign.Center
    } else {
        TextAlign.Start
    }
    // Onboarding renders its own header via OnboardingStepHeader and only calls
    // RestoreMintsStageContent, so that arm is unreachable in production today.
    // It stays keyed off the shared consts rather than being deleted here — the
    // whole RestorePresentation split is dead across every Restore*Step and is
    // worth removing in one pass, not piecemeal.
    val (title, subtitle) = when (presentation) {
        RestorePresentation.Onboarding -> RestoreMintsTitleOnboarding to RestoreMintsSubhead
        RestorePresentation.InApp -> RestoreMintsTitleInApp to RestoreMintsSubhead
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = HeaderPadding)
                .padding(top = CashuTheme.spacing.snug)
                .padding(bottom = CashuTheme.spacing.section),
            horizontalAlignment = titleAlign,
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
        ) {
            Text(
                text = title,
                style = restoreTitleStyle(presentation),
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = titleTextAlign,
                maxLines = if (presentation == RestorePresentation.Onboarding) 1 else Int.MAX_VALUE,
                autoSize = if (presentation == RestorePresentation.Onboarding) OnboardingTitleAutoSize else null,
            )
            Text(
                text = subtitle,
                style = if (presentation == RestorePresentation.InApp) {
                    MaterialTheme.typography.bodyMedium
                } else {
                    MaterialTheme.typography.bodyLarge
                },
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = titleTextAlign,
            )
        }

        RestoreMintsStageContent(
            input = staging.input,
            staged = staging.staged,
            previews = staging.previews,
            notice = staging.notice,
            noticeSeverity = staging.noticeSeverity,
            searching = backupState.isSearching,
            onInputChange = staging::updateInput,
            onAdd = staging::addInput,
            onPaste = staging::pasteFromClipboard,
            onNostr = staging::searchNostrBackup,
            onRemove = staging::remove,
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            backupSearchCompleted = staging.backupSearchCompleted,
        )

        Column(
            modifier = Modifier
                .padding(horizontal = CtaPadding)
                .padding(top = CashuTheme.spacing.snug)
                .padding(bottom = BottomPadding),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            PrimaryButton(
                text = if (staging.staged.isEmpty()) {
                    "Restore"
                } else {
                    "Restore from ${staging.staged.size} mint${if (staging.staged.size == 1) "" else "s"}"
                },
                onClick = { onRestore(staging.staged, staging.previews.toMap()) },
                enabled = staging.staged.isNotEmpty(),
            )
            if (showBottomBack) {
                GhostButton(
                    text = "Back",
                    onClick = {
                        staging.reset()
                        onBack()
                    },
                    textStyle = ghostButtonUnderCtaTextStyle,
                )
            }
        }
    }
}

@Composable
private fun RestoreCapsuleChip(
    text: String,
    icon: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    loading: Boolean = false,
    /** Busy-state label. Set, both states stay resident and cross-fade in
     * place (iOS `mintLookupChip`); unset, [text] is the only label. */
    busyText: String? = null,
) {
    val contentAlpha = if (enabled) 1f else 0.38f
    Surface(
        // Working is not the same as disabled. Passing `enabled = false` while a
        // lookup runs drops the content to 0.38 alpha, and a spinner in a greyed
        // capsule looks broken rather than busy — the spinner is already the
        // busy signal. Swallow the click instead and keep the chip at full
        // strength. Re-entry is refused in the state holder regardless.
        onClick = { if (!loading) onClick() },
        enabled = enabled,
        modifier = modifier,
        shape = CapsuleShape,
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) {
        if (busyText != null) {
            // Both states resident, so the chip's geometry is constant and a
            // lookup starting only moves opacity — a single swapped label
            // re-centres the row mid-animation and drags the glyph across the
            // chip. iOS twin: OnboardingView.mintLookupChip's ZStack.
            val idleAlpha by animateFloatAsState(
                targetValue = if (loading) 0f else 1f,
                label = "chip-idle",
            )
            val busyAlpha by animateFloatAsState(
                targetValue = if (loading) 1f else 0f,
                label = "chip-busy",
            )
            Box(
                modifier = Modifier.fillMaxWidth(),
                contentAlignment = Alignment.Center,
            ) {
                RestoreChipContent(
                    text = text,
                    contentAlpha = contentAlpha * idleAlpha,
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        modifier = Modifier.size(ChipGlyphSize),
                        tint = MaterialTheme.colorScheme.onSurface.copy(alpha = contentAlpha * idleAlpha),
                    )
                }
                RestoreChipContent(
                    text = busyText,
                    contentAlpha = contentAlpha * busyAlpha,
                ) {
                    LoadingIndicator(
                        modifier = Modifier.size(ChipGlyphSize),
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = contentAlpha * busyAlpha),
                    )
                }
            }
        } else {
            RestoreChipContent(text = text, contentAlpha = contentAlpha) {
                // Fixed glyph box so swapping the symbol for a spinner can't
                // change the chip's height, and a cross-fade rather than a
                // swap so the glyph dissolves in place.
                Crossfade(targetState = loading, label = "chip-glyph") { busy ->
                    if (busy) {
                        LoadingIndicator(
                            modifier = Modifier.size(ChipGlyphSize),
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    } else {
                        Icon(
                            imageVector = icon,
                            contentDescription = null,
                            modifier = Modifier.size(ChipGlyphSize),
                            tint = MaterialTheme.colorScheme.onSurface.copy(alpha = contentAlpha),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun RestoreChipContent(
    text: String,
    contentAlpha: Float,
    modifier: Modifier = Modifier,
    glyph: @Composable () -> Unit,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp, horizontal = CashuTheme.spacing.snug),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier.size(ChipGlyphSize),
            contentAlignment = Alignment.Center,
        ) {
            glyph()
        }
        Spacer(Modifier.size(CashuTheme.spacing.micro))
        Text(
            text = text,
            style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = contentAlpha),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun StagedMintRow(
    url: String,
    preview: MintInfo?,
    onRemove: () -> Unit,
) {
    val name = preview?.name?.takeIf { it.isNotBlank() && it != "Unknown Mint" }
        ?: shortenMintUrl(url)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = CashuTheme.spacing.snug),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
    ) {
        MintAvatar(
            mint = MintInfo(
                url = url,
                name = name,
                iconUrl = preview?.iconUrl,
            ),
            size = MintAvatarSize,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = name,
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium),
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = url,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.MiddleEllipsis,
            )
        }
        IconButton(onClick = onRemove) {
            Icon(
                Icons.Filled.Cancel,
                contentDescription = "Remove mint",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Progress (forward-only)
// ---------------------------------------------------------------------------

/**
 * The per-mint restore state machine. Restores start as soon as the state is
 * remembered (via [rememberRestoreProgressState]) and the flow is forward-only.
 */
@Stable
class RestoreProgressState internal constructor(
    private val scope: CoroutineScope,
    private val walletManager: WalletManager,
    val mintUrls: List<String>,
) {
    val phases = mutableStateMapOf<String, RestoreMintPhase>().apply {
        mintUrls.forEach { put(it, RestoreMintPhase.Pending) }
    }
    var finishing by mutableStateOf(false)

    val allSettled: Boolean
        get() = mintUrls.isEmpty() || (
            phases.size == mintUrls.size &&
                phases.values.all {
                    it is RestoreMintPhase.Recovered || it is RestoreMintPhase.Failed
                }
            )

    val totalRecovered: Long
        get() = phases.values.sumOf { phase ->
            (phase as? RestoreMintPhase.Recovered)?.result?.unspent ?: 0L
        }

    val subhead: String
        get() = when {
            !allSettled -> "Checking your mints…"
            totalRecovered > 0L -> "Here's what we restored."
            // Zero back is the outcome the user fears most. Name the one cause
            // they can still act on instead of leaving them to guess.
            else -> "No funds on these mints. If you used others, go back and add them."
        }

    internal suspend fun restoreMint(url: String) {
        phases[url] = RestoreMintPhase.Restoring
        runCatching { walletManager.restoreFromMint(url) }
            .onSuccess { phases[url] = RestoreMintPhase.Recovered(it) }
            .onFailure {
                phases[url] = restoreMintFailurePhase(it)
            }
    }

    internal suspend fun restoreAll() {
        mintUrls.forEach { url -> restoreMint(url) }
    }

    fun retry(url: String) {
        scope.launch { restoreMint(url) }
    }
}

@Composable
fun rememberRestoreProgressState(
    walletManager: WalletManager,
    mintUrls: List<String>,
): RestoreProgressState {
    val scope = rememberCoroutineScope()
    val state = remember(walletManager, mintUrls) {
        RestoreProgressState(scope, walletManager, mintUrls)
    }
    LaunchedEffect(state) { state.restoreAll() }
    return state
}

/** The green recovered-sats total (monospaced digits — Numbers Are Sacred). */
@Composable
fun RestoreRecoveredTotal(
    totalRecovered: Long,
    modifier: Modifier = Modifier,
    centered: Boolean = false,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.micro),
        verticalAlignment = Alignment.CenterVertically,
        modifier = if (centered) modifier.fillMaxWidth() else modifier,
    ) {
        if (centered) {
            Spacer(Modifier.weight(1f))
        }
        Icon(
            imageVector = Icons.Filled.CheckCircle,
            contentDescription = null,
            tint = CashuTheme.colors.onReceivedContainer,
            modifier = Modifier.size(18.dp),
        )
        Text(
            text = "Recovered: $totalRecovered sats",
            style = MaterialTheme.typography.bodyMedium
                .copy(fontWeight = FontWeight.SemiBold)
                .withMonoDigits(),
            color = CashuTheme.colors.onReceivedContainer,
        )
        if (centered) {
            Spacer(Modifier.weight(1f))
        }
    }
}

/** The scrolling per-mint progress rows. Stateless — the caller owns phases. */
@Composable
fun RestoreProgressRows(
    mintUrls: List<String>,
    phases: Map<String, RestoreMintPhase>,
    previews: Map<String, MintInfo>,
    onRetry: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            // Both edges, unlike the staging step: this list scrolls
            // unattended while mints settle, so rows cross both boundaries
            // with nobody driving. The recovered total is pinned above and the
            // CTA below, and rows were cutting dead against each.
            .scrollEdgeFade(top = 0.dp, bottom = 0.dp)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = HeaderPadding)
            // Clearance equal to the fade band at both ends. A static edge mask
            // can't tell "scrolled past" from "this is the end", so without this
            // the first and last rows sit inside the gradient and render dimmed
            // at rest — a defect, not a hint. Padded, the extremes park clear of
            // the band and only genuinely-clipped rows dissolve.
            .padding(vertical = ScrollFadeBand),
    ) {
        mintUrls.forEach { url ->
            RestoreProgressRow(
                url = url,
                phase = phases[url] ?: RestoreMintPhase.Pending,
                preview = previews[url],
                onRetry = { onRetry(url) },
            )
        }
    }
}

/**
 * Per-mint restore progress + results. Forward-only once entered (no back CTA).
 * Primary action is **Continue** once every mint has settled (iOS).
 */
@Composable
fun RestoreProgressStep(
    presentation: RestorePresentation,
    walletManager: WalletManager,
    mintUrls: List<String>,
    stagedPreviews: Map<String, MintInfo> = emptyMap(),
    onContinue: () -> Unit,
) {
    val state = rememberRestoreProgressState(walletManager, mintUrls)

    val titleAlign = if (presentation == RestorePresentation.InApp) {
        Alignment.CenterHorizontally
    } else {
        Alignment.Start
    }
    val titleTextAlign = if (presentation == RestorePresentation.InApp) {
        TextAlign.Center
    } else {
        TextAlign.Start
    }
    val title = when (presentation) {
        RestorePresentation.Onboarding -> "Restoring wallet."
        RestorePresentation.InApp ->
            if (state.allSettled) "Restore complete" else "Restoring…"
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = HeaderPadding)
                .padding(top = CashuTheme.spacing.snug)
                .padding(bottom = CashuTheme.spacing.section),
            horizontalAlignment = titleAlign,
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
        ) {
            Text(
                text = title,
                style = restoreTitleStyle(presentation),
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = titleTextAlign,
                maxLines = if (presentation == RestorePresentation.Onboarding) 1 else Int.MAX_VALUE,
                autoSize = if (presentation == RestorePresentation.Onboarding) OnboardingTitleAutoSize else null,
            )
            Text(
                text = state.subhead,
                style = if (presentation == RestorePresentation.InApp) {
                    MaterialTheme.typography.bodyMedium
                } else {
                    MaterialTheme.typography.bodyLarge
                },
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = titleTextAlign,
            )
            if (state.totalRecovered > 0L) {
                RestoreRecoveredTotal(
                    totalRecovered = state.totalRecovered,
                    centered = presentation == RestorePresentation.InApp,
                )
            }
        }

        RestoreProgressRows(
            mintUrls = mintUrls,
            phases = state.phases,
            previews = stagedPreviews,
            onRetry = state::retry,
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
        )

        Column(
            modifier = Modifier
                .padding(horizontal = CtaPadding)
                .padding(top = CashuTheme.spacing.snug)
                .padding(bottom = BottomPadding),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            PrimaryButton(
                text = "Continue",
                onClick = {
                    state.finishing = true
                    onContinue()
                },
                enabled = state.allSettled && !state.finishing,
                loading = state.finishing,
                colors = ButtonDefaults.filledTonalButtonColors(),
            )
        }
    }
}

@Composable
private fun RestoreProgressRow(
    url: String,
    phase: RestoreMintPhase,
    preview: MintInfo?,
    onRetry: () -> Unit,
) {
    val recovered = (phase as? RestoreMintPhase.Recovered)?.result
    val name = recovered?.mintName
        ?.takeIf { it.isNotBlank() && it != "Unknown Mint" }
        ?: preview?.name?.takeIf { it.isNotBlank() && it != "Unknown Mint" }
        ?: shortenMintUrl(url)
    // iOS: recovered.iconUrl ?? stagedMintIconUrls[url]
    val iconUrl = recovered?.iconUrl?.takeIf { it.isNotBlank() }
        ?: preview?.iconUrl?.takeIf { it.isNotBlank() }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = CashuTheme.spacing.snug),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
    ) {
        MintAvatar(
            mint = MintInfo(url = url, name = name, iconUrl = iconUrl),
            size = MintAvatarSize,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = name,
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium),
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            when (phase) {
                is RestoreMintPhase.Failed ->
                    Text(
                        text = phase.message,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.error,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                else ->
                    Text(
                        text = url,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.MiddleEllipsis,
                    )
            }
        }

        when (phase) {
            RestoreMintPhase.Pending, RestoreMintPhase.Restoring -> {
                // Expressive loader per DESIGN-ANDROID.md §1 — the classic
                // circular spinner is reserved for nothing.
                LoadingIndicator(
                    modifier = Modifier.size(ProgressSpinnerSize),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            is RestoreMintPhase.Recovered -> {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.micro),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = if (phase.result.totalRecovered > 0) {
                            Icons.Filled.CheckCircle
                        } else {
                            Icons.Filled.RemoveCircleOutline
                        },
                        contentDescription = null,
                        tint = if (phase.result.totalRecovered > 0) {
                            CashuTheme.colors.onReceivedContainer
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                        modifier = Modifier.size(18.dp),
                    )
                    Text(
                        text = "${phase.result.unspent} sats",
                        style = MaterialTheme.typography.bodyMedium
                            .copy(
                                fontWeight = if (phase.result.unspent > 0) {
                                    FontWeight.SemiBold
                                } else {
                                    FontWeight.Normal
                                },
                            )
                            .withMonoDigits(),
                        color = if (phase.result.unspent > 0) {
                            MaterialTheme.colorScheme.onSurface
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                    )
                }
            }
            is RestoreMintPhase.Failed -> {
                GhostButton(text = "Retry", onClick = onRetry)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** User-facing seed install errors (iOS initializeAndProceed copy). */
fun restoreSeedInstallErrorMessage(error: Throwable): String {
    val message = error.message.orEmpty()
    val looksInvalid = message.contains("Invalid seed", ignoreCase = true) ||
        message.contains("Seed phrase must", ignoreCase = true) ||
        message.contains("mnemonic", ignoreCase = true)
    return if (looksInvalid) {
        "That seed phrase doesn't look right. Check the spelling and try again."
    } else {
        "Couldn't restore the wallet. ${error.message ?: "Try again."}"
    }
}

/** iOS shortenUrl: strip scheme + trailing slash for display. */
fun shortenMintUrl(url: String): String =
    url.removePrefix("https://").removePrefix("http://").trimEnd('/')

/** iOS normalizedMintUrl: quote-strip, https-default, trailing-slash trim. */
fun normalizeMintUrl(raw: String): String? {
    var trimmed = raw.trim().trim('"', '\'')
    if (trimmed.isEmpty()) return null
    if (!trimmed.startsWith("http://", ignoreCase = true) &&
        !trimmed.startsWith("https://", ignoreCase = true)
    ) {
        trimmed = "https://$trimmed"
    }
    val withoutScheme = trimmed
        .removePrefix("https://")
        .removePrefix("http://")
        .removePrefix("HTTPS://")
        .removePrefix("HTTP://")
    if (withoutScheme.isBlank() || !withoutScheme.contains('.')) return null
    return trimmed.trimEnd('/')
}
