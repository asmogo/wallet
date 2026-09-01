package com.cashu.me.ui.receive

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.CurrencyBitcoin
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Repeat
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.CashuRequestStore
import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry
import com.cashu.me.Core.OnchainExplorer
import com.cashu.me.Core.OnchainPaymentObservation
import com.cashu.me.Core.PriceService
import com.cashu.me.Core.ReceiveConfirmationOwner
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.Wallet.userFacingWalletMessage
import com.cashu.me.Core.WalletManager
import com.cashu.me.Core.mintQuoteDisplayExpiry
import com.cashu.me.Core.quoteExpiryText
import com.cashu.me.Core.shouldPollMintQuote
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.Models.MintQuoteState
import com.cashu.me.Models.PaymentMethodKind
import com.cashu.me.ui.components.AmountEntryHero
import com.cashu.me.ui.components.AmountFlipDisplay
import com.cashu.me.ui.components.AmountText
import com.cashu.me.ui.components.ExplorerLinkRow
import com.cashu.me.ui.components.FlowSheetTitle
import com.cashu.me.ui.components.IconSwap
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.InspectorRow
import com.cashu.me.ui.components.LocalConfirmationToastController
import com.cashu.me.ui.components.MintPickerSheet
import com.cashu.me.ui.components.MintSelectorDirection
import com.cashu.me.ui.components.MintSelectorRow
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.NumberPadFooter
import com.cashu.me.ui.components.PaymentStatusPhase
import com.cashu.me.ui.components.PaymentStatusScreen
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.QrCard
import com.cashu.me.ui.components.SheetHeader
import com.cashu.me.ui.components.TwoFaceScreen
import com.cashu.me.ui.components.UnitPickerSheet
import com.cashu.me.ui.components.WaitingForPaymentRow
import com.cashu.me.ui.components.neutralActionButtonColors
import com.cashu.me.ui.components.openInBrowser
import com.cashu.me.ui.components.shareText
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.theme.CapsuleShape
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withMonoDigits
import com.cashu.me.ui.testing.UiTestTags

private sealed interface ReceiveLnFace {
    data object Input : ReceiveLnFace
    data class Display(val quote: MintQuoteInfo) : ReceiveLnFace
    data class Failure(
        val title: String,
        val detail: String,
        val retry: Retry,
    ) : ReceiveLnFace

    data class Retry(
        val method: PaymentMethodKind,
        val amountless: Boolean,
        val forceNewReusableOffer: Boolean,
        val amountOverride: Long?,
    )
}

private fun receiveRequestHeaderTitle(method: PaymentMethodKind): String = when (method) {
    PaymentMethodKind.Bolt11 -> "Lightning Invoice"
    PaymentMethodKind.Bolt12 -> "Reusable Invoice"
    PaymentMethodKind.Onchain -> "Bitcoin Address"
}

private fun receiveRequestFailureTitle(method: PaymentMethodKind): String = when (method) {
    PaymentMethodKind.Bolt11,
    PaymentMethodKind.Bolt12 -> "Couldn't Create Invoice"
    PaymentMethodKind.Onchain -> "Couldn't Create Address"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReceiveLightningScreen(
    walletManager: WalletManager,
    cashuRequestStore: CashuRequestStore,
    settingsManager: SettingsManager,
    priceService: PriceService,
    onClose: () -> Unit,
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val priceState by priceService.state.collectAsState()
    val cashuRequestState by cashuRequestStore.state.collectAsState()
    val formatter = remember { AmountFormatter() }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current

    var face: ReceiveLnFace by remember { mutableStateOf(ReceiveLnFace.Input) }
    var amount by remember { mutableStateOf("") }
    var method by remember { mutableStateOf(PaymentMethodKind.Bolt11) }
    var creating by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }
    // When a payment lands the body crossfades to the shared receipt while the
    // sheet header stays mounted, matching iOS ReceiveLightningView.
    var successInfo by remember { mutableStateOf<ReceiveSuccessInfo?>(null) }
    // On-chain quotes abandoned via "Use new address": a payment may already be
    // racing toward the old address, so keep checking them for the life of the
    // sheet (mint-status checks only — no extra explorer polling). Set
    // semantics dedupe repeated presses.
    var abandonedOnchainQuoteIds by remember { mutableStateOf(setOf<String>()) }
    var selectedReceiveUnit by remember { mutableStateOf<String?>(null) }
    var unitPickerOpen by remember { mutableStateOf(false) }
    var mintPickerOpen by remember { mutableStateOf(false) }
    var reusableAmountPickerOpen by remember { mutableStateOf(false) }
    var displayActionsOpen by remember { mutableStateOf(false) }
    var methodPickerOpen by remember { mutableStateOf(false) }

    val activeMint = walletState.activeMint
    val supportedMethods = activeMint?.supportedMintMethods?.ifEmpty { listOf(PaymentMethodKind.Bolt11) }
        ?: listOf(PaymentMethodKind.Bolt11)

    // Mint unit: NUT-04 mintable units only; on-chain always mints sat.
    val effectiveUnit = if (method == PaymentMethodKind.Onchain) {
        "sat"
    } else {
        activeMint?.resolvedMintUnit(selectedReceiveUnit) ?: "sat"
    }
    val currency = CurrencyRegistry.currencyForMintUnit(effectiveUnit)
    val isSatUnit = effectiveUnit.equals("sat", ignoreCase = true)
    val amountEntryContext = ReceiveAmountEntry.context(
        quoteUnit = effectiveUnit,
        mintUnitDecimals = currency.decimals,
        preferredPrimary = settings.amountDisplayPrimary,
        btcPrice = priceState.btcPrice,
    )
    var previousAmountEntryContext by remember { mutableStateOf(amountEntryContext) }
    val amountValidation = ReceiveAmountEntry.validation(amount, amountEntryContext)
    val showsUnitSelector = activeMint?.supportsMultipleMintUnits == true &&
        method != PaymentMethodKind.Onchain

    fun persistReusableOffer(quote: MintQuoteInfo) {
        if (quote.paymentMethod != PaymentMethodKind.Bolt12) return
        cashuRequestStore.upsertQuoteIntent(
            quoteId = quote.id,
            quoteKind = "bolt12",
            // CDK reports the latest payment as the quote amount after it has
            // been paid. Keep the intent amountless so History continues to
            // represent this as an "Any" reusable invoice.
            amount = quote.amount.takeUnless { quote.isAmountless },
            unit = quote.unit,
            mints = listOfNotNull(quote.mintUrl ?: activeMint?.url),
            encoded = quote.request,
        )
    }

    fun createMintRequest(
        requestMethod: PaymentMethodKind,
        amountless: Boolean,
        forceNewReusableOffer: Boolean = false,
        amountOverride: Long? = null,
    ) {
        val explicit = amountOverride?.takeIf { it > 0L }
            ?: ReceiveAmountEntry.quoteAmount(
                raw = amount,
                context = amountEntryContext,
                amountless = false,
            )
        if (!amountless && requestMethod.requiresMintAmount && explicit == null) {
            errorText = "Enter an amount."
            return
        }
        if (activeMint == null) {
            errorText = "Add a mint first."
            return
        }
        // After validation, amountless rails mint with a null amount; everything
        // else uses the typed base units.
        val requestAmount = if (amountless) null else explicit
        creating = true
        errorText = null
        scope.launch {
            try {
                val requestUnit = if (requestMethod == PaymentMethodKind.Onchain) {
                    "sat"
                } else {
                    amountEntryContext.quoteUnit
                }
                val quote = if (
                    requestMethod == PaymentMethodKind.Bolt12 &&
                    amountless &&
                    !forceNewReusableOffer
                ) {
                    walletManager.existingAmountlessBolt12Offer(unit = requestUnit)
                        ?: walletManager.createMintQuote(
                            amount = null,
                            method = requestMethod,
                            unit = requestUnit,
                        )
                } else {
                    walletManager.createMintQuote(
                        amount = requestAmount,
                        method = requestMethod,
                        unit = requestUnit,
                    )
                }
                face = ReceiveLnFace.Display(quote)
            } catch (t: Throwable) {
                face = ReceiveLnFace.Failure(
                    title = receiveRequestFailureTitle(requestMethod),
                    detail = t.userFacingWalletMessage,
                    retry = ReceiveLnFace.Retry(
                        method = requestMethod,
                        amountless = amountless,
                        forceNewReusableOffer = forceNewReusableOffer,
                        amountOverride = amountOverride,
                    ),
                )
            } finally {
                creating = false
            }
        }
    }

    fun createNewReusableInvoice() {
        method = PaymentMethodKind.Bolt12
        amount = ""
        errorText = null
        createMintRequest(
            requestMethod = PaymentMethodKind.Bolt12,
            amountless = true,
            forceNewReusableOffer = true,
        )
    }

    /**
     * Fresh deposit address from the overflow menu (BOLT12 "new invoice"
     * parity). Remembers the outgoing quote first — a payment may already be
     * racing toward it (screen-scoped watcher keeps checking it). The header
     * can't see the Display block's live quote; the face quote is safe here
     * because an Issued quote can't still be on screen (the success terminal
     * takes over).
     */
    fun createNewOnchainAddress() {
        val quote = (face as? ReceiveLnFace.Display)?.quote
        if (quote != null && quote.paymentMethod == PaymentMethodKind.Onchain &&
            quote.state != MintQuoteState.Issued && !quote.isExpired
        ) {
            abandonedOnchainQuoteIds = abandonedOnchainQuoteIds + quote.id
        }
        createMintRequest(PaymentMethodKind.Onchain, amountless = true)
    }

    /**
     * Re-mints the reusable BOLT12 offer at a new amount (iOS
     * `setReusableOfferAmount`). null / 0 → amountless (reuse existing offer);
     * positive → a fresh fixed-amount offer.
     */
    fun setReusableOfferAmount(nextAmount: Long?) {
        method = PaymentMethodKind.Bolt12
        errorText = null
        if (nextAmount == null || nextAmount <= 0L) {
            amount = ""
            createMintRequest(
                requestMethod = PaymentMethodKind.Bolt12,
                amountless = true,
                forceNewReusableOffer = false,
            )
        } else {
            val quoteUnit = (face as? ReceiveLnFace.Display)?.quote?.unit ?: effectiveUnit
            val decimals = CurrencyRegistry.currencyForMintUnit(quoteUnit).decimals
            val nextContext = ReceiveAmountEntry.context(
                quoteUnit = quoteUnit,
                mintUnitDecimals = decimals,
                preferredPrimary = settings.amountDisplayPrimary,
                btcPrice = priceState.btcPrice,
            )
            amount = ReceiveAmountEntry.rawForBaseUnits(nextAmount, nextContext)
            createMintRequest(
                requestMethod = PaymentMethodKind.Bolt12,
                amountless = false,
                amountOverride = nextAmount,
            )
        }
    }

    /**
     * Translate a picked method into state + side effects. Amountless rails
     * (reusable BOLT12, on-chain) skip the keypad and create immediately —
     * iOS applyMethodOption / loadOrCreateAmountlessOffer parity.
     */
    fun applyMethodOption(kind: PaymentMethodKind) {
        method = kind
        amount = ""
        errorText = null
        if (!kind.requiresMintAmount) {
            createMintRequest(requestMethod = kind, amountless = true)
        }
    }

    LaunchedEffect(activeMint) {
        selectedReceiveUnit = null
        if (method !in supportedMethods) {
            val fallback = supportedMethods.first()
            // BOLT12-only (or on-chain-only) mints must land on the amountless
            // path, not a keypad that can't create without an amount.
            applyMethodOption(fallback)
        }
    }

    // Preserve the represented sat amount if a cached price becomes available
    // or the persisted primary setting changes while this screen is open.
    LaunchedEffect(amountEntryContext) {
        amount = ReceiveAmountEntry.convert(
            raw = amount,
            from = previousAmountEntryContext,
            to = amountEntryContext,
        )
        previousAmountEntryContext = amountEntryContext
    }

// Dismissal contract: system back = swipe = abandon to the wallet — the
    // sheet handles it at every face. Waiting for an invoice to be paid is a
    // freely-dismissible phase: the global pending-quote sweep and quote-keyed
    // monitors credit a later payment, surfaced via the home delta/History.
    // The header chevron owns the internal Display → Input step-back.
    // Failure terminal uses the header close affordance (and Try Again).

    // Abandoned-quote watcher: every quote-keyed monitor re-keys to the
    // replacement after "Use new address", so this screen-scoped loop is what
    // keeps checking the old address(es). refreshPendingMintQuote returns
    // whether tokens were actually minted — on-chain quotes can sit Pending
    // until a mint attempt succeeds, so the Boolean (not the quote state) is
    // the reliable signal. Keyed on isNotEmpty so the first pass runs
    // immediately after the first tap (a quote already paid at tap time mints
    // on the first tick). Dies with the sheet; the global pending-quote sweep
    // remains the fallback after that.
    LaunchedEffect(abandonedOnchainQuoteIds.isNotEmpty()) {
        while (abandonedOnchainQuoteIds.isNotEmpty() && successInfo == null) {
            for (quoteId in abandonedOnchainQuoteIds) {
                val info = runCatching { walletManager.pollMintQuote(quoteId) }.getOrNull()
                // Drop quotes that expired before the mint saw any deposit; a
                // funded-but-expired quote keeps being checked.
                if (info != null && info.isExpired &&
                    info.state == MintQuoteState.Unpaid &&
                    (info.amount ?: 0L) == 0L && info.amountPaid == 0L
                ) {
                    abandonedOnchainQuoteIds = abandonedOnchainQuoteIds - quoteId
                    continue
                }
                val minted = runCatching {
                    walletManager.refreshPendingMintQuote(
                        quoteId,
                        confirmationOwner = ReceiveConfirmationOwner.InFlow,
                    )
                }
                    .getOrDefault(false)
                if (!minted) continue
                abandonedOnchainQuoteIds = abandonedOnchainQuoteIds - quoteId
                // Refetch for the credited amount (on-chain always mints sat).
                val refreshed = runCatching { walletManager.pollMintQuote(quoteId) }.getOrNull() ?: info
                val paidAmount = refreshed?.amount
                    ?: refreshed?.amountIssued?.takeIf { it > 0 }
                    ?: refreshed?.amountPaid?.takeIf { it > 0 }
                successInfo = ReceiveSuccessInfo(
                    amountLabel = paidAmount?.let {
                        formatter.formatWalletSats(it, settings.useBitcoinSymbol)
                    },
                    mintName = walletState.mints.firstOrNull { it.url == refreshed?.mintUrl }?.name
                        ?: walletState.activeMint?.name,
                    method = refreshed?.paymentMethod ?: PaymentMethodKind.Onchain,
                )
                return@LaunchedEffect // terminal owns the sheet now
            }
            delay(30_000)
        }
    }

    // The paid terminal replaces the sheet body while retaining the same header
    // and explicit Done action as iOS. Standard swap pair (not a bare
    // Crossfade, whose slower symmetric tween buried the terminal's staged
    // celebration): the waiting face exits fast, the terminal fades in and
    // its own entrance stages the check → title → rows.
    AnimatedContent(
        targetState = successInfo,
        transitionSpec = { fadeIn(tween(200)) togetherWith fadeOut(tween(150)) },
        contentKey = { it != null },
        label = "receive-ln-terminal",
    ) { terminal ->
      if (terminal != null) {
        Column(
            modifier = Modifier
                .fillMaxHeight()
                .testTag(UiTestTags.ReceiveLightningScreen),
        ) {
            SheetHeader(
                title = receiveRequestHeaderTitle(terminal.method),
                navigationIcon = Icons.Outlined.Close,
                navigationContentDescription = "Close",
                onNavigationClick = onClose,
            )
            ReceiveSuccessTerminal(
                info = terminal,
                onDone = onClose,
                modifier = Modifier.weight(1f),
            )
        }
      } else {
        Column(
            modifier = Modifier
                .fillMaxHeight()
                .testTag(UiTestTags.ReceiveLightningScreen),
        ) {
        SheetHeader(
            title = when (val current = face) {
                ReceiveLnFace.Input -> "Receive"
                is ReceiveLnFace.Display -> receiveRequestHeaderTitle(current.quote.paymentMethod)
                is ReceiveLnFace.Failure -> receiveRequestHeaderTitle(current.retry.method)
            },
            // Input: close X (same as Receive Ecash / Cashu Request). Display:
            // back chevron returns to the amount pad.
            navigationIcon = when (face) {
                ReceiveLnFace.Input -> Icons.Outlined.Close
                is ReceiveLnFace.Display -> Icons.AutoMirrored.Outlined.ArrowBack
                is ReceiveLnFace.Failure -> Icons.Outlined.Close
            },
            navigationContentDescription = when (face) {
                ReceiveLnFace.Input -> "Close"
                is ReceiveLnFace.Display -> "Back"
                is ReceiveLnFace.Failure -> "Close"
            },
            onNavigationClick = when (face) {
                ReceiveLnFace.Input -> onClose
                is ReceiveLnFace.Display -> { { face = ReceiveLnFace.Input } }
                is ReceiveLnFace.Failure -> onClose
            },
            actions = {
                val current = face
                if (current is ReceiveLnFace.Display) {
                    val menuMethod = current.quote.paymentMethod
                    if (menuMethod == PaymentMethodKind.Bolt12 ||
                        menuMethod == PaymentMethodKind.Onchain
                    ) {
                        // Overflow menu keeps share + new-artifact secondary —
                        // quieter than a prominent Share / New pair (iOS still
                        // uses ShareLink; Android folds both into ⋮). On-chain
                        // mirrors BOLT12 with a fresh deposit address.
                        val isOnchainMenu = menuMethod == PaymentMethodKind.Onchain
                        IconButton(onClick = { displayActionsOpen = true }) {
                            ToolbarIcon(Icons.Filled.MoreVert, contentDescription = "More options")
                        }
                        DropdownMenu(
                            expanded = displayActionsOpen,
                            onDismissRequest = { displayActionsOpen = false },
                            shape = MaterialTheme.shapes.large,
                        ) {
                            DropdownMenuItem(
                                text = { Text("Share") },
                                leadingIcon = {
                                    Icon(Icons.Outlined.IosShare, contentDescription = null)
                                },
                                onClick = {
                                    displayActionsOpen = false
                                    context.shareText(
                                        current.quote.request,
                                        subject = if (isOnchainMenu) "Bitcoin Address" else "Reusable Invoice",
                                    )
                                },
                            )
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        when {
                                            creating -> "Creating…"
                                            isOnchainMenu -> "New address"
                                            else -> "New reusable invoice"
                                        },
                                    )
                                },
                                leadingIcon = {
                                    Icon(
                                        if (isOnchainMenu) Icons.Outlined.Refresh else Icons.Outlined.Repeat,
                                        contentDescription = null,
                                    )
                                },
                                enabled = !creating,
                                onClick = {
                                    displayActionsOpen = false
                                    if (isOnchainMenu) {
                                        createNewOnchainAddress()
                                    } else {
                                        createNewReusableInvoice()
                                    }
                                },
                            )
                        }
                    } else {
                        IconButton(onClick = {
                            context.shareText(current.quote.request, subject = "Payment request")
                        }) {
                            ToolbarIcon(Icons.Outlined.IosShare, contentDescription = "Share")
                        }
                    }
                } else if (current is ReceiveLnFace.Input) {
                    // Method picker rides the header (iOS parity): an icon
                    // opening a bottom sheet, shown only when >1 method exists.
                    if (supportedMethods.size > 1) {
                        IconButton(onClick = { methodPickerOpen = true }) {
                            // Animated glyph replacement on method switch
                            // (iOS .contentTransition(.symbolEffect(.replace))).
                            IconSwap(
                                icon = method.menuIcon,
                                contentDescription = "Receive method: ${method.friendlyTitle}, ${method.friendlyDescriptor}",
                                iconSize = CashuTheme.iconSizes.toolbar,
                            )
                        }
                    }
                    if (showsUnitSelector) {
                        androidx.compose.material3.TextButton(onClick = { unitPickerOpen = true }) {
                            Text(
                                text = effectiveUnit.uppercase(),
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                        }
                    }
                }
            },
        )
        TwoFaceScreen(
            targetState = face,
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            // Display → Display (fresh on-chain address) also slides forward.
            forward = { _, target ->
                target is ReceiveLnFace.Display || target is ReceiveLnFace.Failure
            },
            label = "receive-lightning-face",
        ) { current ->
            when (current) {
                ReceiveLnFace.Input -> {
                    // Amountless rails auto-create (BOLT12 reusable / on-chain).
                    // iOS shows a dedicated "Creating…" overlay instead of the
                    // keypad while that request is in flight.
                    if (creating && !method.requiresMintAmount) {
                        CreatingOverlay(method = method)
                    } else {
                        InputFace(
                            amount = amount,
                            onAmountChange = { amount = it; errorText = null },
                            selectedMethod = method,
                            creating = creating,
                            mint = activeMint,
                            mintBalanceText = activeMint?.let {
                                formatter.formatWalletSats(it.balance, settings.useBitcoinSymbol)
                            },
                            // One mint means nothing to choose between, so the
                            // row drops its chevron and stops opening a picker.
                            onPickMint = { mintPickerOpen = true }
                                .takeIf { walletState.mints.size > 1 },
                            isSatUnit = isSatUnit,
                            unit = effectiveUnit,
                            amountSats = ReceiveAmountEntry.amountBaseUnits(amount, amountEntryContext),
                            entryPrimary = amountEntryContext.bitcoin.primary,
                            onFlipEntryPrimary = { next ->
                                settingsManager.setAmountDisplayPrimary(next.rawValue)
                            },
                            btcPrice = priceState.btcPrice.takeIf { it > 0 },
                            fiatCurrencyCode = priceState.currencyCode,
                            useBitcoinSymbol = settings.useBitcoinSymbol,
                            formatter = formatter,
                            decimals = amountEntryContext.entryDecimals,
                            amountValid = amountValidation == ReceiveAmountValidation.Valid,
                            errorText = errorText,
                            onCreate = {
                                createMintRequest(
                                    requestMethod = method,
                                    amountless = !method.requiresMintAmount &&
                                        amountValidation == ReceiveAmountValidation.Empty,
                                )
                            },
                        )
                    }
                }

                is ReceiveLnFace.Display -> {
                    var liveQuote by remember(current.quote.id) { mutableStateOf(current.quote) }
                    LaunchedEffect(current.quote.id) {
                        persistReusableOffer(current.quote)
                    }
                    // Websocket push is a preference-gated accelerator; the
                    // polling loop below is the always-on fallback that also
                    // covers a dead subscription (iOS ReceiveLightningView
                    // parity).
                    LaunchedEffect(current.quote.id, settings.useWebsockets) {
                        if (!settings.useWebsockets) return@LaunchedEffect
                        walletManager.subscribeToMintQuote(current.quote.id)
                            .catch { /* swallow; polling below is the fallback */ }
                            .collectLatest { liveQuote = it }
                    }
                    LaunchedEffect(current.quote.id) {
                        // iOS pollMintQuote parity: linear backoff (+1s per
                        // iteration up to the max), terminal-state/expiry aware
                        // via shouldPollMintQuote. Per-rail intervals:
                        // BOLT11 5s→15s, BOLT12 10s→30s, on-chain flat 30s.
                        val (initialMs, maxMs) = when (current.quote.paymentMethod) {
                            PaymentMethodKind.Bolt11 -> 5_000L to 15_000L
                            PaymentMethodKind.Bolt12 -> 10_000L to 30_000L
                            PaymentMethodKind.Onchain -> 30_000L to 30_000L
                        }
                        var intervalMs = initialMs
                        while (true) {
                            delay(intervalMs)
                            val refreshed = runCatching { walletManager.pollMintQuote(current.quote.id) }
                                .getOrNull()
                                ?: continue // transient failure — keep monitoring
                            liveQuote = refreshed
                            // Reusable BOLT12 offers stay open after each
                            // payment (the mint never marks them terminally
                            // paid), so keep polling for the next one.
                            val keepPolling = refreshed.paymentMethod == PaymentMethodKind.Bolt12 ||
                                shouldPollMintQuote(
                                    state = refreshed.state,
                                    expiryEpochSeconds = refreshed.expiryEpochSeconds,
                                    nowEpochSeconds = System.currentTimeMillis() / 1000,
                                )
                            if (!keepPolling) break
                            if (intervalMs < maxMs) intervalMs = minOf(intervalMs + 1_000, maxMs)
                        }
                    }
                    // On-chain: watch the address on the block explorer so the
                    // status line can report mempool/confirmation progress before
                    // the mint credits the deposit, and nudge a mint attempt while
                    // the quote is still un-issued (iOS refreshOnchainObservation
                    // + mintQuoteIfReady parity). 30s cadence matches iOS and is
                    // polite to the third-party explorer API.
                    var onchainObservation by remember(current.quote.id) {
                        mutableStateOf<OnchainPaymentObservation?>(null)
                    }
                    val quoteCreatedAtMillis = remember(current.quote.id) { System.currentTimeMillis() }
                    LaunchedEffect(current.quote.id) {
                        if (current.quote.paymentMethod != PaymentMethodKind.Onchain) return@LaunchedEffect
                        while (true) {
                            val quote = liveQuote
                            // CDK reports the deposited amount on the quote once the
                            // mint sees the payment; observing before that would
                            // match any dust against an expectedAmount of zero.
                            val expectedAmount = quote.amount ?: 0L
                            val unissued = quote.state != MintQuoteState.Paid &&
                                quote.state != MintQuoteState.Issued
                            if (unissued && expectedAmount > 0) {
                                onchainObservation = OnchainExplorer.observePayment(
                                    address = quote.request,
                                    mintUrl = quote.mintUrl ?: activeMint?.url,
                                    expectedAmount = expectedAmount,
                                    createdAfterEpochMillis = quoteCreatedAtMillis,
                                )
                                // Mint on the wallet's app-lifetime scope so a
                                // dismissal never cancels a mint mid-flight.
                                walletManager.launch {
                                    runCatching {
                                        walletManager.refreshPendingMintQuote(
                                            quote.id,
                                            confirmationOwner = ReceiveConfirmationOwner.InFlow,
                                        )
                                    }
                                }
                            }
                            delay(30_000)
                        }
                    }
                    val amountLabel = liveQuote.amount?.let {
                        if (liveQuote.unit.equals("sat", ignoreCase = true)) {
                            formatter.formatWalletSats(it, settings.useBitcoinSymbol)
                        } else {
                            CurrencyAmount(
                                it,
                                CurrencyRegistry.currencyForMintUnit(liveQuote.unit),
                            ).formatted()
                        }
                    }
                    val receivedAmountLabel = liveQuote.amountPaid
                        .takeIf { it > 0 }
                        ?.let { paid ->
                            if (liveQuote.unit.equals("sat", ignoreCase = true)) {
                                formatter.formatWalletSats(paid, settings.useBitcoinSymbol)
                            } else {
                                CurrencyAmount(
                                    paid,
                                    CurrencyRegistry.currencyForMintUnit(liveQuote.unit),
                                ).formatted()
                            }
                        }
                    LaunchedEffect(
                        liveQuote.id,
                        liveQuote.state,
                        liveQuote.amountPaid,
                        liveQuote.amountIssued,
                    ) {
                        if (liveQuote.paymentMethod == PaymentMethodKind.Bolt12) {
                            // Reusable offers never reach the one-shot success
                            // terminal. The synchronizer mints a newly-paid
                            // amount when needed and always reloads History,
                            // including the already-issued case. Keep the QR on
                            // screen to accept the next payment.
                            if (liveQuote.amountPaid > 0 ||
                                liveQuote.state == MintQuoteState.Paid ||
                                liveQuote.state == MintQuoteState.Issued
                            ) {
                                walletManager.launch {
                                    runCatching {
                                        walletManager.refreshPendingMintQuote(
                                            liveQuote.id,
                                            confirmationOwner = ReceiveConfirmationOwner.InFlow,
                                        )
                                    }
                                }
                            }
                            return@LaunchedEffect
                        }
                        if (liveQuote.state == MintQuoteState.Paid ||
                            liveQuote.state == MintQuoteState.Issued
                        ) {
                            // Finish the UX immediately and mint on the wallet's
                            // app-lifetime scope so the dismiss never cancels it
                            // (iOS: unstructured task that outlives the sheet).
                            walletManager.launch {
                                runCatching {
                                    walletManager.mintTokens(
                                        quoteId = liveQuote.id,
                                        unit = liveQuote.unit,
                                        confirmationOwner = ReceiveConfirmationOwner.InFlow,
                                    )
                                }
                            }
                            successInfo = ReceiveSuccessInfo(
                                amountLabel = amountLabel,
                                mintName = activeMint?.name,
                                method = liveQuote.paymentMethod,
                            )
                        }
                    }
                    val isOnchain = liveQuote.paymentMethod == PaymentMethodKind.Onchain
                    val observation = onchainObservation
                    val explorerUrl = if (isOnchain) {
                        val explorerMintUrl = liveQuote.mintUrl ?: activeMint?.url
                        observation?.txid?.let {
                            OnchainExplorer.transactionWebUrl(
                                txid = it,
                                address = liveQuote.request,
                                mintUrl = explorerMintUrl,
                            )
                        } ?: OnchainExplorer.addressWebUrl(
                            address = liveQuote.request,
                            mintUrl = explorerMintUrl,
                        )
                    } else {
                        null
                    }
                    DisplayFace(
                        quote = liveQuote,
                        amountLabel = amountLabel.takeUnless {
                            liveQuote.paymentMethod == PaymentMethodKind.Bolt12 && liveQuote.isAmountless
                        },
                        receivedAmountLabel = receivedAmountLabel,
                        mintName = activeMint?.name,
                        createdAtEpochMillis = cashuRequestState.requests
                            .firstOrNull { it.quoteId == liveQuote.id }
                            ?.createdAtEpochMillis,
                        errorText = errorText,
                        amountPrimary = AmountDisplayPrimary.fromRaw(settings.amountDisplayPrimary),
                        onFlipAmountPrimary = {
                            settingsManager.setAmountDisplayPrimary(it.rawValue)
                        },
                        fiatPrice = if (settings.showFiatBalance) {
                            priceState.btcPrice.takeIf { it > 0 }
                        } else {
                            null
                        },
                        fiatCurrencyCode = settings.bitcoinPriceCurrency,
                        useBitcoinSymbol = settings.useBitcoinSymbol,
                        pendingStatusText = when {
                            !isOnchain -> "Waiting for payment…"
                            observation != null -> "${observation.statusText}. Trying to mint…"
                            else -> "Waiting for on-chain payment…"
                        },
                        explorerLabel = if (observation == null) {
                            "View address in block explorer"
                        } else {
                            "View transaction in block explorer"
                        },
                        onCopy = { clipboard.setText(AnnotatedString(liveQuote.request)) },
                        onEditReusableAmount = if (
                            liveQuote.paymentMethod == PaymentMethodKind.Bolt12
                        ) {
                            { reusableAmountPickerOpen = true }
                        } else {
                            null
                        },
                        onOpenExplorer = explorerUrl?.let { url -> { context.openInBrowser(url) } },
                    )
                }

                is ReceiveLnFace.Failure -> PaymentStatusScreen(
                    phase = PaymentStatusPhase.Failure,
                    title = current.title,
                    detail = current.detail,
                    doneLabel = "Try Again",
                    onDone = {
                        val retry = current.retry
                        face = ReceiveLnFace.Input
                        createMintRequest(
                            requestMethod = retry.method,
                            amountless = retry.amountless,
                            forceNewReusableOffer = retry.forceNewReusableOffer,
                            amountOverride = retry.amountOverride,
                        )
                    },
                )
            }
        }
      }
    }
    }

    if (mintPickerOpen) {
        MintPickerSheet(
            mints = walletState.mints,
            activeMintUrl = activeMint?.url,
            onSelect = { mint ->
                mint?.let { scope.launch { walletManager.setActiveMint(it) } }
                amount = ""
                errorText = null
                mintPickerOpen = false
            },
            onDismiss = { mintPickerOpen = false },
        )
    }

    if (unitPickerOpen) {
        UnitPickerSheet(
            units = activeMint?.effectiveMintUnits ?: listOf("sat"),
            selectedUnit = effectiveUnit,
            onSelect = {
                selectedReceiveUnit = it
                amount = ""
                errorText = null
                unitPickerOpen = false
            },
            onDismiss = { unitPickerOpen = false },
        )
    }

    if (methodPickerOpen) {
        ReceiveMethodPickerSheet(
            methods = supportedMethods,
            selectedMethod = method,
            onSelect = { kind ->
                methodPickerOpen = false
                applyMethodOption(kind)
            },
            onDismiss = { methodPickerOpen = false },
        )
    }

    val displayQuote = (face as? ReceiveLnFace.Display)?.quote
    if (reusableAmountPickerOpen && displayQuote?.paymentMethod == PaymentMethodKind.Bolt12) {
        val quoteUnit = displayQuote.unit
        val isSat = quoteUnit.equals("sat", ignoreCase = true)
        val quoteCurrency = CurrencyRegistry.currencyForMintUnit(quoteUnit)
        val editEntryContext = ReceiveAmountEntry.context(
            quoteUnit = quoteUnit,
            mintUnitDecimals = quoteCurrency.decimals,
            preferredPrimary = settings.amountDisplayPrimary,
            btcPrice = priceState.btcPrice,
        )
        ReusableAmountEditSheet(
            initialAmount = displayQuote.amount.takeUnless { displayQuote.isAmountless },
            isSat = isSat,
            unit = quoteUnit,
            entryContext = editEntryContext,
            fiatCurrencyCode = priceState.currencyCode,
            btcPrice = priceState.btcPrice.takeIf { it > 0 },
            useBitcoinSymbol = settings.useBitcoinSymbol,
            formatter = formatter,
            onFlipEntryPrimary = { next ->
                settingsManager.setAmountDisplayPrimary(next.rawValue)
            },
            onDone = { next ->
                reusableAmountPickerOpen = false
                setReusableOfferAmount(next)
            },
            onDismiss = { reusableAmountPickerOpen = false },
        )
    }
}

/** iOS creatingOverlay parity for amountless BOLT12 / on-chain auto-create. */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun CreatingOverlay(method: PaymentMethodKind) {
    val label = if (method == PaymentMethodKind.Onchain) {
        "Generating address"
    } else {
        "Creating reusable invoice"
    }
    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        LoadingIndicator(modifier = Modifier.size(48.dp))
        Spacer(Modifier.height(CashuTheme.spacing.comfortable))
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * First face, in the iOS element order: mint selector row (top) → amount hero
 * (with an ON-CHAIN badge for on-chain) → error → number pad → create CTA. The
 * method picker lives in the top bar, not on the canvas.
 */
@Composable
private fun InputFace(
    amount: String,
    onAmountChange: (String) -> Unit,
    selectedMethod: PaymentMethodKind,
    creating: Boolean,
    mint: MintInfo?,
    mintBalanceText: String?,
    onPickMint: (() -> Unit)?,
    isSatUnit: Boolean,
    unit: String,
    amountSats: Long,
    entryPrimary: AmountDisplayPrimary,
    onFlipEntryPrimary: (AmountDisplayPrimary) -> Unit,
    btcPrice: Double?,
    fiatCurrencyCode: String,
    useBitcoinSymbol: Boolean,
    formatter: AmountFormatter,
    decimals: Int,
    amountValid: Boolean,
    errorText: String?,
    onCreate: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = CashuTheme.spacing.comfortable)
            .imePadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(CashuTheme.spacing.default))
        Spacer(Modifier.weight(1f))
        if (selectedMethod == PaymentMethodKind.Onchain) {
            Text(
                text = "ON-CHAIN",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .background(
                        color = MaterialTheme.colorScheme.surfaceContainerHigh,
                        shape = CapsuleShape,
                    )
                    .padding(
                        horizontal = CashuTheme.spacing.default,
                        vertical = CashuTheme.spacing.micro,
                    ),
            )
            Spacer(Modifier.height(CashuTheme.spacing.snug))
        }
        // Sat mint unit: iOS CurrencyAmountDisplay entry mode — preferred unit
        // leads, mint-unit (sats) stays visible/flipable. Non-sat mint units
        // stay native with no BTC-price conversion.
        if (isSatUnit) {
            AmountFlipDisplay(
                amountSats = amountSats,
                primary = entryPrimary,
                onFlip = onFlipEntryPrimary,
                btcPrice = btcPrice,
                currencyCode = fiatCurrencyCode,
                useBitcoinSymbol = useBitcoinSymbol,
                entryRaw = amount,
                primaryAccessibilityPrefix = "Request amount",
            )
        } else {
            AmountEntryHero(
                entryRaw = amount,
                isSat = false,
                unit = unit,
                useBitcoinSymbol = useBitcoinSymbol,
                formatter = formatter,
            )
        }
        if (errorText != null) {
            Spacer(Modifier.height(CashuTheme.spacing.default))
            InlineNotice(text = errorText, severity = NoticeSeverity.Error)
        }
        Spacer(Modifier.weight(1f))
        // Under the amount, over the keypad — the same slot the send flows use.
        if (mint != null) {
            MintSelectorRow(
                direction = MintSelectorDirection.Destination,
                mint = mint,
                balanceText = mintBalanceText,
                showBalance = true,
                onPickMint = onPickMint,
            )
            Spacer(Modifier.height(CashuTheme.spacing.snug))
        }
        NumberPadFooter(
            amount = amount,
            onAmountChange = onAmountChange,
            decimals = decimals,
            buttonText = if (creating) "Creating…" else selectedMethod.createActionTitle,
            onButtonClick = onCreate,
            buttonEnabled = !creating && (!selectedMethod.requiresMintAmount || amountValid),
            buttonLoading = creating,
        )
    }
}

private val PaymentMethodKind.menuIcon
    get() = when (this) {
        PaymentMethodKind.Bolt11 -> Icons.Outlined.Bolt
        PaymentMethodKind.Bolt12 -> Icons.Outlined.Repeat
        PaymentMethodKind.Onchain -> Icons.Outlined.CurrencyBitcoin
    }

private val PaymentMethodKind.copyActionTitle: String
    get() = when (this) {
        PaymentMethodKind.Bolt11 -> "Copy invoice"
        PaymentMethodKind.Bolt12 -> "Copy invoice"
        PaymentMethodKind.Onchain -> "Copy address"
    }

@Composable
private fun DisplayFace(
    quote: MintQuoteInfo,
    amountLabel: String?,
    receivedAmountLabel: String?,
    mintName: String?,
    createdAtEpochMillis: Long?,
    errorText: String?,
    amountPrimary: AmountDisplayPrimary,
    onFlipAmountPrimary: (AmountDisplayPrimary) -> Unit,
    fiatPrice: Double?,
    fiatCurrencyCode: String,
    useBitcoinSymbol: Boolean,
    pendingStatusText: String,
    explorerLabel: String,
    onCopy: () -> Unit,
    onEditReusableAmount: (() -> Unit)?,
    onOpenExplorer: (() -> Unit)?,
) {
    val confirmationToastController = LocalConfirmationToastController.current
    val isReusable = quote.paymentMethod == PaymentMethodKind.Bolt12
    Column(modifier = Modifier.fillMaxSize()) {
        // Scrolling content region; the copy CTA is pinned to the bottom (iOS
        // parity — the QR is the focal element, actions sit below the fold).
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
        ) {
            Spacer(Modifier.height(CashuTheme.spacing.comfortable))
            QrCard(
                content = quote.request,
                shareSubject = "Payment request",
                staticOnly = true,
                confirmationMessage = if (quote.paymentMethod == PaymentMethodKind.Onchain) {
                    "Copied Bitcoin address"
                } else {
                    "Copied payment request"
                },
            )
            if (amountLabel != null) {
                GeneratedInvoiceAmount(
                    amount = quote.amount ?: 0L,
                    amountLabel = amountLabel,
                    unit = quote.unit,
                    paymentMethod = quote.paymentMethod,
                    primary = amountPrimary,
                    onFlipPrimary = onFlipAmountPrimary,
                    btcPrice = fiatPrice,
                    currencyCode = fiatCurrencyCode,
                    useBitcoinSymbol = useBitcoinSymbol,
                )
            }
            if (isReusable) {
                ReusableOfferStatus(
                    received = receivedAmountLabel != null,
                    receivedAmountLabel = receivedAmountLabel,
                )
            } else {
                WaitingForPaymentRow(text = pendingStatusText)
            }
            errorText?.let { InlineNotice(text = it, severity = NoticeSeverity.Error) }
            if (!isReusable) {
                ExpiryCaption(expirySeconds = quote.expiryEpochSeconds)
            }
            if (isReusable) {
                // Cashu-Request-style inspector group (iOS reusableOfferDisplayView).
                Column(modifier = Modifier.fillMaxWidth()) {
                    if (mintName != null) {
                        InspectorRow(
                            label = "Mint",
                            value = mintName,
                        )
                    }
                    InspectorRow(
                        label = "Amount",
                        value = amountLabel ?: "Any",
                        valueMonospaced = amountLabel != null,
                        editable = onEditReusableAmount != null,
                        onClick = onEditReusableAmount,
                    )
                    if (createdAtEpochMillis != null) {
                        InspectorRow(
                            label = "Created",
                            value = formatReusableCreatedAt(createdAtEpochMillis),
                        )
                    }
                    if (receivedAmountLabel != null) {
                        InspectorRow(
                            label = "Total received",
                            value = receivedAmountLabel,
                            valueMonospaced = true,
                        )
                    }
                }
            } else if (mintName != null || onOpenExplorer != null) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    if (mintName != null) {
                        InspectorRow(
                            label = "Mint",
                            value = mintName,
                        )
                    }
                    if (onOpenExplorer != null) {
                        ExplorerLinkRow(label = explorerLabel, onClick = onOpenExplorer)
                    }
                }
            }
        }
        Column(
            modifier = Modifier.padding(horizontal = CashuTheme.spacing.comfortable),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
        ) {
            // Copy is a secondary convenience, not a primary action — quiet
            // neutral tonal fill (iOS gray .glassButton() parity on every rail).
            PrimaryButton(
                text = quote.paymentMethod.copyActionTitle,
                onClick = {
                    onCopy()
                    confirmationToastController?.show(
                        if (quote.paymentMethod == PaymentMethodKind.Onchain) {
                            "Copied Bitcoin address"
                        } else {
                            "Copied payment request"
                        },
                    )
                },
                colors = neutralActionButtonColors(),
            )
        }
        Spacer(Modifier.navigationBarsPadding())
    }
}

/**
 * Preferred-unit presentation for fixed Lightning requests. Amountless offers,
 * on-chain deposits, and non-sat mint units retain their rail-native display.
 */
@Composable
internal fun GeneratedInvoiceAmount(
    amount: Long,
    amountLabel: String,
    unit: String,
    paymentMethod: PaymentMethodKind,
    primary: AmountDisplayPrimary,
    onFlipPrimary: (AmountDisplayPrimary) -> Unit,
    btcPrice: Double?,
    currencyCode: String,
    useBitcoinSymbol: Boolean,
) {
    val supportsPreferredUnit = amount > 0L &&
        unit.equals("sat", ignoreCase = true) &&
        (paymentMethod == PaymentMethodKind.Bolt11 || paymentMethod == PaymentMethodKind.Bolt12)
    if (supportsPreferredUnit) {
        AmountFlipDisplay(
            amountSats = amount,
            primary = primary,
            onFlip = onFlipPrimary,
            btcPrice = btcPrice,
            currencyCode = currencyCode,
            useBitcoinSymbol = useBitcoinSymbol,
            primaryTextStyle = MaterialTheme.typography.headlineMedium
                .copy(fontWeight = FontWeight.SemiBold),
            primaryAccessibilityPrefix = when (paymentMethod) {
                PaymentMethodKind.Bolt11 -> "Invoice amount"
                PaymentMethodKind.Bolt12 -> "Offer amount"
                PaymentMethodKind.Onchain -> "Amount"
            },
        )
    } else {
        AmountText(
            text = amountLabel,
            style = MaterialTheme.typography.headlineMedium
                .copy(fontWeight = FontWeight.SemiBold)
                .withMonoDigits(),
        )
    }
}

/**
 * Status line for a reusable BOLT12 offer. Mirrors the Cashu Request status
 * block: quiet waiting pulse, then a green "Payment received!" once funds land
 * — without the old multi-line explainer that crowded the QR.
 */
@Composable
private fun ReusableOfferStatus(received: Boolean, receivedAmountLabel: String?) {
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
        label = "reusable-offer-status",
    ) { isReceived ->
        if (isReceived) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
            ) {
                Icon(
                    imageVector = Icons.Outlined.CheckCircle,
                    contentDescription = null,
                    tint = CashuTheme.colors.onReceivedContainer,
                    modifier = Modifier.size(CashuTheme.spacing.loose),
                )
                Text(
                    text = receivedAmountLabel?.let { "Received $it" } ?: "Payment received!",
                    style = MaterialTheme.typography.titleMedium,
                    color = CashuTheme.colors.onReceivedContainer,
                )
            }
        } else {
            WaitingForPaymentRow()
        }
    }
}

private fun formatReusableCreatedAt(epochMillis: Long): String =
    DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(epochMillis))

/** Amount-only edit sheet for a reusable BOLT12 offer (iOS
 *  `CashuRequestAmountPickerSheet` parity). Empty pad → "Any". */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReusableAmountEditSheet(
    initialAmount: Long?,
    isSat: Boolean,
    unit: String,
    entryContext: ReceiveAmountEntryContext,
    fiatCurrencyCode: String,
    btcPrice: Double?,
    useBitcoinSymbol: Boolean,
    formatter: AmountFormatter,
    onFlipEntryPrimary: (AmountDisplayPrimary) -> Unit,
    onDone: (Long?) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var amount by remember {
        mutableStateOf(ReceiveAmountEntry.rawForBaseUnits(initialAmount ?: 0, entryContext))
    }
    var previousEntryContext by remember { mutableStateOf(entryContext) }
    LaunchedEffect(entryContext) {
        amount = ReceiveAmountEntry.convert(amount, previousEntryContext, entryContext)
        previousEntryContext = entryContext
    }
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
            if (isSat) {
                AmountFlipDisplay(
                    amountSats = ReceiveAmountEntry.amountBaseUnits(amount, entryContext),
                    primary = entryContext.bitcoin.primary,
                    onFlip = onFlipEntryPrimary,
                    btcPrice = btcPrice,
                    currencyCode = fiatCurrencyCode,
                    useBitcoinSymbol = useBitcoinSymbol,
                    entryRaw = amount,
                    primaryAccessibilityPrefix = "Offer amount",
                )
            } else {
                AmountEntryHero(
                    entryRaw = amount,
                    isSat = false,
                    unit = unit,
                    useBitcoinSymbol = useBitcoinSymbol,
                    formatter = formatter,
                )
            }
            Spacer(Modifier.weight(1f))
            NumberPadFooter(
                amount = amount,
                onAmountChange = { amount = it },
                decimals = entryContext.entryDecimals,
                buttonText = "Done",
                onButtonClick = {
                    onDone(
                        ReceiveAmountEntry.amountBaseUnits(amount, entryContext)
                            .takeIf { it > 0L },
                    )
                },
            )
        }
    }
}

/** Receive-method chooser bottom sheet (iOS `MethodPickerSheet` / "Receive
 *  with" parity) — replaces the old toolbar dropdown for mints that support
 *  more than one receive rail. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReceiveMethodPickerSheet(
    methods: List<PaymentMethodKind>,
    selectedMethod: PaymentMethodKind,
    onSelect: (PaymentMethodKind) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = CashuTheme.spacing.comfortable)
                .navigationBarsPadding(),
        ) {
            FlowSheetTitle(title = "Receive with")
            methods.forEach { kind ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onSelect(kind) }
                        .padding(
                            horizontal = CashuTheme.spacing.snug,
                            vertical = CashuTheme.spacing.default,
                        ),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
                ) {
                    Icon(
                        imageVector = kind.menuIcon,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(CashuTheme.spacing.loose),
                    )
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = kind.friendlyTitle,
                            style = MaterialTheme.typography.bodyLarge,
                            fontWeight = FontWeight.Medium,
                        )
                        Text(
                            text = kind.friendlyDescriptor,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (kind == selectedMethod) {
                        Icon(
                            imageVector = Icons.Filled.Check,
                            contentDescription = "Selected",
                            tint = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.size(CashuTheme.spacing.loose),
                        )
                    }
                }
            }
            Spacer(Modifier.height(CashuTheme.spacing.snug))
        }
    }
}

/** Plain "Expires in 12m 30s" caption, ticking every second and turning red
 *  under a minute. Reuses the shared [quoteExpiryText] formatter; hidden for
 *  never-expiring reusable offers (BOLT12 amountless). */
@Composable
private fun ExpiryCaption(expirySeconds: Long?) {
    val displayExpiry = mintQuoteDisplayExpiry(expirySeconds) ?: return
    var nowSeconds by remember(displayExpiry) { mutableStateOf(System.currentTimeMillis() / 1000) }
    LaunchedEffect(displayExpiry) {
        while (nowSeconds < displayExpiry) {
            delay(1000)
            nowSeconds = System.currentTimeMillis() / 1000
        }
    }
    val text = quoteExpiryText(expirySeconds, nowSeconds) ?: return
    val remaining = displayExpiry - nowSeconds
    val urgent = remaining < 60
    val color = if (urgent) {
        MaterialTheme.colorScheme.error
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.micro),
    ) {
        Icon(
            imageVector = Icons.Outlined.Timer,
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(14.dp),
        )
        Text(
            text = if (remaining <= 0) "Expired" else "Expires in $text",
            style = MaterialTheme.typography.labelMedium.withMonoDigits(),
            color = color,
        )
    }
}

/** Success-row data lifted out of the paid quote so the terminal renders even
 *  after the sheet body crossfades away. */
private data class ReceiveSuccessInfo(
    val amountLabel: String?,
    val mintName: String?,
    val method: PaymentMethodKind,
)

/** Full-screen shared success terminal for a paid receive (iOS
 *  `receiveSuccessView`). The mint still runs on the wallet's app-lifetime
 *  scope, while dismissal remains an explicit user action on both platforms. */
@Composable
private fun ReceiveSuccessTerminal(
    info: ReceiveSuccessInfo,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    PaymentStatusScreen(
        phase = PaymentStatusPhase.Success,
        title = "Payment Received!",
        onDone = onDone,
        modifier = modifier,
        rows = {
            if (info.amountLabel != null) {
                InspectorRow(
                    label = "Amount",
                    value = info.amountLabel,
                    valueMonospaced = true,
                )
            }
            if (info.mintName != null) {
                InspectorRow(
                    label = "Mint",
                    value = info.mintName,
                )
            }
        },
    )
}
