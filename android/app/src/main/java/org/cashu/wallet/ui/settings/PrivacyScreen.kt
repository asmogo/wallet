package org.cashu.wallet.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
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
import androidx.compose.ui.Modifier
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.ui.components.CanvasDivider
import org.cashu.wallet.ui.components.SectionHeader
import org.cashu.wallet.ui.components.ToggleRow

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
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            SectionHeader("Background work")
            ToggleRow(
                title = "Check pending tokens on startup",
                subtitle = "Refresh status when the app launches",
                checked = settings.checkPendingOnStartup,
                onCheckedChange = settingsManager::setCheckPendingOnStartup,
            )
            CanvasDivider(leadingInset = 16)
            ToggleRow(
                title = "Check sent token claims",
                subtitle = "Detect when recipients redeem tokens you sent",
                checked = settings.checkSentTokens,
                onCheckedChange = settingsManager::setCheckSentTokens,
            )
            CanvasDivider(leadingInset = 16)
            ToggleRow(
                title = "Check incoming invoices",
                subtitle = "Poll mint quotes while screens are open",
                checked = settings.checkIncomingInvoices,
                onCheckedChange = settingsManager::setCheckIncomingInvoices,
            )
            CanvasDivider(leadingInset = 16)
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

            SectionHeader("Convenience")
            ToggleRow(
                title = "Auto-paste ecash on Receive",
                subtitle = "Prefill the token field from clipboard",
                checked = settings.autoPasteEcashReceive,
                onCheckedChange = settingsManager::setAutoPasteEcashReceive,
            )
        }
    }
}
