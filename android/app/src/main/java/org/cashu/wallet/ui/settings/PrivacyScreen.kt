package org.cashu.wallet.ui.settings

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.text.DateFormat
import java.util.Date
import org.cashu.wallet.Core.PriceService
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.ui.components.CanvasDivider
import org.cashu.wallet.ui.components.SectionHeader
import org.cashu.wallet.ui.components.ToggleRow

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PrivacyScreen(
    settingsManager: SettingsManager,
    priceService: PriceService,
    onClose: () -> Unit,
) {
    val settings by settingsManager.state.collectAsState()
    val price by priceService.state.collectAsState()
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
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState()),
        ) {
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

            SectionHeader("Fiat")
            ToggleRow(
                title = "Show fiat balance",
                subtitle = "Display fiat equivalent next to sats",
                checked = settings.showFiatBalance,
                onCheckedChange = {
                    settingsManager.setShowFiatBalance(it)
                    priceService.syncFromSettings(refresh = it)
                },
            )
            AnimatedVisibility(visible = settings.showFiatBalance) {
                Column {
                    CanvasDivider(leadingInset = 16)
                    CurrencyPickerRow(
                        currency = settings.bitcoinPriceCurrency,
                        currencies = SettingsManager.supportedFiatCurrencies,
                        onSelect = {
                            settingsManager.setBitcoinPriceCurrency(it)
                            priceService.refresh()
                        },
                    )
                    CanvasDivider(leadingInset = 16)
                    PriceRow(
                        priceText = formatPrice(price.btcPrice, price.currencyCode),
                        subtext = priceSubtext(price.lastUpdatedEpochMillis, price.errorMessage),
                        isFetching = price.isFetching,
                        onRefresh = priceService::refresh,
                    )
                }
            }
        }
    }
}

@Composable
private fun CurrencyPickerRow(
    currency: String,
    currencies: List<String>,
    onSelect: (String) -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }
    Box {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Currency",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = { menuOpen = true }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = currency,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Icon(
                        imageVector = Icons.Outlined.UnfoldMore,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }
        }
        DropdownMenu(
            expanded = menuOpen,
            onDismissRequest = { menuOpen = false },
        ) {
            currencies.forEach { code ->
                DropdownMenuItem(
                    text = { Text(code) },
                    onClick = {
                        menuOpen = false
                        onSelect(code)
                    },
                )
            }
        }
    }
}

@Composable
private fun PriceRow(
    priceText: String,
    subtext: String?,
    isFetching: Boolean,
    onRefresh: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "BTC price",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = priceText,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (subtext != null) {
                Text(
                    text = subtext,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        IconButton(onClick = onRefresh, enabled = !isFetching) {
            if (isFetching) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    strokeWidth = 2.dp,
                )
            } else {
                Icon(
                    imageVector = Icons.Outlined.Refresh,
                    contentDescription = "Refresh price",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private fun formatPrice(price: Double, currency: String): String {
    if (price <= 0.0) return "—"
    return "%,.2f %s".format(price, currency)
}

private fun priceSubtext(lastUpdated: Long?, error: String?): String? {
    if (error != null) return error
    if (lastUpdated == null) return null
    val time = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(lastUpdated))
    return "Updated $time"
}
