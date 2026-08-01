package com.cashu.me.ui.navigation

import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.navArgument
import com.cashu.me.App.AppContainer
import com.cashu.me.Core.Platform.ConnectivityState
import com.cashu.me.ui.history.HistoryScreen
import com.cashu.me.ui.history.TransactionDetailScreen
import com.cashu.me.ui.home.HomeScreen
import com.cashu.me.ui.mints.MintDetailScreen
import com.cashu.me.ui.mints.MintsScreen
import com.cashu.me.ui.receive.CashuRequestDetailScreen
import com.cashu.me.ui.settings.AdvancedKeysScreen
import com.cashu.me.ui.settings.BackupRestoreScreen
import com.cashu.me.ui.settings.RestoreWalletScreen
import com.cashu.me.ui.settings.DeviceKeyDetailScreen
import com.cashu.me.ui.settings.LightningScreen
import com.cashu.me.ui.settings.NostrScreen
import com.cashu.me.ui.settings.NwcSettingsScreen
import com.cashu.me.ui.settings.P2PKScreen
import com.cashu.me.ui.settings.PrivacyScreen
import com.cashu.me.ui.settings.SettingsScreen
import com.cashu.me.ui.theme.CashuMotion
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

/**
 * The NavHost. Tabs + pushed detail destinations only — the money flows
 * (Send, Send Ecash, Receive Ecash, Receive Lightning) are native modal
 * bottom sheets hosted by the shell (see `ui.shell.WalletFlowSheetHost`),
 * and Scanner/Contactless are shell overlays.
 */
@Composable
fun CashuNavHost(
    navController: NavHostController,
    container: AppContainer,
    connectivityState: ConnectivityState,
    contentPadding: PaddingValues,
    onScan: () -> Unit,
    onReceiveEcash: () -> Unit,
    onReceiveLightning: () -> Unit,
    onSend: () -> Unit,
    pendingMintScan: String?,
    onPendingMintScanConsumed: () -> Unit,
    onClaimReceiveToken: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    NavHost(
        navController = navController,
        startDestination = Routes.HOME,
        modifier = modifier,
        // Shared-axis X for pushed destinations, spring-driven (M3 Expressive).
        enterTransition = pushEnter,
        exitTransition = pushExit,
        popEnterTransition = popEnter,
        popExitTransition = popExit,
    ) {
        tabDestinations(
            navController = navController,
            container = container,
            connectivityState = connectivityState,
            contentPadding = contentPadding,
            onScan = onScan,
            onReceiveEcash = onReceiveEcash,
            onReceiveLightning = onReceiveLightning,
            onSend = onSend,
            pendingMintScan = pendingMintScan,
            onPendingMintScanConsumed = onPendingMintScanConsumed,
        )
        composable(
            route = Routes.MINT_DETAIL,
            arguments = listOf(navArgument("mintUrl") { type = NavType.StringType }),
        ) { entry ->
            val encoded = entry.arguments?.getString("mintUrl").orEmpty()
            val mintUrl = URLDecoder.decode(encoded, StandardCharsets.UTF_8.name())
            MintDetailScreen(
                walletManager = container.walletManager,
                settingsManager = container.settingsManager,
                priceService = container.priceService,
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
                onClaimReceiveToken = onClaimReceiveToken,
                snackbarHostState = container.snackbarHostState,
            )
        }
        composable(
            route = Routes.CASHU_REQUEST_DETAIL,
            arguments = listOf(
                navArgument("requestId") { type = NavType.StringType },
                navArgument("fresh") { type = NavType.BoolType; defaultValue = false },
            ),
        ) { entry ->
            val encoded = entry.arguments?.getString("requestId").orEmpty()
            val requestId = URLDecoder.decode(encoded, StandardCharsets.UTF_8.name())
            CashuRequestDetailScreen(
                walletManager = container.walletManager,
                settingsManager = container.settingsManager,
                nostrService = container.nostrService,
                cashuRequestStore = container.cashuRequestStore,
                nfcReceiveCoordinator = container.nfcReceiveCoordinator,
                requestId = requestId,
                onClose = { navController.popBackStack() },
                snackbarHostState = container.snackbarHostState,
            )
        }

        // Settings is a wallet-origin destination, not a bottom navigation tab.
        composable(Routes.SETTINGS) {
            SettingsScreen(
                walletManager = container.walletManager,
                settingsManager = container.settingsManager,
                priceService = container.priceService,
                onClose = { navController.popBackStack() },
                onOpenBackupRestore = { navController.navigate(Routes.SETTINGS_BACKUP_RESTORE) },
                onOpenLightning = { navController.navigate(Routes.SETTINGS_LIGHTNING) },
                onOpenLockedEcash = { navController.navigate(Routes.SETTINGS_P2PK) },
                onOpenNostr = { navController.navigate(Routes.SETTINGS_NOSTR) },
                onOpenPrivacy = { navController.navigate(Routes.SETTINGS_PRIVACY) },
                contentPadding = contentPadding,
            )
        }

        // Settings sub-screens
        composable(Routes.SETTINGS_BACKUP_RESTORE) {
            BackupRestoreScreen(
                walletManager = container.walletManager,
                settingsManager = container.settingsManager,
                nostrMintBackupService = container.nostrMintBackupService,
                appLockManager = container.appLockManager,
                onClose = { navController.popBackStack() },
                onOpenRestore = { navController.navigate(Routes.SETTINGS_RESTORE) },
            )
        }
        composable(Routes.SETTINGS_RESTORE) {
            RestoreWalletScreen(
                walletManager = container.walletManager,
                nostrMintBackupService = container.nostrMintBackupService,
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
                nostrService = container.nostrService,
                appLockManager = container.appLockManager,
                onOpenAdvancedKeys = { navController.navigate(Routes.SETTINGS_P2PK_ADVANCED) },
                onClose = { navController.popBackStack() },
            )
        }
        composable(Routes.SETTINGS_P2PK_ADVANCED) {
            AdvancedKeysScreen(
                settingsManager = container.settingsManager,
                onOpenKey = { keyId ->
                    navController.navigate(
                        Routes.SETTINGS_P2PK_KEY.replace(
                            "{keyId}",
                            URLEncoder.encode(keyId, StandardCharsets.UTF_8.name()),
                        ),
                    )
                },
                onClose = { navController.popBackStack() },
            )
        }
        composable(
            route = Routes.SETTINGS_P2PK_KEY,
            arguments = listOf(navArgument("keyId") { type = NavType.StringType }),
        ) { entry ->
            val encoded = entry.arguments?.getString("keyId").orEmpty()
            val keyId = URLDecoder.decode(encoded, StandardCharsets.UTF_8.name())
            DeviceKeyDetailScreen(
                settingsManager = container.settingsManager,
                appLockManager = container.appLockManager,
                keyId = keyId,
                onClose = { navController.popBackStack() },
            )
        }
        composable(Routes.SETTINGS_NOSTR) {
            NostrScreen(
                nostrService = container.nostrService,
                settingsManager = container.settingsManager,
                nwcManager = container.nwcManager,
                appLockManager = container.appLockManager,
                onOpenWalletConnect = { navController.navigate(Routes.SETTINGS_NWC) },
                onClose = { navController.popBackStack() },
            )
        }
        composable(Routes.SETTINGS_NWC) {
            NwcSettingsScreen(
                walletManager = container.walletManager,
                settingsManager = container.settingsManager,
                nwcManager = container.nwcManager,
                onClose = { navController.popBackStack() },
            )
        }
        composable(Routes.SETTINGS_PRIVACY) {
            PrivacyScreen(
                settingsManager = container.settingsManager,
                appLockManager = container.appLockManager,
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

internal fun cashuRequestDetailRouteFor(requestId: String): String {
    val encoded = URLEncoder.encode(requestId, StandardCharsets.UTF_8.name())
    return "request/$encoded?fresh=false"
}

private fun NavGraphBuilder.tabDestinations(
    navController: NavHostController,
    container: AppContainer,
    connectivityState: ConnectivityState,
    contentPadding: PaddingValues,
    onScan: () -> Unit,
    onReceiveEcash: () -> Unit,
    onReceiveLightning: () -> Unit,
    onSend: () -> Unit,
    pendingMintScan: String?,
    onPendingMintScanConsumed: () -> Unit,
) {
    composable(
        route = Routes.HOME,
        enterTransition = tabEnter,
        exitTransition = tabExit,
        popEnterTransition = tabEnter,
        popExitTransition = tabExit,
    ) {
        HomeScreen(
            walletManager = container.walletManager,
            settingsManager = container.settingsManager,
            priceService = container.priceService,
            onOpenMints = { navController.navigateToTab(TopTab.Mints) },
            onOpenHistory = { navController.navigateToTab(TopTab.History) },
            onOpenTransaction = { tx ->
                navController.navigate(transactionDetailRouteFor(tx.id))
            },
            // Receive goes straight to the unified surface — no chooser (iOS
            // parity). Bitcoin is now a button inside that sheet, not a chooser row.
            onReceive = onReceiveEcash,
            // Send goes straight to the unified surface — no chooser (iOS parity).
            onSend = onSend,
            onOpenSettings = { navController.navigate(Routes.SETTINGS) },
            onScan = onScan,
            contentPadding = contentPadding,
        )
    }
    composable(
        route = Routes.HISTORY,
        enterTransition = tabEnter,
        exitTransition = tabExit,
        popEnterTransition = tabEnter,
        popExitTransition = tabExit,
    ) {
        HistoryScreen(
            walletManager = container.walletManager,
            settingsManager = container.settingsManager,
            priceService = container.priceService,
            cashuRequestStore = container.cashuRequestStore,
            onOpenTransaction = { tx ->
                navController.navigate(transactionDetailRouteFor(tx.id))
            },
            onOpenCashuRequest = { req ->
                navController.navigate(cashuRequestDetailRouteFor(req.id))
            },
            contentPadding = contentPadding,
        )
    }
    composable(
        route = Routes.MINTS,
        enterTransition = tabEnter,
        exitTransition = tabExit,
        popEnterTransition = tabEnter,
        popExitTransition = tabExit,
    ) {
        MintsScreen(
            walletManager = container.walletManager,
            settingsManager = container.settingsManager,
            mintDiscoveryManager = container.mintDiscoveryManager,
            onOpenMint = { mint -> navController.navigate(mintDetailRouteFor(mint.url)) },
            onScan = onScan,
            contentPadding = contentPadding,
            allowCleartextLocalTestMints =
                container.runtimePolicy.allowCleartextLocalTestMints,
            scannedMintUrl = pendingMintScan,
            onScannedMintUrlConsumed = onPendingMintScanConsumed,
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

// ---------------------------------------------------------------------------
// Motion: Material Shared Axis X (push/pop) + subtle fade-through (tabs).
// ---------------------------------------------------------------------------

/** Incoming content travels ~25% of width while fading in after the outgoing fade. */
private val pushEnter: AnimatedContentTransitionScope<NavBackStackEntry>.() -> EnterTransition = {
    slideInHorizontally(
        animationSpec = tween(CashuMotion.SharedAxisDurationMs, easing = FastOutSlowInEasing),
    ) { it / 4 } + fadeIn(
        tween(
            durationMillis = CashuMotion.SharedAxisInMs,
            delayMillis = CashuMotion.SharedAxisOutMs,
            easing = LinearOutSlowInEasing,
        ),
    )
}
private val pushExit: AnimatedContentTransitionScope<NavBackStackEntry>.() -> ExitTransition = {
    slideOutHorizontally(
        animationSpec = tween(CashuMotion.SharedAxisDurationMs, easing = FastOutSlowInEasing),
    ) { -it / 4 } + fadeOut(
        tween(durationMillis = CashuMotion.SharedAxisOutMs, easing = FastOutLinearInEasing),
    )
}
private val popEnter: AnimatedContentTransitionScope<NavBackStackEntry>.() -> EnterTransition = {
    slideInHorizontally(
        animationSpec = tween(CashuMotion.SharedAxisDurationMs, easing = FastOutSlowInEasing),
    ) { -it / 4 } + fadeIn(
        tween(
            durationMillis = CashuMotion.SharedAxisInMs,
            delayMillis = CashuMotion.SharedAxisOutMs,
            easing = LinearOutSlowInEasing,
        ),
    )
}
private val popExit: AnimatedContentTransitionScope<NavBackStackEntry>.() -> ExitTransition = {
    slideOutHorizontally(
        animationSpec = tween(CashuMotion.SharedAxisDurationMs, easing = FastOutSlowInEasing),
    ) { it / 4 } + fadeOut(
        tween(durationMillis = CashuMotion.SharedAxisOutMs, easing = FastOutLinearInEasing),
    )
}

/** Subtle fade-through between sibling tabs — soft scale, short stagger. */
internal val tabEnter: AnimatedContentTransitionScope<NavBackStackEntry>.() -> EnterTransition = {
    fadeIn(
        tween(
            durationMillis = CashuMotion.TabFadeInMs,
            delayMillis = CashuMotion.TabFadeOutMs,
            easing = LinearOutSlowInEasing,
        ),
    ) + scaleIn(
        initialScale = CashuMotion.TabFadeInitialScale,
        animationSpec = tween(
            durationMillis = CashuMotion.TabFadeInMs,
            delayMillis = CashuMotion.TabFadeOutMs,
            easing = FastOutSlowInEasing,
        ),
    )
}
internal val tabExit: AnimatedContentTransitionScope<NavBackStackEntry>.() -> ExitTransition = {
    fadeOut(
        tween(
            durationMillis = CashuMotion.TabFadeOutMs,
            easing = FastOutLinearInEasing,
        ),
    )
}
