package org.cashu.wallet.App

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import org.cashu.wallet.Core.PaymentRequestDecodeResult
import org.cashu.wallet.Core.PaymentRequestDecoder
import org.cashu.wallet.Core.TokenParser
import org.cashu.wallet.Core.Navigation.CashuRoute
import org.cashu.wallet.Resources.CashuTheme
import org.cashu.wallet.Views.Components.ScannerView
import org.cashu.wallet.Views.History.HistoryView
import org.cashu.wallet.Views.Main.MainWalletView
import org.cashu.wallet.Views.Main.OnboardingView
import org.cashu.wallet.Views.Mints.MintsListView
import org.cashu.wallet.Views.Receive.ReceiveView
import org.cashu.wallet.Views.Send.ContactlessPayView
import org.cashu.wallet.Views.Send.SendView
import org.cashu.wallet.Views.Settings.SettingsView

private enum class RootTab(val title: String) {
    Wallet("Wallet"),
    Receive("Receive"),
    Send("Send"),
    Mints("Mints"),
    History("History"),
    Settings("Settings"),
}

private enum class ScannerTarget {
    Auto,
    Receive,
    Send,
    Mints,
}

@Composable
fun CashuWalletApp(container: AppContainer) {
    CashuTheme {
        val walletState by container.walletManager.state.collectAsState()
        val lifecycleOwner = LocalLifecycleOwner.current
        val isAuthenticated = walletState.isInitialized && !walletState.needsOnboarding
        LaunchedEffect(Unit) {
            container.walletManager.initialize()
        }
        LaunchedEffect(isAuthenticated) {
            if (isAuthenticated) {
                container.cashuRequestListener.start()
                val settings = container.settingsManager.state.value
                if (settings.checkPendingOnStartup && settings.checkSentTokens) {
                    container.walletManager.checkAllPendingTokens()
                }
            } else {
                container.cashuRequestListener.stop()
            }
        }
        DisposableEffect(lifecycleOwner, isAuthenticated) {
            val observer = LifecycleEventObserver { _, event ->
                if (!isAuthenticated) return@LifecycleEventObserver
                when (event) {
                    Lifecycle.Event.ON_START,
                    Lifecycle.Event.ON_RESUME -> container.cashuRequestListener.start()
                    Lifecycle.Event.ON_STOP -> container.cashuRequestListener.stop()
                    else -> Unit
                }
            }
            lifecycleOwner.lifecycle.addObserver(observer)
            onDispose {
                lifecycleOwner.lifecycle.removeObserver(observer)
                container.cashuRequestListener.stop()
            }
        }

        when {
            !walletState.isInitialized -> LoadingView()
            walletState.needsOnboarding -> OnboardingView(walletManager = container.walletManager)
            else -> WalletShell(container = container)
        }
    }
}

@Composable
private fun WalletShell(container: AppContainer) {
    var selectedTab by remember { mutableStateOf(RootTab.Wallet) }
    var showContactless by remember { mutableStateOf(false) }
    var scannerTarget by remember { mutableStateOf<ScannerTarget?>(null) }
    var pendingReceiveScan by remember { mutableStateOf<String?>(null) }
    var pendingSendScan by remember { mutableStateOf<String?>(null) }
    var pendingMintScan by remember { mutableStateOf<String?>(null) }
    val pendingDeepLink by container.navigationManager.pendingDeepLink.collectAsState()
    val connectivityState by container.connectivityObserver.state.collectAsState()

    LaunchedEffect(pendingDeepLink) {
        val deepLink = pendingDeepLink ?: return@LaunchedEffect
        when (deepLink.route) {
            CashuRoute.Receive -> {
                pendingReceiveScan = deepLink.payload.orEmpty()
                selectedTab = RootTab.Receive
            }
            CashuRoute.Send -> {
                pendingSendScan = deepLink.payload.orEmpty()
                selectedTab = RootTab.Send
            }
            CashuRoute.Mints -> {
                pendingMintScan = deepLink.payload.orEmpty()
                selectedTab = RootTab.Mints
            }
            CashuRoute.Main -> selectedTab = RootTab.Wallet
            CashuRoute.History -> selectedTab = RootTab.History
            CashuRoute.Settings -> selectedTab = RootTab.Settings
            CashuRoute.Scanner -> scannerTarget = ScannerTarget.Auto
            CashuRoute.Contactless -> showContactless = true
        }
        container.navigationManager.consumeDeepLink()
    }

    val target = scannerTarget
    if (showContactless) {
        ContactlessPayView(
            walletManager = container.walletManager,
            onClose = { showContactless = false },
            onLightningRequest = { invoice ->
                pendingSendScan = invoice
                selectedTab = RootTab.Send
                showContactless = false
            },
        )
    } else if (target != null) {
        ScannerView(
            onClose = { scannerTarget = null },
            onScanned = { payload ->
                scannerTarget = null
                when (target) {
                    ScannerTarget.Receive -> {
                        pendingReceiveScan = TokenParser.extractToken(payload) ?: payload.trim()
                        selectedTab = RootTab.Receive
                    }
                    ScannerTarget.Send -> {
                        pendingSendScan = payload.trim()
                        selectedTab = RootTab.Send
                    }
                    ScannerTarget.Mints -> {
                        pendingMintScan = payload.trim()
                        selectedTab = RootTab.Mints
                    }
                    ScannerTarget.Auto -> routeScannedPayload(
                        payload = payload,
                        onReceive = {
                            pendingReceiveScan = it
                            selectedTab = RootTab.Receive
                        },
                        onSend = {
                            pendingSendScan = it
                            selectedTab = RootTab.Send
                        },
                        onMint = {
                            pendingMintScan = it
                            selectedTab = RootTab.Mints
                        },
                    )
                }
            },
        )
    } else {
        Scaffold(
            bottomBar = {
                NavigationBar {
                    RootTab.entries.forEach { tab ->
                        NavigationBarItem(
                            selected = selectedTab == tab,
                            onClick = { selectedTab = tab },
                            icon = {
                                Icon(
                                    imageVector = when (tab) {
                                        RootTab.Wallet -> Icons.Default.AccountBalanceWallet
                                        RootTab.Receive -> Icons.Default.QrCode
                                        RootTab.Send -> Icons.Default.Payments
                                        RootTab.Mints -> Icons.Default.AccountBalance
                                        RootTab.History -> Icons.Default.History
                                        RootTab.Settings -> Icons.Default.Settings
                                    },
                                    contentDescription = tab.title,
                                )
                            },
                            label = { Text(tab.title) },
                        )
                    }
                }
            },
        ) { padding ->
            when (selectedTab) {
                RootTab.Wallet -> MainWalletView(
                    walletManager = container.walletManager,
                    settingsManager = container.settingsManager,
                    priceService = container.priceService,
                    connectivityState = connectivityState,
                    onOpenMints = { selectedTab = RootTab.Mints },
                    onScan = { scannerTarget = ScannerTarget.Auto },
                    onContactless = { showContactless = true },
                )
                RootTab.Receive -> ReceiveView(
                    walletManager = container.walletManager,
                    settingsManager = container.settingsManager,
                    priceService = container.priceService,
                    nostrService = container.nostrService,
                    cashuRequestStore = container.cashuRequestStore,
                    contentPadding = padding,
                    scannedPayload = pendingReceiveScan,
                    onScannedPayloadConsumed = { pendingReceiveScan = null },
                    onScan = { scannerTarget = ScannerTarget.Receive },
                )
                RootTab.Send -> SendView(
                    walletManager = container.walletManager,
                    settingsManager = container.settingsManager,
                    priceService = container.priceService,
                    contentPadding = padding,
                    scannedPayload = pendingSendScan,
                    onScannedPayloadConsumed = { pendingSendScan = null },
                    onScan = { scannerTarget = ScannerTarget.Send },
                )
                RootTab.Mints -> MintsListView(
                    walletManager = container.walletManager,
                    settingsManager = container.settingsManager,
                    mintDiscoveryManager = container.mintDiscoveryManager,
                    contentPadding = padding,
                    scannedMintUrl = pendingMintScan,
                    onScannedMintUrlConsumed = { pendingMintScan = null },
                    onScan = { scannerTarget = ScannerTarget.Mints },
                )
                RootTab.History -> HistoryView(container.walletManager, padding)
                RootTab.Settings -> SettingsView(
                    walletManager = container.walletManager,
                    settingsManager = container.settingsManager,
                    nostrService = container.nostrService,
                    priceService = container.priceService,
                    npcService = container.npcService,
                    connectivityState = connectivityState,
                    onRefreshConnectivity = { container.connectivityObserver.refresh() },
                    onOpenMints = { selectedTab = RootTab.Mints },
                    contentPadding = padding,
                )
            }
        }
    }
}

private fun routeScannedPayload(
    payload: String,
    onReceive: (String) -> Unit,
    onSend: (String) -> Unit,
    onMint: (String) -> Unit,
) {
    val trimmed = payload.trim()
    TokenParser.extractToken(trimmed)?.let {
        onReceive(it)
        return
    }
    when (PaymentRequestDecoder.decode(trimmed, includeCashuPaymentRequests = true, preferCashuPaymentRequests = true)) {
        is PaymentRequestDecodeResult.Bolt11,
        is PaymentRequestDecodeResult.Bolt12,
        is PaymentRequestDecodeResult.CashuPaymentRequest,
        is PaymentRequestDecodeResult.LightningAddress,
        is PaymentRequestDecodeResult.Onchain -> onSend(trimmed)
        PaymentRequestDecodeResult.Unrecognized -> {
            if (trimmed.startsWith("https://", ignoreCase = true)) {
                onMint(trimmed)
            } else {
                onSend(trimmed)
            }
        }
    }
}

@Composable
private fun LoadingView() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}
