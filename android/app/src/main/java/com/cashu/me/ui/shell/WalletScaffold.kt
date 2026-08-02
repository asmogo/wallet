package com.cashu.me.ui.shell

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.History
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.cashu.me.App.AppContainer
import com.cashu.me.Core.Platform.ConnectivityState
import com.cashu.me.ui.components.CanvasDivider
import com.cashu.me.ui.navigation.CashuNavHost
import com.cashu.me.ui.navigation.Routes
import com.cashu.me.ui.navigation.TopTab
import com.cashu.me.ui.navigation.navigateToTab
import com.cashu.me.ui.theme.CashuTheme
@Composable
fun WalletScaffold(
    container: AppContainer,
    connectivityState: ConnectivityState,
    onScan: () -> Unit,
    onReceiveEcash: () -> Unit,
    onAddMint: () -> Unit,
    onReceiveLightning: () -> Unit,
    onSend: () -> Unit,
    pendingMintScan: String?,
    onPendingMintScanConsumed: () -> Unit,
    onClaimReceiveToken: (String) -> Unit,
    navController: NavHostController = rememberNavController(),
) {
    val backStack by navController.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route
    val selectedTab = Routes.TopTabs.firstOrNull { it.route == currentRoute }
    Scaffold(
        bottomBar = {
            // Slide the bar away on pushed destinations instead of blinking it out.
            AnimatedVisibility(
                visible = selectedTab != null,
                enter = slideInVertically(
                    spring(
                        stiffness = Spring.StiffnessMediumLow,
                        visibilityThreshold = IntOffset.VisibilityThreshold,
                    ),
                ) { it } + fadeIn(spring(stiffness = Spring.StiffnessMedium)),
                exit = slideOutVertically(
                    spring(
                        stiffness = Spring.StiffnessMediumLow,
                        visibilityThreshold = IntOffset.VisibilityThreshold,
                    ),
                ) { it } + fadeOut(spring(stiffness = Spring.StiffnessMedium)),
            ) {
                CashuNavigationBar(
                    selected = selectedTab ?: TopTab.Home,
                    onSelect = { tab ->
                        if (tab != selectedTab) navController.navigateToTab(tab)
                    },
                )
            }
        },
    ) { padding ->
        CashuNavHost(
            navController = navController,
            container = container,
            connectivityState = connectivityState,
            contentPadding = padding,
            onScan = onScan,
            onReceiveEcash = onReceiveEcash,
            onAddMint = onAddMint,
            onReceiveLightning = onReceiveLightning,
            onSend = onSend,
            pendingMintScan = pendingMintScan,
            onPendingMintScanConsumed = onPendingMintScanConsumed,
            onClaimReceiveToken = onClaimReceiveToken,
        )
    }
}

@Composable
private fun CashuNavigationBar(
    selected: TopTab,
    onSelect: (TopTab) -> Unit,
) {
    val haptics = LocalHapticFeedback.current
    // Unified with the canvas: the bar shares the page background (white/black
    // inverted ink) instead of sitting on a tonal surface band; a full-bleed
    // hairline is the only separation — nearly invisible in dark mode.
    Column {
        CanvasDivider(leadingInset = 0.dp, trailingInset = 0.dp)
        NavigationBar(containerColor = MaterialTheme.colorScheme.background) {
            Routes.TopTabs.forEach { tab ->
                val isSelected = tab == selected
                NavigationBarItem(
                    selected = isSelected,
                    onClick = {
                        if (!isSelected) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        onSelect(tab)
                    },
                    icon = {
                        Icon(
                            // Always filled — selected state is conveyed by the
                            // NavigationBarItem indicator, not outlined↔filled.
                            imageVector = tab.iconFilled,
                            contentDescription = tab.label,
                            modifier = Modifier.size(CashuTheme.iconSizes.navigation),
                        )
                    },
                    label = { Text(tab.label, style = MaterialTheme.typography.labelLarge) },
                )
            }
        }
    }
}

private val TopTab.iconFilled: ImageVector
    get() = when (this) {
        TopTab.Home -> Icons.Filled.AccountBalanceWallet
        TopTab.History -> Icons.Filled.History
        TopTab.Mints -> Icons.Filled.AccountBalance
    }

@Suppress("unused")
internal val DefaultStartTabRoute = Routes.HOME
