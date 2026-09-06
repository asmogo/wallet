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
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import com.cashu.me.Core.normalizedOfferDescription
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
import com.cashu.me.Models.MintQuoteRetryState
import com.cashu.me.Models.MintQuoteState
import com.cashu.me.Models.PaymentMethodKind
import com.cashu.me.ui.components.AmountEntryHero
import com.cashu.me.ui.components.AmountFlipDisplay
import com.cashu.me.ui.components.AmountText
import com.cashu.me.ui.components.CashuTextField
import com.cashu.me.ui.components.CompactSheetContent
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
import com.cashu.me.ui.components.PaymentDetailContent
import com.cashu.me.ui.components.DescriptionDetailRow
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

private enum class MintQuoteSettlementState {
    Waiting,
    PaymentDetected,
    Issuing,
    RetryScheduled,
    NeedsAttention,
    Ready,
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

/** Defensive cap for the payer-facing BOLT12 offer description. */
private const val MAX_OFFER_DESCRIPTION_LENGTH = 640

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
    var reusableDescriptionEditorOpen by remember { mutableStateOf(false) }
    // Description the next reusable BOLT12 offer is minted with. Initialized
    // once per mint/unit from the last presented amountless offer intent so
    // re-opening the screen reloads the described offer instead of minting a
    // duplicate (CDK never returns offer descriptions — local memo is the
    // only record). A mint or unit switch resets and re-restores.
    var reusableOfferDescription by remember { mutableStateOf<String?>(null) }
    var reusableOfferDescriptionLoadedFor by remember { mutableStateOf<String?>(null) }
    // Quote creation is serialized through this handle — a new create cancels
    // the in-flight one so the slowest job can't clobber the freshest offer.
    var createJob by remember { mutableStateOf<Job?>(null) }
    var displayActionsOpen by remember { mutableStateOf(false) }
    var methodPickerOpen by remember { mutableStateOf(false) }

    val activeMint = walletState.activeMint
    val supportedMethods = activeMint?.supportedMintMethods?.ifEmpty { listOf(PaymentMethodKind.Bolt11) }
        ?: listOf(PaymentMethodKind.Bolt11)
    // Fail closed: only mints that advertised NUT-04 bolt12 description=true
    // get a Description row / description minting.
    val mintSupportsBolt12Description = activeMint?.supportsBolt12MintDescription == true

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

    val descriptionContext = activeMint?.url?.let { "$it|$effectiveUnit" }
    LaunchedEffect(descriptionContext, cashuRequestState.requests, mintSupportsBolt12Description) {
        if (reusableOfferDescriptionLoadedFor != descriptionContext) {
            reusableOfferDescription = null
            reusableOfferDescriptionLoadedFor = null
        }
        if (!mintSupportsBolt12Description) {
            reusableOfferDescription = null
            reusableOfferDescriptionLoadedFor = null
            return@LaunchedEffect
        }
        if (reusableOfferDescriptionLoadedFor == null && activeMint != null) {
            reusableOfferDescription = cashuRequestStore
                .lastPresentedAmountlessOffer(activeMint.url, effectiveUnit)?.memo
            reusableOfferDescriptionLoadedFor = descriptionContext
        }
    }

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
            // An offer's description is immutable like the offer itself, so a
            // null here means "unknown" and must not wipe the stored memo.
            memo = quote.description,
            encoded = quote.request,
        )
        cashuRequestStore.markQuotePresented(quote.id)
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
        createJob?.cancel()
        createJob = scope.launch {
            try {
                val requestUnit = if (requestMethod == PaymentMethodKind.Onchain) {
                    "sat"
                } else {
                    amountEntryContext.quoteUnit
                }
                // Offers are immutable: reuse only matches an offer carrying
                // this exact description, so a changed description mints fresh.
                val offerDescription = reusableOfferDescription
                    .takeIf {
                        requestMethod == PaymentMethodKind.Bolt12 &&
                            mintSupportsBolt12Description
                    }
                val quote = if (
                    requestMethod == PaymentMethodKind.Bolt12 &&
                    amountless &&
                    !forceNewReusableOffer
                ) {
                    walletManager.existingAmountlessBolt12Offer(
                        unit = requestUnit,
                        description = offerDescription,
                    ) ?: walletManager.createMintQuote(
                        amount = null,
                        method = requestMethod,
                        unit = requestUnit,
                        description = offerDescription,
                    )
                } else {
                    walletManager.createMintQuote(
                        amount = requestAmount,
                        method = requestMethod,
                        unit = requestUnit,
                        description = offerDescription,
                    )
                }
                // createMintQuote (and the reuse path) already carry the
                // description on the returned quote; no face-level copy.
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
            quote.state != MintQuoteState.Issued
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
     * Re-mints the reusable BOLT12 offer with a new payer-facing description
     * (iOS `setReusableOfferDescription` parity). Blank → null (plain offer,
     * reuse allowed); non-blank → a fresh offer, since offers are immutable.
     * The current fixed amount, if any, is preserved.
     */
    fun setReusableOfferDescription(next: String?) {
        method = PaymentMethodKind.Bolt12
        errorText = null
        reusableOfferDescription = normalizedOfferDescription(next)
        reusableOfferDescriptionLoadedFor = descriptionContext
        val currentQuote = (face as? ReceiveLnFace.Display)?.quote
        if (currentQuote != null &&
            currentQuote.paymentMethod == PaymentMethodKind.Bolt12 &&
            !currentQuote.isAmountless
        ) {
            // Preserve the displayed fixed amount via the same keypad/quote
            // conversion as the Amount pencil. `UnitAmountEntry.entryString`
            // would rebuild a mint-unit string and, on a sat quote with fiat
            // primary, parse it as fiat — reminting the wrong amount.
            setReusableOfferAmount(currentQuote.amount)
        } else {
            amount = ""
            createMintRequest(
                requestMethod = PaymentMethodKind.Bolt12,
                amountless = true,
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

    // Keep outgoing addresses in the shared reconciliation lane, including
    // expired quotes whose deposits may still be waiting for confirmations.
    // The global pending-quote sweep remains the fallback after dismissal.
    LaunchedEffect(abandonedOnchainQuoteIds.isNotEmpty()) {
        while (abandonedOnchainQuoteIds.isNotEmpty() && successInfo == null) {
            for (quoteId in abandonedOnchainQuoteIds) {
                val reconciliation = runCatching {
                    walletManager.refreshPendingMintQuote(
                        quoteId,
                        confirmationOwner = ReceiveConfirmationOwner.InFlow,
                    )
                }
                    .getOrNull()
                if (reconciliation?.hasSettledPayment != true) continue
                abandonedOnchainQuoteIds = abandonedOnchainQuoteIds - quoteId
                // Refetch for the credited amount (on-chain always mints sat).
                val refreshed = reconciliation.quote
                val paidAmount = reconciliation.newlyIssued.takeIf { it > 0 }
                    ?: refreshed?.amount
                    ?: refreshed?.amountIssued?.takeIf { it > 0 }
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
                    var mintRetryStatus by remember(current.quote.id) {
                        mutableStateOf(walletManager.mintQuoteRetryStatus(current.quote.id))
                    }
                    var isReconcilingQuote by remember(current.quote.id) { mutableStateOf(false) }
                    var isIssuingEcash by remember(current.quote.id) { mutableStateOf(false) }
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
                        // BOLT11/BOLT12 5s→15s, on-chain flat 30s.
                        val (initialMs, maxMs) = when (current.quote.paymentMethod) {
                            PaymentMethodKind.Bolt11 -> 5_000L to 15_000L
                            PaymentMethodKind.Bolt12 -> 5_000L to 15_000L
                            PaymentMethodKind.Onchain -> 30_000L to 30_000L
                        }
                        var intervalMs = initialMs
                        while (true) {
                            delay(intervalMs)
                            if (!walletManager.shouldAttemptMintQuote(current.quote.id)) continue
                            val refreshed = runCatching { walletManager.pollMintQuote(current.quote.id) }
                                .getOrNull()
                                ?: continue // transient failure — keep monitoring
                            liveQuote = refreshed
                            mintRetryStatus = walletManager.mintQuoteRetryStatus(refreshed.id)
                            // Reusable BOLT12 offers stay open after each
                            // payment (the mint never marks them terminally
                            // paid), so keep polling for the next one.
                            val keepPolling = refreshed.paymentMethod == PaymentMethodKind.Bolt12 ||
                                (refreshed.paymentMethod == PaymentMethodKind.Onchain && !refreshed.hasSettledPayment) ||
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
                    // Green/received state is based on issued ecash, never on
                    // a Lightning payment that is still waiting to be minted.
                    val receivedAmountLabel = liveQuote.amountIssued
                        .takeIf { it > 0 }
                        ?.let { issued ->
                            if (liveQuote.unit.equals("sat", ignoreCase = true)) {
                                formatter.formatWalletSats(issued, settings.useBitcoinSymbol)
                            } else {
                                CurrencyAmount(
                                    issued,
                                    CurrencyRegistry.currencyForMintUnit(liveQuote.unit),
                                ).formatted()
                            }
                        }

                    // Runs on WalletManager's app-lifetime scope so dismissing
                    // the sheet cannot cancel a paid quote midway through
                    // issuance. The local flag describes only a real
                    // check/issue operation; durable retry truth comes from the
                    // scheduler record returned with the result.
                    fun reconcileDisplayedQuote(force: Boolean = false) {
                        if (isReconcilingQuote) return
                        val quoteId = liveQuote.id
                        val paymentMethod = liveQuote.paymentMethod
                        isReconcilingQuote = true
                        // A caught-up reusable quote is merely being checked;
                        // don't claim ecash issuance until its counters already
                        // prove that a paid delta exists.
                        isIssuingEcash = (force || walletManager.shouldAttemptMintQuote(quoteId)) &&
                            (liveQuote.mintableAmount > 0 || liveQuote.state == MintQuoteState.Paid)
                        walletManager.launch {
                            try {
                                val result = walletManager.refreshPendingMintQuote(
                                    quoteId,
                                    confirmationOwner = ReceiveConfirmationOwner.InFlow,
                                    force = force,
                                )
                                result.quote?.let { liveQuote = it }
                                mintRetryStatus = result.retryStatus
                                if (paymentMethod != PaymentMethodKind.Bolt12 &&
                                    result.hasSettledPayment
                                ) {
                                    successInfo = ReceiveSuccessInfo(
                                        amountLabel = amountLabel,
                                        mintName = activeMint?.name,
                                        method = paymentMethod,
                                    )
                                }
                            } finally {
                                isIssuingEcash = false
                                isReconcilingQuote = false
                            }
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
                                reconcileDisplayedQuote()
                            }
                            return@LaunchedEffect
                        }
                        if (liveQuote.state == MintQuoteState.Paid ||
                            liveQuote.state == MintQuoteState.Issued
                        ) {
                            // Keep the request visible until reconciliation
                            // verifies amount_issued. A paid invoice is not yet
                            // a successful ecash receive.
                            reconcileDisplayedQuote()
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
                    val quoteIntent = cashuRequestState.requests
                        .firstOrNull { it.quoteId == liveQuote.id }
                    DisplayFace(
                        quote = liveQuote,
                        amountLabel = amountLabel.takeUnless {
                            liveQuote.paymentMethod == PaymentMethodKind.Bolt12 && liveQuote.isAmountless
                        },
                        receivedAmountLabel = receivedAmountLabel,
                        settlementState = when {
                            isIssuingEcash -> MintQuoteSettlementState.Issuing
                            liveQuote.mintableAmount > 0 &&
                                mintRetryStatus.state == MintQuoteRetryState.NeedsAttention ->
                                MintQuoteSettlementState.NeedsAttention
                            liveQuote.mintableAmount > 0 &&
                                mintRetryStatus.state == MintQuoteRetryState.RetryScheduled ->
                                MintQuoteSettlementState.RetryScheduled
                            liveQuote.mintableAmount > 0 -> MintQuoteSettlementState.PaymentDetected
                            liveQuote.paymentMethod == PaymentMethodKind.Bolt12 &&
                                liveQuote.amountIssued > 0 -> MintQuoteSettlementState.Ready
                            liveQuote.paymentMethod == PaymentMethodKind.Bolt12 ->
                                MintQuoteSettlementState.Waiting
                            else -> null
                        },
                        mintName = walletState.mints.firstOrNull { it.url == liveQuote.mintUrl }?.name
                            ?: liveQuote.mintUrl?.let { android.net.Uri.parse(it).host }
                            ?: activeMint?.name,
                        createdAtEpochMillis = quoteIntent?.createdAtEpochMillis ?: quoteCreatedAtMillis,
                        descriptionLabel = quoteIntent?.displayDescription
                            ?: liveQuote.description,
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
                        onRetryPendingMint = { reconcileDisplayedQuote(force = true) },
                        onEditReusableAmount = if (
                            liveQuote.paymentMethod == PaymentMethodKind.Bolt12
                        ) {
                            { reusableAmountPickerOpen = true }
                        } else {
                            null
                        },
                        onEditReusableDescription = if (
                            liveQuote.paymentMethod == PaymentMethodKind.Bolt12 &&
                            mintSupportsBolt12Description
                        ) {
                            { reusableDescriptionEditorOpen = true }
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

    if (reusableDescriptionEditorOpen &&
        displayQuote?.paymentMethod == PaymentMethodKind.Bolt12 &&
        mintSupportsBolt12Description
    ) {
        ReusableDescriptionEditSheet(
            initialDescription = cashuRequestState.requests
                .firstOrNull { it.quoteId == displayQuote.id }?.memo
                ?: displayQuote.description,
            onDone = { next ->
                reusableDescriptionEditorOpen = false
                setReusableOfferDescription(next)
            },
            onDismiss = { reusableDescriptionEditorOpen = false },
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
    settlementState: MintQuoteSettlementState?,
    mintName: String?,
    createdAtEpochMillis: Long?,
    descriptionLabel: String?,
    errorText: String?,
    amountPrimary: AmountDisplayPrimary,
    onFlipAmountPrimary: (AmountDisplayPrimary) -> Unit,
    fiatPrice: Double?,
    fiatCurrencyCode: String,
    useBitcoinSymbol: Boolean,
    pendingStatusText: String,
    explorerLabel: String,
    onCopy: () -> Unit,
    onRetryPendingMint: () -> Unit,
    onEditReusableAmount: (() -> Unit)?,
    onEditReusableDescription: (() -> Unit)?,
    onOpenExplorer: (() -> Unit)?,
) {
    val confirmationToastController = LocalConfirmationToastController.current
    val isReusable = quote.paymentMethod == PaymentMethodKind.Bolt12
    Column(modifier = Modifier.fillMaxSize()) {
        PaymentDetailContent(
            modifier = Modifier.weight(1f),
            hero = { qrSize ->
                QrCard(
                    content = quote.request,
                    size = qrSize,
                    shareSubject = "Payment request",
                    staticOnly = true,
                    confirmationMessage = if (quote.paymentMethod == PaymentMethodKind.Onchain) {
                        "Copied Bitcoin address"
                    } else {
                        "Copied payment request"
                    },
                )
            },
        ) {
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
            if (settlementState != null) {
                MintQuoteSettlementStatus(
                    state = settlementState,
                    onRetry = onRetryPendingMint,
                )
            } else {
                WaitingForPaymentRow(text = pendingStatusText)
            }
            errorText?.let { InlineNotice(text = it, severity = NoticeSeverity.Error) }
            if (!isReusable) {
                ExpiryCaption(expirySeconds = quote.expiryEpochSeconds)
            }
            Column(modifier = Modifier.fillMaxWidth()) {
                if (mintName != null) {
                    InspectorRow(label = "Mint", value = mintName)
                }
                if (isReusable && onEditReusableDescription != null) {
                    InspectorRow(
                        label = "Description",
                        value = descriptionLabel ?: "None",
                        editable = true,
                        onClick = onEditReusableDescription,
                    )
                } else if (!descriptionLabel.isNullOrBlank()) {
                    DescriptionDetailRow(descriptionLabel)
                }
                if (isReusable) {
                    InspectorRow(
                        label = "Amount",
                        value = amountLabel ?: "Any",
                        valueMonospaced = amountLabel != null,
                        editable = onEditReusableAmount != null,
                        onClick = onEditReusableAmount,
                    )
                    if (receivedAmountLabel != null) {
                        InspectorRow(label = "Total received", value = receivedAmountLabel,
                            valueMonospaced = true)
                    }
                }
                if (createdAtEpochMillis != null) {
                    InspectorRow(label = "Created", value = formatReusableCreatedAt(createdAtEpochMillis))
                }
                if (onOpenExplorer != null) {
                    ExplorerLinkRow(label = explorerLabel, onClick = onOpenExplorer)
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
 * Honest mint settlement status shared by one-shot and reusable receives.
 * A spinner means an operation is active, while scheduled/attention states
 * come from durable retry metadata and always retain an explicit manual retry.
 */
@Composable
private fun MintQuoteSettlementStatus(
    state: MintQuoteSettlementState,
    onRetry: () -> Unit,
) {
    AnimatedContent(
        modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
        targetState = state,
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
        label = "mint-quote-settlement-status",
    ) { current ->
        when (current) {
            MintQuoteSettlementState.Waiting -> WaitingForPaymentRow()
            MintQuoteSettlementState.PaymentDetected -> Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
            ) {
                Icon(
                    imageVector = Icons.Outlined.Schedule,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(CashuTheme.spacing.loose),
                )
                Text(
                    text = "Payment received. Ecash issuance is pending.",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            MintQuoteSettlementState.Issuing -> Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(CashuTheme.spacing.loose),
                    strokeWidth = 2.dp,
                )
                Text(
                    text = "Payment received. Issuing ecash…",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            MintQuoteSettlementState.RetryScheduled,
            MintQuoteSettlementState.NeedsAttention -> {
                val needsAttention = current == MintQuoteSettlementState.NeedsAttention
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
                    ) {
                        Icon(
                            imageVector = if (needsAttention) {
                                Icons.Outlined.WarningAmber
                            } else {
                                Icons.Outlined.Schedule
                            },
                            contentDescription = null,
                            tint = if (needsAttention) {
                                MaterialTheme.colorScheme.error
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                            modifier = Modifier.size(CashuTheme.spacing.loose),
                        )
                        Text(
                            text = if (needsAttention) {
                                "Payment received. Ecash is still pending."
                            } else {
                                "Payment received. Retrying ecash automatically."
                            },
                            style = MaterialTheme.typography.titleMedium,
                            color = if (needsAttention) {
                                MaterialTheme.colorScheme.error
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                        )
                    }
                    androidx.compose.material3.TextButton(onClick = onRetry) {
                        Icon(
                            imageVector = Icons.Outlined.Refresh,
                            contentDescription = null,
                        )
                        Text("Retry now")
                    }
                }
            }
            MintQuoteSettlementState.Ready -> Row(
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
                    text = "Ready for another payment",
                    style = MaterialTheme.typography.titleMedium,
                    color = CashuTheme.colors.onReceivedContainer,
                )
            }
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

/**
 * Description edit sheet for a reusable BOLT12 offer (iOS
 * `ReusableOfferDescriptionSheet` parity). The text is embedded in the offer
 * payers receive. Seeded verbatim from the current offer's stored memo;
 * never from profile or mint metadata. Empty →
 * removes the description (plain offer).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ReusableDescriptionEditSheet(
    initialDescription: String?,
    onDone: (String?) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var description by rememberSaveable { mutableStateOf(initialDescription.orEmpty()) }
    val focusRequester = remember { FocusRequester() }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = CashuTheme.colors.compactSheetContainer,
    ) {
        CompactSheetContent {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .imePadding()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = CashuTheme.spacing.loose)
                    .padding(bottom = CashuTheme.spacing.comfortable),
            ) {
                SheetHeader(
                    title = "Description",
                    navigationIcon = Icons.Outlined.Close,
                    navigationContentDescription = "Close",
                    onNavigationClick = onDismiss,
                )
                Text(
                    text = "Add a note for anyone paying this invoice.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = CashuTheme.spacing.comfortable),
                )
                CashuTextField(
                    value = description,
                    onValueChange = { description = it.take(MAX_OFFER_DESCRIPTION_LENGTH) },
                    label = "Description",
                    placeholder = "e.g. Coffee tips",
                    modifier = Modifier
                        .fillMaxWidth()
                        .focusRequester(focusRequester)
                        .testTag("reusable-description-field"),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                    minLines = 3,
                    maxLines = 5,
                )
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = CashuTheme.spacing.snug, bottom = CashuTheme.spacing.section),
                    horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
                ) {
                    Text(
                        text = "Leave blank to remove.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        text = "${description.length} / $MAX_OFFER_DESCRIPTION_LENGTH",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                PrimaryButton(
                    text = "Save",
                    onClick = { onDone(description.trim().ifEmpty { null }) },
                    colors = ButtonDefaults.buttonColors(),
                    modifier = Modifier.fillMaxWidth().testTag("reusable-description-save"),
                )
            }
        }
        LaunchedEffect(Unit) { focusRequester.requestFocus() }
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
