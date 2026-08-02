package com.cashu.me.ui.screenshots

import android.content.res.Configuration
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CurrencyBitcoin
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.tooling.preview.Wallpapers
import androidx.compose.ui.unit.dp
import com.android.tools.screenshot.PreviewTest
import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.AmountDisplayText
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import com.cashu.me.Views.Send.ContactlessAvailability
import com.cashu.me.Views.Send.ContactlessPayContent
import com.cashu.me.ui.components.AmountEntryHero
import com.cashu.me.ui.components.BalanceDisplay
import com.cashu.me.ui.components.MintAvatar
import com.cashu.me.ui.components.NavRow
import com.cashu.me.ui.components.PaymentStatusPhase
import com.cashu.me.ui.components.PaymentStatusScreen
import com.cashu.me.ui.components.QrCard
import com.cashu.me.ui.components.ToggleRow
import com.cashu.me.ui.components.TransactionRow
import com.cashu.me.ui.components.TransactionRowModel
import com.cashu.me.ui.theme.CashuTheme

@PreviewTest
@Preview(name = "balance-light", widthDp = 390, heightDp = 180, showBackground = true)
@Composable
fun balanceHeaderLightScreenshot() {
    PreviewFrame {
        BalanceDisplay(
            amount = AmountDisplayText(
                primary = "12,345 sat",
                secondary = "€7.89",
                effectivePrimary = AmountDisplayPrimary.Sats,
            ),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@PreviewTest
@Preview(
    name = "balance-dark",
    widthDp = 390,
    heightDp = 180,
    uiMode = Configuration.UI_MODE_NIGHT_YES,
)
@Composable
fun balanceHeaderDarkScreenshot() {
    PreviewFrame(darkTheme = true) {
        BalanceDisplay(
            amount = AmountDisplayText(
                primary = "2,100 sat",
                secondary = "\$1.34",
                effectivePrimary = AmountDisplayPrimary.Sats,
            ),
            receivedDelta = "+500",
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@PreviewTest
@Preview(name = "amount-entry", widthDp = 390, heightDp = 180, showBackground = true)
@Composable
fun amountEntryScreenshot() {
    PreviewFrame {
        AmountEntryHero(
            entryRaw = "12500",
            isSat = true,
            unit = "sat",
            decimals = 0,
            useBitcoinSymbol = false,
            formatter = AmountFormatter(),
        )
    }
}

@PreviewTest
@Preview(name = "mixed-history", widthDp = 390, heightDp = 280, showBackground = true)
@Composable
fun mixedTransactionStatesScreenshot() {
    PreviewFrame(contentPadding = 0.dp) {
        Column {
            TransactionRow(
                model = transactionModel(
                    id = "incoming",
                    title = "Lightning received",
                    amount = 2_500,
                    type = TransactionType.Incoming,
                    kind = TransactionKind.Lightning,
                    status = TransactionStatus.Completed,
                    amountLabel = "2,500 sat",
                    timestamp = "Today, 12:15",
                ),
                onClick = {},
            )
            TransactionRow(
                model = transactionModel(
                    id = "pending",
                    title = "Ecash sent",
                    amount = 800,
                    type = TransactionType.Outgoing,
                    kind = TransactionKind.Ecash,
                    status = TransactionStatus.Pending,
                    amountLabel = "800 sat",
                    timestamp = "Today, 11:40",
                ),
                onClick = {},
            )
        }
    }
}

@PreviewTest
@Preview(name = "qr-request", widthDp = 390, heightDp = 360, showBackground = true)
@Composable
fun paymentRequestQrScreenshot() {
    PreviewFrame {
        QrCard(
            content = "lnbc2500n1deterministicpreviewrequest",
            size = 220.dp,
            staticOnly = true,
        )
    }
}

@PreviewTest
@Preview(name = "payment-success", widthDp = 390, heightDp = 640, showBackground = true)
@Composable
fun paymentSuccessScreenshot() {
    PreviewFrame(contentPadding = 0.dp) {
        PaymentStatusScreen(
            phase = PaymentStatusPhase.Success,
            title = "Payment Received!",
            detail = "2,500 sat",
            onDone = {},
        )
    }
}

@PreviewTest
@Preview(name = "payment-failure", widthDp = 390, heightDp = 640, showBackground = true)
@Composable
fun paymentFailureScreenshot() {
    PreviewFrame(contentPadding = 0.dp) {
        PaymentStatusScreen(
            phase = PaymentStatusPhase.Failure,
            title = "Payment failed",
            detail = "The mint is temporarily unavailable. Try again.",
            doneLabel = "Try again",
            onDone = {},
        )
    }
}

@PreviewTest
@Preview(name = "settings-controls", widthDp = 390, heightDp = 260, showBackground = true)
@Composable
fun settingsControlsScreenshot() {
    PreviewFrame(contentPadding = 0.dp) {
        Column {
            ToggleRow(
                title = "Use ₿ symbol",
                subtitle = "Use ₿ symbol instead of sats.",
                leadingIcon = Icons.Outlined.CurrencyBitcoin,
                checked = true,
                onCheckedChange = {},
            )
            NavRow(
                title = "Locked Ecash",
                leadingIcon = Icons.Outlined.Lock,
                onClick = {},
            )
        }
    }
}

@PreviewTest
@Preview(name = "contactless-unavailable", widthDp = 390, heightDp = 360, showBackground = true)
@Composable
fun contactlessUnavailableScreenshot() {
    PreviewFrame {
        ContactlessPayContent(
            availability = ContactlessAvailability.Unavailable,
            status = "",
            error = null,
            isProcessing = false,
            paymentComplete = false,
            lastPaymentAmount = null,
            onOpenNfcSettings = {},
        )
    }
}

@PreviewTest
@Preview(
    name = "large-font-long-mint",
    widthDp = 390,
    heightDp = 520,
    fontScale = 2f,
    wallpaper = Wallpapers.RED_DOMINATED_EXAMPLE,
)
@Composable
fun largeFontLongMintScreenshot() {
    PreviewFrame {
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            MintAvatar(
                mint = MintInfo(
                    url = "https://deterministic.example",
                    name = "A deliberately long deterministic mint name",
                ),
                size = 72.dp,
            )
            Text(
                text = "A deliberately long deterministic mint name",
                style = MaterialTheme.typography.headlineSmall,
            )
            Text(
                text = "Connection Online · Balance 12,345 sat",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun PreviewFrame(
    darkTheme: Boolean = false,
    contentPadding: androidx.compose.ui.unit.Dp = 24.dp,
    content: @Composable () -> Unit,
) {
    CashuTheme(darkTheme = darkTheme) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.background,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(contentPadding),
                verticalArrangement = Arrangement.Center,
            ) {
                content()
            }
        }
    }
}

private fun transactionModel(
    id: String,
    title: String,
    amount: Long,
    type: TransactionType,
    kind: TransactionKind,
    status: TransactionStatus,
    amountLabel: String,
    timestamp: String,
): TransactionRowModel = TransactionRowModel(
    transaction = WalletTransaction(
        id = id,
        amount = amount,
        type = type,
        kind = kind,
        dateEpochMillis = 1_750_000_000_000,
        status = status,
        mintUrl = "https://deterministic.example",
    ),
    title = title,
    timestamp = timestamp,
    primaryAmount = amountLabel,
    secondaryAmount = null,
)
