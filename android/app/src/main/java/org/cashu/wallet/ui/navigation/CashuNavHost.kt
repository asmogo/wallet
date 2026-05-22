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
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import androidx.navigation.NavType
import androidx.navigation.navArgument
import org.cashu.wallet.ui.history.HistoryScreen
import org.cashu.wallet.ui.history.TransactionDetailScreen
import org.cashu.wallet.ui.home.HomeScreen
import org.cashu.wallet.ui.home.ReceiveAction
import org.cashu.wallet.ui.home.SendAction
import org.cashu.wallet.ui.mints.MintDetailScreen
import org.cashu.wallet.ui.mints.MintDiscoveryScreen
import org.cashu.wallet.ui.mints.MintsScreen
import org.cashu.wallet.ui.receive.ReceiveEcashScreen
import org.cashu.wallet.ui.receive.ReceiveLightningScreen
import org.cashu.wallet.ui.send.SendEcashScreen
import org.cashu.wallet.ui.send.SendLightningScreen
import org.cashu.wallet.ui.settings.AppearanceScreen
import org.cashu.wallet.ui.settings.BackupScreen
import org.cashu.wallet.ui.settings.LightningScreen
import org.cashu.wallet.ui.settings.NWCScreen
import org.cashu.wallet.ui.settings.NostrScreen
import org.cashu.wallet.ui.settings.P2PKScreen
import org.cashu.wallet.ui.settings.PrivacyScreen
import org.cashu.wallet.ui.settings.SettingsScreen

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
        composable(Routes.MINT_DISCOVERY) {
            MintDiscoveryScreen(
                walletManager = container.walletManager,
                settingsManager = container.settingsManager,
                mintDiscoveryManager = container.mintDiscoveryManager,
                onClose = { navController.popBackStack() },
            )
        }
        composable(
            route = Routes.MINT_DETAIL,
            arguments = listOf(navArgument("mintUrl") { type = NavType.StringType }),
        ) { entry ->
            val encoded = entry.arguments?.getString("mintUrl").orEmpty()
            val mintUrl = URLDecoder.decode(encoded, StandardCharsets.UTF_8.name())
            MintDetailScreen(
                walletManager = container.walletManager,
                mintUrl = mintUrl,
                onClose = { navController.popBackStack() },
            )
        }
        composable(
            route = Routes.TRANSACTION_DETAIL,
            arguments = listOf(navArgument("transactionId") { type = NavType.StringType }),
        ) { entry ->
            val encoded = entry.arguments?.getString("transactionId").orEmpty()
            val txId = URLDecoder.decode(encoded, StandardCharsets.UTF_8.name())
            TransactionDetailScreen(
                walletManager = container.walletManager,
                settingsManager = container.settingsManager,
                transactionId = txId,
                onClose = { navController.popBackStack() },
            )
        }

        // Settings sub-screens
        composable(Routes.SETTINGS_BACKUP) {
            BackupScreen(
                walletManager = container.walletManager,
                onClose = { navController.popBackStack() },
            )
        }
        composable(Routes.SETTINGS_LIGHTNING) {
            LightningScreen(
                walletManager = container.walletManager,
                npcService = container.npcService,
                onClose = { navController.popBackStack() },
            )
        }
        composable(Routes.SETTINGS_P2PK) {
            P2PKScreen(
                settingsManager = container.settingsManager,
                onClose = { navController.popBackStack() },
            )
        }
        composable(Routes.SETTINGS_NOSTR) {
            NostrScreen(
                nostrService = container.nostrService,
                settingsManager = container.settingsManager,
                onClose = { navController.popBackStack() },
            )
        }
        composable(Routes.SETTINGS_NWC) {
            NWCScreen(
                settingsManager = container.settingsManager,
                onClose = { navController.popBackStack() },
            )
        }
        composable(Routes.SETTINGS_PRIVACY) {
            PrivacyScreen(
                settingsManager = container.settingsManager,
                onClose = { navController.popBackStack() },
            )
        }
        composable(Routes.SETTINGS_APPEARANCE) {
            AppearanceScreen(
                settingsManager = container.settingsManager,
                priceService = container.priceService,
                onClose = { navController.popBackStack() },
            )
        }
    }
}

internal fun mintDetailRouteFor(mintUrl: String): String {
    val encoded = URLEncoder.encode(mintUrl, StandardCharsets.UTF_8.name())
    return Routes.MINT_DETAIL.replace("{mintUrl}", encoded)
}

internal fun transactionDetailRouteFor(transactionId: String): String {
    val encoded = URLEncoder.encode(transactionId, StandardCharsets.UTF_8.name())
    return Routes.TRANSACTION_DETAIL.replace("{transactionId}", encoded)
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
            onOpenTransaction = { tx ->
                navController.navigate(transactionDetailRouteFor(tx.id))
            },
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
        HistoryScreen(
            walletManager = container.walletManager,
            settingsManager = container.settingsManager,
            priceService = container.priceService,
            onOpenTransaction = { tx ->
                navController.navigate(transactionDetailRouteFor(tx.id))
            },
            contentPadding = contentPadding,
        )
    }
    composable(Routes.MINTS) {
        MintsScreen(
            walletManager = container.walletManager,
            settingsManager = container.settingsManager,
            onOpenMint = { mint -> navController.navigate(mintDetailRouteFor(mint.url)) },
            onOpenDiscovery = { navController.navigate(Routes.MINT_DISCOVERY) },
            onScan = onScan,
            contentPadding = contentPadding,
            scannedMintUrl = pendingMintScan,
            onScannedMintUrlConsumed = onPendingMintScanConsumed,
        )
    }
    composable(Routes.SETTINGS) {
        SettingsScreen(
            walletManager = container.walletManager,
            onOpenBackup = { navController.navigate(Routes.SETTINGS_BACKUP) },
            onOpenLightning = { navController.navigate(Routes.SETTINGS_LIGHTNING) },
            onOpenP2PK = { navController.navigate(Routes.SETTINGS_P2PK) },
            onOpenNostr = { navController.navigate(Routes.SETTINGS_NOSTR) },
            onOpenNWC = { navController.navigate(Routes.SETTINGS_NWC) },
            onOpenPrivacy = { navController.navigate(Routes.SETTINGS_PRIVACY) },
            onOpenAppearance = { navController.navigate(Routes.SETTINGS_APPEARANCE) },
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
