package com.cashu.me.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.cashu.me.Core.AppLockManager
import com.cashu.me.Core.SettingsManager
import com.cashu.me.ui.components.CanvasDivider
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.ToggleRow
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.security.findFragmentActivity
import com.cashu.me.ui.theme.CashuTheme
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PrivacyScreen(
    settingsManager: SettingsManager,
    appLockManager: AppLockManager,
    onClose: () -> Unit,
) {
    val settings by settingsManager.state.collectAsState()
    val context = LocalContext.current
    val activity = remember(context) { context.findFragmentActivity() }
    val scope = rememberCoroutineScope()
    var isEnablingAppLock by remember { mutableStateOf(false) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Privacy", style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        ToolbarIcon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState()),
        ) {
            SectionHeader("Security")
            ToggleRow(
                title = "App Lock",
                subtitle = "Require device authentication when returning to the wallet",
                checked = settings.appLockEnabled,
                onCheckedChange = { enabled ->
                    if (!enabled) {
                        settingsManager.setAppLockEnabled(false)
                    } else {
                        scope.launch {
                            isEnablingAppLock = true
                            try {
                                enableAppLockAfterAuthentication(
                                    authenticate = { appLockManager.authenticateForAppLockEnablement(activity) },
                                    setEnabled = settingsManager::setAppLockEnabled,
                                )
                            } finally {
                                isEnablingAppLock = false
                            }
                        }
                    }
                },
                enabled = !isEnablingAppLock,
            )

            SectionHeader("Background work")
            ToggleRow(
                title = "Check pending tokens on startup",
                subtitle = "Refresh status when the app launches",
                checked = settings.checkPendingOnStartup,
                onCheckedChange = settingsManager::setCheckPendingOnStartup,
            )
            CanvasDivider(leadingInset = 16.dp)
            ToggleRow(
                title = "Check sent token claims",
                subtitle = "Detect when recipients redeem tokens you sent",
                checked = settings.checkSentTokens,
                onCheckedChange = settingsManager::setCheckSentTokens,
            )
            CanvasDivider(leadingInset = 16.dp)
            ToggleRow(
                title = "Check incoming invoices",
                subtitle = "Poll mint quotes while screens are open",
                checked = settings.checkIncomingInvoices,
                onCheckedChange = settingsManager::setCheckIncomingInvoices,
            )
            CanvasDivider(leadingInset = 16.dp)
            ToggleRow(
                title = "Periodic invoice checks",
                subtitle = "Refresh quote status on a timer",
                checked = settings.periodicallyCheckIncomingInvoices,
                onCheckedChange = settingsManager::setPeriodicallyCheckIncomingInvoices,
            )

            SectionHeader("Network")
            ToggleRow(
                title = "Use WebSockets",
                subtitle = "Required for Nostr discovery and live invoice updates",
                checked = settings.useWebsockets,
                onCheckedChange = settingsManager::setUseWebsockets,
            )

            SectionHeader("Payment requests")
            ToggleRow(
                title = "Listen for payment requests",
                subtitle = "Receive ecash sent to your Nostr key while the app is open",
                checked = settings.enablePaymentRequests,
                onCheckedChange = settingsManager::setEnablePaymentRequests,
            )
            CanvasDivider(leadingInset = 16.dp)
            ToggleRow(
                title = "Receive automatically",
                subtitle = "Automatically receive payments from mints you already trust",
                checked = settings.receivePaymentRequestsAutomatically,
                onCheckedChange = settingsManager::setReceivePaymentRequestsAutomatically,
                enabled = settings.enablePaymentRequests,
            )

            SectionHeader("Convenience")
            ToggleRow(
                title = "Auto-paste ecash on Receive",
                subtitle = "Prefill the token field from clipboard",
                checked = settings.autoPasteEcashReceive,
                onCheckedChange = settingsManager::setAutoPasteEcashReceive,
            )

            SectionHeader("Diagnostics")
            ToggleRow(
                title = "Send anonymous crash reports",
                subtitle = "Opt-in. Screenshots and view hierarchy are never attached, and no Sentry PII is collected.",
                checked = settings.sentryEnabled,
                onCheckedChange = settingsManager::setSentryEnabled,
            )

        }
    }
}

internal suspend fun enableAppLockAfterAuthentication(
    authenticate: suspend () -> Boolean,
    setEnabled: (Boolean) -> Unit,
) {
    setEnabled(authenticate())
}
