package org.cashu.wallet.Views.Main

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.cashu.wallet.Core.AmountFormatter
import org.cashu.wallet.Core.Platform.ConnectivityState
import org.cashu.wallet.Core.Platform.ConnectivityStatus
import org.cashu.wallet.Core.PriceService
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Views.Components.CurrencyAmountDisplay
import org.cashu.wallet.Views.Components.KeyValueRow
import org.cashu.wallet.Views.Components.PrimaryActionButton
import org.cashu.wallet.Views.Components.QuietCard
import org.cashu.wallet.Views.Components.SectionHeader
import org.cashu.wallet.Views.Components.SecondaryActionButton

@Composable
fun MainWalletView(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    priceService: PriceService,
    connectivityState: ConnectivityState,
    onOpenMints: () -> Unit,
    onScan: () -> Unit,
    onContactless: () -> Unit,
) {
    val state by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val priceState by priceService.state.collectAsState()
    val formatter = AmountFormatter()
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Wallet", style = MaterialTheme.typography.headlineSmall)
        if (connectivityState.status != ConnectivityStatus.Online) {
            Text(
                text = connectivityState.displayText,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        CurrencyAmountDisplay(
            sats = state.balance,
            settings = settings,
            priceState = priceState,
            onPrimaryChange = { settingsManager.setAmountDisplayPrimary(it.rawValue) },
        )
        Row(Modifier.fillMaxWidth()) {
            PrimaryActionButton("Refresh", enabled = !state.isLoading) {
                walletManager.launch { walletManager.refreshBalance() }
            }
            Spacer(Modifier.width(12.dp))
        }
        SecondaryActionButton("Scan QR", onClick = onScan)
        SecondaryActionButton("Contactless", onClick = onContactless)
        SectionHeader("Active mint")
        QuietCard {
            KeyValueRow("Mint", state.activeMint?.name ?: "No mint")
            KeyValueRow("URL", state.activeMint?.url ?: "Add a mint to begin")
        }
        SecondaryActionButton("Manage mints", onClick = onOpenMints)
        SectionHeader("Recent")
        if (state.transactions.isEmpty()) {
            Text("No transactions yet.", color = MaterialTheme.colorScheme.secondary)
        } else {
            state.transactions.take(5).forEach {
                KeyValueRow(it.kind.displayName, formatter.formatWalletSats(it.amount, settings.useBitcoinSymbol))
            }
        }
        state.errorMessage?.let {
            Text(it, color = MaterialTheme.colorScheme.error)
        }
    }
}
