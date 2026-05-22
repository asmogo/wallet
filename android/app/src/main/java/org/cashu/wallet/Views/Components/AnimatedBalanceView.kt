package org.cashu.wallet.Views.Components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.animation.togetherWith
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import org.cashu.wallet.Core.AmountFormatter
import org.cashu.wallet.Resources.CashuGreen

@Composable
fun AnimatedBalanceView(
    value: Long,
    modifier: Modifier = Modifier,
    textStyle: TextStyle = MaterialTheme.typography.displayLarge,
    hideBalance: Boolean = false,
    formatter: AmountFormatter = AmountFormatter(),
    useBitcoinSymbol: Boolean = false,
) {
    AnimatedContent(
        targetState = if (hideBalance) "••••••" else formatter.formatWalletSats(value, useBitcoinSymbol, includeUnit = false),
        transitionSpec = { fadeIn(tween(160)) togetherWith fadeOut(tween(120)) },
        label = "animated-balance",
        modifier = modifier.animateContentSize(),
    ) { text ->
        Text(
            text = text,
            style = textStyle,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
fun AnimatedAmountDisplay(
    value: Long,
    modifier: Modifier = Modifier,
    showUnit: Boolean = true,
    hideBalance: Boolean = false,
    unitSuffix: String = "sat",
    useBitcoinSymbol: Boolean = false,
) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        AnimatedBalanceView(
            value = value,
            hideBalance = hideBalance,
            useBitcoinSymbol = useBitcoinSymbol,
        )
        if (showUnit && !hideBalance && !useBitcoinSymbol) {
            Text(unitSuffix, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.secondary)
        }
    }
}

@Composable
fun BalanceCardView(
    balance: Long,
    mintName: String?,
    pendingBalance: Long,
    modifier: Modifier = Modifier,
    unitLabel: String = "sat",
    unitSuffix: String = "sat",
    useBitcoinSymbol: Boolean = false,
    hideBalance: Boolean = false,
    fiatText: String? = null,
    onUnitToggle: (() -> Unit)? = null,
    onHideToggle: (() -> Unit)? = null,
    onPendingClick: (() -> Unit)? = null,
) {
    QuietCard(modifier = modifier) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            TextButton(onClick = { onUnitToggle?.invoke() }, enabled = onUnitToggle != null) {
                Icon(Icons.Default.SwapHoriz, contentDescription = null)
                Text(unitLabel)
            }
            TextButton(onClick = { onHideToggle?.invoke() }, enabled = onHideToggle != null) {
                AnimatedAmountDisplay(
                    value = balance,
                    showUnit = true,
                    hideBalance = hideBalance,
                    unitSuffix = unitSuffix,
                    useBitcoinSymbol = useBitcoinSymbol,
                )
            }
            if (!hideBalance && fiatText != null) {
                Text(fiatText, color = MaterialTheme.colorScheme.secondary)
            }
            mintName?.let { KeyValueRow("Mint", it) }
            if (pendingBalance > 0) {
                PendingBalanceBadge(
                    amount = pendingBalance,
                    unitSuffix = unitSuffix,
                    onClick = onPendingClick,
                )
            }
        }
    }
}

@Composable
fun PendingBalanceBadge(
    amount: Long,
    modifier: Modifier = Modifier,
    unitSuffix: String = "sat",
    formatter: AmountFormatter = AmountFormatter(),
    onClick: (() -> Unit)? = null,
) {
    TextButton(onClick = { onClick?.invoke() }, enabled = onClick != null, modifier = modifier) {
        Icon(Icons.Default.AccessTime, contentDescription = null)
        Text("Pending: ${formatter.formatSats(amount, includeUnit = false)} $unitSuffix")
    }
}

@Composable
fun TransactionAmountView(
    amount: Long,
    isIncoming: Boolean,
    modifier: Modifier = Modifier,
    formatter: AmountFormatter = AmountFormatter(),
) {
    val sign = if (isIncoming) "+" else "-"
    Text(
        text = "$sign${formatter.formatSats(kotlin.math.abs(amount), includeUnit = false)}",
        modifier = modifier,
        style = MaterialTheme.typography.bodyLarge,
        fontWeight = FontWeight.SemiBold,
        color = if (isIncoming) CashuGreen else MaterialTheme.colorScheme.onBackground,
    )
}
