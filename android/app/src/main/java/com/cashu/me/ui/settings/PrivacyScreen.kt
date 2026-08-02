package com.cashu.me.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.unit.dp
import com.cashu.me.Core.SettingsManager
import com.cashu.me.ui.components.CanvasDivider
import com.cashu.me.ui.components.ToggleRow
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.theme.CashuTheme

/** iOS PrivacySettingsSection — same toggles, order, copy, and footer. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PrivacyScreen(
    settingsManager: SettingsManager,
    onClose: () -> Unit,
) {
    val settings by settingsManager.state.collectAsState()
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
            ToggleRow(
                title = "Check incoming invoice",
                checked = settings.checkIncomingInvoices,
                onCheckedChange = settingsManager::setCheckIncomingInvoices,
            )
            CanvasDivider(leadingInset = 16.dp)
            ToggleRow(
                title = "Check all invoices",
                checked = settings.periodicallyCheckIncomingInvoices,
                onCheckedChange = settingsManager::setPeriodicallyCheckIncomingInvoices,
                enabled = settings.checkIncomingInvoices,
                modifier = Modifier.alpha(if (settings.checkIncomingInvoices) 1f else 0.5f),
            )
            CanvasDivider(leadingInset = 16.dp)
            ToggleRow(
                title = "Check sent ecash",
                checked = settings.checkSentTokens,
                onCheckedChange = settingsManager::setCheckSentTokens,
            )
            CanvasDivider(leadingInset = 16.dp)
            ToggleRow(
                title = "Use WebSockets",
                subtitle = "Required for Nostr discovery and live invoice updates.",
                checked = settings.useWebsockets,
                onCheckedChange = settingsManager::setUseWebsockets,
            )
            CanvasDivider(leadingInset = 16.dp)
            ToggleRow(
                title = "Paste ecash automatically",
                checked = settings.autoPasteEcashReceive,
                onCheckedChange = settingsManager::setAutoPasteEcashReceive,
            )
            CanvasDivider(leadingInset = 16.dp)
            ToggleRow(
                title = "Listen for payment requests",
                subtitle = "Receives ecash sent to your Nostr key while the app is open.",
                checked = settings.enablePaymentRequests,
                onCheckedChange = settingsManager::setEnablePaymentRequests,
            )
            CanvasDivider(leadingInset = 16.dp)
            ToggleRow(
                title = "Claim received ecash automatically",
                subtitle = "Off asks you to confirm each incoming payment before it's claimed.",
                checked = settings.receivePaymentRequestsAutomatically,
                onCheckedChange = settingsManager::setReceivePaymentRequestsAutomatically,
                enabled = settings.enablePaymentRequests,
                modifier = Modifier.alpha(if (settings.enablePaymentRequests) 1f else 0.5f),
            )
            CanvasDivider(leadingInset = 16.dp)
            ToggleRow(
                title = "Send crash reports",
                subtitle = "Opt-in. Screenshots and view hierarchy are not attached. " +
                    "Reports can include technical error details and recent wallet actions.",
                checked = settings.sentryEnabled,
                onCheckedChange = settingsManager::setSentryEnabled,
            )
            Text(
                text = "These settings affect your privacy and wallet responsiveness.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(
                    horizontal = CashuTheme.spacing.comfortable,
                    vertical = CashuTheme.spacing.tight,
                ),
            )
        }
    }
}
