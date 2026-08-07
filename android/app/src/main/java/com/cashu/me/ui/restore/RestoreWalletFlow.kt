package com.cashu.me.ui.restore

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
import com.cashu.me.Core.NostrMintBackupService
import com.cashu.me.Core.WalletManager
import com.cashu.me.Core.Wallet.userFacingWalletMessage
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
 * The live seed-entry stage: monospaced editor with paste/clear corner control,
 * word counter, and the error notice. Stateless — the caller owns the input.
 */
@Composable
fun RestoreSeedStageContent(
    input: String,
    onInputChange: (String) -> Unit,
    wordCount: Int,
    invalidCount: Int,
    errorText: String?,
    modifier: Modifier = Modifier,
) {
    val clipboard = LocalClipboardManager.current
    val haptics = LocalHapticFeedback.current

    Column(
        modifier = modifier
            .padding(horizontal = HeaderPadding)
            .padding(top = CashuTheme.spacing.section),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
        ) {
            CashuTextField(
                value = input,
                onValueChange = onInputChange,
                modifier = Modifier.fillMaxSize(),
                placeholder = "word1 word2 word3 …",
                textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = CashuTheme.fonts.mono).withSlashedZero(),
                isError = errorText != null || (wordCount >= 12 && invalidCount > 0),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
            )
            IconButton(
                onClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    if (input.isBlank()) {
                        clipboard.getText()?.text?.let {
                            onInputChange(it.trim())
                        }
                    } else {
                        onInputChange("")
                    }
                },
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(CashuTheme.spacing.micro),
            ) {
                IconSwap(
                    icon = if (input.isBlank()) Icons.Outlined.ContentPaste else Icons.Filled.Cancel,
                    contentDescription = if (input.isBlank()) "Paste from clipboard" else "Clear",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(
                CashuTheme.spacing.micro,
                Alignment.CenterHorizontally,
            ),
        ) {
            Text(
                text = "$wordCount / 12 words",
                style = MaterialTheme.typography.labelMedium,
                color = if (wordCount == 12 && invalidCount == 0) {
                    CashuTheme.colors.received
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
            )
            if (wordCount > 0 && invalidCount > 0) {
                Text(
                    text = "· $invalidCount invalid",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
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
    requireValidWords: Boolean = presentation == RestorePresentation.InApp,
) {
    var input by remember { mutableStateOf("") }
    val wordCount = remember(input) {
        input.trim().split(Regex("\\s+")).count { it.isNotBlank() }
    }
    val invalidCount = remember(input) { Bip39WordList.invalidWordIndices(input).size }
    val wordsValid = invalidCount == 0
    val canContinue = wordCount == 12 &&
        !restoring &&
        (!requireValidWords || wordsValid)

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
            input = input,
            onInputChange = {
                input = it
                onClearError()
            },
            wordCount = wordCount,
            invalidCount = invalidCount,
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
                onClick = { onNext(input) },
                enabled = canContinue,
                loading = restoring,
            )
            if (onBack != null) {
                GhostButton(text = "Back", onClick = onBack, enabled = !restoring)
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

    private var hasAutoSearched = false

    /**
     * Run the backup lookup once on arrival. Publishing is on by default
     * (`nostrMintBackupEnabled`), so most people already have a mint list
     * waiting and never need to type a URL — asking them to press a button for
     * it was making them do the wallet's work.
     */
    fun autoSearchBackup() {
        if (hasAutoSearched) return
        hasAutoSearched = true
        searchMintBackup(automatic = true)
    }

    fun searchNostrBackup() = searchMintBackup(automatic = false)

    /**
     * The automatic pass stays quiet on failure: the user didn't ask for it,
     * and a relay timeout is not something they can act on. Only an explicit
     * tap earns an error.
     */
    private fun searchMintBackup(automatic: Boolean) {
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
                        // The empty-state line already carries this for the
                        // automatic pass — don't say it twice.
                        normalized.isEmpty() ->
                            if (!automatic) {
                                setNotice("No backup of your mint list found.", NoticeSeverity.Caution)
                            }
                        else -> setNotice("Backup found. Its mints are already in the list.")
                    }
                    backupSearchCompleted = true
                }
                .onFailure {
                    backupSearchCompleted = true
                    if (automatic) return@onFailure
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
            .verticalScroll(rememberScrollState())
            .padding(horizontal = HeaderPadding),
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
            text = if (searching) "Checking for your mints…" else "Find my mints",
            icon = Icons.Outlined.Search,
            onClick = onNostr,
            enabled = !searching,
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
            // The list is empty far more often than not, and the disabled
            // primary never says why. This is the only place that explains the
            // wait and the way out.
            Text(
                text = when {
                    searching -> "Checking for a backup of your mint list…"
                    backupSearchCompleted ->
                        "No backup found. Add the mints you used before, then restore."
                    else -> "Add the mints you used before, then restore."
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

    LaunchedEffect(staging) { staging.autoSearchBackup() }

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
    // Name the reason this step exists at all. Without it the screen reads as
    // busywork, and the user has no way to know the seed alone can't find
    // their money.
    val (title, subtitle) = when (presentation) {
        RestorePresentation.Onboarding ->
            "Add your mints." to
                "Your seed phrase doesn't record which mints you used."
        RestorePresentation.InApp ->
            "Add your mints" to
                "Your seed phrase doesn't record which mints you used."
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
) {
    val contentAlpha = if (enabled) 1f else 0.38f
    Surface(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier,
        shape = CapsuleShape,
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 12.dp, horizontal = CashuTheme.spacing.snug),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.onSurface.copy(alpha = contentAlpha),
            )
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
            tint = CashuTheme.colors.received,
            modifier = Modifier.size(18.dp),
        )
        Text(
            text = "Recovered: $totalRecovered sats",
            style = MaterialTheme.typography.bodyMedium
                .copy(fontWeight = FontWeight.SemiBold)
                .withMonoDigits(),
            color = CashuTheme.colors.received,
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
            .verticalScroll(rememberScrollState())
            .padding(horizontal = HeaderPadding),
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
                            CashuTheme.colors.received
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
