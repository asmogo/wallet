package com.cashu.me.ui.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ArrowCircleRight
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberBottomSheetState
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
import androidx.compose.ui.draw.blur
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag as semanticsTestTag
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import com.cashu.me.Core.Bip39WordList
import com.cashu.me.Core.MnemonicInput
import com.cashu.me.Core.NostrMintBackupService
import com.cashu.me.Core.WalletManager
import com.cashu.me.Core.WalletStartupFailure
import com.cashu.me.Models.MintInfo
import com.cashu.me.ui.components.CashuTextField
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.IconSwap
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.MintAvatar
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.restore.RestoreMintsStageContent
import com.cashu.me.ui.restore.RestoreProgressRows
import com.cashu.me.ui.restore.RestoreRecoveredTotal
import com.cashu.me.ui.restore.RestoreSeedStageContent
import com.cashu.me.ui.restore.rememberRestoreMintsStagingState
import com.cashu.me.ui.restore.rememberRestoreProgressState
import com.cashu.me.ui.restore.restoreSeedInstallErrorMessage
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.mints.RecommendedMints
import com.cashu.me.ui.testing.UiTestTags

// ---------------------------------------------------------------------------
// iOS OnboardingView parity. Source of truth: ios/CashuWallet/Views/Main/
// OnboardingView.swift — welcome → showMnemonic (redacted seed, tap-to-reveal,
// acknowledge checkbox) → firstMint (multi-select recommended mints), plus the
// seed-restore branch. Step changes are quiet 250ms crossfades.
//
// Restyle stage 1 (docs/product/onboarding-restyle-brief.md §3): one
// OnboardingChassis instance is pinned below the step switch; the steps render
// stage-only content above it. The chassis swaps its text instantly on step
// change — the motion pass gives each slot its explicit in-place cross-fade.
// ---------------------------------------------------------------------------

private sealed interface OnboardingStep {
    data object Welcome : OnboardingStep
    data class ShowMnemonic(val mnemonic: String) : OnboardingStep
    data class FirstMint(val mnemonic: String) : OnboardingStep
    data object RestoreMethod : OnboardingStep
    data object RestoreInput : OnboardingStep
    data class RestoreMints(val mnemonic: String) : OnboardingStep
    data class RestoreProgress(
        val mnemonic: String,
        val mintUrls: List<String>,
        val mintPreviews: Map<String, MintInfo> = emptyMap(),
    ) : OnboardingStep
}

private val SeedGridColumnGap = 12.dp
private val SeedGridRowGap = 14.dp
private val SeedIndexWidth = 22.dp
private val SeedBlurRadius = 9.dp
private val AckIconSize = 22.dp
private val SelectIconSize = 24.dp
private val MintAvatarSize = 36.dp
private val WarningIconSize = 16.dp
private val RevealEyeSize = 22.dp

/** Hoisted first-mint selection state — the chassis reads the Continue rule
 * and commits pending drafts while the stage renders the list. */
internal class FirstMintSelectionState {
    var selected by mutableStateOf(setOf<String>())
        private set
    var customUrls by mutableStateOf(listOf<String>())
        private set
    val customPreviews = mutableStateMapOf<String, MintInfo>()
    var customInputOpen by mutableStateOf(false)
    var customDraft by mutableStateOf(FirstMintUrlDraft())

    val canContinue: Boolean
        get() = selected.isNotEmpty() || customDraft.input.isNotBlank()

    fun toggle(url: String) {
        selected = if (url in selected) selected - url else selected + url
    }

    fun commitCustomUrl() {
        val existing = RecommendedMints.map { it.url } + customUrls
        val result = customDraft.stage(existing)
        customDraft = result.draft
        val normalized = result.stagedUrl ?: return
        customUrls = customUrls + normalized
        selected = selected + normalized
        customInputOpen = false
    }

    /** Preserve display order: recommended first, then customs. */
    fun orderedSelection(): List<String> =
        (RecommendedMints.map { it.url } + customUrls).filter { it in selected }

    fun reset() {
        selected = emptySet()
        customUrls = emptyList()
        customPreviews.clear()
        customInputOpen = false
        customDraft = FirstMintUrlDraft()
    }
}

@Composable
fun OnboardingScreen(
    walletManager: WalletManager,
    nostrMintBackupService: NostrMintBackupService,
) {
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    val walletState by walletManager.state.collectAsState()

    var step: OnboardingStep by remember { mutableStateOf(OnboardingStep.Welcome) }
    var infoOpen by remember { mutableStateOf(false) }
    var creating by remember { mutableStateOf(false) }
    var retryingStartup by remember { mutableStateOf(false) }
    var createError by remember { mutableStateOf<String?>(null) }
    var restoring by remember { mutableStateOf(false) }
    var restoreError by remember { mutableStateOf<String?>(null) }
    var restoreSeedInput by remember { mutableStateOf("") }
    var seedAcknowledged by remember { mutableStateOf(false) }
    val firstMint = remember { FirstMintSelectionState() }
    // First-mint completion state (wallet installs once, then mints add sequentially).
    var walletInstalled by remember { mutableStateOf(false) }
    val walletInstallMutex = remember { Mutex() }
    var finishing by remember { mutableStateOf(false) }
    var addingMintUrl by remember { mutableStateOf<String?>(null) }
    var firstMintError by remember { mutableStateOf<String?>(null) }

    val restoreMintsStaging = rememberRestoreMintsStagingState(walletManager, nostrMintBackupService)
    val nostrBackupState by nostrMintBackupService.state.collectAsState()

    suspend fun ensureWalletInstalled(mnemonic: String) {
        walletInstallMutex.withLock {
            if (!walletInstalled) {
                walletManager.initializeNewWalletForOnboarding(mnemonic)
                walletInstalled = true
            }
        }
    }

    fun finishCreate(mnemonic: String, mintUrls: List<String>) {
        scope.launch {
            finishing = true
            firstMintError = null
            var current: String? = null
            try {
                ensureWalletInstalled(mnemonic)
                for (url in mintUrls) {
                    current = url
                    addingMintUrl = url
                    walletManager.addMint(url)
                }
                addingMintUrl = null
                walletManager.completeOnboarding()
            } catch (t: Throwable) {
                firstMintError = current?.let {
                    "Couldn't connect to ${shortenMintUrl(it)}. Check the URL or try another mint."
                } ?: (t.message ?: "Couldn't set up the wallet.")
                addingMintUrl = null
            } finally {
                finishing = false
            }
        }
    }

    fun handleFirstMintContinue(mnemonic: String) {
        if (firstMint.customDraft.input.isNotBlank()) {
            firstMint.commitCustomUrl()
            if (firstMint.customDraft.error != null) return
        }
        if (firstMint.selected.isEmpty()) return
        finishCreate(mnemonic, firstMint.orderedSelection())
    }

    // CDK mint-info fetching requires an open wallet repository. Start that
    // preparation as soon as this step appears; Continue shares the same mutex
    // so a fast tap waits for this installation instead of racing a second one.
    LaunchedEffect(step) {
        val firstMintStep = step as? OnboardingStep.FirstMint ?: return@LaunchedEffect
        runCatching { ensureWalletInstalled(firstMintStep.mnemonic) }
            .onFailure { firstMintError = it.message ?: "Couldn't set up the wallet." }
    }

    // A URL can be staged before repository preparation finishes. Keying this
    // effect by both inputs retries all missing previews once the repository is
    // ready, while leaving selection and Continue independent of network speed.
    LaunchedEffect(walletInstalled, firstMint.customUrls) {
        if (!walletInstalled) return@LaunchedEffect
        firstMint.customUrls.filterNot { it in firstMint.customPreviews }.forEach { url ->
            runCatching { walletManager.fetchLiveMintInfo(url) }
                .getOrNull()
                ?.let { firstMint.customPreviews[url] = it }
        }
    }

    val progressStep = step as? OnboardingStep.RestoreProgress
    val progressState = progressStep?.let {
        rememberRestoreProgressState(walletManager, it.mintUrls)
    }

    val chassis: OnboardingChassisModel = when (val current = step) {
        OnboardingStep.Welcome -> welcomeChassis(
            creating = creating,
            retryingStartup = retryingStartup,
            onCreate = {
                seedAcknowledged = false
                firstMint.reset()
                scope.launch {
                    creating = true
                    createError = null
                    try {
                        // Resume an interrupted onboarding with its original
                        // seed — the user may have written those words down.
                        val mnemonic = walletManager.persistedOnboardingMnemonic()
                            ?: walletManager.generateMnemonicForOnboarding()
                        step = OnboardingStep.ShowMnemonic(mnemonic)
                    } catch (t: Throwable) {
                        createError = t.message ?: "Couldn't create a wallet."
                    } finally {
                        creating = false
                    }
                }
            },
            onRestore = {
                restoreError = null
                step = OnboardingStep.RestoreMethod
            },
            onInfo = { infoOpen = true },
        )

        is OnboardingStep.ShowMnemonic -> OnboardingChassisModel(
            headline = "Your Seed Phrase.",
            subhead = "Write these 12 words down in order. This is the only way to recover your wallet.",
            primary = ChassisAction(
                label = "I've Saved My Seed Phrase",
                onClick = { step = OnboardingStep.FirstMint(current.mnemonic) },
                enabled = seedAcknowledged,
                testTag = UiTestTags.SeedSaved,
            ),
        )

        is OnboardingStep.FirstMint -> OnboardingChassisModel(
            headline = "Pick your first mint.",
            subhead = "Mints issue your ecash and redeem it for Bitcoin. Add more anytime in Settings.",
            primary = ChassisAction(
                label = "Continue",
                onClick = { handleFirstMintContinue(current.mnemonic) },
                enabled = firstMint.canContinue && !finishing,
                loading = finishing,
                testTag = UiTestTags.ContinueWithMint,
            ),
            tertiary = ChassisAction(
                label = "Skip for now",
                onClick = { finishCreate(current.mnemonic, emptyList()) },
                style = ChassisButtonStyle.Ghost,
                enabled = !finishing,
                testTag = UiTestTags.SkipMint,
            ),
        )

        OnboardingStep.RestoreMethod -> OnboardingChassisModel(
            headline = "Restore Wallet",
            subhead = "Choose how to recover your wallet.",
            // Android has no iCloud twin, so the chooser's single real option
            // keeps its existing Secondary styling in the primary slot.
            primary = ChassisAction(
                label = "Use Seed Phrase",
                onClick = {
                    restoreError = null
                    restoreSeedInput = ""
                    step = OnboardingStep.RestoreInput
                },
                style = ChassisButtonStyle.Secondary,
            ),
            tertiary = ChassisAction(
                label = "Back",
                onClick = { step = OnboardingStep.Welcome },
                style = ChassisButtonStyle.Ghost,
            ),
        )

        OnboardingStep.RestoreInput -> {
            val wordCount = restoreSeedInput.trim().split(Regex("\\s+")).count { it.isNotBlank() }
            OnboardingChassisModel(
                headline = "Restore Wallet.",
                subhead = "Enter your 12 words in order.",
                primary = ChassisAction(
                    label = "Next",
                    onClick = {
                        // iOS initializeAndProceed: install the restored wallet
                        // before the mint-staging step so the repository is keyed
                        // to this seed — the Nostr backup search derives its keys
                        // from it.
                        scope.launch {
                            restoring = true
                            restoreError = null
                            val normalized = MnemonicInput.normalize(restoreSeedInput)
                            runCatching { walletManager.initializeRestoredWallet(normalized) }
                                .onSuccess {
                                    restoreMintsStaging.reset()
                                    step = OnboardingStep.RestoreMints(normalized)
                                }
                                .onFailure { restoreError = restoreSeedInstallErrorMessage(it) }
                            restoring = false
                        }
                    },
                    enabled = wordCount == 12 && !restoring,
                    loading = restoring,
                ),
                // iOS retreats to welcome (skips the method chooser on the way back).
                tertiary = ChassisAction(
                    label = "Back",
                    onClick = { step = OnboardingStep.Welcome },
                    style = ChassisButtonStyle.Ghost,
                    enabled = !restoring,
                ),
            )
        }

        is OnboardingStep.RestoreMints -> OnboardingChassisModel(
            headline = "Recover Funds.",
            subhead = "Add the mints you used before to recover funds from this seed.",
            primary = ChassisAction(
                label = if (restoreMintsStaging.staged.isEmpty()) {
                    "Restore"
                } else {
                    "Restore from ${restoreMintsStaging.staged.size} mint${if (restoreMintsStaging.staged.size == 1) "" else "s"}"
                },
                onClick = {
                    step = OnboardingStep.RestoreProgress(
                        current.mnemonic,
                        restoreMintsStaging.staged,
                        restoreMintsStaging.previews.toMap(),
                    )
                },
                enabled = restoreMintsStaging.staged.isNotEmpty(),
            ),
            tertiary = ChassisAction(
                label = "Back",
                onClick = {
                    restoreMintsStaging.reset()
                    step = OnboardingStep.RestoreInput
                },
                style = ChassisButtonStyle.Ghost,
            ),
        )

        is OnboardingStep.RestoreProgress -> OnboardingChassisModel(
            headline = "Recover Funds.",
            subhead = progressState?.subhead,
            // Forward-only — Continue enables once every mint has settled.
            primary = ChassisAction(
                label = "Continue",
                onClick = {
                    progressState?.let { state ->
                        state.finishing = true
                        scope.launch {
                            runCatching { walletManager.completeRestore() }
                        }
                    }
                },
                enabled = progressState?.let { it.allSettled && !it.finishing } == true,
                loading = progressState?.finishing == true,
                colors = ButtonDefaults.filledTonalButtonColors(),
            ),
        )
    }

    // System back mirrors the on-screen Back affordances, and only those: the
    // method chooser and seed entry retreat to welcome (seed entry deliberately
    // skips the chooser, like its Back link), mint staging retreats to seed
    // entry clearing the staged list exactly as its Back button does. Steps
    // without a Back affordance — welcome, the seed reveal, first mint, and the
    // forward-only restore progress — keep the platform default (exit).
    BackHandler(
        enabled = step is OnboardingStep.RestoreMethod ||
            step is OnboardingStep.RestoreInput ||
            step is OnboardingStep.RestoreMints,
    ) {
        when (step) {
            OnboardingStep.RestoreMethod -> step = OnboardingStep.Welcome
            OnboardingStep.RestoreInput -> if (!restoring) step = OnboardingStep.Welcome
            is OnboardingStep.RestoreMints -> {
                restoreMintsStaging.reset()
                step = OnboardingStep.RestoreInput
            }
            else -> Unit
        }
    }

    val accessory: (@Composable () -> Unit)? = if (step is OnboardingStep.ShowMnemonic) {
        {
            SeedAcknowledgeRow(
                acknowledged = seedAcknowledged,
                onToggle = {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    seedAcknowledged = !seedAcknowledged
                },
            )
        }
    } else {
        null
    }

    OnboardingScaffold(
        chassis = chassis,
        modifier = Modifier
            .fillMaxSize()
            .testTag(UiTestTags.OnboardingRoot)
            .background(MaterialTheme.colorScheme.background)
            .statusBarsPadding()
            .navigationBarsPadding()
            .imePadding(),
        accessory = accessory,
    ) {
        AnimatedContent(
            targetState = step,
            modifier = Modifier.fillMaxSize(),
            // Quiet crossfade — a horizontal push between steps was rejected as
            // jarring (2026-06-26 iOS decision, binding product behavior).
            transitionSpec = { fadeIn(tween(250)).togetherWith(fadeOut(tween(250))) },
            label = "onboarding-step",
        ) { current ->
            when (current) {
                OnboardingStep.Welcome -> WelcomeStageContent(
                    startupFailure = walletState.startupFailure,
                    retryingStartup = retryingStartup,
                    errorText = createError,
                    onRetryStartup = {
                        scope.launch {
                            retryingStartup = true
                            try {
                                walletManager.initialize()
                            } finally {
                                retryingStartup = false
                            }
                        }
                    },
                )

                is OnboardingStep.ShowMnemonic -> ShowMnemonicStageContent(
                    mnemonic = current.mnemonic,
                )

                is OnboardingStep.FirstMint -> FirstMintStageContent(
                    state = firstMint,
                    busy = finishing,
                    addingMintUrl = addingMintUrl,
                    errorText = firstMintError,
                )

                // Quiet stage — stage 3 of the restyle adds the restrained
                // variant of the welcome piece here.
                OnboardingStep.RestoreMethod -> Box(Modifier.fillMaxSize())

                OnboardingStep.RestoreInput -> RestoreSeedStageContent(
                    input = restoreSeedInput,
                    onInputChange = {
                        restoreSeedInput = it
                        restoreError = null
                    },
                    wordCount = restoreSeedInput.trim().split(Regex("\\s+")).count { it.isNotBlank() },
                    invalidCount = Bip39WordList.invalidWordIndices(restoreSeedInput).size,
                    errorText = restoreError,
                    modifier = Modifier.fillMaxSize(),
                )

                is OnboardingStep.RestoreMints -> RestoreMintsStageContent(
                    input = restoreMintsStaging.input,
                    staged = restoreMintsStaging.staged,
                    previews = restoreMintsStaging.previews,
                    notice = restoreMintsStaging.notice,
                    noticeSeverity = restoreMintsStaging.noticeSeverity,
                    searching = nostrBackupState.isSearching,
                    onInputChange = restoreMintsStaging::updateInput,
                    onAdd = restoreMintsStaging::addInput,
                    onPaste = restoreMintsStaging::pasteFromClipboard,
                    onNostr = restoreMintsStaging::searchNostrBackup,
                    onRemove = restoreMintsStaging::remove,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(top = CashuTheme.spacing.snug),
                )

                is OnboardingStep.RestoreProgress -> Column(Modifier.fillMaxSize()) {
                    if (progressState != null && progressState.totalRecovered > 0L) {
                        // Money value — monospaced digits + no roll (Numbers Are
                        // Sacred), exactly as the shared component renders it.
                        RestoreRecoveredTotal(
                            totalRecovered = progressState.totalRecovered,
                            modifier = Modifier
                                .padding(horizontal = HeaderPadding)
                                .padding(top = CashuTheme.spacing.snug, bottom = CashuTheme.spacing.default),
                        )
                    }
                    RestoreProgressRows(
                        mintUrls = current.mintUrls,
                        phases = progressState?.phases ?: emptyMap(),
                        previews = current.mintPreviews,
                        onRetry = { url -> progressState?.retry(url) },
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth(),
                    )
                }
            }
        }
    }

    if (infoOpen) {
        EcashConceptSheet(onDismiss = { infoOpen = false })
    }
}

// ---------------------------------------------------------------------------
// Welcome
// ---------------------------------------------------------------------------

/** The welcome chassis — shared with WalletStartupFailureComposeTest so the
 * test composes exactly the production frame. */
@Composable
internal fun welcomeChassis(
    creating: Boolean,
    retryingStartup: Boolean,
    onCreate: () -> Unit,
    onRestore: () -> Unit,
    onInfo: () -> Unit,
): OnboardingChassisModel = OnboardingChassisModel(
    // The only headline that keeps a hardcoded break. Left to wrap
    // naturally it wraps after "In" — "Private cash. In" / "your
    // pocket." — splitting the second sentence. Breaking at the
    // sentence boundary is the deliberate exception.
    headline = "Private cash.\nIn your pocket.",
    subhead = "An ecash wallet for Bitcoin and Lightning.",
    primary = ChassisAction(
        label = "Create Wallet",
        onClick = onCreate,
        enabled = !retryingStartup,
        loading = creating,
        testTag = UiTestTags.CreateWallet,
        colors = ButtonDefaults.filledTonalButtonColors(),
    ),
    secondary = ChassisAction(
        label = "Restore Wallet",
        onClick = onRestore,
        style = ChassisButtonStyle.Secondary,
        enabled = !creating && !retryingStartup,
    ),
    tertiary = ChassisAction(
        label = "What is ecash?",
        onClick = onInfo,
        style = ChassisButtonStyle.Ghost,
    ),
)

/** The welcome stage: startup-failure recovery + create errors, pinned just
 * above the chassis. Stage 3 of the restyle adds the welcome piece above. */
@Composable
internal fun WelcomeStageContent(
    startupFailure: WalletStartupFailure?,
    retryingStartup: Boolean,
    errorText: String?,
    onRetryStartup: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxSize()) {
        Spacer(Modifier.weight(1f))
        if (startupFailure != null) {
            Column(
                modifier = Modifier.padding(horizontal = CtaPadding),
                verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
            ) {
                InlineNotice(text = startupFailure.message)
                PrimaryButton(
                    text = startupFailure.recoveryActionLabel,
                    onClick = onRetryStartup,
                    loading = retryingStartup,
                    modifier = Modifier.testTag(UiTestTags.RetryWalletStartup),
                )
            }
            Spacer(Modifier.height(CashuTheme.spacing.snug))
        }
        if (errorText != null) {
            InlineNotice(
                text = errorText,
                modifier = Modifier.padding(horizontal = CtaPadding),
            )
            Spacer(Modifier.height(CashuTheme.spacing.snug))
        }
    }
}

/** iOS concept sheet: heavy title + three bearer-cash beats + Got it. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EcashConceptSheet(onDismiss: () -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        // Skip the partially-expanded detent. At that height a short viewport
        // (360x800dp) or a large font scale pushed "Got it" past the sheet edge,
        // where it was clipped and the gesture pill drew across it.
        sheetState = rememberBottomSheetState(
            initialValue = SheetValue.Hidden,
            enabledValues = setOf(SheetValue.Hidden, SheetValue.Expanded),
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = HeaderPadding)
                .padding(bottom = CashuTheme.spacing.comfortable)
                .navigationBarsPadding(),
        ) {
            // Prose scrolls; the CTA stays pinned below it. iOS gets the same
            // shape from a Spacer() ahead of the button in `conceptSheet`.
            Column(
                modifier = Modifier
                    .weight(1f, fill = false)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
            ) {
                Text(
                    text = "Ecash is bearer cash for Bitcoin.",
                    style = MaterialTheme.typography.headlineMedium.copy(
                        fontWeight = FontWeight.ExtraBold,
                        letterSpacing = (-0.3).sp,
                    ),
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Column(verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default)) {
                    Text(
                        text = "Whoever holds it, owns it. Your balance stays on this device, hidden from everyone else.",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = "Mints hold the Bitcoin behind your ecash. You can use several at once.",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = "Send instantly. Cash out to Lightning anytime.",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Spacer(Modifier.height(CashuTheme.spacing.comfortable))
            PrimaryButton(text = "Got it", onClick = onDismiss)
        }
    }
}

// ---------------------------------------------------------------------------
// Seed phrase (showMnemonic)
// ---------------------------------------------------------------------------

/** The acknowledge row rides the chassis accessory slot — above the primary it
 * gates, so it can never move the button. */
@Composable
internal fun SeedAcknowledgeRow(
    acknowledged: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onToggle,
            )
            .testTag(UiTestTags.AcknowledgeSeed)
            .padding(horizontal = CashuTheme.spacing.micro),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
    ) {
        // Circle ↔ check morphs (iOS .contentTransition(.symbolEffect(.replace))).
        IconSwap(
            icon = if (acknowledged) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
            contentDescription = if (acknowledged) "Acknowledged" else "Not acknowledged",
            tint = if (acknowledged) {
                MaterialTheme.colorScheme.onSurface
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
            modifier = Modifier.size(AckIconSize),
        )
        Text(
            text = "I've written down my seed phrase and stored it safely.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** The seed stage: warning, redacted grid with tap-to-reveal, and Copy. */
@Composable
internal fun ShowMnemonicStageContent(
    mnemonic: String,
    modifier: Modifier = Modifier,
) {
    val clipboard = LocalClipboardManager.current
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val words = remember(mnemonic) { mnemonic.trim().split(' ').filter { it.isNotBlank() } }

    var revealed by remember { mutableStateOf(false) }
    var copied by remember { mutableStateOf(false) }

    fun reveal() {
        if (revealed) return // one-way, like iOS
        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        revealed = true
    }

    Column(
        modifier = modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = HeaderPadding),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
        ) {
            Icon(
                imageVector = Icons.Filled.Warning,
                contentDescription = null,
                tint = CashuTheme.colors.pending,
                modifier = Modifier.size(WarningIconSize),
            )
            Text(
                text = "Never share these words with anyone",
                style = MaterialTheme.typography.labelMedium,
                color = CashuTheme.colors.pending,
            )
        }
        // The seed grid deliberately gets NO entrance motion: any motion on
        // this block reads as a flicker on first paint, and recomposition
        // mid-entrance restarts it. The step crossfade owns its appearance;
        // the tap-to-reveal swap is untouched.
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = CashuTheme.spacing.comfortable),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            SeedPhraseReveal(
                words = words,
                revealed = revealed,
                onReveal = ::reveal,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = HeaderPadding),
            )
            GhostButton(
                text = if (copied) "Copied" else "Copy",
                onClick = {
                    clipboard.setText(AnnotatedString(words.joinToString(" ")))
                    copied = true
                    scope.launch {
                        delay(3_000)
                        copied = false
                    }
                },
            )
        }
        Spacer(Modifier.weight(1f))
    }
}

/**
 * Keeps the masked phrase out of TalkBack's tree and replaces the whole visual
 * with one reveal control. Once revealed, the control semantics disappear so
 * TalkBack can traverse the ordered words in [SeedGrid].
 */
@Composable
internal fun SeedPhraseReveal(
    words: List<String>,
    revealed: Boolean,
    onReveal: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val accessibilityModifier = if (revealed) {
        Modifier
    } else {
        Modifier
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClickLabel = "Reveal seed phrase",
                onClick = onReveal,
            )
            .clearAndSetSemantics {
                semanticsTestTag = UiTestTags.RevealSeed
                contentDescription = "Reveal seed phrase"
                role = Role.Button
                onClick(label = "Reveal seed phrase") {
                    onReveal()
                    true
                }
            }
    }

    Box(
        modifier = modifier.then(accessibilityModifier),
        contentAlignment = Alignment.Center,
    ) {
        SeedGrid(words = words, revealed = revealed)
        if (!revealed) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.micro),
            ) {
                Icon(
                    imageVector = Icons.Outlined.Visibility,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(RevealEyeSize),
                )
                Text(
                    text = "Tap to reveal",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/**
 * 3-column × 4-row seed grid, plain on the canvas (no card chrome) — iOS
 * mnemonicWordsGrid. Zero-padded indices in a fixed trailing-aligned column,
 * monospaced medium words.
 *
 * While hidden the real words are never composed (iOS `.redacted` rationale:
 * an animatable blur alone can flicker the phrase legible on entrance, and
 * `Modifier.blur` is a no-op below API 31). Placeholder dots stand in, with
 * the blur layered on top where supported.
 */
@Composable
private fun SeedGrid(words: List<String>, revealed: Boolean) {
    val indexStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace)
    val wordStyle = MaterialTheme.typography.bodyMedium.copy(
        fontFamily = FontFamily.Monospace,
        fontWeight = FontWeight.Medium,
    )
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (revealed) {
                    Modifier.semantics {
                        semanticsTestTag = UiTestTags.SeedPhrase
                        isTraversalGroup = true
                    }
                } else {
                    Modifier.clearAndSetSemantics {
                        semanticsTestTag = UiTestTags.HiddenSeedPhrase
                    }
                },
            )
            .then(if (revealed) Modifier else Modifier.blur(SeedBlurRadius)),
        verticalArrangement = Arrangement.spacedBy(SeedGridRowGap),
    ) {
        words.chunked(3).forEachIndexed { rowIndex, rowWords ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(SeedGridColumnGap),
            ) {
                rowWords.forEachIndexed { columnIndex, word ->
                    val number = rowIndex * 3 + columnIndex + 1
                    Row(
                        modifier = Modifier
                            .weight(1f)
                            .then(
                                if (revealed) {
                                    Modifier.clearAndSetSemantics {
                                        contentDescription = "$number. $word"
                                        traversalIndex = number.toFloat()
                                    }
                                } else {
                                    Modifier
                                },
                            ),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.micro),
                    ) {
                        Text(
                            text = "%02d".format(number),
                            style = indexStyle,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.65f),
                            textAlign = TextAlign.End,
                            modifier = Modifier.width(SeedIndexWidth),
                        )
                        Text(
                            text = if (revealed) word else "••••••",
                            style = wordStyle,
                            color = if (revealed) {
                                MaterialTheme.colorScheme.onSurface
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                            },
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// First mint (multi-select recommended mints)
// ---------------------------------------------------------------------------

/** The first-mint stage: mint list, custom-URL entry, notices. The chassis
 * owns Continue/Skip; [state] is hoisted so the chassis reads the rule. */
@Composable
internal fun FirstMintStageContent(
    state: FirstMintSelectionState,
    busy: Boolean,
    addingMintUrl: String?,
    errorText: String?,
    modifier: Modifier = Modifier,
) {
    val haptics = LocalHapticFeedback.current
    val clipboard = LocalClipboardManager.current

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = HeaderPadding)
            .padding(top = CashuTheme.spacing.snug),
    ) {
        val rows = RecommendedMints.map { Triple(it.name, it.url, it.iconUrl) } +
            state.customUrls.map {
                Triple(
                    state.customPreviews[it]?.name ?: shortenMintUrl(it),
                    it,
                    state.customPreviews[it]?.iconUrl,
                )
            }
        rows.forEach { (name, url, iconUrl) ->
            MintSelectRow(
                name = name,
                url = url,
                iconUrl = iconUrl,
                selected = url in state.selected,
                enabled = !busy,
                onToggle = {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    state.toggle(url)
                },
            )
        }
        if (!state.customInputOpen) {
            // iOS routes both this and "Skip for now" through
            // `.textLinkButton()`; GhostButton is that style's analog, so the
            // two stay centered and share press feedback on both platforms.
            GhostButton(
                text = "Add custom mint URL",
                onClick = { state.customInputOpen = true },
                enabled = !busy,
                leadingIcon = Icons.Outlined.Add,
                contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = CashuTheme.spacing.micro)
                    .testTag(UiTestTags.AddCustomMint),
            )
        } else {
            Spacer(Modifier.height(CashuTheme.spacing.snug))
            CashuTextField(
                value = state.customDraft.input,
                onValueChange = { state.customDraft = state.customDraft.updateInput(it) },
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag(UiTestTags.CustomMintUrl),
                placeholder = "https://mint.example.com",
                textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                singleLine = true,
                isError = state.customDraft.error != null,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    keyboardType = KeyboardType.Uri,
                ),
                trailingIcon = {
                    if (state.customDraft.input.isBlank()) {
                        IconButton(onClick = {
                            clipboard.getText()?.text?.let {
                                state.customDraft = state.customDraft.updateInput(it.trim())
                            }
                        }) {
                            Icon(Icons.Outlined.ContentPaste, contentDescription = "Paste")
                        }
                    } else {
                        IconButton(onClick = state::commitCustomUrl) {
                            Icon(Icons.Outlined.ArrowCircleRight, contentDescription = "Add mint")
                        }
                    }
                },
            )
        }
        val notice = state.customDraft.error ?: errorText
        if (notice != null) {
            Spacer(Modifier.height(CashuTheme.spacing.snug))
            InlineNotice(text = notice)
        }
        if (addingMintUrl != null) {
            Spacer(Modifier.height(CashuTheme.spacing.snug))
            Text(
                text = "Connecting to ${shortenMintUrl(addingMintUrl)}…",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** iOS mint row: avatar + name/URL + trailing multi-select check circle. */
@Composable
private fun MintSelectRow(
    name: String,
    url: String,
    iconUrl: String?,
    selected: Boolean,
    enabled: Boolean,
    onToggle: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, onClick = onToggle)
            .padding(vertical = CashuTheme.spacing.default),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
    ) {
        RecommendedMintAvatar(name = name, url = url, iconUrl = iconUrl)
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = name,
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium),
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = shortenMintUrl(url),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.MiddleEllipsis,
            )
        }
        // Selection glyph morphs instead of hard-cutting (symbol-replace parity).
        IconSwap(
            icon = if (selected) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
            contentDescription = if (selected) "Selected" else "Not selected",
            tint = if (selected) {
                MaterialTheme.colorScheme.onSurface
            } else {
                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.22f)
            },
            modifier = Modifier.size(SelectIconSize),
        )
    }
}

/** 36dp circular avatar with curated icon; monogram fallback (iOS MintAvatarView). */
@Composable
private fun RecommendedMintAvatar(name: String, url: String, iconUrl: String?, size: Dp = MintAvatarSize) {
    MintAvatar(
        mint = MintInfo(url = url, name = name, iconUrl = iconUrl),
        size = size,
    )
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** iOS shortenUrl: strip scheme + trailing slash for display. */
private fun shortenMintUrl(url: String): String =
    url.removePrefix("https://").removePrefix("http://").trimEnd('/')
