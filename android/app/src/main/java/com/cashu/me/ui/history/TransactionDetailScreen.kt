package com.cashu.me.ui.history

import android.content.ClipData
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.PendingTokenClaimCheckResult
import com.cashu.me.Core.PriceService
import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry
import com.cashu.me.Core.OnchainExplorer
import com.cashu.me.Core.ReceiveConfirmationOwner
import com.cashu.me.Core.runPendingTokenClaimCheck
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.shouldOfferManualClaimCheck
import com.cashu.me.Core.TransactionDisplay
import com.cashu.me.Core.WalletManager
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import com.cashu.me.Models.liveDetail
import com.cashu.me.ui.components.AmountText
import com.cashu.me.ui.components.AmountHero
import com.cashu.me.ui.components.CompactSheetContent
import com.cashu.me.ui.components.ExplorerLinkRow
import com.cashu.me.ui.components.InspectorRow
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.LocalConfirmationToastController
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.QrCard
import com.cashu.me.ui.components.SecondaryButton
import com.cashu.me.ui.components.SheetHeader
import com.cashu.me.ui.components.openInBrowser
import com.cashu.me.ui.theme.AmountScale
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.LeadingLabel
import com.cashu.me.ui.theme.atSize
import com.cashu.me.ui.theme.withMonoDigits
import com.cashu.me.ui.testing.UiTestTags

/**
 * Content-fitting bottom sheet for any transaction, settled or live. Every
 * detail opens over the originating list instead of replacing it with a pushed
 * full-screen destination (iOS `TransactionDetailView` parity): a live request
 * shows its QR hero, a completed receipt the green check, a failed one the red
 * X, above the shared rows and actions. Sharing a live artifact stays on the
 * QR itself (long-press menu), not in chrome.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TransactionReceiptSheet(
    transaction: WalletTransaction,
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    priceService: PriceService,
    onDismissRequest: () -> Unit,
    onClaimReceiveToken: ((String) -> Unit)? = null,
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val priceState by priceService.state.collectAsState()
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    val formatter = remember { AmountFormatter() }
    val sheetState = rememberBottomSheetState(
        initialValue = SheetValue.Hidden,
        enabledValues = setOf(SheetValue.Hidden, SheetValue.Expanded),
    )
    val confirmationToastController = LocalConfirmationToastController.current

    // Pending mint-quote rows use id == quoteId; after mint CDK swaps in a new
    // transaction id with the same quoteId. Keep the open-time identity so the
    // sheet can follow Pending → Completed without going blank.
    var openSnapshot by remember(transaction.id) { mutableStateOf(transaction) }
    val resolved = remember(walletState.transactions, transaction.id, openSnapshot) {
        walletState.transactions.liveDetail(
            openId = transaction.id,
            openQuoteId = openSnapshot.quoteId ?: openSnapshot.id,
        )
    }
    LaunchedEffect(resolved) {
        if (resolved != null) openSnapshot = resolved
    }
    val current = resolved ?: openSnapshot

    var checkingClaim by remember(transaction.id) { mutableStateOf(false) }
    var manualCheckResult: PendingTokenClaimCheckResult? by remember(transaction.id) {
        mutableStateOf(null)
    }
    // Single-quote check on open (not the full pending list). Re-checks this
    // mint quote against the mint and mints if already paid — same path Receive
    // uses for its per-quote poll, without the global loading spinner. Keyed on
    // the opening id so a successful mint → Completed transition does not
    // cancel the in-flight check.
    LaunchedEffect(transaction.id) {
        val quoteId = transaction.mintQuoteIdForStatusRefresh ?: return@LaunchedEffect
        runCatching {
            walletManager.refreshPendingMintQuote(
                quoteId,
                confirmationOwner = ReceiveConfirmationOwner.Home,
            )
        }
    }

    val showsQr = TransactionDisplay.showsQr(current)
    val qrContent = TransactionDisplay.qrContent(current)
    val copyableContent = TransactionDisplay.copyableContent(current)
    val title = TransactionDisplay.title(current)
    val fields = remember(current) { TransactionDisplay.detailFields(current) }
    val explorerUrl = remember(current) { current.explorerUrl() }
    val pendingReceiveToken = current.token?.takeIf {
        current.isPendingReceiveToken &&
            current.type == TransactionType.Incoming &&
            current.status == TransactionStatus.Pending
    }
    val offersManualClaimCheck = shouldOfferManualClaimCheck(
        automaticChecksEnabled = settings.checkSentTokens,
        transaction = current,
    )

    ModalBottomSheet(
        onDismissRequest = onDismissRequest,
        sheetState = sheetState,
        containerColor = CashuTheme.colors.compactSheetContainer,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .testTag(UiTestTags.TransactionReceiptSheet),
        ) {
            CompactSheetContent {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState()),
                ) {
                    SheetHeader(title = title)

                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = CashuTheme.spacing.comfortable),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
                    ) {
                        // Hero state slot: live request → QR; completed → 64dp green
                        // check; failed → 64dp red X; pending with no QR → no glyph.
                        // State detail lives in the monochrome Status row below.
                        when {
                            showsQr && qrContent != null -> QrCard(
                                content = qrContent,
                                staticOnly = current.kind != TransactionKind.Ecash,
                                shareSubject = title,
                                confirmationMessage =
                                    "Copied ${TransactionDisplay.qrLabel(current).replaceFirstChar { it.lowercase() }}",
                            )
                            current.status == TransactionStatus.Completed -> Icon(
                                imageVector = Icons.Filled.CheckCircle,
                                contentDescription = "Completed",
                                tint = CashuTheme.colors.received,
                                modifier = Modifier.size(COMPLETED_RECEIPT_GLYPH_SIZE),
                            )
                            current.status == TransactionStatus.Failed -> Icon(
                                imageVector = Icons.Filled.Cancel,
                                contentDescription = "Failed",
                                tint = MaterialTheme.colorScheme.error,
                                modifier = Modifier.size(FAILED_GLYPH_SIZE),
                            )
                            else -> Unit
                        }

                        HeroAmount(
                            transaction = current,
                            formatter = formatter,
                            useBitcoinSymbol = settings.useBitcoinSymbol,
                            showFiat = settings.showFiatBalance,
                            btcPrice = priceState.btcPrice,
                            currencyCode = priceState.currencyCode,
                            compact = showsQr,
                        )

                        Column(modifier = Modifier.fillMaxWidth()) {
                            fields.forEach { field ->
                                InspectorRow(
                                    label = field.label,
                                    value = field.value,
                                    valueMonospaced = field.value.length > 24 ||
                                        field.label in MonospacedLabels,
                                    onClick = field.copyValue?.let { full ->
                                        {
                                            scope.launch {
                                                clipboard.setClipEntry(
                                                    ClipEntry(ClipData.newPlainText(field.label, full)),
                                                )
                                                confirmationToastController?.show(
                                                    copyConfirmationMessage(field.label),
                                                )
                                            }
                                        }
                                    },
                                    trailingIcon = field.copyValue?.let { Icons.Outlined.ContentCopy },
                                )
                            }
                            // Explorer link joins the detail rows (iOS parity) —
                            // it's reference material, not an action.
                            if (explorerUrl != null) {
                                ExplorerLinkRow(onClick = { context.openInBrowser(explorerUrl) })
                            }
                        }

                        if (offersManualClaimCheck) {
                            when (val outcome = manualCheckResult) {
                                PendingTokenClaimCheckResult.NotClaimed -> InlineNotice(
                                    text = "Status checked",
                                    detail = "This token has not been claimed yet.",
                                    severity = NoticeSeverity.Info,
                                    modifier = Modifier.semantics {
                                        liveRegion = LiveRegionMode.Polite
                                    },
                                )
                                is PendingTokenClaimCheckResult.Failed -> InlineNotice(
                                    text = "Couldn't check status",
                                    detail = outcome.message.text,
                                    modifier = Modifier.semantics {
                                        liveRegion = LiveRegionMode.Polite
                                    },
                                    severity = NoticeSeverity.Caution,
                                )
                                PendingTokenClaimCheckResult.Claimed, null -> Unit
                            }
                        }

                        if (pendingReceiveToken != null && onClaimReceiveToken != null) {
                            Spacer(Modifier.height(CashuTheme.spacing.snug))
                            PrimaryButton(
                                text = "Receive",
                                onClick = { onClaimReceiveToken(pendingReceiveToken) },
                                modifier = Modifier.fillMaxWidth(),
                            )
                        } else {
                            if (copyableContent != null) {
                                Spacer(Modifier.height(CashuTheme.spacing.snug))
                                SecondaryButton(
                                    text = "Copy",
                                    onClick = {
                                        scope.launch {
                                            clipboard.setClipEntry(
                                                ClipEntry(ClipData.newPlainText(title, copyableContent)),
                                            )
                                            confirmationToastController?.show(
                                                "Copied ${TransactionDisplay.qrLabel(current).replaceFirstChar { it.lowercase() }}",
                                            )
                                        }
                                    },
                                    modifier = Modifier.semantics {
                                        liveRegion = LiveRegionMode.Polite
                                    },
                                )
                            }
                            if (offersManualClaimCheck) {
                                PrimaryButton(
                                    text = if (checkingClaim) "Checking…" else "Check Status",
                                    onClick = {
                                        checkingClaim = true
                                        manualCheckResult = null
                                        scope.launch {
                                            try {
                                                manualCheckResult = runPendingTokenClaimCheck {
                                                    walletManager.checkPendingTokenStatus(current)
                                                }
                                            } finally {
                                                checkingClaim = false
                                            }
                                        }
                                    },
                                    loading = checkingClaim,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .testTag(UiTestTags.HistoryCheckTokenStatus)
                                        .semantics {
                                            contentDescription = if (checkingClaim) {
                                                "Checking claim status"
                                            } else {
                                                "Check Status"
                                            }
                                            liveRegion = LiveRegionMode.Polite
                                        },
                                )
                            }
                        }

                        Spacer(Modifier.height(CashuTheme.spacing.comfortable))
                    }
                }
            }
        }
    }
}

// Status glyphs stay at the same restrained scale for every outcome.
private val COMPLETED_RECEIPT_GLYPH_SIZE = 64.dp
private val FAILED_GLYPH_SIZE = 64.dp

private val MonospacedLabels = setOf("Request", "Address", "Payment Proof", "Transaction ID", "Quote ID", "Mint")

private fun copyConfirmationMessage(label: String): String = when (label) {
    "Address" -> "Copied Bitcoin address"
    "Transaction ID" -> "Copied transaction ID"
    "Payment Proof" -> "Copied payment proof"
    else -> "Copied ${label.lowercase()}"
}

// Static receipt amount pair — direction already lives in the sheet title, so
// historical details keep the settled sat amount quiet and unsigned. Fiat is a
// subordinate live reference, never an interactive display-mode control.
@Composable
private fun HeroAmount(
    transaction: WalletTransaction,
    formatter: AmountFormatter,
    useBitcoinSymbol: Boolean,
    showFiat: Boolean,
    btcPrice: Double,
    currencyCode: String,
    compact: Boolean,
) {
    if (!transaction.unit.equals("sat", ignoreCase = true)) {
        val formatted = CurrencyAmount(
            transaction.amount,
            CurrencyRegistry.currencyForMintUnit(transaction.unit),
        ).formatted()
        AmountText(
            text = formatted,
            style = (if (compact) MaterialTheme.typography.headlineLarge else MaterialTheme.typography.displayMedium)
                .copy(fontWeight = FontWeight.Bold)
                .withMonoDigits(),
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.padding(vertical = 5.dp),
        )
        return
    }

    val fiatParts = if (showFiat) {
        formatter.fiatParts(
            amountSats = transaction.amount,
            btcPrice = btcPrice.takeIf { it > 0 },
            currencyCode = currencyCode,
        )
    } else {
        null
    }
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        AmountHero(
            parts = formatter.satsParts(transaction.amount, useBitcoinSymbol),
            scale = if (compact) AmountScale.Compact else AmountScale.Confirm,
            accessibilityPrefix = "Amount",
        )
        fiatParts?.let { parts ->
            AmountText(
                text = parts.joined,
                style = MaterialTheme.typography.bodyLarge
                    .atSize(18.sp, leading = LeadingLabel)
                    .copy(fontWeight = FontWeight.Medium)
                    .withMonoDigits(),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                animated = false,
            )
        }
    }
}

private fun WalletTransaction.explorerUrl(): String? {
    if (kind != TransactionKind.Onchain) return null
    return preimage?.let {
        OnchainExplorer.transactionWebUrl(txid = it, address = invoice, mintUrl = mintUrl)
    } ?: invoice?.let {
        OnchainExplorer.addressWebUrl(address = it, mintUrl = mintUrl)
    }
}
