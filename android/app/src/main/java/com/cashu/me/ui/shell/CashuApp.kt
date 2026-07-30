package com.cashu.me.ui.shell

import androidx.activity.compose.BackHandler
import androidx.activity.compose.ReportDrawnWhen
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.IntOffset
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.navigation.compose.rememberNavController
import kotlinx.coroutines.flow.StateFlow
import com.cashu.me.R
import com.cashu.me.App.AppContainer
import com.cashu.me.Core.Navigation.CashuRoute
import com.cashu.me.Core.PaymentRequestDecodeResult
import com.cashu.me.Core.PaymentRequestDecoder
import com.cashu.me.Core.TokenParser
import com.cashu.me.Views.Components.ScannerView
import com.cashu.me.Views.Send.ContactlessPaySheet
import com.cashu.me.ui.onboarding.OnboardingScreen
import com.cashu.me.ui.navigation.Routes
import com.cashu.me.ui.navigation.TopTab
import com.cashu.me.ui.navigation.cashuRequestDetailRouteFor
import com.cashu.me.ui.navigation.navigateToTab
import com.cashu.me.ui.navigation.shellBackAction
import com.cashu.me.ui.receive.ReceiveEcashDetailScreen
import com.cashu.me.ui.receive.ReceiveEcashScreen
import com.cashu.me.ui.receive.ReceiveLightningScreen
import com.cashu.me.ui.send.SendEcashScreen
import com.cashu.me.ui.send.UnifiedSendScreen
import com.cashu.me.ui.security.AppLockGate
import com.cashu.me.ui.security.PrivacyCover
import com.cashu.me.ui.security.SecureWindowEffect
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.testing.UiTestTags

/**
 * Top-level entry. Replaces `App.ContentView.CashuWalletApp`.
 *
 * Gating order matches iOS:
 *   - `!isInitialized`  → centered spinner
 *   - `needsOnboarding` → full-screen onboarding (no bottom nav)
 *   - otherwise         → 3-tab `WalletScaffold` over a `NavHost`
 *
 * Scanner and Contactless render as full-screen overlays driven by shell state;
 * the money flows (Send / Send Ecash / Receive Ecash / Receive Lightning) are
 * native modal bottom sheets hosted by [WalletFlowSheetHost] (iOS sheet parity).
 */
@Composable
fun CashuApp(containerFlow: StateFlow<AppContainer?>) {
    CashuTheme {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .testTag(UiTestTags.AppRoot)
                .semantics { testTagsAsResourceId = true },
        ) {
            val container by containerFlow.collectAsState()
            if (container == null) {
                LoadingScreen()
            } else {
                CashuAppContent(container = checkNotNull(container))
            }
        }
    }
}

@Composable
private fun CashuAppContent(container: AppContainer) {
    val walletState by container.walletManager.state.collectAsState()
    val settings by container.settingsManager.state.collectAsState()
    val lifecycleOwner = LocalLifecycleOwner.current
    val isAuthenticated = walletState.isInitialized && !walletState.needsOnboarding
    val isRuntimeReady = isAuthenticated && walletState.isRuntimeReady
    // StartupTimingMetric's full-display boundary: cached balance and
    // transaction history have both been decoded into WalletState.
    ReportDrawnWhen { walletState.isInitialized }
    SecureWindowEffect(enabled = settings.appLockEnabled)

    LaunchedEffect(Unit) {
        container.walletManager.initialize()
    }
    LaunchedEffect(isAuthenticated) {
        if (isAuthenticated) {
            container.appLockManager.startAuthenticatedSession()
        } else {
            container.appLockManager.endAuthenticatedSession()
        }
    }

    val isRuntimeReadyRef by rememberUpdatedState(isRuntimeReady)
    val shouldListenForRequests =
        container.runtimePolicy.startExternalListeners &&
            isRuntimeReady &&
            settings.enablePaymentRequests
    val shouldListenForRequestsRef by rememberUpdatedState(shouldListenForRequests)

    LaunchedEffect(isRuntimeReady) {
        if (isRuntimeReady) {
            val currentSettings = container.settingsManager.state.value
            if (container.runtimePolicy.runStartupMaintenance &&
                currentSettings.checkPendingOnStartup &&
                currentSettings.checkSentTokens
            ) {
                container.walletManager.checkAllPendingTokens()
            }
            // Runtime became ready while the process is already foregrounded —
            // ProcessLifecycle ON_START won't re-fire. Arm quote detection now
            // (iOS deferred-startup parity).
            if (container.runtimePolicy.pollQuotesInForeground &&
                ProcessLifecycleOwner.get().lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)
            ) {
                container.walletManager.onAppEnteredForeground()
            }
        } else {
            container.cashuRequestListener.stop()
            container.walletManager.stopPendingQuoteForegroundPolling()
        }
    }
    LaunchedEffect(shouldListenForRequests) {
        if (shouldListenForRequests) {
            container.cashuRequestListener.start()
        } else {
            container.cashuRequestListener.stop()
        }
    }
    // App-process foreground (not Activity): M3 ModalBottomSheet runs in its own
    // Dialog window and can ON_STOP the Activity while the user is still in the
    // app. Quote detection must keep running — iOS scenePhase parity.
    DisposableEffect(container) {
        val processLifecycle = ProcessLifecycleOwner.get().lifecycle
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> {
                    if (container.runtimePolicy.pollQuotesInForeground && isRuntimeReadyRef) {
                        container.walletManager.onAppEnteredForeground()
                    }
                }
                Lifecycle.Event.ON_STOP -> {
                    container.walletManager.stopPendingQuoteForegroundPolling()
                }
                else -> Unit
            }
        }
        processLifecycle.addObserver(observer)
        onDispose {
            processLifecycle.removeObserver(observer)
            container.walletManager.stopPendingQuoteForegroundPolling()
        }
    }

    // Activity lifecycle: app-lock + Cashu-request listener only. Do not stop
    // quote polling here — sheets/overlays pause the Activity without leaving
    // the app.
    DisposableEffect(lifecycleOwner, container) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START,
                Lifecycle.Event.ON_RESUME -> {
                    container.appLockManager.appBecameActive()
                    if (shouldListenForRequestsRef) {
                        container.cashuRequestListener.start()
                    }
                }
                Lifecycle.Event.ON_PAUSE,
                Lifecycle.Event.ON_STOP -> {
                    container.appLockManager.appResignedActive()
                    if (event == Lifecycle.Event.ON_STOP) {
                        container.cashuRequestListener.stop()
                    }
                }
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            container.cashuRequestListener.stop()
        }
    }

    // Root gating cross-fades (fade-through) instead of hard-cutting.
    val gate = when {
        !walletState.isInitialized -> AppGate.Loading
        walletState.needsOnboarding -> AppGate.Onboarding
        else -> AppGate.Shell
    }
    Box(modifier = Modifier.fillMaxSize()) {
        AnimatedContent(
            targetState = gate,
            transitionSpec = {
                (fadeIn(spring(stiffness = Spring.StiffnessMedium)) +
                    scaleIn(initialScale = 0.98f, animationSpec = spring(stiffness = Spring.StiffnessMedium)))
                    .togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
            },
            label = "app-gate",
        ) { target ->
            when (target) {
                AppGate.Loading -> LoadingScreen()
                AppGate.Onboarding -> OnboardingScreen(
                    walletManager = container.walletManager,
                    nostrMintBackupService = container.nostrMintBackupService,
                )
                AppGate.Shell -> AuthenticatedShell(container = container)
            }
        }
        // Covers pushed nav destinations and the base shell; money-flow sheets
        // mount their own host below since ModalBottomSheet renders in a
        // separate Android Window this one can't reach.
        SnackbarHost(
            hostState = container.snackbarHostState,
            modifier = Modifier.align(Alignment.BottomCenter),
        )
    }
}

private enum class AppGate { Loading, Onboarding, Shell }

@Composable
private fun AuthenticatedShell(container: AppContainer) {
    val navController = rememberNavController()
    val walletState by container.walletManager.state.collectAsState()
    val isRuntimeReadyRef by rememberUpdatedState(walletState.isRuntimeReady)
    var showContactless by remember { mutableStateOf(false) }
    var scannerTarget by remember { mutableStateOf<ScannerTarget?>(null) }
    // The active money flow, hosted in a modal bottom sheet (iOS WalletFlow sheets).
    var activeFlow by remember { mutableStateOf<WalletFlow?>(null) }
    var flowDismissLocked by remember { mutableStateOf(false) }
    val flowHandoff = remember { WalletFlowHandoffCoordinator() }
    var pendingReceiveScan by remember { mutableStateOf<String?>(null) }
    var pendingSendScan by remember { mutableStateOf<String?>(null) }
    var pendingMintScan by remember { mutableStateOf<String?>(null) }
    // Full-screen "Receive Ecash" page (iOS ReceiveTokenDetailView via
    // .fullScreenCover): every token that arrives from *outside* the paste
    // flow — scanner, cashu: deep link, token pasted into Send — lands here.
    // The Receive sheet's Review face survives only for the paste flow and
    // its in-sheet scan.
    var receiveTokenDetail by remember { mutableStateOf<String?>(null) }
    var receiveDetailDismissLocked by remember { mutableStateOf(false) }

    // A fresh flow starts unlocked, whatever the last one left behind.
    LaunchedEffect(activeFlow) { flowDismissLocked = false }
    LaunchedEffect(receiveTokenDetail) { receiveDetailDismissLocked = false }
    LaunchedEffect(walletState.isRuntimeReady) {
        if (!walletState.isRuntimeReady) {
            activeFlow = null
            receiveTokenDetail = null
            showContactless = false
        }
    }

    val openPaymentFlow: (WalletFlow) -> Unit = { flow ->
        if (isRuntimeReadyRef) activeFlow = flow
    }
    val openReceiveDetail: (String) -> Unit = { payload ->
        if (isRuntimeReadyRef) receiveTokenDetail = payload
    }

    val pendingDeepLink by container.navigationManager.pendingDeepLink.collectAsState()
    val connectivityState by container.connectivityObserver.state.collectAsState()
    val appLockState by container.appLockManager.state.collectAsState()
    val cashuRequestListenerState by container.cashuRequestListener.state.collectAsState()

    // Incoming payments that are not eligible for silent receipt are already
    // persisted before being surfaced. Present the normal Receive review when
    // the shell is idle; closing it leaves the payment claimable from History.
    LaunchedEffect(
        cashuRequestListenerState.heldForApproval?.tokenId,
        receiveTokenDetail,
        activeFlow,
        scannerTarget,
        showContactless,
        appLockState.isLocked,
        walletState.isRuntimeReady,
    ) {
        val held = cashuRequestListenerState.heldForApproval ?: return@LaunchedEffect
        val canPresent = walletState.isRuntimeReady &&
            receiveTokenDetail == null &&
            activeFlow == null &&
            scannerTarget == null &&
            !showContactless &&
            !appLockState.isLocked
        if (canPresent) {
            receiveTokenDetail = held.token
            container.cashuRequestListener.dismissHeldPayment()
        }
    }

    LaunchedEffect(pendingDeepLink, walletState.isRuntimeReady) {
        val deepLink = pendingDeepLink ?: return@LaunchedEffect
        // Keep payment deep links pending until the encrypted seed and CDK
        // repository are available. Non-payment destinations can open normally.
        if (!walletState.isRuntimeReady && deepLink.route in paymentRoutes) {
            return@LaunchedEffect
        }
        when (deepLink.route) {
            CashuRoute.Receive -> {
                val payload = deepLink.payload.orEmpty()
                if (payload.isNotBlank()) {
                    // Deep-linked token: full-screen claim page (iOS presents
                    // ReceiveTokenDetailView via .fullScreenCover from ContentView).
                    openReceiveDetail(payload)
                } else {
                    // Bare cashu: link with no token — open the paste sheet.
                    openPaymentFlow(WalletFlow.ReceiveEcash)
                }
            }
            CashuRoute.Send -> {
                pendingSendScan = deepLink.payload.orEmpty()
                openPaymentFlow(WalletFlow.Send)
            }
            CashuRoute.Mints -> {
                pendingMintScan = deepLink.payload.orEmpty()
                navController.navigateToTab(TopTab.Mints)
            }
            CashuRoute.Main -> navController.navigateToTab(TopTab.Home)
            CashuRoute.History -> navController.navigateToTab(TopTab.History)
            CashuRoute.Settings -> navController.navigate(Routes.SETTINGS)
            CashuRoute.Scanner -> scannerTarget = ScannerTarget.Auto
            CashuRoute.Contactless -> if (isRuntimeReadyRef) showContactless = true
        }
        container.navigationManager.consumeDeepLink()
    }

    val activeScannerTarget = scannerTarget
    // The shell stays mounted; camera surfaces animate over it (slide-up + fade)
    // instead of replacing it with a one-frame cut.
    var lastScannerTarget by remember { mutableStateOf(ScannerTarget.Auto) }
    if (activeScannerTarget != null) lastScannerTarget = activeScannerTarget

    Box(modifier = Modifier.fillMaxSize()) {
        WalletScaffold(
            container = container,
            connectivityState = connectivityState,
            onScan = { scannerTarget = ScannerTarget.Auto },
            onReceiveEcash = { openPaymentFlow(WalletFlow.ReceiveEcash) },
            onReceiveLightning = { openPaymentFlow(WalletFlow.ReceiveLightning) },
            onSend = { openPaymentFlow(WalletFlow.Send) },
            pendingMintScan = pendingMintScan,
            onPendingMintScanConsumed = { pendingMintScan = null },
            // Pending "Receive later" tokens claim on the full-screen page.
            onClaimReceiveToken = openReceiveDetail,
            navController = navController,
        )
        AnimatedVisibility(
            visible = activeScannerTarget != null,
            modifier = Modifier.testTag(UiTestTags.ScannerRoot),
            enter = overlayEnter,
            exit = overlayExit,
        ) {
            ScannerView(
                onClose = { scannerTarget = null },
                useDeterministicPermission =
                    container.runtimePolicy.useDeterministicCameraPermission,
                onScanned = { payload ->
                    scannerTarget = null
                    routeScannedPayload(
                        target = lastScannerTarget,
                        payload = payload,
                        // In-sheet scan (ScannerTarget.Receive): back to the
                        // sheet's Review face — the user is inside the paste flow.
                        onReceiveInSheet = {
                            if (isRuntimeReadyRef) {
                                pendingReceiveScan = it
                                openPaymentFlow(WalletFlow.ReceiveEcash)
                            }
                        },
                        // Main scan button: tokens read as a brand-new full
                        // screen, never the home sheet (iOS scanner parity).
                        onReceiveDetail = openReceiveDetail,
                        onSend = {
                            if (isRuntimeReadyRef) {
                                pendingSendScan = it
                                openPaymentFlow(WalletFlow.Send)
                            }
                        },
                        onMint = {
                            pendingMintScan = it
                            navController.navigateToTab(TopTab.Mints)
                        },
                    )
                },
            )
        }
        // Full-screen Receive Ecash claim page — rendered above the camera
        // overlays (scanner closes before routing, so no live camera shows
        // behind, matching the iOS fullScreenCover rationale).
        // Remember the last payload so exit animates with content intact.
        var lastReceiveTokenDetail by remember { mutableStateOf("") }
        if (receiveTokenDetail != null) lastReceiveTokenDetail = receiveTokenDetail!!
        AnimatedVisibility(
            visible = walletState.isRuntimeReady && receiveTokenDetail != null,
            enter = overlayEnter,
            exit = overlayExit,
        ) {
            ReceiveEcashDetailScreen(
                walletManager = container.walletManager,
                settingsManager = container.settingsManager,
                priceService = container.priceService,
                payload = lastReceiveTokenDetail,
                onDone = { receiveTokenDetail = null },
                onDismissLockChanged = { receiveDetailDismissLocked = it },
                claimPendingReceiveToken = { pending ->
                    if (pending.isCashuRequestPayment) {
                        container.cashuRequestListener.claimHeldPayment(pending)
                    } else {
                        container.walletManager.claimPendingReceiveToken(pending)
                    }
                },
                onDeclinePendingReceiveToken = container.cashuRequestListener::declineHeldPayment,
            )
        }
        // System back (including predictive back) must dismiss the topmost overlay
        // instead of popping the NavHost — or exiting the app — underneath it.
        // Declared after WalletScaffold so this callback registers last on the
        // OnBackPressedDispatcher and takes precedence over NavHost back handling
        // while an overlay is visible. Receive detail renders above the scanner.
        // Modal sheets live in their own windows and handle back themselves.
        BackHandler(enabled = !appLockState.isLocked && (receiveTokenDetail != null || activeScannerTarget != null)) {
            when (shellBackAction(receiveTokenDetail != null, activeScannerTarget != null)) {
                com.cashu.me.ui.navigation.ShellBackAction.CloseReceiveDetail -> {
                    // Never abandon a redeem in flight.
                    if (!receiveDetailDismissLocked) receiveTokenDetail = null
                }
                com.cashu.me.ui.navigation.ShellBackAction.CloseScanner -> scannerTarget = null
                null -> Unit
            }
        }
        if (appLockState.isObscured && !appLockState.isLocked) {
            PrivacyCover()
        }
        if (appLockState.isLocked) {
            AppLockGate(appLockManager = container.appLockManager)
        }
    }

    WalletFlowSheetHost(
        // The effect above clears stale state; this synchronous gate also
        // prevents a sheet from mounting for a frame if readiness drops.
        flow = activeFlow.takeIf { walletState.isRuntimeReady },
        dismissLocked = flowDismissLocked,
        onDismissed = {
            activeFlow = null
            flowHandoff.completeDismissal(
                openScanner = { scannerTarget = ScannerTarget.Auto },
                openContactless = {
                    if (isRuntimeReadyRef) showContactless = true
                },
            )
        },
        snackbarHostState = container.snackbarHostState,
    ) { flow, close ->
        when (flow) {
            WalletFlow.ReceiveEcash -> ReceiveEcashScreen(
                walletManager = container.walletManager,
                settingsManager = container.settingsManager,
                nostrService = container.nostrService,
                cashuRequestStore = container.cashuRequestStore,
                onOpenRequest = { id ->
                    close()
                    navController.navigate(cashuRequestDetailRouteFor(id))
                },
                onClose = close,
                // Universal scanner (Send parity): auto-routes whatever it reads.
                // Camera overlays render in the activity window, underneath this
                // sheet's dialog window — the sheet must yield before scanning.
                onScan = {
                    flowHandoff.requestScanner(close)
                },
                // A pasted/scanned token opens the full-screen claim page — same
                // destination Send bounces a token to (iOS ReceiveTokenDetailView).
                onOpenReceiveToken = { token ->
                    close()
                    receiveTokenDetail = token
                },
                // A payable pasted into Receive is really a Send — swap the sheet
                // content to the Send flow, pre-filled (inverse of onOpenReceiveToken).
                onSendPayable = { raw ->
                    pendingSendScan = raw
                    activeFlow = WalletFlow.Send
                },
                // Bitcoin opens the mint's Lightning / on-chain receive dialog.
                onReceiveBitcoin = { activeFlow = WalletFlow.ReceiveLightning },
                prefilledPayload = pendingReceiveScan,
                onPrefilledConsumed = { pendingReceiveScan = null },
                allowAutomaticClipboardRead = container.runtimePolicy.allowAutomaticClipboardReads,
            )

            WalletFlow.ReceiveLightning -> ReceiveLightningScreen(
                walletManager = container.walletManager,
                cashuRequestStore = container.cashuRequestStore,
                settingsManager = container.settingsManager,
                onClose = close,
            )

            WalletFlow.Send -> UnifiedSendScreen(
                walletManager = container.walletManager,
                settingsManager = container.settingsManager,
                priceService = container.priceService,
                onClose = close,
                onScan = {
                    flowHandoff.requestScanner(close)
                },
                onContactless = {
                    // Android has no system NFC sheet. Let Send finish its hide
                    // animation before mounting the fresh Material NFC sheet.
                    flowHandoff.requestContactless(close)
                },
                onSendEcash = { activeFlow = WalletFlow.SendEcash },
                onOpenReceiveToken = { token ->
                    // A token pasted into Send is a receive: bounce it to the
                    // full-screen claim page (iOS SendRoute.receiveToken →
                    // fullScreenCover), closing the Send sheet.
                    close()
                    receiveTokenDetail = token
                },
                onOpenMints = {
                    close()
                    navController.navigateToTab(TopTab.Mints)
                },
                onReceive = { activeFlow = WalletFlow.ReceiveEcash },
                prefilledPayload = pendingSendScan,
                onPrefilledConsumed = { pendingSendScan = null },
                onDismissLockChanged = { flowDismissLocked = it },
            )

            WalletFlow.SendEcash -> SendEcashScreen(
                walletManager = container.walletManager,
                settingsManager = container.settingsManager,
                priceService = container.priceService,
                onBack = { activeFlow = WalletFlow.Send },
                onClose = close,
                onDismissLockChanged = { flowDismissLocked = it },
            )
        }
    }

    if (walletState.isRuntimeReady && showContactless) {
        ContactlessPaySheet(
            walletManager = container.walletManager,
            onDismissed = { showContactless = false },
            onLightningRequest = { invoice ->
                showContactless = false
                pendingSendScan = invoice
                openPaymentFlow(WalletFlow.Send)
            },
        )
    }
}

private val paymentRoutes = setOf(
    CashuRoute.Receive,
    CashuRoute.Send,
    CashuRoute.Contactless,
)

// Camera-surface overlay motion: slide up over the shell, slide back down on close.
private val overlayEnter = slideInVertically(
    spring(stiffness = Spring.StiffnessMediumLow, visibilityThreshold = IntOffset.VisibilityThreshold),
) { it / 5 } + fadeIn(spring(stiffness = Spring.StiffnessMedium))
private val overlayExit = slideOutVertically(
    spring(stiffness = Spring.StiffnessMediumLow, visibilityThreshold = IntOffset.VisibilityThreshold),
) { it / 5 } + fadeOut(spring(stiffness = Spring.StiffnessMedium))

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun LoadingScreen() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
        contentAlignment = Alignment.Center,
    ) {
        val loadingLabel = stringResource(R.string.loading_wallet)
        Column(
            modifier = Modifier.clearAndSetSemantics {
                contentDescription = loadingLabel
                progressBarRangeInfo = ProgressBarRangeInfo.Indeterminate
            },
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
        ) {
            LoadingIndicator()
            Text(
                text = loadingLabel,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

internal enum class ScannerTarget { Auto, Receive, Send, Mints }

private fun routeScannedPayload(
    target: ScannerTarget,
    payload: String,
    onReceiveInSheet: (String) -> Unit,
    onReceiveDetail: (String) -> Unit,
    onSend: (String) -> Unit,
    onMint: (String) -> Unit,
) {
    val trimmed = payload.trim()
    when (target) {
        ScannerTarget.Receive -> {
            onReceiveInSheet(TokenParser.extractToken(trimmed) ?: trimmed)
            return
        }
        ScannerTarget.Send -> {
            onSend(trimmed)
            return
        }
        ScannerTarget.Mints -> {
            onMint(trimmed)
            return
        }
        ScannerTarget.Auto -> Unit
    }
    TokenParser.extractToken(trimmed)?.let {
        onReceiveDetail(it)
        return
    }
    when (PaymentRequestDecoder.decode(trimmed, includeCashuPaymentRequests = true, preferCashuPaymentRequests = true)) {
        is PaymentRequestDecodeResult.Bolt11,
        is PaymentRequestDecodeResult.Bolt12,
        is PaymentRequestDecodeResult.CashuPaymentRequest,
        is PaymentRequestDecodeResult.LightningAddress,
        is PaymentRequestDecodeResult.Onchain -> onSend(trimmed)
        PaymentRequestDecodeResult.Unrecognized -> {
            if (trimmed.startsWith("https://", ignoreCase = true)) onMint(trimmed) else onSend(trimmed)
        }
    }
}
