package com.cashu.me.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.CurrencyBitcoin
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale
import com.cashu.me.Core.PriceService
import com.cashu.me.Core.SettingsManager
import com.cashu.me.ui.components.FlowSheetTitle
import com.cashu.me.ui.components.formatRelativeRecency
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withMonoDigits

private val CheckSize = 20.dp
private val ProgressSize = 16.dp

/**
 * The Settings → Currency sheet (iOS CurrencyPickerSheet): "Off / Sats only"
 * first, then one row per supported fiat currency, with a BTC-price footer
 * (value + relative "updated" timestamp + refresh) shown while fiat display is on.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CurrencyPickerSheet(
    settingsManager: SettingsManager,
    priceService: PriceService,
    onDismiss: () -> Unit,
) {
    val settings by settingsManager.state.collectAsState()
    val price by priceService.state.collectAsState()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val fiatOn = settings.showFiatBalance

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(modifier = Modifier.navigationBarsPadding()) {
            FlowSheetTitle(title = "Currency")
            LazyColumn(modifier = Modifier.weight(1f, fill = false)) {
                item("off") {
                    CurrencyRow(
                        title = "Off",
                        subtitle = "Sats only",
                        selected = !fiatOn,
                        leading = {
                            Icon(
                                imageVector = Icons.Outlined.CurrencyBitcoin,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(CashuTheme.spacing.loose),
                            )
                        },
                        onClick = {
                            settingsManager.setShowFiatBalance(false)
                            priceService.syncFromSettings(refresh = false)
                            onDismiss()
                        },
                    )
                }
                items(SettingsManager.supportedFiatCurrencies, key = { it }) { code ->
                    CurrencyRow(
                        title = code,
                        subtitle = currencyDisplayName(code),
                        selected = fiatOn && settings.bitcoinPriceCurrency == code,
                        leading = {
                            Text(
                                text = currencySymbol(code),
                                style = MaterialTheme.typography.titleMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        },
                        onClick = {
                            settingsManager.setShowFiatBalance(true)
                            settingsManager.setBitcoinPriceCurrency(code)
                            priceService.syncFromSettings(refresh = true)
                            onDismiss()
                        },
                    )
                }
            }
            if (fiatOn) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(
                            horizontal = CashuTheme.spacing.section,
                            vertical = CashuTheme.spacing.default,
                        ),
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "BTC Price",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            text = if (price.btcPrice > 0) {
                                formatBtcPrice(price.btcPrice, price.currencyCode)
                            } else {
                                "Loading…"
                            },
                            style = MaterialTheme.typography.bodyLarge.withMonoDigits(),
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                    val lastUpdated = price.lastUpdatedEpochMillis
                    if (lastUpdated != null && price.btcPrice > 0) {
                        Text(
                            text = "Updated ${formatRelativeRecency(lastUpdated)}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.size(CashuTheme.spacing.comfortable))
                    }
                    if (price.isFetching) {
                        LoadingIndicator(
                            modifier = Modifier.size(ProgressSize),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else {
                        IconButton(onClick = priceService::refresh) {
                            Icon(
                                imageVector = Icons.Outlined.Refresh,
                                contentDescription = "Refresh price",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
            Spacer(Modifier.height(CashuTheme.spacing.snug))
        }
    }
}

@Composable
private fun CurrencyRow(
    title: String,
    subtitle: String?,
    selected: Boolean,
    leading: @Composable () -> Unit,
    onClick: () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(
                horizontal = CashuTheme.spacing.section,
                vertical = CashuTheme.spacing.default,
            ),
    ) {
        leading()
        Spacer(Modifier.size(CashuTheme.spacing.comfortable))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            if (subtitle != null && !subtitle.equals(title, ignoreCase = true)) {
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        if (selected) {
            Icon(
                imageVector = Icons.Filled.Check,
                contentDescription = "Selected",
                tint = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.size(CheckSize),
            )
        }
    }
}

private fun currencyDisplayName(code: String): String? =
    runCatching { Currency.getInstance(code).getDisplayName(Locale.getDefault()) }.getOrNull()

private fun currencySymbol(code: String): String =
    runCatching { Currency.getInstance(code).symbol }.getOrDefault(code)

private fun formatBtcPrice(price: Double, currencyCode: String): String {
    val formatter = NumberFormat.getCurrencyInstance(Locale.getDefault())
    runCatching { formatter.currency = Currency.getInstance(currencyCode) }
    formatter.maximumFractionDigits = 0
    return formatter.format(price)
}
