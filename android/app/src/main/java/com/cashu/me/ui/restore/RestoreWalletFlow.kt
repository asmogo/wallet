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
import androidx.compose.material.icons.outlined.CellTower
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
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
import com.cashu.me.ui.components.CanvasDivider
import com.cashu.me.ui.components.CashuTextField
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.IconSwap
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.MintAvatar
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.SecondaryButton
import com.cashu.me.ui.theme.CapsuleShape
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withMonoDigits
import kotlinx.coroutines.launch

// iOS restore twin: OnboardingView seed branch + Settings RestoreWalletView.
// Shared seed → mints → progress phases with quiet crossfades owned by callers.

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
    MaterialTheme.typography.displaySmall.copy(
        fontWeight = FontWeight.ExtraBold,
        letterSpacing = (-0.5).sp,
        lineHeight = 40.sp,
    )

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
    val clipboard = LocalClipboardManager.current
    val haptics = LocalHapticFeedback.current
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
        "Restore Wallet."
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

        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
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
                    onValueChange = {
                        input = it
                        onClearError()
                    },
                    modifier = Modifier.fillMaxSize(),
                    placeholder = "word1 word2 word3 …",
                    textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                    isError = errorText != null || (wordCount >= 12 && invalidCount > 0),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
                )
                IconButton(
                    onClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        if (input.isBlank()) {
                            clipboard.getText()?.text?.let {
                                input = it.trim()
                                onClearError()
                            }
                        } else {
                            input = ""
                            onClearError()
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
                    color = if (wordCount == 12 && wordsValid) {
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
                InlineNotice(text = errorText)
            }
        }

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
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    val clipboard = LocalClipboardManager.current
    val backupState by nostrMintBackupService.state.collectAsState()
    var input by remember { mutableStateOf("") }
    var staged by remember { mutableStateOf<List<String>>(emptyList()) }
    val previews = remember { mutableStateMapOf<String, MintInfo>() }
    var notice by remember { mutableStateOf<String?>(null) }
    var noticeSeverity by remember { mutableStateOf(NoticeSeverity.Info) }

    fun setNotice(message: String?, severity: NoticeSeverity = NoticeSeverity.Info) {
        notice = message
        noticeSeverity = severity
    }

    fun stageUrl(raw: String, showDuplicate: Boolean, showInvalid: Boolean): Boolean {
        val normalized = normalizeMintUrl(raw) ?: run {
            if (showInvalid) setNotice("That doesn't look like a mint URL.", NoticeSeverity.Error)
            return false
        }
        if (staged.any { it.equals(normalized, ignoreCase = true) }) {
            if (showDuplicate) setNotice("That mint is already staged.")
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
            added == 0 -> setNotice("No new mint URLs to add.")
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
            added == 0 -> setNotice("No new mint URLs to add.")
            invalid > 0 -> {
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                setNotice("Added $added mint${if (added == 1) "" else "s"}. Skipped $invalid invalid.")
            }
            else -> {
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                setNotice("Added $added mint${if (added == 1) "" else "s"}.")
            }
        }
    }

    fun searchNostrBackup() {
        scope.launch {
            runCatching { nostrMintBackupService.fetchBackedUpMintUrls() }
                .onSuccess { urls ->
                    val normalized = urls.mapNotNull(::normalizeMintUrl)
                    var added = 0
                    for (url in normalized) {
                        if (stageUrl(url, showDuplicate = false, showInvalid = false)) added++
                    }
                    setNotice(
                        when {
                            normalized.isEmpty() -> "No Nostr mint backup found on your relays."
                            added == 0 -> "Backup found — its mints are already in the list."
                            else -> "Added $added mint${if (added == 1) "" else "s"} from your Nostr backup."
                        },
                    )
                }
                .onFailure {
                    setNotice(it.message ?: "Could not search your relays.", NoticeSeverity.Error)
                }
        }
    }

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
    val (title, subtitle) = when (presentation) {
        RestorePresentation.Onboarding ->
            "Recover Funds." to
                "Add the mints you used before to recover funds from this seed."
        RestorePresentation.InApp ->
            "Restore Funds" to
                "Add the mints you used before to recover funds from this seed."
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

        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = HeaderPadding),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
        ) {
            CashuTextField(
                value = input,
                onValueChange = {
                    input = it
                    notice = null
                },
                modifier = Modifier.fillMaxWidth(),
                placeholder = "mint.example.com",
                textStyle = MaterialTheme.typography.bodyMedium,
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    keyboardType = KeyboardType.Uri,
                    imeAction = ImeAction.Done,
                ),
                keyboardActions = KeyboardActions(onDone = { addInput() }),
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
            ) {
                RestoreCapsuleChip(
                    text = "Add",
                    icon = Icons.Outlined.Add,
                    onClick = ::addInput,
                    enabled = input.isNotBlank(),
                    modifier = Modifier.weight(1f),
                )
                RestoreCapsuleChip(
                    text = "Paste",
                    icon = Icons.Outlined.ContentPaste,
                    onClick = ::pasteFromClipboard,
                    modifier = Modifier.weight(1f),
                )
                RestoreCapsuleChip(
                    text = if (backupState.isSearching) "Searching…" else "Nostr",
                    icon = Icons.Outlined.CellTower,
                    onClick = ::searchNostrBackup,
                    enabled = !backupState.isSearching,
                    modifier = Modifier.weight(1f),
                )
            }

            if (notice != null) {
                InlineNotice(text = notice!!, severity = noticeSeverity)
            }

            if (staged.isNotEmpty()) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    staged.forEachIndexed { index, url ->
                        StagedMintRow(
                            url = url,
                            preview = previews[url],
                            onRemove = {
                                staged = staged.filterNot { it == url }
                                previews.remove(url)
                            },
                        )
                        if (index < staged.lastIndex) {
                            CanvasDivider()
                        }
                    }
                }
            }
        }

        Column(
            modifier = Modifier
                .padding(horizontal = CtaPadding)
                .padding(top = CashuTheme.spacing.snug)
                .padding(bottom = BottomPadding),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            PrimaryButton(
                text = if (staged.isEmpty()) {
                    "Restore"
                } else {
                    "Restore from ${staged.size} mint${if (staged.size == 1) "" else "s"}"
                },
                onClick = { onRestore(staged, previews.toMap()) },
                enabled = staged.isNotEmpty(),
            )
            if (showBottomBack) {
                GhostButton(
                    text = "Back",
                    onClick = {
                        staged = emptyList()
                        notice = null
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
    val phases = remember(mintUrls) {
        mutableStateMapOf<String, RestoreMintPhase>().apply {
            mintUrls.forEach { put(it, RestoreMintPhase.Pending) }
        }
    }
    val scope = rememberCoroutineScope()
    var finishing by remember { mutableStateOf(false) }

    suspend fun restoreMint(url: String) {
        phases[url] = RestoreMintPhase.Restoring
        runCatching { walletManager.restoreFromMint(url) }
            .onSuccess { phases[url] = RestoreMintPhase.Recovered(it) }
            .onFailure {
                phases[url] = restoreMintFailurePhase(it)
            }
    }

    LaunchedEffect(mintUrls) {
        mintUrls.forEach { url -> restoreMint(url) }
    }

    val allSettled = mintUrls.isEmpty() || (
        phases.size == mintUrls.size &&
            phases.values.all {
                it is RestoreMintPhase.Recovered || it is RestoreMintPhase.Failed
            }
        )
    val totalRecovered = phases.values.sumOf { phase ->
        (phase as? RestoreMintPhase.Recovered)?.result?.unspent ?: 0L
    }
    val subhead = when {
        !allSettled -> "Recovering funds from your mints…"
        totalRecovered > 0L -> "Here's what we recovered."
        else -> "No funds found on these mints."
    }

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
        RestorePresentation.Onboarding -> "Recover Funds."
        RestorePresentation.InApp ->
            if (allSettled) "Restore Complete" else "Restoring…"
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
                text = subhead,
                style = if (presentation == RestorePresentation.InApp) {
                    MaterialTheme.typography.bodyMedium
                } else {
                    MaterialTheme.typography.bodyLarge
                },
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = titleTextAlign,
            )
            if (totalRecovered > 0L) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.micro),
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = if (presentation == RestorePresentation.InApp) {
                        Modifier.fillMaxWidth()
                    } else {
                        Modifier
                    },
                ) {
                    if (presentation == RestorePresentation.InApp) {
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
                    if (presentation == RestorePresentation.InApp) {
                        Spacer(Modifier.weight(1f))
                    }
                }
            }
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = HeaderPadding),
        ) {
            mintUrls.forEachIndexed { index, url ->
                RestoreProgressRow(
                    url = url,
                    phase = phases[url] ?: RestoreMintPhase.Pending,
                    preview = stagedPreviews[url],
                    onRetry = { scope.launch { restoreMint(url) } },
                )
                if (index < mintUrls.lastIndex) {
                    CanvasDivider()
                }
            }
        }

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
                    finishing = true
                    onContinue()
                },
                enabled = allSettled && !finishing,
                loading = finishing,
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
                CircularProgressIndicator(
                    modifier = Modifier.size(ProgressSpinnerSize),
                    strokeWidth = 2.dp,
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
// Method chooser (onboarding only — Android has no iCloud twin)
// ---------------------------------------------------------------------------

@Composable
fun RestoreMethodStep(
    onBack: () -> Unit,
    onSeedPhrase: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        Spacer(Modifier.weight(1f))
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = HeaderPadding),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
        ) {
            Text(
                text = "Restore Wallet",
                style = restoreOnboardingTitleStyle(),
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = "Choose how to recover your wallet.",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.weight(1f))
        Column(
            modifier = Modifier
                .padding(horizontal = CtaPadding)
                .padding(bottom = BottomPadding),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            SecondaryButton(
                text = "Use Seed Phrase",
                onClick = onSeedPhrase,
            )
            GhostButton(text = "Back", onClick = onBack)
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
        "Couldn't open the wallet. ${error.message ?: "Try again."}"
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
