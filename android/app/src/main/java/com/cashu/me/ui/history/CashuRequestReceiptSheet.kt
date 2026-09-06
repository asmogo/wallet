package com.cashu.me.ui.history

import android.content.ClipData
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.CashuRequestStore
import com.cashu.me.Core.PriceService
import com.cashu.me.Core.ReceiveConfirmationOwner
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.TransactionDisplay
import com.cashu.me.Core.WalletManager
import com.cashu.me.Core.displayMintUnitAmount
import com.cashu.me.Models.CashuRequest
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.WalletTransaction
import com.cashu.me.ui.components.ActivityDetailSheet
import com.cashu.me.ui.components.ActivityPaymentCode
import com.cashu.me.ui.components.AmountHero
import com.cashu.me.ui.components.DescriptionDetailRow
import com.cashu.me.ui.components.InspectorRow
import com.cashu.me.ui.components.LocalConfirmationToastController
import com.cashu.me.ui.components.SecondaryButton
import com.cashu.me.ui.theme.AmountScale
import kotlinx.coroutines.launch
import java.net.URI
import java.text.DateFormat
import java.util.Date

@Composable
fun CashuRequestReceiptSheet(
    request: CashuRequest,
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    priceService: PriceService,
    store: CashuRequestStore,
    onDismissRequest: () -> Unit,
    onManageRequest: (String) -> Unit,
    onOpenPayment: (WalletTransaction) -> Unit,
) {
    val storeState by store.state.collectAsState()
    val wallet by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val prices by priceService.state.collectAsState()
    val current = storeState.requests.firstOrNull { it.id == request.id } ?: request
    val payments = wallet.transactions.filter { tx -> current.receivedPayments.any { it.transactionId == tx.id } }
    val total = current.receivedPayments.sumOf { payment ->
        payments.firstOrNull { it.id == payment.transactionId }?.amount ?: payment.amount
    }
    val reusable = current.isEcashRequest || current.quoteKind.equals("bolt12", ignoreCase = true)
    val quoteTransaction = wallet.transactions.firstOrNull {
        current.quoteId != null && (it.id == current.quoteId || it.quoteId == current.quoteId)
    }
    val status = when {
        reusable && current.receivedPayments.isNotEmpty() -> "Active"
        current.receivedPayments.isNotEmpty() -> if (current.quoteKind == "onchain") "Confirmed" else "Paid"
        quoteTransaction?.status == TransactionStatus.Expired -> "Expired"
        quoteTransaction?.status == TransactionStatus.Failed -> "Failed"
        quoteTransaction?.status == TransactionStatus.Completed -> TransactionDisplay.statusText(quoteTransaction)
        else -> "Waiting for payment"
    }
    val codeAvailable = !current.encoded.isBlank() && (reusable ||
        (current.receivedPayments.isEmpty() && quoteTransaction?.let(TransactionDisplay::showsQr) == true))
    val formatter = remember { AmountFormatter() }
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    val toast = LocalConfirmationToastController.current
    fun amountDisplay(amount: Long) = formatter.displayMintUnitAmount(
        amount = amount, unit = current.unit, preferredPrimary = settings.homeBalancePrimary,
        showFiat = settings.showFiatBalance, btcPrice = prices.btcPrice,
        currencyCode = settings.bitcoinPriceCurrency, useBitcoinSymbol = settings.useBitcoinSymbol,
    )
    fun date(epochMillis: Long) = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(epochMillis))

    LaunchedEffect(request.id) {
        current.quoteId?.let { quoteId ->
            runCatching {
                walletManager.refreshPendingMintQuote(quoteId, confirmationOwner = ReceiveConfirmationOwner.Home)
            }
        }
    }

    ActivityDetailSheet(title = current.displayTitle, onDismissRequest = onDismissRequest) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            if (current.receivedPayments.isNotEmpty()) {
                Text("Total received", style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            val amount = if (current.receivedPayments.isEmpty()) current.amount else total
            if (amount != null) {
                val display = amountDisplay(amount)
                AmountHero(parts = display.primaryParts, scale = AmountScale.Confirm, accessibilityPrefix = "Amount")
                display.secondary?.let {
                    Text(it, style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                Text("Any amount", style = MaterialTheme.typography.headlineLarge)
            }
        }
        Column(Modifier.fillMaxWidth()) {
            InspectorRow(label = "Status", value = status)
            InspectorRow(label = "Date", value = date(current.createdAtEpochMillis))
            InspectorRow(label = "Mint", value = current.mints.joinToString(", ") { url ->
                wallet.mints.firstOrNull { it.url == url }?.name
                    ?: runCatching { URI(url).host }.getOrNull() ?: url
            }.ifEmpty { "Any mint" })
            current.displayDescription?.let { DescriptionDetailRow(it) }
            if (reusable) {
                InspectorRow(label = "Requested amount", value = current.amount?.let { amountDisplay(it).primary } ?: "Any amount")
                InspectorRow(label = "Payments received", value = current.receivedPayments.size.toString())
            }
            payments.forEach { payment ->
                InspectorRow(label = date(payment.dateEpochMillis), value = amountDisplay(payment.amount).primary,
                    trailingIcon = Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                    onClick = { onOpenPayment(payment) })
            }
        }
        if (codeAvailable) {
            ActivityPaymentCode(content = current.encoded, title = current.displayTitle)
            SecondaryButton(text = "Copy", onClick = {
                scope.launch {
                    clipboard.setClipEntry(ClipEntry(ClipData.newPlainText("Payment request", current.encoded)))
                    toast?.show("Copied payment request")
                }
            })
        }
        if (current.isEcashRequest) {
            SecondaryButton(text = "Manage request", onClick = { onManageRequest(current.id) })
        }
    }
}
