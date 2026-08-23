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
import androidx.compose.material.icons.outlined.Nfc
import androidx.compose.material.icons.outlined.QrCodeScanner
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
import com.cashu.me.Core.NostrSignerType
import com.cashu.me.Views.Send.ContactlessAvailability
import com.cashu.me.Views.Send.ContactlessPayContent
import com.cashu.me.ui.components.AmountEntryHero
import com.cashu.me.ui.components.BalanceDisplay
import com.cashu.me.ui.components.CashuTextField
import com.cashu.me.ui.components.CompactSheetContent
import com.cashu.me.ui.components.MethodActionRow
import com.cashu.me.ui.components.MintAvatar
import com.cashu.me.ui.components.MintSelectorRow
import com.cashu.me.ui.components.NavRow
import com.cashu.me.ui.components.NumberPad
import com.cashu.me.ui.components.PaymentStatusPhase
import com.cashu.me.ui.components.PaymentStatusScreen
import com.cashu.me.ui.components.QrCard
import com.cashu.me.ui.components.ToggleRow
import com.cashu.me.ui.components.TransactionRow
import com.cashu.me.ui.components.TransactionRowModel
import com.cashu.me.ui.settings.NostrKeySection
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
            useBitcoinSymbol = false,
            formatter = AmountFormatter(),
        )
    }
}

/** Guards Android's explicit Bitcoin glyph fallback against system-font drift. */
@PreviewTest
@Preview(name = "amount-entry-bitcoin", widthDp = 390, heightDp = 180, showBackground = true)
@Composable
fun amountEntryBitcoinScreenshot() {
    PreviewFrame {
        AmountEntryHero(
            entryRaw = "12500",
            isSat = true,
            unit = "sat",
            useBitcoinSymbol = true,
            formatter = AmountFormatter(),
        )
    }
}

/**
 * The whole-number-first hero, keystroke by keystroke. "21" must read as
 * twenty-one dollars — the empty pad shows no fraction at all, and the
 * fraction only appears once the decimal key is pressed.
 */
@PreviewTest
@Preview(name = "amount-entry-fiat", widthDp = 390, heightDp = 400, showBackground = true)
@Composable
fun amountEntryFiatScreenshot() {
    PreviewFrame {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            listOf("", "21", "21.", "21.5", "21.50").forEach { raw ->
                AmountEntryHero(
                    entryRaw = raw,
                    isSat = false,
                    unit = "USD",
                    useBitcoinSymbol = false,
                    formatter = AmountFormatter(),
                    fiatCurrencyCode = "USD",
                )
            }
        }
    }
}

/** The decimal key exists only where the unit actually has a fraction. */
@PreviewTest
@Preview(name = "number-pad-decimals", widthDp = 390, heightDp = 260, showBackground = true)
@Composable
fun numberPadDecimalsScreenshot() {
    PreviewFrame {
        NumberPad(amount = "21.50", onAmountChange = {}, decimals = 2)
    }
}

@PreviewTest
@Preview(name = "number-pad-integer", widthDp = 390, heightDp = 260, showBackground = true)
@Composable
fun numberPadIntegerScreenshot() {
    PreviewFrame {
        NumberPad(amount = "12500", onAmountChange = {}, decimals = 0)
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
@Preview(name = "nostr-key-section", widthDp = 390, heightDp = 620, showBackground = true)
@Composable
fun nostrKeySectionScreenshot() {
    PreviewFrame(contentPadding = 0.dp) {
        Column {
            NostrKeySection(
                npub = "npub1e26a9azcspw39xdeterministicpreview407nd3zxxtj3gpqevzh9l",
                publicKeyHex = "cab5d2f458805d129af2deterministicpreviewb455fe9b622319728a02",
                isReady = true,
                signerType = NostrSignerType.Seed,
                isMutating = false,
                progressMessage = null,
                errorMessage = null,
                onRevealNsec = {},
                onSelectSigner = {},
                onGenerateKey = {},
                onImportKey = {},
                onResetToSeed = {},
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
@Preview(name = "compact-method-sheet", widthDp = 390, heightDp = 460, showBackground = true)
@Composable
fun compactMethodSheetLightScreenshot() {
    PreviewFrame {
        CompactMethodSheetPreview()
    }
}

@PreviewTest
@Preview(
    name = "compact-method-sheet-dark",
    widthDp = 390,
    heightDp = 460,
    uiMode = Configuration.UI_MODE_NIGHT_YES,
)
@Composable
fun compactMethodSheetDarkScreenshot() {
    PreviewFrame(darkTheme = true) {
        CompactMethodSheetPreview()
    }
}

@Composable
private fun CompactMethodSheetPreview() {
    CompactSheetContent {
        Surface(
            color = CashuTheme.colors.compactSheetContainer,
            shape = MaterialTheme.shapes.extraLarge,
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                CashuTextField(
                    value = "",
                    onValueChange = {},
                    placeholder = "Address, invoice, or Cashu Request",
                    modifier = Modifier.fillMaxWidth(),
                )
                MethodActionRow(
                    icon = Icons.Outlined.QrCodeScanner,
                    title = "Scan",
                    subtitle = "Scan an invoice, address, or request",
                    accessibilityLabel = "Scan QR code",
                    onClick = {},
                )
                MethodActionRow(
                    icon = Icons.Outlined.Nfc,
                    title = "Tap",
                    subtitle = "Pay contactlessly with NFC",
                    accessibilityLabel = "Contactless, tap to pay nearby",
                    enabled = false,
                    status = "Unavailable",
                    onClick = {},
                )
            }
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

private val ScreenshotMint = MintInfo(
    url = "https://deterministic.example",
    name = "Testnut mint",
)

private val ScreenshotLongMint = MintInfo(
    url = "https://deterministic.example",
    name = "A deliberately long deterministic mint name",
)

/**
 * Every state of the flow-top selector in one frame: with and without the Send
 * Max chip, the single-mint variant that has no chevron and no picker, and a
 * name long enough to truncate. This row has no test tag and no instrumented
 * coverage, so the golden is the regression net.
 */
@PreviewTest
@Preview(name = "mint-selector-light", widthDp = 390, heightDp = 320, showBackground = true)
@Composable
fun mintSelectorRowLightScreenshot() {
    PreviewFrame {
        MintSelectorRowCatalog()
    }
}

@PreviewTest
@Preview(
    name = "mint-selector-dark",
    widthDp = 390,
    heightDp = 320,
    uiMode = Configuration.UI_MODE_NIGHT_YES,
)
@Composable
fun mintSelectorRowDarkScreenshot() {
    PreviewFrame(darkTheme = true) {
        MintSelectorRowCatalog()
    }
}

@PreviewTest
@Preview(name = "mint-selector-large-font", widthDp = 390, heightDp = 560, fontScale = 2f)
@Composable
fun mintSelectorRowLargeFontScreenshot() {
    PreviewFrame {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            MintSelectorRow(
                mint = ScreenshotLongMint,
                balanceText = "\u20bf27,096",
                onPickMint = {},
                onUseMax = {},
            )
            MintSelectorRow(
                mint = ScreenshotLongMint,
                balanceText = null,
                onPickMint = {},
            )
        }
    }
}

@Composable
private fun MintSelectorRowCatalog() {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // Multi-mint, spendable balance: chip and chevron.
        MintSelectorRow(
            mint = ScreenshotMint,
            balanceText = "\u20bf27,096",
            onPickMint = {},
            onUseMax = {},
        )
        // Empty mint: no chip.
        MintSelectorRow(
            mint = ScreenshotMint,
            balanceText = "\u20bf0",
            onPickMint = {},
        )
        // Single mint: no chevron, not a control.
        MintSelectorRow(
            mint = ScreenshotMint,
            balanceText = "\u20bf27,096",
            onUseMax = {},
        )
        // Long name truncates.
        MintSelectorRow(
            mint = ScreenshotLongMint,
            balanceText = "\u20bf27,096",
            onPickMint = {},
            onUseMax = {},
        )
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
