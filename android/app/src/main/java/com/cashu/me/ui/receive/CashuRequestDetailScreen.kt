package com.cashu.me.ui.receive

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material.icons.outlined.CalendarToday
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.CurrencyExchange
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.delay
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.CashuRequestStore
import com.cashu.me.Core.CashuRequestNostrReadiness
import com.cashu.me.Core.NostrService
import com.cashu.me.Core.NfcReceive.NfcReceiveCoordinator
import com.cashu.me.Core.NfcReceive.NfcReceivePhase
import com.cashu.me.Core.NfcReceive.shouldOfferNfcReceive
import com.cashu.me.Core.PaymentRequestBuilder
import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.UnitAmountEntry
import com.cashu.me.Core.Wallet.userFacingWalletMessage
import com.cashu.me.Core.WalletManager
import com.cashu.me.Models.CashuRequestPayment
import com.cashu.me.ui.components.AmountEntryHero
import com.cashu.me.ui.components.AmountText
import com.cashu.me.ui.components.DetailActionFooter
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.InlineNoticeHost
import com.cashu.me.ui.components.InspectorRow
import com.cashu.me.ui.components.MintPickerSheet
import com.cashu.me.ui.components.NumberPadFooter
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.PaymentStatusPhase
import com.cashu.me.ui.components.PaymentStatusScreen
import com.cashu.me.ui.components.QrCard
import com.cashu.me.ui.components.SecondaryButton
import com.cashu.me.ui.components.SheetHeader
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.components.UnitPickerSheet
import com.cashu.me.ui.components.WaitingForPaymentRow
import com.cashu.me.ui.components.shareText
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withMonoDigits
import com.cashu.me.ui.receive.nfc.NfcReceiveIndicator
import com.cashu.me.ui.receive.nfc.NfcReceiveLifecycle
import com.cashu.me.ui.receive.nfc.NfcReceiveOverlay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CashuRequestDetailScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    nostrService: NostrService,
    cashuRequestStore: CashuRequestStore,
    nfcReceiveCoordinator: NfcReceiveCoordinator,
    requestId: String,
    onClose: () -> Unit,
    snackbarHostState: SnackbarHostState? = null,
) {
    val storeState by cashuRequestStore.state.collectAsState()
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val nostrState by nostrService.state.collectAsState()
    val nfcState by nfcReceiveCoordinator.state.collectAsState()
    val formatter = remember { AmountFormatter() }
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current

    val request = storeState.requests.firstOrNull { it.id == requestId }
    val requestReadiness = remember(settings, nostrState) {
        CashuRequestNostrReadiness.current(nostrService, settingsManager)
    }
    var copied by remember { mutableStateOf(false) }
    var mintPickerOpen by remember { mutableStateOf(false) }
    var amountPickerOpen by remember { mutableStateOf(false) }
    var unitPickerOpen by remember { mutableStateOf(false) }
    var regenerateError by remember { mutableStateOf<String?>(null) }
    val offerNfcReceive = request?.shouldOfferNfcReceive() == true
    val keepNfcSessionMounted = shouldKeepNfcSessionMounted(offerNfcReceive, nfcState.phase)
    val nfcTransferActive = keepNfcSessionMounted && nfcState.phase.isNfcTransferActive()

    // Re-signs the same NUT-18 request in place (same id/history entry) — used
    // by the Mint sheet, the Amount sheet's Done, and "New Request" (called
    // with no args, which just re-signs the current values).
    fun regenerate(
        nextAmount: Long? = request?.amount,
        nextMints: List<String> = request?.mints.orEmpty(),
        nextUnit: String? = null,
    ) {
        if (nfcReceiveCoordinator.state.value.phase.isNfcTransferActive()) return
        val req = request ?: return
        val readiness = CashuRequestNostrReadiness.current(nostrService, settingsManager)
        val configuration = readiness.requestConfigurationOrNull()
        if (configuration == null) {
            regenerateError = (readiness as? CashuRequestNostrReadiness.Blocked)?.recoveryMessage
            return
        }
        val resolvedUnit = walletState.mints.firstOrNull { it.url == nextMints.firstOrNull() }
            ?.resolvedMintUnit(nextUnit ?: req.unit) ?: (nextUnit ?: req.unit)
        // A stored integer means something different after a unit change; clear
        // it instead of silently turning (for example) 500 sat into 500 cents.
        val resolvedAmount = nextAmount.takeUnless { resolvedUnit != req.unit }
        runCatching {
            PaymentRequestBuilder.build(
                id = req.id,
                amount = resolvedAmount,
                unit = resolvedUnit,
                mints = nextMints,
                description = req.memo,
                nostrPubkeyHex = configuration.publicKeyHex,
                relays = configuration.relays,
            )
        }.onSuccess { encoded ->
            cashuRequestStore.update(
                id = req.id,
                amount = resolvedAmount,
                unit = resolvedUnit,
                mints = nextMints,
                memo = req.memo,
                encoded = encoded,
            )
            regenerateError = null
        }.onFailure { regenerateError = it.userFacingWalletMessage }
    }

    LaunchedEffect(copied) {
        if (copied) {
            delay(2000)
            copied = false
        }
    }

    // A tap may begin while an editor sheet is open. Once the peer connects,
    // settle the sheet away so the full-screen keep-together state is visible
    // and the signed request cannot change during the exchange.
    LaunchedEffect(nfcTransferActive) {
        if (nfcTransferActive) {
            mintPickerOpen = false
            amountPickerOpen = false
            unitPickerOpen = false
        }
    }

    val paymentCount = request?.receivedPayments?.size ?: 0
    var observedPaymentIds by rememberSaveable(requestId) {
        mutableStateOf(request?.receivedPayments?.map { it.transactionId })
    }
    var successPaymentId by rememberSaveable(requestId) { mutableStateOf<String?>(null) }
    LaunchedEffect(requestId, request?.receivedPayments) {
        val currentPayments = request?.receivedPayments ?: return@LaunchedEffect
        newestUnseenPayment(observedPaymentIds, currentPayments)?.let { payment ->
            successPaymentId = payment.transactionId
        }
        observedPaymentIds = currentPayments.map { it.transactionId }
    }

    // A payment that lands while this request is open always gets the shared
    // full-screen receipt, regardless of whether it arrived via NFC or Nostr.
    // Existing payments form the baseline, so revisiting history stays inline.
    val successPayment = request?.receivedPayments
        ?.firstOrNull { it.transactionId == successPaymentId }
    val showSuccessTerminal = request != null && successPayment != null &&
        nfcState.phase != NfcReceivePhase.Success

    // One gate keeps the detail and the receipt in the same composition so
    // the swap fades through instead of hard-cutting (iOS:
    // .animation(.smooth(duration: 0.3)) on the same beat).
    AnimatedContent(
        targetState = showSuccessTerminal,
        transitionSpec = { fadeIn(tween(200)) togetherWith fadeOut(tween(150)) },
        label = "creq-detail-terminal",
    ) { terminal ->
        if (terminal && request != null && successPayment != null) {
            val isSatRequest = request.unit.equals("sat", ignoreCase = true)
            val requestCurrency = CurrencyRegistry.currencyForMintUnit(request.unit)
            val amountLabel = successPayment.amount.takeIf { it > 0L }?.let {
                if (isSatRequest) formatter.formatWalletSats(it, settings.useBitcoinSymbol)
                else CurrencyAmount(it, requestCurrency).formatted()
            }
            val transactionMintUrl = walletState.transactions
                .firstOrNull { it.id == successPayment.transactionId }
                ?.mintUrl
            val creditedMintUrl = transactionMintUrl
                ?: nfcState.settlementMint.takeIf { nfcState.phase == NfcReceivePhase.Success }
                ?: request.mints.singleOrNull()
            val mintName = creditedMintUrl?.let { url ->
                walletState.mints.firstOrNull { it.url == url }?.name ?: url
            }
            Scaffold(
                topBar = {
                    CashuRequestDetailTopBar(
                        title = request.displayTitle,
                        onClose = onClose,
                        onShare = {
                            context.shareText(request.encoded, subject = request.displayTitle)
                        },
                    )
                },
            ) { padding ->
                CashuRequestSuccessTerminal(
                    amountLabel = amountLabel,
                    mintName = mintName,
                    onDone = {
                        nfcReceiveCoordinator.deactivate()
                        onClose()
                    },
                    modifier = Modifier.padding(padding),
                )
            }
        } else {

        Scaffold(
            topBar = {
                CashuRequestDetailTopBar(
                    title = request?.displayTitle ?: "Cashu Request",
                    onClose = onClose,
                    onShare = request?.let { current ->
                        {
                            context.shareText(
                                current.encoded,
                                subject = current.displayTitle,
                            )
                        }
                    },
                )
            },
        ) { padding ->
            if (request == null) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text(
                        text = "Request not found",
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Spacer(Modifier.height(CashuTheme.spacing.comfortable))
                    GhostButton(text = "Back", onClick = onClose)
                }
                return@Scaffold
            }

            if (keepNfcSessionMounted) {
                NfcReceiveLifecycle(
                    coordinator = nfcReceiveCoordinator,
                    request = request,
                    settlementMintUrl = walletState.activeMint?.url,
                )
            }

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
                    verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Spacer(Modifier.height(CashuTheme.spacing.snug))
                    QrCard(
                        content = request.encoded,
                        shareSubject = request.displayTitle,
                        staticOnly = true,
                        snackbarHostState = snackbarHostState,
                    )

                    // Request amounts render in the request's own unit.
                    val isSatRequest = request.unit.equals("sat", ignoreCase = true)
                    val requestCurrency = CurrencyRegistry.currencyForMintUnit(request.unit)
                    fun formatRequestAmount(amount: Long): String = if (isSatRequest) {
                        formatter.formatWalletSats(amount, settings.useBitcoinSymbol)
                    } else {
                        CurrencyAmount(amount, requestCurrency).formatted()
                    }

                    if (request.amount != null && request.amount > 0L) {
                        AmountText(
                            text = formatRequestAmount(request.amount),
                            style = MaterialTheme.typography.headlineMedium
                                .copy(fontWeight = FontWeight.Bold)
                                .withMonoDigits(),
                            modifier = Modifier.padding(vertical = 5.dp),
                        )
                    }

                    if (offerNfcReceive) {
                        NfcReceiveIndicator(coordinator = nfcReceiveCoordinator)
                    }

                    val deliveryNotice = requestReadiness.deliveryNoticeOrNull()
                    if (request.isEcashRequest && request.receivedPayments.isEmpty() && deliveryNotice != null) {
                        InlineNotice(
                            text = deliveryNotice.title,
                            detail = deliveryNotice.message,
                            severity = NoticeSeverity.Caution,
                        )
                    } else {
                        StatusBlock(
                            received = request.receivedPayments.isNotEmpty(),
                            paymentCount = paymentCount,
                        )
                    }

                    Column(modifier = Modifier.fillMaxWidth()) {
                        val activeMintUrl = request.mints.firstOrNull()
                        val requestMint = activeMintUrl?.let { url ->
                            walletState.mints.firstOrNull { it.url == url }
                        }
                        val mintLabel = activeMintUrl?.let { url ->
                            requestMint?.name ?: url
                        } ?: "Any mint"
                        val requestEditable = request.isEcashRequest && !nfcTransferActive
                        InspectorRow(
                            label = "Mint",
                            value = mintLabel,
                            leadingIcon = Icons.Outlined.AccountBalance,
                            editable = requestEditable,
                            onClick = { mintPickerOpen = true },
                        )
                        InspectorRow(
                            label = "Amount",
                            value = request.amount?.let {
                                if (isSatRequest) "$it sat" else formatRequestAmount(it)
                            } ?: "Any",
                            leadingIcon = Icons.Outlined.AccountBalanceWallet,
                            valueMonospaced = true,
                            editable = requestEditable,
                            onClick = { amountPickerOpen = true },
                        )
                        InspectorRow(
                            label = "Unit",
                            value = request.unit.uppercase(),
                            leadingIcon = Icons.Outlined.CurrencyExchange,
                            editable = requestEditable && requestMint?.supportsMultipleMintUnits == true,
                            onClick = { unitPickerOpen = true },
                        )
                        InspectorRow(
                            label = "Created",
                            value = formatDate(request.createdAtEpochMillis),
                            leadingIcon = Icons.Outlined.CalendarToday,
                        )
                        if (request.totalReceived > 0L) {
                            InspectorRow(
                                label = "Total received",
                                value = formatRequestAmount(request.totalReceived),
                                leadingIcon = Icons.Outlined.CheckCircle,
                                valueMonospaced = true,
                            )
                        }
                    }

                    InlineNoticeHost(
                        text = regenerateError,
                        modifier = Modifier.fillMaxWidth(),
                        severity = NoticeSeverity.Error,
                    )

                    Spacer(Modifier.height(CashuTheme.spacing.snug))
                }

                DetailActionFooter {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
                    ) {
                        SecondaryButton(
                            text = if (copied) "Copied" else "Copy",
                            onClick = {
                                clipboard.setText(AnnotatedString(request.encoded))
                                copied = true
                            },
                            modifier = Modifier.weight(1f),
                        )
                        // Quote-backed invoices/addresses cannot be regenerated in
                        // place; only a NUT-18 ecash request owns this action.
                        if (request.isEcashRequest) {
                            SecondaryButton(
                                text = "New Request",
                                onClick = { regenerate() },
                                modifier = Modifier.weight(1f),
                                enabled = !nfcTransferActive,
                            )
                        }
                    }
                }
            }
        }

        if (mintPickerOpen && request?.isEcashRequest == true) {
            val activeMintUrl = request.mints.firstOrNull()
            MintPickerSheet(
                mints = walletState.mints,
                activeMintUrl = activeMintUrl,
                allowAnyMint = true,
                onSelect = { mint ->
                    regenerate(nextMints = listOfNotNull(mint?.url))
                    mintPickerOpen = false
                },
                onDismiss = { mintPickerOpen = false },
            )
        }

        if (amountPickerOpen && request?.isEcashRequest == true) {
            val isSatRequest = request.unit.equals("sat", ignoreCase = true)
            val requestCurrency = CurrencyRegistry.currencyForMintUnit(request.unit)
            CashuRequestAmountEditSheet(
                initialAmount = request.amount,
                isSat = isSatRequest,
                unit = request.unit,
                decimals = requestCurrency.decimals,
                useBitcoinSymbol = settings.useBitcoinSymbol,
                formatter = formatter,
                onDone = { value ->
                    regenerate(nextAmount = value)
                    amountPickerOpen = false
                },
                onDismiss = { amountPickerOpen = false },
            )
        }

        if (unitPickerOpen && request?.isEcashRequest == true) {
            val requestMint = request.mints.firstOrNull()?.let { url ->
                walletState.mints.firstOrNull { it.url == url }
            }
            if (requestMint != null && requestMint.supportsMultipleMintUnits) {
                UnitPickerSheet(
                    units = requestMint.effectiveMintUnits,
                    selectedUnit = request.unit,
                    title = "Choose request unit",
                    onSelect = { unit ->
                        regenerate(nextUnit = unit)
                        unitPickerOpen = false
                    },
                    onDismiss = { unitPickerOpen = false },
                )
            } else {
                LaunchedEffect(Unit) { unitPickerOpen = false }
            }
        }

        if (keepNfcSessionMounted) {
            val nfcSuccessAmountLabel = request?.let { currentRequest ->
                nfcState.amount?.takeIf { it > 0L }?.let { amount ->
                    if (currentRequest.unit.equals("sat", ignoreCase = true)) {
                        formatter.formatWalletSats(amount, settings.useBitcoinSymbol)
                    } else {
                        CurrencyAmount(
                            amount,
                            CurrencyRegistry.currencyForMintUnit(currentRequest.unit),
                        ).formatted()
                    }
                }
            }
            val nfcSuccessMintName = nfcState.settlementMint?.let { url ->
                walletState.mints.firstOrNull { it.url == url }?.name ?: url
            }
            NfcReceiveOverlay(
                coordinator = nfcReceiveCoordinator,
                successAmountLabel = nfcSuccessAmountLabel,
                successMintName = nfcSuccessMintName,
                onSuccessDone = {
                    nfcReceiveCoordinator.deactivate()
                    onClose()
                },
            )
        }
        }
    }
}

internal fun shouldKeepNfcSessionMounted(
    offerNfcReceive: Boolean,
    phase: NfcReceivePhase,
): Boolean = offerNfcReceive || phase in setOf(
    NfcReceivePhase.Connected,
    NfcReceivePhase.Receiving,
    NfcReceivePhase.Validating,
    NfcReceivePhase.Redeeming,
    NfcReceivePhase.Converting,
    NfcReceivePhase.Success,
    NfcReceivePhase.Failure,
)

private fun NfcReceivePhase.isNfcTransferActive(): Boolean = this in setOf(
    NfcReceivePhase.Connected,
    NfcReceivePhase.Receiving,
    NfcReceivePhase.Validating,
    NfcReceivePhase.Redeeming,
    NfcReceivePhase.Converting,
)

@Composable
private fun StatusBlock(received: Boolean, paymentCount: Int) {
    // Waiting → received swaps with the same fade + scale-in the terminal
    // glyph uses, so an arriving payment reads as a morph, not a pop.
    AnimatedContent(
        targetState = received,
        transitionSpec = {
            (
                fadeIn(tween(200)) + scaleIn(
                    animationSpec = spring(
                        dampingRatio = 0.7f,
                        stiffness = Spring.StiffnessMediumLow,
                    ),
                    initialScale = 0.9f,
                )
                ) togetherWith fadeOut(tween(150))
        },
        label = "creq-status-block",
    ) { isReceived ->
        if (isReceived) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
            ) {
                Icon(
                    imageVector = Icons.Outlined.CheckCircle,
                    contentDescription = null,
                    tint = CashuTheme.colors.received,
                    modifier = Modifier.size(CashuTheme.spacing.loose),
                )
                Text(
                    text = if (paymentCount == 1) "1 payment received" else "$paymentCount payments received",
                    style = MaterialTheme.typography.titleMedium,
                    color = CashuTheme.colors.received,
                )
            }
        } else {
            WaitingForPaymentRow()
        }
    }
}

private fun formatDate(epochMillis: Long): String =
    DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(epochMillis))

/** Amount-only edit sheet for an existing Cashu Request (iOS
 *  `CashuRequestAmountPickerSheet` parity). An empty pad on Done naturally
 *  produces null ("Any") — no separate clear action needed. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CashuRequestAmountEditSheet(
    initialAmount: Long?,
    isSat: Boolean,
    unit: String,
    decimals: Int,
    useBitcoinSymbol: Boolean,
    formatter: AmountFormatter,
    onDone: (Long?) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var amount by remember { mutableStateOf(UnitAmountEntry.entryString(initialAmount ?: 0, decimals)) }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .imePadding()
                .padding(horizontal = CashuTheme.spacing.comfortable),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            SheetHeader(
                title = "Amount",
                navigationIcon = Icons.Outlined.Close,
                navigationContentDescription = "Close",
                onNavigationClick = onDismiss,
            )
            Spacer(Modifier.weight(1f))
            AmountEntryHero(
                entryRaw = amount,
                isSat = isSat,
                unit = unit,
                useBitcoinSymbol = useBitcoinSymbol,
                formatter = formatter,
            )
            Spacer(Modifier.weight(1f))
            NumberPadFooter(
                amount = amount,
                onAmountChange = { amount = it },
                decimals = decimals,
                buttonText = "Done",
                onButtonClick = { onDone(UnitAmountEntry.baseUnits(amount, decimals).takeIf { it > 0 }) },
            )
        }
    }
}

/** Full-screen shared receipt for a payment that lands while the request is open. */
@Composable
internal fun CashuRequestSuccessTerminal(
    amountLabel: String?,
    mintName: String?,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    PaymentStatusScreen(
        modifier = modifier,
        phase = PaymentStatusPhase.Success,
        title = "Payment Received!",
        onDone = onDone,
        rows = {
            CashuRequestReceiptRows(amountLabel = amountLabel, mintName = mintName)
        },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CashuRequestDetailTopBar(
    title: String,
    onClose: () -> Unit,
    onShare: (() -> Unit)?,
) {
    CenterAlignedTopAppBar(
        title = {
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
            )
        },
        navigationIcon = {
            IconButton(onClick = onClose) {
                ToolbarIcon(
                    imageVector = Icons.Outlined.Close,
                    contentDescription = "Close",
                )
            }
        },
        actions = {
            if (onShare != null) {
                IconButton(onClick = onShare) {
                    ToolbarIcon(Icons.Outlined.IosShare, contentDescription = "Share")
                }
            }
        },
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = MaterialTheme.colorScheme.background,
        ),
    )
}

@Composable
internal fun ColumnScope.CashuRequestReceiptRows(
    amountLabel: String?,
    mintName: String?,
) {
    if (amountLabel != null) {
        InspectorRow(
            label = "Amount",
            value = amountLabel,
            leadingIcon = Icons.Outlined.Payments,
            valueMonospaced = true,
        )
    }
    if (mintName != null) {
        InspectorRow(
            label = "Mint",
            value = mintName,
            leadingIcon = Icons.Outlined.AccountBalance,
        )
    }
}

/**
 * Returns the newest payment that was not present in the last observed snapshot.
 * A null snapshot means the request has just opened, so its payments establish
 * the baseline and must not replay an old success terminal.
 */
internal fun newestUnseenPayment(
    observedPaymentIds: Collection<String>?,
    currentPayments: List<CashuRequestPayment>,
): CashuRequestPayment? = observedPaymentIds?.let { observed ->
    currentPayments.lastOrNull { it.transactionId !in observed }
}
