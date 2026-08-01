package com.cashu.me.ui.history

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
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
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.DetailAmountPresentation
import com.cashu.me.Core.PendingTokenClaimCheckResult
import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry
import com.cashu.me.Core.OnchainExplorer
import com.cashu.me.Core.PriceService
import com.cashu.me.Core.ReceiveConfirmationOwner
import com.cashu.me.Core.pendingSentTokenFor
import com.cashu.me.Core.resolveTransactionForDetail
import com.cashu.me.Core.runPendingTokenClaimCheck
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.shouldOfferManualClaimCheck
import com.cashu.me.Core.TransactionDisplay
import com.cashu.me.Core.WalletManager
import com.cashu.me.Core.isPendingReceiveToken
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.WalletTransaction
import com.cashu.me.ui.components.AmountFlipDisplay
import com.cashu.me.ui.components.AmountText
import com.cashu.me.ui.components.CanvasDivider
import com.cashu.me.ui.components.DetailActionFooter
import com.cashu.me.ui.components.DestructiveTextButton
import com.cashu.me.ui.components.EmptyState
import com.cashu.me.ui.components.ExplorerLinkRow
import com.cashu.me.ui.components.InspectorRow
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.QrCard
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.components.neutralActionButtonColors
import com.cashu.me.ui.components.openInBrowser
import com.cashu.me.ui.components.shareText
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withMonoDigits
import com.cashu.me.ui.testing.UiTestTags

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TransactionDetailScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    priceService: PriceService,
    transactionId: String,
    onClose: () -> Unit,
    onClaimReceiveToken: ((String) -> Unit)? = null,
    snackbarHostState: SnackbarHostState? = null,
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val priceState by priceService.state.collectAsState()
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val formatter = remember { AmountFormatter() }
    val scope = rememberCoroutineScope()

    // Pending mint-quote rows use id == quoteId; after mint CDK swaps in a new
    // transaction id with the same quoteId. Keep the open-time identity so the
    // detail can follow Pending → Completed without flashing "not found".
    var openSnapshot by remember(transactionId) { mutableStateOf<WalletTransaction?>(null) }
    val resolved = remember(walletState.transactions, transactionId, openSnapshot) {
        resolveTransactionForDetail(
            transactions = walletState.transactions,
            openId = transactionId,
            openQuoteId = openSnapshot?.quoteId ?: openSnapshot?.id,
        )
    }
    LaunchedEffect(resolved) {
        if (resolved != null) openSnapshot = resolved
    }
    val transaction = resolved ?: openSnapshot

    var copied by remember { mutableStateOf(false) }
    var checkingClaim by remember(transactionId) { mutableStateOf(false) }
    var manualCheckResult: PendingTokenClaimCheckResult? by remember(transactionId) {
        mutableStateOf(null)
    }
    LaunchedEffect(copied) {
        if (copied) {
            delay(2000)
            copied = false
        }
    }
    // Single-quote check on open (not the full pending list). Re-checks this
    // mint quote against the mint and mints if already paid — same path Receive
    // uses for its per-quote poll, without the global loading spinner.
    // Keyed only on transactionId so a successful mint → Completed transition
    // does not cancel the in-flight check.
    LaunchedEffect(transactionId) {
        val quoteId = resolveTransactionForDetail(
            transactions = walletManager.state.value.transactions,
            openId = transactionId,
        )?.mintQuoteIdForStatusRefresh
            ?: return@LaunchedEffect
        runCatching {
            walletManager.refreshPendingMintQuote(
                quoteId,
                confirmationOwner = ReceiveConfirmationOwner.Home,
            )
        }
    }
    // Tap-to-copy inspector rows (Address / Transaction ID / Payment Proof):
    // which row last copied, for the ContentCopy → green Check swap.
    var copiedFieldLabel by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(copiedFieldLabel) {
        if (copiedFieldLabel != null) {
            delay(3000)
            copiedFieldLabel = null
        }
    }

    val showsQr = transaction?.let { TransactionDisplay.showsQr(it) } == true
    val qrContent = transaction?.let { TransactionDisplay.qrContent(it) }
    val copyableContent = transaction?.let { TransactionDisplay.copyableContent(it) }
    val title = transaction?.let { TransactionDisplay.title(it) } ?: ""

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text(title, style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        ToolbarIcon(Icons.Outlined.Close, contentDescription = "Close")
                    }
                },
                actions = {
                    // Share rides the top bar only while the artifact is live.
                    if (showsQr && qrContent != null) {
                        IconButton(onClick = {
                            context.shareText(qrContent, subject = title)
                        }) {
                            ToolbarIcon(Icons.Outlined.IosShare, contentDescription = "Share")
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { padding ->
        if (transaction == null) {
            EmptyState(
                icon = Icons.Outlined.Close,
                title = "Transaction not found",
                modifier = Modifier.padding(padding),
            )
            return@Scaffold
        }

        val explorerUrl = remember(transaction) { transaction.explorerUrl() }
        val pendingReceiveToken = transaction.token?.takeIf { transaction.isPendingReceiveToken }
        var removeParkedToken by remember { mutableStateOf(false) }
        val pendingSentToken = pendingSentTokenFor(transaction, walletState.pendingTokens)
        val offersManualClaimCheck = shouldOfferManualClaimCheck(
            automaticChecksEnabled = settings.checkSentTokens,
            pendingToken = pendingSentToken,
        )
        val hasPrimaryAction =
            (pendingReceiveToken != null && onClaimReceiveToken != null) ||
                offersManualClaimCheck ||
                copyableContent != null

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = CashuTheme.spacing.comfortable),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
            ) {
                Spacer(Modifier.height(CashuTheme.spacing.snug))
                // Hero state slot: live request → QR; completed → 64dp green check;
                // failed → 64dp red X; pending with no QR → no glyph. State detail
                // lives in the monochrome Status row below.
                when {
                    showsQr && qrContent != null -> QrCard(
                        content = qrContent,
                        staticOnly = transaction.kind != TransactionKind.Ecash,
                        shareSubject = title,
                        snackbarHostState = snackbarHostState,
                    )
                    transaction.status == TransactionStatus.Completed -> Icon(
                        imageVector = Icons.Filled.CheckCircle,
                        contentDescription = "Completed",
                        tint = CashuTheme.colors.received,
                        modifier = Modifier
                            .padding(top = CashuTheme.spacing.comfortable)
                            .size(COMPLETED_HERO_GLYPH_SIZE),
                    )
                    transaction.status == TransactionStatus.Failed -> Icon(
                        imageVector = Icons.Filled.Cancel,
                        contentDescription = "Failed",
                        tint = MaterialTheme.colorScheme.error,
                        modifier = Modifier.size(FAILED_HERO_GLYPH_SIZE),
                    )
                    else -> Unit
                }
                HeroAmount(
                    transaction = transaction,
                    formatter = formatter,
                    amountPrimary = AmountDisplayPrimary.fromRaw(settings.amountDisplayPrimary),
                    onFlipPrimary = { settingsManager.setAmountDisplayPrimary(it.rawValue) },
                    btcPrice = if (settings.showFiatBalance) {
                        priceState.btcPrice.takeIf { it > 0 }
                    } else {
                        null
                    },
                    currencyCode = settings.bitcoinPriceCurrency,
                    useBitcoinSymbol = settings.useBitcoinSymbol,
                    compact = showsQr,
                )
                Column(modifier = Modifier.fillMaxWidth()) {
                    val fields = remember(transaction) { TransactionDisplay.detailFields(transaction) }
                    fields.forEachIndexed { index, field ->
                        val fieldCopied = copiedFieldLabel == field.label
                        InspectorRow(
                            label = field.label,
                            value = field.value,
                            valueMonospaced = field.value.length > 24 ||
                                field.label in MonospacedLabels,
                            onClick = field.copyValue?.let { full ->
                                {
                                    // No app snackbar: Android 13+ shows the system
                                    // clipboard bubble, so the row's check swap is
                                    // the only in-app confirmation.
                                    clipboard.setText(AnnotatedString(full))
                                    copiedFieldLabel = field.label
                                }
                            },
                            trailingIcon = field.copyValue?.let {
                                if (fieldCopied) Icons.Outlined.Check else Icons.Outlined.ContentCopy
                            },
                            trailingIconTint = if (fieldCopied) CashuTheme.colors.received else null,
                        )
                        if (index != fields.lastIndex) CanvasDivider(leadingInset = 16.dp)
                    }
                    // Explorer link joins the detail rows (iOS parity), not the
                    // pinned footer — it's reference material, not an action.
                    if (explorerUrl != null) {
                        if (fields.isNotEmpty()) CanvasDivider(leadingInset = 16.dp)
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
                        )
                        PendingTokenClaimCheckResult.Claimed, null -> Unit
                    }
                }
                Spacer(Modifier.height(CashuTheme.spacing.snug))
            }

            if (hasPrimaryAction) {
                DetailActionFooter {
                    if (pendingReceiveToken != null && onClaimReceiveToken != null) {
                        PrimaryButton(
                            text = "Receive",
                            onClick = { onClaimReceiveToken(pendingReceiveToken) },
                        )
                        Spacer(Modifier.height(CashuTheme.spacing.snug))
                        // Discard is the ordinary parked-token counterpart of
                        // declining a held Cashu Request payment (iOS History
                        // swipe-action parity, surfaced on the detail too).
                        // Full width keeps the label centered under the Receive
                        // capsule (Remove mint on MintDetailScreen precedent).
                        DestructiveTextButton(
                            text = "Remove",
                            onClick = { removeParkedToken = true },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    } else {
                        if (copyableContent != null) {
                            // Copy is a secondary convenience, not a primary action —
                            // quiet neutral tonal fill (matches Home's Send/Receive)
                            // rather than the loud inverted-ink primary.
                            PrimaryButton(
                                text = if (copied) "Copied" else "Copy",
                                onClick = {
                                    clipboard.setText(AnnotatedString(copyableContent))
                                    copied = true
                                },
                                colors = neutralActionButtonColors(),
                            )
                        }
                        if (offersManualClaimCheck && pendingSentToken != null) {
                            if (copyableContent != null) {
                                Spacer(Modifier.height(CashuTheme.spacing.tight))
                            }
                            PrimaryButton(
                                text = if (checkingClaim) "Checking…" else "Check Status",
                                onClick = {
                                    checkingClaim = true
                                    manualCheckResult = null
                                    scope.launch {
                                        try {
                                            manualCheckResult = runPendingTokenClaimCheck {
                                                walletManager.checkPendingTokenStatus(pendingSentToken)
                                            }
                                        } finally {
                                            checkingClaim = false
                                        }
                                    }
                                },
                                loading = checkingClaim,
                                modifier = Modifier
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
                }
            }
        }

        if (removeParkedToken) {
            ParkedTokenRemovalDialog(
                onConfirm = {
                    // The synthetic row id is the pending token id; the reload
                    // drops the row from History before the user lands back.
                    removeParkedToken = false
                    walletManager.removePendingReceiveToken(transaction.id)
                    scope.launch { walletManager.loadTransactions() }
                    onClose()
                },
                onDismiss = { removeParkedToken = false },
            )
        }
    }
}

// Historical success gets a more generous 96dp hero; failure stays restrained.
private val COMPLETED_HERO_GLYPH_SIZE = 96.dp
private val FAILED_HERO_GLYPH_SIZE = 64.dp

private val MonospacedLabels = setOf("Request", "Address", "Payment Proof", "Transaction ID", "Quote ID", "Mint")

// Crisp primary amount hero — direction already lives in the screen title, so
// the historical detail keeps the amount itself quiet and unsigned like iOS.
// Sat-denominated Lightning/ecash records lead with the saved primary unit and
// keep the alternate on the flip pill (iOS CurrencyAmountDisplay parity);
// on-chain stays in sats and non-sat mint units stay native.
@Composable
private fun HeroAmount(
    transaction: WalletTransaction,
    formatter: AmountFormatter,
    amountPrimary: AmountDisplayPrimary,
    onFlipPrimary: (AmountDisplayPrimary) -> Unit,
    btcPrice: Double?,
    currencyCode: String,
    useBitcoinSymbol: Boolean,
    compact: Boolean,
) {
    val heroStyle = (if (compact) {
        MaterialTheme.typography.headlineLarge
    } else {
        MaterialTheme.typography.displayMedium
    }).copy(fontWeight = FontWeight.Bold)
    when (TransactionDisplay.amountPresentation(transaction)) {
        DetailAmountPresentation.PreferredUnit -> AmountFlipDisplay(
            amountSats = transaction.amount,
            primary = amountPrimary,
            onFlip = onFlipPrimary,
            btcPrice = btcPrice,
            currencyCode = currencyCode,
            useBitcoinSymbol = useBitcoinSymbol,
            modifier = Modifier.padding(vertical = 5.dp),
            primaryTextStyle = heroStyle,
            primaryAccessibilityPrefix = "Amount",
        )
        DetailAmountPresentation.SatsOnly -> AmountText(
            text = formatter.formatWalletSats(transaction.amount, useBitcoinSymbol),
            style = heroStyle.withMonoDigits(),
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.padding(vertical = 5.dp),
        )
        DetailAmountPresentation.NativeUnit -> AmountText(
            text = CurrencyAmount(
                transaction.amount,
                CurrencyRegistry.currencyForMintUnit(transaction.unit),
            ).formatted(),
            style = heroStyle.withMonoDigits(),
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.padding(vertical = 5.dp),
        )
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
