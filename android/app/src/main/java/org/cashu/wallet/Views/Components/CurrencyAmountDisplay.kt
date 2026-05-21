package org.cashu.wallet.Views.Components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import org.cashu.wallet.Core.AmountDisplayPrimary
import org.cashu.wallet.Core.AmountFormatter
import org.cashu.wallet.Core.PriceState
import org.cashu.wallet.Core.SettingsState
import org.cashu.wallet.Core.displayText

@Composable
fun CurrencyAmountDisplay(
    sats: Long,
    settings: SettingsState,
    priceState: PriceState,
    modifier: Modifier = Modifier,
    primaryStyle: TextStyle = MaterialTheme.typography.displayLarge,
    horizontalAlignment: Alignment.Horizontal = Alignment.Start,
    onPrimaryChange: ((AmountDisplayPrimary) -> Unit)? = null,
) {
    val formatter = remember { AmountFormatter() }
    val currencyCode = priceState.currencyCode.ifBlank { settings.bitcoinPriceCurrency }
    val display = remember(
        sats,
        settings.amountDisplayPrimary,
        settings.showFiatBalance,
        settings.useBitcoinSymbol,
        priceState.btcPrice,
        currencyCode,
    ) {
        formatter.displayText(
            amountSats = sats,
            preferredPrimary = settings.amountDisplayPrimary,
            showFiat = settings.showFiatBalance,
            btcPrice = priceState.btcPrice,
            currencyCode = currencyCode,
            useBitcoinSymbol = settings.useBitcoinSymbol,
        )
    }

    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(2.dp),
        horizontalAlignment = horizontalAlignment,
    ) {
        Text(
            text = display.primary,
            style = primaryStyle,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        val secondary = display.secondary
        if (secondary != null) {
            if (onPrimaryChange != null) {
                val nextPrimary = when (display.effectivePrimary) {
                    AmountDisplayPrimary.Fiat -> AmountDisplayPrimary.Sats
                    AmountDisplayPrimary.Sats -> AmountDisplayPrimary.Fiat
                }
                TextButton(
                    onClick = { onPrimaryChange(nextPrimary) },
                    contentPadding = PaddingValues(horizontal = 0.dp, vertical = 4.dp),
                ) {
                    Icon(Icons.Default.SwapVert, contentDescription = "Switch primary amount")
                    Spacer(Modifier.width(4.dp))
                    Text(secondary)
                }
            } else {
                Text(
                    text = secondary,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.secondary,
                )
            }
        }
    }
}
