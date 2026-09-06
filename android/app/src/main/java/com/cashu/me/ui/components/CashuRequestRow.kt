package com.cashu.me.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import com.cashu.me.Core.AmountDisplayText
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.displayMintUnitAmount
import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry
import com.cashu.me.Models.CashuRequest
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withMonoDigits

/**
 * Trailing amount for a request row, in the request's own unit: cumulative
 * received when payments landed, the fixed target while waiting, nothing for
 * a waiting any-amount request.
 */
fun requestRowAmount(
    request: CashuRequest,
    formatter: AmountFormatter,
    useBitcoinSymbol: Boolean,
): String? {
    val amount = when {
        request.totalReceived > 0L -> request.totalReceived
        request.amount != null && request.amount > 0L -> request.amount
        else -> return null
    }
    return if (CurrencyRegistry.isSatoshiUnit(request.unit)) {
        formatter.formatWalletSats(amount, useBitcoinSymbol)
    } else {
        CurrencyAmount(amount, CurrencyRegistry.currencyForMintUnit(request.unit)).formatted()
    }
}

fun requestRowDisplay(
    request: CashuRequest,
    formatter: AmountFormatter,
    preferredPrimary: String,
    showFiat: Boolean,
    btcPrice: Double?,
    currencyCode: String,
    useBitcoinSymbol: Boolean,
): AmountDisplayText? {
    val amount = when {
        request.totalReceived > 0L -> request.totalReceived
        request.amount != null && request.amount > 0L -> request.amount
        else -> return null
    }
    return formatter.displayMintUnitAmount(
        amount = amount,
        unit = request.unit,
        preferredPrimary = preferredPrimary,
        showFiat = showFiat,
        btcPrice = btcPrice,
        currencyCode = currencyCode,
        useBitcoinSymbol = useBitcoinSymbol,
    )
}

/**
 * Cashu Request timeline row, paired with [TransactionRow] in History. A
 * request is structurally an incoming-ecash event in waiting, so the
 * leading icon is the same muted down-arrow. Amount states mirror iOS
 * CashuRequestAmountColumn: fixed+waiting → bare muted amount; received →
 * "+amount" in primary; any-amount+waiting → no trailing element (caller passes
 * null primaryAmountText).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun CashuRequestRow(
    request: CashuRequest,
    timestamp: String,
    primaryAmountText: String?,
    secondaryAmountText: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onLongClick: (() -> Unit)? = null,
) {
    val received = request.receivedPayments.isNotEmpty()
    Row(
        modifier = modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = onClick,
                onLongClick = onLongClick,
                onLongClickLabel = if (onLongClick != null) {
                    "Remove request from history"
                } else {
                    null
                },
            )
            .padding(horizontal = CashuTheme.spacing.comfortable, vertical = CashuTheme.spacing.comfortable),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        DirectionIcon(incoming = true)
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = request.displayTitle,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
            )
            request.displayDescription?.let { description ->
                Text(
                    text = description,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Text(
                text = timestamp,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            if (primaryAmountText != null) {
                AmountText(
                    text = if (received) "+$primaryAmountText" else primaryAmountText,
                    style = MaterialTheme.typography.bodyLarge
                        .copy(fontWeight = FontWeight.Medium)
                        .withMonoDigits(),
                    color = if (received) {
                        CashuTheme.colors.onReceivedContainer
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    maxLines = 1,
                )
            }
            if (secondaryAmountText != null) {
                AmountText(
                    text = secondaryAmountText,
                    style = MaterialTheme.typography.bodyMedium
                        .copy(fontWeight = FontWeight.Normal)
                        .withMonoDigits(),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                )
            }
        }
    }
}
