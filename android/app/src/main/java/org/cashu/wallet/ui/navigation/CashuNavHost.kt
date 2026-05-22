package org.cashu.wallet.ui.navigation

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import org.cashu.wallet.App.AppContainer
import org.cashu.wallet.Core.Platform.ConnectivityState
import org.cashu.wallet.Views.History.HistoryView
import org.cashu.wallet.Views.Mints.MintsListView
import org.cashu.wallet.Views.Settings.SettingsView
import org.cashu.wallet.ui.home.HomeScreen
import org.cashu.wallet.ui.home.ReceiveAction
import org.cashu.wallet.ui.home.SendAction
import org.cashu.wallet.ui.receive.ReceiveEcashScreen
import org.cashu.wallet.ui.receive.ReceiveLightningScreen
import org.cashu.wallet.ui.send.SendEcashScreen
import org.cashu.wallet.ui.send.SendLightningScreen

/**
 * The NavHost. For PR #1, top-level destinations call legacy Views composables;
 * later PRs replace each destination with a freshly-built screen under ui.home, ui.history, etc.
 *
 * Send/Receive/Scanner/Contactless are pushed destinations (or shell overlays), not tabs.
 */
@Composable
fun CashuNavHost(
    navController: NavHostController,
    container: AppContainer,
    connectivityState: ConnectivityState,
    contentPadding: PaddingValues,
    onScan: () -> Unit,
    onContactless: () -> Unit,
    pendingReceiveScan: String?,
    onPendingReceiveScanConsumed: () -> Unit,
    pendingSendScan: String?,
    onPendingSendScanConsumed: () -> Unit,
    pendingMintScan: String?,
    onPendingMintScanConsumed: () -> Unit,
    modifier: Modifier = Modifier,
) {
    NavHost(
        navController = navController,
        startDestination = Routes.HOME,
        modifier = modifier,
    ) {
        tabDestinations(
            navController = navController,
            container = container,
            connectivityState = connectivityState,
            contentPadding = contentPadding,
            onScan = onScan,
            onContactless = onContactless,
            pendingMintScan = pendingMintScan,
            onPendingMintScanConsumed = onPendingMintScanConsumed,
        )
        composable(Routes.RECEIVE_ECASH) {
            ReceiveEcashScreen(
                walletManager = container.walletManager,
                settingsManager = container.settingsManager,
                onClose = { navController.popBackStack() },
                onScan = onScan,
                prefilledPayload = pendingReceiveScan,
                onPrefilledConsumed = onPendingReceiveScanConsumed,
            )
        }
        composable(Routes.RECEIVE_LIGHTNING) {
            ReceiveLightningScreen(
                walletManager = container.walletManager,
                settingsManager = container.settingsManager,
                onClose = { navController.popBackStack() },
            )
        }
        composable(Routes.SEND_ECASH) {
            SendEcashScreen(
                walletManager = container.walletManager,
                settingsManager = container.settingsManager,
                onClose = { navController.popBackStack() },
            )
        }
        composable(Routes.SEND_LIGHTNING) {
            SendLightningScreen(
                walletManager = container.walletManager,
                settingsManager = container.settingsManager,
                onClose = { navController.popBackStack() },
                prefilledPayload = pendingSendScan,
                onPrefilledConsumed = onPendingSendScanConsumed,
            )
        }
    }
}

private fun NavGraphBuilder.tabDestinations(
    navController: NavHostController,
    container: AppContainer,
    connectivityState: ConnectivityState,
    contentPadding: PaddingValues,
    onScan: () -> Unit,
    onContactless: () -> Unit,
    pendingMintScan: String?,
    onPendingMintScanConsumed: () -> Unit,
) {
    composable(Routes.HOME) {
        HomeScreen(
            walletManager = container.walletManager,
            settingsManager = container.settingsManager,
            priceService = container.priceService,
            onOpenMints = { navController.navigateToTab(TopTab.Mints) },
            onOpenHistory = { navController.navigateToTab(TopTab.History) },
            onOpenTransaction = { _ -> navController.navigateToTab(TopTab.History) },
            onReceive = { action ->
                val route = when (action) {
                    ReceiveAction.Ecash -> Routes.RECEIVE_ECASH
                    ReceiveAction.Bitcoin -> Routes.RECEIVE_LIGHTNING
                }
                navController.navigate(route)
            },
            onSend = { action ->
                val route = when (action) {
                    SendAction.Ecash -> Routes.SEND_ECASH
                    SendAction.Bitcoin -> Routes.SEND_LIGHTNING
                    SendAction.Contactless -> Routes.SEND_ECASH
                }
                navController.navigate(route)
            },
            onScan = onScan,
            onContactless = onContactless,
            contentPadding = contentPadding,
        )
    }
    composable(Routes.HISTORY) {
        HistoryView(container.walletManager, contentPadding)
    }
    composable(Routes.MINTS) {
        MintsListView(
            walletManager = container.walletManager,
            settingsManager = container.settingsManager,
            mintDiscoveryManager = container.mintDiscoveryManager,
            contentPadding = contentPadding,
            scannedMintUrl = pendingMintScan,
            onScannedMintUrlConsumed = onPendingMintScanConsumed,
            onScan = onScan,
        )
    }
    composable(Routes.SETTINGS) {
        SettingsView(
            walletManager = container.walletManager,
            settingsManager = container.settingsManager,
            nostrService = container.nostrService,
            priceService = container.priceService,
            npcService = container.npcService,
            connectivityState = connectivityState,
            onRefreshConnectivity = { container.connectivityObserver.refresh() },
            onOpenMints = { navController.navigateToTab(TopTab.Mints) },
            contentPadding = contentPadding,
        )
    }
}

/** Navigate to a top-level tab, popping back to the start destination and saving state. */
fun NavHostController.navigateToTab(tab: TopTab) {
    navigate(tab.route) {
        popUpTo(graph.startDestinationId) {
            saveState = true
        }
        launchSingleTop = true
        restoreState = true
    }
}
