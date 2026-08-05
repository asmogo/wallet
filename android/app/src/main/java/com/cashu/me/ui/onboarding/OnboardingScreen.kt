package com.cashu.me.ui.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ArrowCircleRight
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.ContentCopy
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
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
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
import com.cashu.me.ui.components.materializeBlur
import com.cashu.me.ui.restore.RestoreMintsStageContent
import com.cashu.me.ui.restore.RestoreProgressRows
import com.cashu.me.ui.restore.RestoreRecoveredTotal
import com.cashu.me.ui.restore.RestoreSeedStageContent
import com.cashu.me.ui.restore.rememberRestoreMintsStagingState
import com.cashu.me.ui.restore.rememberRestoreProgressState
import com.cashu.me.ui.restore.restoreSeedInstallErrorMessage
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.rememberReducedMotion
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
private val SeedCardRadius = 14.dp
private val SeedCardPadding = 20.dp
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

    // Stage-swap motion (onboarding-restyle-brief §5, expressed per the
    // Android charter as M3 Expressive motion-scheme springs, captured here
    // because transitionSpec lambdas are not composable).
    val reducedMotion = rememberReducedMotion()
    val stageEnterSpec = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
    val stageScaleSpec = MaterialTheme.motionScheme.defaultSpatialSpec<Float>()
    val stageExitSpec = MaterialTheme.motionScheme.fastEffectsSpec<Float>()

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
        )

        is OnboardingStep.ShowMnemonic -> OnboardingChassisModel(
            primary = ChassisAction(
                label = "I've Saved My Seed Phrase",
                onClick = { step = OnboardingStep.FirstMint(current.mnemonic) },
                enabled = seedAcknowledged,
                testTag = UiTestTags.SeedSaved,
            ),
        )

        is OnboardingStep.FirstMint -> OnboardingChassisModel(
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
        )

        OnboardingStep.RestoreInput -> {
            val wordCount = restoreSeedInput.trim().split(Regex("\\s+")).count { it.isNotBlank() }
            OnboardingChassisModel(
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
            )
        }

        is OnboardingStep.RestoreMints -> OnboardingChassisModel(
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
        )

        is OnboardingStep.RestoreProgress -> OnboardingChassisModel(
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

    // System back mirrors the on-screen back buttons, and only those: seed
    // reveal, the method chooser, and seed entry retreat to welcome (seed
    // entry deliberately skips the chooser, like iOS), mint staging retreats
    // to seed entry clearing the staged list exactly as its back button does.
    // Steps with no back affordance — welcome, first mint, and the
    // forward-only restore progress — keep the platform default (exit).
    BackHandler(
        enabled = step is OnboardingStep.ShowMnemonic ||
            step is OnboardingStep.FirstMint ||
            step is OnboardingStep.RestoreMethod ||
            step is OnboardingStep.RestoreInput ||
            step is OnboardingStep.RestoreMints,
    ) {
        when (val current = step) {
            is OnboardingStep.ShowMnemonic -> step = OnboardingStep.Welcome
            is OnboardingStep.FirstMint ->
                if (!finishing) step = OnboardingStep.ShowMnemonic(current.mnemonic)
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
            Column(
                verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
            ) {
                SeedWarningNotice()
                SeedAcknowledgeRow(
                    acknowledged = seedAcknowledged,
                    onToggle = {
                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        seedAcknowledged = !seedAcknowledged
                    },
                )
            }
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
            // Quiet materialize — no lateral push between steps (2026-06-26
            // iOS decision, binding product behavior). The incoming stage
            // scales 0.96 → 1 on the expressive spatial spring while fading in
            // and resolving from blur (the materializeBlur below); the outgoing
            // stage just fades on the fast spec — exits subtler than entrances.
            // Reduce Motion keeps a plain crossfade.
            transitionSpec = {
                if (reducedMotion) {
                    fadeIn(tween(250)).togetherWith(fadeOut(tween(180)))
                } else {
                    (
                        fadeIn(stageEnterSpec) +
                            scaleIn(animationSpec = stageScaleSpec, initialScale = 0.96f)
                        )
                        .togetherWith(fadeOut(stageExitSpec))
                }
            },
            label = "onboarding-step",
        ) { current ->
            // Incoming stages resolve from a 4dp blur (API 31+ and
            // reduce-motion gated inside materializeBlur). Skipped on the
            // initial composition so a cold launch's first frame renders sharp.
            val enteredViaTransition = remember { transition.currentState != transition.targetState }
            val stageModifier = if (enteredViaTransition) {
                Modifier
                    .fillMaxSize()
                    .materializeBlur()
            } else {
                Modifier.fillMaxSize()
            }
            Box(stageModifier) {
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
                        onInfo = { infoOpen = true },
                    )

                    is OnboardingStep.ShowMnemonic -> ShowMnemonicStageContent(
                        mnemonic = current.mnemonic,
                        onBack = { step = OnboardingStep.Welcome },
                    )

                    is OnboardingStep.FirstMint -> FirstMintStageContent(
                        state = firstMint,
                        busy = finishing,
                        addingMintUrl = addingMintUrl,
                        errorText = firstMintError,
                        onBack = { step = OnboardingStep.ShowMnemonic(current.mnemonic) },
                    )

                    OnboardingStep.RestoreMethod -> Column(Modifier.fillMaxSize()) {
                        OnboardingBackButton(
                            onBack = { step = OnboardingStep.Welcome },
                            modifier = Modifier.padding(
                                start = OnboardingMetrics.BarStartInset,
                                top = OnboardingMetrics.BarTopInset,
                            ),
                        )
                        OnboardingStepHeader(
                            title = "Restore Wallet",
                            subhead = "Choose how to recover your wallet.",
                            modifier = Modifier.padding(top = OnboardingMetrics.TitleGap),
                        )
                        Spacer(Modifier.weight(1f))
                    }

                    OnboardingStep.RestoreInput -> Column(Modifier.fillMaxSize()) {
                        OnboardingBackButton(
                            onBack = { step = OnboardingStep.Welcome },
                            modifier = Modifier.padding(
                                start = OnboardingMetrics.BarStartInset,
                                top = OnboardingMetrics.BarTopInset,
                            ),
                        )
                        OnboardingStepHeader(
                            title = "Restore Wallet.",
                            subhead = "Enter your 12 words in order.",
                            modifier = Modifier.padding(top = OnboardingMetrics.TitleGap),
                        )
                        RestoreSeedStageContent(
                            input = restoreSeedInput,
                            onInputChange = {
                                restoreSeedInput = it
                                restoreError = null
                            },
                            wordCount = restoreSeedInput.trim().split(Regex("\\s+")).count { it.isNotBlank() },
                            invalidCount = Bip39WordList.invalidWordIndices(restoreSeedInput).size,
                            errorText = restoreError,
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxWidth(),
                        )
                    }

                    is OnboardingStep.RestoreMints -> Column(Modifier.fillMaxSize()) {
                        OnboardingBackButton(
                            onBack = {
                                restoreMintsStaging.reset()
                                step = OnboardingStep.RestoreInput
                            },
                            modifier = Modifier.padding(
                                start = OnboardingMetrics.BarStartInset,
                                top = OnboardingMetrics.BarTopInset,
                            ),
                        )
                        OnboardingStepHeader(
                            title = "Recover Funds.",
                            subhead = "Add the mints you used before to recover funds from this seed.",
                            modifier = Modifier.padding(top = OnboardingMetrics.TitleGap),
                        )
                        RestoreMintsStageContent(
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
                                .weight(1f)
                                .fillMaxWidth()
                                .padding(top = CashuTheme.spacing.comfortable),
                        )
                    }

                    is OnboardingStep.RestoreProgress -> Column(Modifier.fillMaxSize()) {
                        // No back button on this step (forward-only), so it
                        // reserves the bar band rather than skipping it —
                        // otherwise the title jumps up 56 dp on arrival.
                        OnboardingStepHeader(
                            title = "Recover Funds.",
                            subhead = progressState?.subhead,
                            modifier = Modifier.padding(
                                top = OnboardingMetrics.TitleTopInset,
                                bottom = CashuTheme.spacing.default,
                            ),
                        )
                        if (progressState != null && progressState.totalRecovered > 0L) {
                            // Money value — monospaced digits + no roll (Numbers
                            // Are Sacred), exactly as the shared component
                            // renders it.
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
// Two slots only. "What is ecash?" used to sit in the tertiary slot, making
// welcome the sole 3-slot step — the button stack shrank the moment you left
// it. It is now a bar-band icon on the stage (see WelcomeStageContent).
internal fun welcomeChassis(
    creating: Boolean,
    retryingStartup: Boolean,
    onCreate: () -> Unit,
    onRestore: () -> Unit,
): OnboardingChassisModel = OnboardingChassisModel(
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
)

/** The welcome stage: the app's title where every other step puts its own, then
 * startup-failure recovery + create errors pinned just above the chassis. */
@Composable
internal fun WelcomeStageContent(
    startupFailure: WalletStartupFailure?,
    retryingStartup: Boolean,
    errorText: String?,
    onRetryStartup: () -> Unit,
    onInfo: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxSize()) {
        // "What is ecash?" lives here rather than in the chassis: as a ghost
        // tertiary it made welcome the only 3-slot step, so the button stack
        // changed height the moment you left it. It sits in the bar band's
        // trailing slot — opposite where other steps put Back — so the band
        // reads the same everywhere and the chassis holds a steady two buttons.
        OnboardingInfoButton(
            onClick = onInfo,
            modifier = Modifier
                .align(Alignment.End)
                .padding(
                    // Symmetric with the back button's leading inset.
                    end = OnboardingMetrics.BarStartInset,
                    top = OnboardingMetrics.BarTopInset,
                ),
        )
        // The only title that keeps a hardcoded break. Left to wrap naturally
        // it wraps after "In" — "Private cash. In" / "your pocket." — splitting
        // the second sentence. Breaking at the sentence boundary is the
        // deliberate exception.
        //
        // Welcome now draws a bar button like every other step, so it uses the
        // same BarTopInset + BarHeight + TitleGap stack instead of
        // TitleTopInset — the title lands on the identical line either way.
        OnboardingStepHeader(
            title = "Private cash.\nIn your pocket.",
            subhead = "An ecash wallet for Bitcoin and Lightning.",
            modifier = Modifier.padding(top = OnboardingMetrics.TitleGap),
        )
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

/**
 * Centered caution above the acknowledge row. Deliberately a warning triangle,
 * not a check-shield: a shield reads as "you're protected", which is the
 * opposite of what this sentence says.
 *
 * Not [com.cashu.me.ui.components.InlineNotice] — that is a tinted, left-aligned
 * rounded container, and this screen already has one card. Bare centered
 * icon-over-text keeps the bottom band quiet.
 */
@Composable
internal fun SeedWarningNotice(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {},
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
    ) {
        Icon(
            imageVector = Icons.Filled.Warning,
            contentDescription = null,
            tint = CashuTheme.colors.pending,
            modifier = Modifier.size(WarningIconSize),
        )
        Text(
            text = "Never share these words with anyone.",
            style = MaterialTheme.typography.labelMedium,
            color = CashuTheme.colors.pending,
            textAlign = TextAlign.Center,
        )
    }
}

/** The acknowledge row rides the chassis accessory slot — above the primary it
 * gates, so it can never move the button. The warning rides it for the same
 * reason: pinned there it argues for the checkbox directly below it and can
 * never push the CTA around. */
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

/** The seed stage: back, header + warning at the top, redacted grid with
 * tap-to-reveal, and Copy. */
@Composable
internal fun ShowMnemonicStageContent(
    mnemonic: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val clipboard = LocalClipboardManager.current
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val words = remember(mnemonic) { mnemonic.trim().split(' ').filter { it.isNotBlank() } }

    var revealed by remember { mutableStateOf(false) }
    var copied by remember { mutableStateOf(false) }

    // Tapping the card toggles the phrase, like iOS — the seed should be easy
    // to put away once it's been written down, not stuck on screen for the
    // rest of the step. Hiding re-composes the "••••••" placeholders, so the
    // real words stop being drawn on the same frame the blur returns.
    fun toggleReveal() {
        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        revealed = !revealed
    }

    Column(
        modifier = modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        OnboardingBackButton(
            onBack = onBack,
            modifier = Modifier
                .align(Alignment.Start)
                .padding(
                    start = OnboardingMetrics.BarStartInset,
                    top = OnboardingMetrics.BarTopInset,
                ),
        )
        // Title + subhead only, like every sibling step. The "never share"
        // warning used to sit here; it now rides the chassis accessory
        // directly above the acknowledge row it argues for.
        OnboardingStepHeader(
            title = "Your Seed Phrase.",
            subhead = "Write these 12 words down in order. This is the only way to recover your wallet.",
            modifier = Modifier.padding(top = OnboardingMetrics.TitleGap),
        )
        // The seed grid deliberately gets NO entrance motion: any motion on
        // this block reads as a flicker on first paint, and recomposition
        // mid-entrance restarts it. The step crossfade owns its appearance;
        // the tap-to-reveal swap is untouched.
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = CashuTheme.spacing.section),
            // default + snug = 20dp between grid and Copy — flush against the
            // words the link read as part of the grid (design review).
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // SeedPhraseReveal draws its own card — the caller passes layout
            // only, so the screenshot previews can't drift from production.
            SeedPhraseReveal(
                words = words,
                revealed = revealed,
                onToggle = ::toggleReveal,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = HeaderPadding),
            )
            GhostButton(
                text = if (copied) "Copied" else "Copy",
                leadingIcon = if (copied) Icons.Filled.Check else Icons.Outlined.ContentCopy,
                onClick = {
                    clipboard.setText(AnnotatedString(words.joinToString(" ")))
                    copied = true
                    scope.launch {
                        delay(3_000)
                        copied = false
                    }
                },
                // The card edge already separates the link from the words, so
                // the total gap is 16 (snug + snug), not the bare grid's 20.
                modifier = Modifier.padding(top = CashuTheme.spacing.snug),
            )
        }
        Spacer(Modifier.weight(1f))
    }
}

/**
 * The seed card: keeps the masked phrase out of TalkBack's tree and replaces the
 * whole visual with one reveal control. Once revealed, the masking semantics
 * disappear so TalkBack can traverse the ordered words in [SeedGrid], and the
 * card's click action becomes "Hide seed phrase" — tapping toggles both ways.
 *
 * Draws its own card surface (The Seed Card Exception — the phrase is a single
 * object you act on, not screen content, so it earns a container; the card is
 * also what gives tap-to-reveal a visible edge, where the gesture previously
 * targeted an invisible box). Owning the surface here rather than at the call
 * site is what keeps the screenshot previews from drifting from production.
 */
@Composable
internal fun SeedPhraseReveal(
    words: List<String>,
    revealed: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val currentToggle by rememberUpdatedState(onToggle)
    val accessibilityModifier = if (revealed) {
        // Revealed: the card stays tappable so the phrase can be put away
        // again. Deliberately NOT `Modifier.clickable` — that merges its
        // descendants' semantics, collapsing the 12 individually-traversable
        // words into a single node and destroying the ordered per-word
        // reading TalkBack relies on (and that
        // `revealReplacesActionWithOrderedNumberedWords` asserts). A raw
        // pointer handler plus a non-merging `onClick` semantic gives the same
        // affordance while leaving the subtree intact.
        Modifier
            .pointerInput(Unit) { detectTapGestures { currentToggle() } }
            .semantics {
                onClick(label = "Hide seed phrase") {
                    currentToggle()
                    true
                }
            }
    } else {
        Modifier
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClickLabel = "Reveal seed phrase",
                onClick = onToggle,
            )
            .clearAndSetSemantics {
                semanticsTestTag = UiTestTags.RevealSeed
                contentDescription = "Reveal seed phrase"
                role = Role.Button
                onClick(label = "Reveal seed phrase") {
                    onToggle()
                    true
                }
            }
    }

    Box(
        // Modifier order is load-bearing. clip + background come BEFORE the
        // clickable so the whole card is the tap target, and the card's inner
        // padding comes AFTER it — padded first, the tap target would shrink
        // to the grid and the 20dp margin would look tappable without being
        // tappable. Callers pass layout only.
        modifier = modifier
            .clip(RoundedCornerShape(SeedCardRadius))
            .background(MaterialTheme.colorScheme.surfaceContainerHigh)
            .then(accessibilityModifier)
            .padding(SeedCardPadding),
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
 * 3-column × 4-row seed grid — iOS mnemonicWordsGrid. Zero-padded indices in a
 * fixed trailing-aligned column, monospaced medium words. The card around the
 * whole grid (applied by the caller, see The Seed Card Exception) carries the
 * containment, so the words themselves stay quiet — no per-word chrome.
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
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxSize()) {
        OnboardingBackButton(
            onBack = onBack,
            modifier = Modifier.padding(
                start = OnboardingMetrics.BarStartInset,
                top = OnboardingMetrics.BarTopInset,
            ),
        )
        OnboardingStepHeader(
            title = "Pick your first mint.",
            subhead = "Mints issue your ecash and redeem it for Bitcoin. Add more anytime in Settings.",
            modifier = Modifier.padding(top = OnboardingMetrics.TitleGap),
        )
        FirstMintList(
            state = state,
            busy = busy,
            addingMintUrl = addingMintUrl,
            errorText = errorText,
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
        )
    }
}

@Composable
private fun FirstMintList(
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
