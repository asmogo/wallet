package com.cashu.me.ui.send

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.ArrowCircleDown
import androidx.compose.material.icons.outlined.Cancel
import androidx.compose.material.icons.outlined.Nfc
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.CashuPaymentRequestRoute
import com.cashu.me.Core.MintDiscoveryManager
import com.cashu.me.Core.PaymentRequestDecodeResult
import com.cashu.me.Core.PaymentRequestDecoder
import com.cashu.me.Core.PriceService
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.Wallet.WalletMessage
import com.cashu.me.Core.Wallet.isInsufficientBalance
import com.cashu.me.Core.Wallet.userFacingWalletMessage
import com.cashu.me.Core.Wallet.walletMessage
import com.cashu.me.Core.WalletManager
import com.cashu.me.Core.normalizedMintUrlForSelection
import com.cashu.me.Core.routeForCashuPaymentRequest
import com.cashu.me.Models.MeltPaymentResult
import com.cashu.me.Models.MeltQuoteInfo
import com.cashu.me.Models.MeltSettlement
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.R
import com.cashu.me.ui.components.AmountFlipDisplay
import com.cashu.me.ui.components.AmountText
import com.cashu.me.ui.components.CashuTextField
import com.cashu.me.ui.components.EmptyState
import com.cashu.me.ui.components.EmptyStateSize
import com.cashu.me.ui.components.FlowSheetTitle
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.InlineNoticeHost
import com.cashu.me.ui.components.InspectorRow
import com.cashu.me.ui.components.MethodActionRow
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
import com.cashu.me.ui.components.SpinnerRing
import com.cashu.me.ui.components.TwoFaceScreen
import com.cashu.me.ui.mints.ConnectMintContext
import com.cashu.me.ui.mints.ConnectMintSheetContent
import com.cashu.me.ui.testing.UiTestTags
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withMonoDigits
import com.cashu.me.ui.theme.rememberReducedMotion
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val TYPE_DEBOUNCE_MS = 400L

// PaymentStatusScreen's scaffold metrics, mirrored so the confirm face's hero
// band (amount / quote spinner / caution face) lands at the same Y as the
// status terminal's glyph — the pay transition then keeps the spinner still
// instead of jumping.
private const val ConfirmTopFraction = 0.16f
private val ConfirmHeroMinHeight = 220.dp
private val ConfirmGlyphSlotSize = 72.dp
private val ConfirmGlyphSize = 64.dp

private enum class SendStep { Input, Amount, Confirm }

internal sealed interface SendStatus {
    val details: SendPaymentDetails

    data class Sending(override val details: SendPaymentDetails) : SendStatus
    data class Sent(
        override val details: SendPaymentDetails,
        val result: MeltPaymentResult?,
    ) : SendStatus
    data class Failed(
        override val details: SendPaymentDetails,
        val message: WalletMessage,
    ) : SendStatus
}

/**
 * The Send surface (iOS UnifiedSendView): one destination field that infers the
 * rail, a Scan · Ecash · Tap ways-to-send row, then amount → confirm → status.
 * Home's Send button lands here directly — there is no send chooser.
 *
 * Input (and empty states) wrap content so the sheet hugs the field + method
 * buttons — thumb-reachable, matching iOS's content-fit detent. Amount /
 * confirm / status expand to fill the sheet (iOS `.large`).
 */
@Composable
fun UnifiedSendScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    priceService: PriceService,
    mintDiscoveryManager: MintDiscoveryManager,
    onClose: () -> Unit,
    onScan: () -> Unit,
    onContactless: () -> Unit,
    onSendEcash: () -> Unit,
    onOpenReceiveToken: (String) -> Unit,
    onReceive: () -> Unit,
    allowCleartextLocalTestMints: Boolean = false,
    prefilledPayload: String? = null,
    onPrefilledConsumed: () -> Unit = {},
    onDismissLockChanged: (Boolean) -> Unit = {},
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val priceState by priceService.state.collectAsState()
    val formatter = remember { AmountFormatter() }
    val unsupportedCashuRequestUnit =
        stringResource(R.string.send_cashu_request_unsupported_unit)
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current
    val context = androidx.compose.ui.platform.LocalContext.current
    val hasNfc = remember(context) {
        context.packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_NFC) &&
            android.nfc.NfcAdapter.getDefaultAdapter(context) != null
    }

    var step by remember { mutableStateOf(SendStep.Input) }
    var status by remember { mutableStateOf<SendStatus?>(null) }
    var destination by remember { mutableStateOf("") }
    var locked by remember { mutableStateOf<LockedRail?>(null) }
    var inputHint by remember { mutableStateOf<String?>(null) }
    // A recipient the user backed out of: still valid, must not auto-advance.
    var suppressedValue by remember { mutableStateOf<String?>(null) }
    var amount by remember { mutableStateOf("") }
    var cameFromAmount by remember { mutableStateOf(false) }
    var selectedMintUrl by remember { mutableStateOf<String?>(null) }
    var mintPickerOpen by remember { mutableStateOf(false) }
    var meltQuote by remember { mutableStateOf<MeltQuoteInfo?>(null) }
    var topUpQuote by remember { mutableStateOf<MintQuoteInfo?>(null) }
    var topUpLoading by remember { mutableStateOf(false) }
    var topUpError by remember { mutableStateOf<String?>(null) }
    var quoteError by remember { mutableStateOf<String?>(null) }
    // Structured companion to quoteError: whether the failure was the mint
    // refusing for balance — that state gets a real recovery CTA, never a
    // futile Retry Quote (iOS errorShowsMintAction parity).
    var quoteErrorInsufficient by remember { mutableStateOf(false) }
    var confirmError by remember { mutableStateOf<String?>(null) }
    var cashuRequestFeeEstimate by remember {
        mutableStateOf<CashuRequestFeeEstimate>(CashuRequestFeeEstimate.Unrequested)
    }

    val entryFiatPrice = priceState.btcPrice.takeIf {
        settings.showFiatBalance && it > 0
    }
    val entryContext = UnifiedSendAmountEntry.context(
        preferredPrimary = settings.amountDisplayPrimary,
        btcPrice = entryFiatPrice ?: 0.0,
    )
    var previousEntryContext by remember { mutableStateOf(entryContext) }
    val activeMintUrl = selectedMintUrl ?: walletState.activeMint?.url
    val enteredAmount = UnifiedSendAmountEntry.amountSats(amount, entryContext)
    val confirmAmount = locked?.let { rail ->
        when (rail) {
            is LockedRail.Melt -> rail.knownAmount ?: enteredAmount
            is LockedRail.Creq -> rail.knownAmount ?: enteredAmount
        }
    } ?: 0L
    val cashuRoute = (locked as? LockedRail.Creq)?.let { rail ->
        routeForCashuPaymentRequest(
            rawRequest = rail.raw,
            request = rail.decoded.summary,
            mints = walletState.mints,
            selectedMintUrl = selectedMintUrl,
            activeMintUrl = walletState.activeMint?.url,
            amountSats = confirmAmount,
        )
    }
    val activeMint = when (val route = cashuRoute) {
        is CashuPaymentRequestRoute.PayWithEcash -> route.mint
        else -> walletState.mints.firstOrNull { it.url == activeMintUrl } ?: walletState.activeMint
    }
    val cashuRequestFeeKey = (locked as? LockedRail.Creq)?.let { rail ->
        (cashuRoute as? CashuPaymentRequestRoute.PayWithEcash)?.let { route ->
            CashuRequestFeeEstimateKey(
                request = rail.raw,
                amountSats = route.amountSats,
                mintUrl = route.mint.url,
            )
        }
    }
    // Render loading on the very first confirmation frame and whenever the
    // route changes; the effect below then fills this reserved row in place.
    val displayedCashuRequestFeeEstimate = cashuRequestFeeKey?.let { key ->
        cashuRequestFeeEstimate.takeIf { it.key == key }
            ?: CashuRequestFeeEstimate.Loading(key)
    } ?: CashuRequestFeeEstimate.Unrequested
    // Only a scanned/deep-linked Cashu Request hides the raw string and swaps
    // the header (iOS CashuPaymentRequestPayView); typed/pasted ones keep the
    // "To" pill like iOS's UnifiedSendView.
    val creqFromScan = (locked as? LockedRail.Creq)?.fromScan == true

    fun reset(toInput: Boolean = true) {
        locked = null
        amount = ""
        meltQuote = null
        topUpQuote = null
        topUpLoading = false
        topUpError = null
        quoteError = null
        confirmError = null
        cashuRequestFeeEstimate = CashuRequestFeeEstimate.Unrequested
        cameFromAmount = false
        if (toInput) step = SendStep.Input
    }

    /** Rail inference (iOS handleDestinationChange → advance). */
    fun advance(
        raw: String,
        fromScan: Boolean = false,
        showUnrecognizedHint: Boolean = true,
    ) {
        val trimmed = raw.trim()
        if (trimmed.isEmpty() || trimmed == suppressedValue) return
        inputHint = null
        when (val resolution = resolveSendDestination(trimmed, walletState.mints)) {
            is SendDestinationResolution.Hint -> inputHint = resolution.message
            is SendDestinationResolution.Melt -> {
                locked = LockedRail.Melt(resolution.request, resolution.decoded, resolution.knownAmount)
                if (resolution.requiresAmountEntry) {
                    step = SendStep.Amount
                } else {
                    cameFromAmount = false
                    step = SendStep.Confirm
                }
            }
            is SendDestinationResolution.CashuRequest -> {
                locked = LockedRail.Creq(
                    resolution.request,
                    resolution.decoded,
                    resolution.knownAmount,
                    fromScan = fromScan,
                )
                if (resolution.requiresAmountEntry) {
                    step = SendStep.Amount
                } else {
                    cameFromAmount = false
                    step = SendStep.Confirm
                }
            }
            is SendDestinationResolution.EcashToken -> onOpenReceiveToken(resolution.token)
            SendDestinationResolution.Unrecognized -> {
                if (showUnrecognizedHint) {
                    inputHint =
                        "Unrecognized — try a Lightning address, invoice, Bitcoin address, or Cashu Request"
                }
            }
        }
    }

    fun pay() {
        val rail = locked ?: return
        var paymentDetails = buildSendPaymentDetails(
            rail = rail,
            cashuRoute = cashuRoute,
            amountSats = confirmAmount,
            mint = activeMint,
            meltQuote = meltQuote,
        )
        confirmError = null
        status = SendStatus.Sending(paymentDetails)
        scope.launch {
            try {
                when (rail) {
                    is LockedRail.Melt -> {
                        val quote = meltQuote ?: error("No quote.")
                        val result = walletManager.meltTokens(quote.id, activeMintUrl)
                        paymentDetails = paymentDetails.withMeltResult(result)
                        status = SendStatus.Sent(paymentDetails, result)
                    }
                    is LockedRail.Creq -> {
                        when (val route = cashuRoute) {
                            is CashuPaymentRequestRoute.PayWithEcash -> {
                                walletManager.payCashuPaymentRequest(rail.raw, route.amountSats, route.mint.url)
                            }
                            is CashuPaymentRequestRoute.PayBolt11Fallback -> {
                                val quote = walletManager.createMeltQuote(
                                    request = route.lightningRequest,
                                    amountSats = null,
                                    preferredMintURL = activeMintUrl,
                                )
                                paymentDetails = paymentDetails.withNetworkFeeUpperBound(quote.feeReserve)
                                    .withMintName(
                                        walletState.mints.firstOrNull {
                                            normalizedMintUrlForSelection(it.url) ==
                                                normalizedMintUrlForSelection(quote.mintUrl)
                                        }?.name ?: quote.mintUrl,
                                    )
                                status = SendStatus.Sending(paymentDetails)
                                val result = walletManager.meltTokens(quote.id, activeMintUrl)
                                paymentDetails = paymentDetails.withMeltResult(result)
                                status = SendStatus.Sent(paymentDetails, result)
                                return@launch
                            }
                            is CashuPaymentRequestRoute.AddMintToPay -> {
                                val mintUrl = route.mintUrls.firstOrNull()
                                    ?: error("No compatible mint was supplied.")
                                walletManager.addMintAndPayCashuPaymentRequest(
                                    encoded = rail.raw,
                                    customAmountSats = route.amountSats,
                                    mintUrl = mintUrl,
                                )
                            }
                            is CashuPaymentRequestRoute.NeedsExternalTopUp -> {
                                error("Top up the target mint before paying this Cashu Request.")
                            }
                            CashuPaymentRequestRoute.MissingAmount -> {
                                error("Enter an amount before paying this Cashu Request.")
                            }
                            is CashuPaymentRequestRoute.UnsupportedUnit -> {
                                error(unsupportedCashuRequestUnit)
                            }
                            null -> {
                                walletManager.payCashuPaymentRequest(rail.raw, confirmAmount, activeMintUrl)
                            }
                        }
                        status = SendStatus.Sent(paymentDetails, null)
                    }
                }
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (t: Throwable) {
                status = SendStatus.Failed(paymentDetails.resolvingFailed(), t.walletMessage)
            }
        }
    }

    fun goBack() {
        when {
            status != null -> Unit
            step == SendStep.Confirm && cameFromAmount -> {
                step = SendStep.Amount
                meltQuote = null
                quoteError = null
                quoteErrorInsufficient = false
                confirmError = null
            }
            step != SendStep.Input -> {
                suppressedValue = destination.trim()
                reset()
            }
            else -> onClose()
        }
    }

    // Typing debounces; paste/scan advance immediately.
    LaunchedEffect(destination) {
        if (step != SendStep.Input || status != null) return@LaunchedEffect
        val trimmed = destination.trim()
        if (trimmed != suppressedValue) suppressedValue = null
        if (trimmed.isEmpty()) {
            inputHint = null
            return@LaunchedEffect
        }
        delay(TYPE_DEBOUNCE_MS)
        // A paused keystroke is not a submit. Keep resolving valid destinations
        // automatically, but reserve the generic error for discrete complete
        // inputs such as paste and scan so the form never jumps while typing.
        advance(destination, showUnrecognizedHint = false)
    }

    LaunchedEffect(prefilledPayload) {
        val pre = prefilledPayload?.takeIf { it.isNotBlank() } ?: return@LaunchedEffect
        destination = pre
        advance(pre, fromScan = true)
        suppressedValue = pre.trim()
        onPrefilledConsumed()
    }

    // Re-express an in-progress amount when fiat entry becomes available (or
    // the saved primary changes), preserving the economic amount through sats.
    LaunchedEffect(entryContext.primary, entryContext.btcPrice) {
        if (previousEntryContext.primary != entryContext.primary) {
            amount = UnifiedSendAmountEntry.convert(
                raw = amount,
                from = previousEntryContext,
                to = entryContext,
            )
        }
        previousEntryContext = entryContext
    }

    // Confirm entry prefetches the melt quote (iOS shows fee/total skeleton).
    LaunchedEffect(step, locked, confirmAmount, activeMintUrl) {
        if (step != SendStep.Confirm) return@LaunchedEffect
        val rail = locked as? LockedRail.Melt ?: return@LaunchedEffect
        meltQuote = null
        quoteError = null
        quoteErrorInsufficient = false
        try {
            meltQuote = walletManager.createMeltQuote(
                request = rail.raw,
                // Invoices/offers carry their own amount; address rails pass the entry.
                amountSats = if (rail.knownAmount != null) null else confirmAmount,
                preferredMintURL = activeMintUrl,
            )
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (failure: Throwable) {
            quoteError = failure.userFacingWalletMessage
            quoteErrorInsufficient = failure.isInsufficientBalance
        }
    }

    // Cashu Request payments use CDK's include-fee coin selection. Key the
    // preview to every input that can change that selection, cancel obsolete
    // work automatically, and reject a stale completion as a final backstop.
    LaunchedEffect(step, cashuRequestFeeKey) {
        val key = cashuRequestFeeKey
        if (step != SendStep.Confirm || key == null) {
            cashuRequestFeeEstimate = CashuRequestFeeEstimate.Unrequested
            return@LaunchedEffect
        }
        cashuRequestFeeEstimate = CashuRequestFeeEstimate.Loading(key)
        val result = resolveCashuRequestFeeEstimate(key) { amountSats, mintUrl ->
            walletManager.estimateCashuPaymentRequestFee(amountSats, mintUrl)
        }
        cashuRequestFeeEstimate = cashuRequestFeeEstimate.acceptIfCurrent(result)
    }

    // Block sheet dismissal while the melt is in flight — a stray swipe must
    // not tear down the coroutine mid-payment.
    LaunchedEffect(status) { onDismissLockChanged(status is SendStatus.Sending) }

    // Dismissal contract: system back = swipe = abandon to the wallet, so the
    // sheet handles it. The header chevron owns internal step-back (Confirm →
    // Amount → Input). Swallow back only while the melt is in flight.
    BackHandler(enabled = status is SendStatus.Sending) {}

    // Compact while the input face is up so Scan/Ecash/Tap sit near the thumb;
    // amount/confirm/status need the full sheet for the keypad and pay scaffold.
    val prefersCompactSheet = status == null && step == SendStep.Input
    Column(
        modifier = (
            if (prefersCompactSheet) {
                Modifier.fillMaxWidth()
            } else {
                Modifier.fillMaxHeight()
            }
            ).testTag(UiTestTags.SendSheet),
    ) {
        // Status terminal replaces the form body but retains the sheet title,
        // matching the toolbar-owned iOS PaymentStatusView slot.
        // One content key for every status value keeps a single
        // PaymentStatusScreen mounted across Sending → Sent/Failed, so the
        // spinner morphs into the check/X in place; the form ↔ terminal swap
        // itself fades through instead of hard-cutting.
        AnimatedContent(
            targetState = status,
            modifier = if (status == null && step == SendStep.Input) {
                Modifier.fillMaxWidth()
            } else {
                Modifier
                    .weight(1f)
                    .fillMaxWidth()
            },
            transitionSpec = { fadeIn(tween(200)) togetherWith fadeOut(tween(150)) },
            label = "unified-send-terminal",
            contentKey = { it != null },
        ) { current ->
            if (current != null) {
                Column(modifier = Modifier.fillMaxSize()) {
                    FlowSheetTitle(
                        title = if (creqFromScan) "Pay Cashu Request" else "Send",
                    )
                    SendStatusTerminal(
                        status = current,
                        formatter = formatter,
                        useBitcoinSymbol = settings.useBitcoinSymbol,
                        onClose = onClose,
                        onRetry = { status = null },
                        modifier = Modifier.weight(1f),
                    )
                }
            } else if (step == SendStep.Input && walletState.mints.isEmpty()) {
                // Same surface the wallet-home "Add mint" CTA opens. It draws its
                // own header so it can swap the title and reveal a back chevron
                // when its URL / discovery steps are pushed — don't add one here.
                // Adding a mint drops this face and the Send input takes over, so
                // there is nothing to do on success.
                ConnectMintSheetContent(
                    walletManager = walletManager,
                    settingsManager = settingsManager,
                    mintDiscoveryManager = mintDiscoveryManager,
                    context = ConnectMintContext.Send,
                    allowCleartextLocalTestMints = allowCleartextLocalTestMints,
                    onMintAdded = {},
                )
            } else {
                Column(
                    modifier = if (step == SendStep.Input) {
                        Modifier.fillMaxWidth()
                    } else {
                        Modifier.fillMaxSize()
                    },
                ) {
                    if (step == SendStep.Input) {
                        FlowSheetTitle(
                            title = if (creqFromScan) "Pay Cashu Request" else "Send",
                        )
                    } else {
                        SheetHeader(
                            title = if (creqFromScan) "Pay Cashu Request" else "Send",
                            navigationIcon = Icons.AutoMirrored.Outlined.ArrowBack,
                            navigationContentDescription = "Back",
                            onNavigationClick = ::goBack,
                        )
                    }
                    // The pinned "To" row is shared by the amount AND confirm
                    // faces, rendered once up here so the recipient is the step
                    // swap's fixed anchor — it never slides with the faces
                    // (iOS parity).
                    if (step != SendStep.Input && !creqFromScan) {
                        (locked?.raw ?: destination).takeIf { it.isNotBlank() }?.let { recipient ->
                            ToRow(
                                destination = recipient,
                                modifier = Modifier.padding(horizontal = CashuTheme.spacing.comfortable),
                            )
                        }
                    }
                    TwoFaceScreen(
                        targetState = step,
                        modifier = if (step == SendStep.Input) {
                            Modifier.fillMaxWidth()
                        } else {
                            Modifier.weight(1f).fillMaxWidth()
                        },
                        forward = { initial, target -> target.ordinal >= initial.ordinal },
                        label = "unified-send-step",
                    ) { current ->
                        when (current) {
                            SendStep.Input -> InputFace(
                                hasBalance = walletState.hasAnyBalance,
                                destination = destination,
                                onDestinationChange = {
                                    destination = it
                                    inputHint = null
                                },
                                onPaste = {
                                    val clip = clipboard.getText()?.text?.trim().orEmpty()
                                    if (clip.isNotEmpty()) {
                                        destination = clip
                                        advance(clip)
                                        suppressedValue = clip
                                    }
                                },
                                onClear = {
                                    destination = ""
                                    inputHint = null
                                },
                                clipboardHasText = clipboard.hasText(),
                                inputHint = inputHint,
                                hasNfc = hasNfc,
                                onScan = onScan,
                                onSendEcash = onSendEcash,
                                onContactless = onContactless,
                                onReceive = onReceive,
                            )

                            SendStep.Amount -> AmountFace(
                                amount = amount,
                                onAmountChange = { amount = it },
                                mint = activeMint,
                                balanceText = activeMint?.let {
                                    formatter.formatWalletSats(it.balance, settings.useBitcoinSymbol)
                                },
                                // One mint means nothing to choose between, so the row
                                // drops its chevron and stops opening a picker.
                                onPickMint = { mintPickerOpen = true }
                                    .takeIf { walletState.mints.size > 1 },
                                onUseMax = {
                                    activeMint?.balance?.takeIf { it > 0 }?.let {
                                        amount = UnifiedSendAmountEntry.maxRawForBalance(it, entryContext)
                                    }
                                },
                                amountSats = enteredAmount,
                                entryPrimary = entryContext.primary,
                                onFlipEntryPrimary = {
                                    settingsManager.setAmountDisplayPrimary(it.rawValue)
                                },
                                btcPrice = entryFiatPrice,
                                fiatCurrencyCode = priceState.currencyCode,
                                useBitcoinSymbol = settings.useBitcoinSymbol,
                                formatter = formatter,
                                onContinue = {
                                    cameFromAmount = true
                                    step = SendStep.Confirm
                                },
                            )

                            SendStep.Confirm -> ConfirmFace(
                                rail = locked,
                                cashuRoute = cashuRoute,
                                amountSats = confirmAmount,
                                mint = activeMint,
                                onPickMint = { mintPickerOpen = true },
                                // One mint means nothing to choose between, so the row
                                // drops its chevron and stops opening a picker.
                                canPickMint = walletState.mints.size > 1,
                                onCreateTopUp = { mintUrl, requestedAmount ->
                                    topUpError = null
                                    topUpLoading = true
                                    scope.launch {
                                        try {
                                            topUpQuote = createExternalTopUpQuote(
                                                mintUrl = mintUrl,
                                                requestedAmountSats = requestedAmount,
                                            ) { targetMintUrl, amount, method, unit ->
                                                walletManager.createMintQuoteForMint(
                                                    mintUrl = targetMintUrl,
                                                    amount = amount,
                                                    method = method,
                                                    unit = unit,
                                                )
                                            }
                                        } catch (cancellation: CancellationException) {
                                            throw cancellation
                                        } catch (failure: Throwable) {
                                            topUpError = failure.userFacingWalletMessage
                                        } finally {
                                            topUpLoading = false
                                        }
                                    }
                                },
                                quote = meltQuote,
                                cashuRequestFeeEstimate = displayedCashuRequestFeeEstimate,
                                quoteError = quoteError,
                                quoteErrorInsufficient = quoteErrorInsufficient,
                                onRetryQuote = {
                                    quoteError = null
                                    quoteErrorInsufficient = false
                                    // Re-trigger the prefetch by nudging state.
                                    val current = selectedMintUrl
                                    selectedMintUrl = null
                                    selectedMintUrl = current
                                },
                                // goBack's Confirm→Amount branch is exactly the
                                // "change amount" reset; fixed-amount rails
                                // have no amount step to return to.
                                onChangeAmount = { goBack() }.takeIf { cameFromAmount },
                                confirmError = confirmError,
                                mintBalance = activeMint?.balance ?: 0L,
                                formatter = formatter,
                                useBitcoinSymbol = settings.useBitcoinSymbol,
                                preferredPrimary = settings.amountDisplayPrimary,
                                showFiat = settings.showFiatBalance,
                                btcPrice = priceState.btcPrice,
                                currencyCode = priceState.currencyCode,
                                topUpLoading = topUpLoading,
                                topUpError = topUpError,
                                onPay = ::pay,
                            )
                        }
                    }
                }
            }
        }
    }

    if (mintPickerOpen) {
        MintPickerSheet(
            mints = walletState.mints,
            activeMintUrl = activeMintUrl,
            onSelect = { mint ->
                mint?.let { selectedMintUrl = it.url }
                mintPickerOpen = false
            },
            onDismiss = { mintPickerOpen = false },
        )
    }

    topUpQuote?.let { quote ->
        TopUpQuoteSheet(
            quote = quote,
            formatter = formatter,
            useBitcoinSymbol = settings.useBitcoinSymbol,
            onDismiss = { topUpQuote = null },
        )
    }
}

/**
 * One [PaymentStatusScreen] for every send status: staying mounted across
 * Sending → Sent/Failed lets the spinner morph into the check/X in place and
 * the title crossfade (iOS PaymentStatusView), instead of remounting a fresh
 * terminal per outcome.
 */
@Composable
private fun SendStatusTerminal(
    status: SendStatus,
    formatter: AmountFormatter,
    useBitcoinSymbol: Boolean,
    onClose: () -> Unit,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // An async-accepted (NUT-05) melt — typical for on-chain — isn't settled
    // yet: the mint took the payment and pays out in the background, so say
    // "processing", not "sent" (iOS parity).
    val settlementPending = (status as? SendStatus.Sent)
        ?.result?.settlement == MeltSettlement.Pending
    // A terminal outcome (already paid) can't be retried — offer Done;
    // anything else returns to the confirm step.
    val failure = (status as? SendStatus.Failed)?.message
    PaymentStatusScreen(
        modifier = modifier,
        phase = when (status) {
            is SendStatus.Sending -> PaymentStatusPhase.Processing
            is SendStatus.Sent -> PaymentStatusPhase.Success
            is SendStatus.Failed -> PaymentStatusPhase.Failure
        },
        title = when (status) {
            is SendStatus.Sending -> "Sending payment…"
            is SendStatus.Sent -> if (settlementPending) "Payment processing" else "Payment sent"
            is SendStatus.Failed -> "Payment failed"
        },
        detail = when {
            failure != null -> failure.text
            settlementPending ->
                "The mint accepted this payment and is settling it. " +
                    "Your balance will update automatically."
            else -> null
        },
        settlementPending = settlementPending,
        doneLabel = if (failure != null && !failure.isTerminal) "Try again" else "Done",
        onDone = when (status) {
            is SendStatus.Sending -> null
            is SendStatus.Sent -> onClose
            is SendStatus.Failed -> {
                { if (status.message.isTerminal) onClose() else onRetry() }
            }
        },
        rows = { SendPaymentDetailRows(status.details, formatter, useBitcoinSymbol) },
    )
}

@Composable
internal fun SendPaymentDetailRows(
    details: SendPaymentDetails,
    formatter: AmountFormatter,
    useBitcoinSymbol: Boolean,
) {
    details.rows.forEachIndexed { index, row ->
        val loading = row.value == SendPaymentDetailValue.Pending
        val value = when (val detailValue = row.value) {
            SendPaymentDetailValue.Pending -> ""
            SendPaymentDetailValue.Unavailable -> "Unavailable"
            is SendPaymentDetailValue.Text -> detailValue.text
            is SendPaymentDetailValue.Sats -> {
                val formatted = formatter.formatWalletSats(detailValue.amount, useBitcoinSymbol)
                when {
                    row.key in FeeDetailKeys && detailValue.amount == 0L -> "No fee"
                    detailValue.isUpperBound -> "Up to $formatted"
                    else -> formatted
                }
            }
        }
        InspectorRow(
            label = row.label,
            value = value,
            modifier = if (loading) {
                Modifier.semantics { stateDescription = "Loading" }
            } else {
                Modifier
            },
            valueMonospaced = row.valueMonospaced,
            loading = loading,
        )
    }
}

private val FeeDetailKeys = setOf(
    SendPaymentDetailKey.NetworkFee,
    SendPaymentDetailKey.InputFee,
)

@Composable
private fun InputFace(
    hasBalance: Boolean,
    destination: String,
    onDestinationChange: (String) -> Unit,
    onPaste: () -> Unit,
    onClear: () -> Unit,
    clipboardHasText: Boolean,
    inputHint: String?,
    hasNfc: Boolean,
    onScan: () -> Unit,
    onSendEcash: () -> Unit,
    onContactless: () -> Unit,
    onReceive: () -> Unit,
) {
    // The no-mints case never reaches here — UnifiedSendScreen swaps the whole
    // body (header included) for the connect-a-mint surface.
    when {
        !hasBalance -> {
            // Compact (no fillMaxHeight) so the sheet hugs this empty state.
            EmptyState(
                // Circled down arrow — same glyph and .section scale as the
                // iOS zero-balance Send sheet.
                icon = Icons.Outlined.ArrowCircleDown,
                title = "Nothing to send yet",
                supporting = "Receive some ecash before you can send.",
                actionLabel = "Receive",
                onAction = onReceive,
                fillHeight = false,
                size = EmptyStateSize.Section,
                modifier = Modifier
                    .padding(vertical = CashuTheme.spacing.section)
                    .navigationBarsPadding(),
            )
            return
        }
    }
    // Wrap-content — no fillMaxSize / weight spacer — so the sheet settles just
    // below Scan · Ecash · Tap instead of stretching full-screen.
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = CashuTheme.spacing.comfortable)
            .padding(bottom = 52.dp)
            .navigationBarsPadding()
            .imePadding()
            .verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CashuTextField(
            value = destination,
            onValueChange = onDestinationChange,
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = CashuTheme.spacing.default)
                .testTag(UiTestTags.SendDestination),
            placeholder = "Address, invoice, or Cashu Request",
            singleLine = false,
            maxLines = 4,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
            // Deliberate divergence from the iOS ClipboardPaymentChip: Android
            // surfaces paste as an M3 trailing affordance. The Paste ↔ Clear
            // swap cross-fades (no hard cut) as input state changes.
            trailingIcon = if (destination.isNotBlank() || clipboardHasText) {
                {
                    AnimatedContent(
                        targetState = destination.isNotBlank(),
                        transitionSpec = {
                            fadeIn(spring(stiffness = Spring.StiffnessMedium))
                                .togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
                        },
                        label = "input-trailing",
                    ) { hasInput ->
                        if (hasInput) {
                            IconButton(onClick = onClear) {
                                Icon(Icons.Outlined.Cancel, contentDescription = "Clear")
                            }
                        } else {
                            GhostButton(text = "Paste", onClick = onPaste)
                        }
                    }
                }
            } else null,
        )
        InlineNoticeHost(
            text = inputHint,
            severity = NoticeSeverity.Caution,
            contentModifier = Modifier.padding(top = CashuTheme.spacing.default),
        )
        Spacer(Modifier.height(CashuTheme.spacing.section))
        Column(verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default)) {
            MethodActionRow(
                icon = Icons.Outlined.QrCodeScanner,
                title = "Scan",
                subtitle = "Scan an invoice, address, or request",
                accessibilityLabel = "Scan. Scan QR code",
                onClick = onScan,
            )
            MethodActionRow(
                icon = Icons.Outlined.Payments,
                title = "Ecash",
                subtitle = "Create ecash to share",
                accessibilityLabel = "Ecash. Create ecash",
                onClick = onSendEcash,
            )
            MethodActionRow(
                icon = Icons.Outlined.Nfc,
                title = "Tap",
                subtitle = "Pay contactlessly with NFC",
                accessibilityLabel = "Tap. Contactless, tap to pay nearby",
                onClick = onContactless,
                enabled = hasNfc,
                status = if (hasNfc) null else "Unavailable",
            )
        }
    }
}

/**
 * Recipient row in the flow-row vocabulary — the same quiet, unboxed shape as
 * [MintSelectorRow], so "From" and "To" share one left edge and one label
 * style instead of a lone capsule breaking the alignment (iOS `toRow` parity).
 * Rendered once above the step swap, so the recipient never travels or
 * double-renders between the amount and confirm faces.
 */
@Composable
private fun ToRow(destination: String, modifier: Modifier = Modifier) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp),
    ) {
        Text(
            text = "To",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.width(CashuTheme.spacing.snug))
        Text(
            text = destination,
            style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            overflow = TextOverflow.MiddleEllipsis,
        )
    }
}

@Composable
private fun AmountFace(
    amount: String,
    onAmountChange: (String) -> Unit,
    mint: MintInfo?,
    balanceText: String?,
    onPickMint: (() -> Unit)?,
    onUseMax: () -> Unit,
    amountSats: Long,
    entryPrimary: AmountDisplayPrimary,
    onFlipEntryPrimary: (AmountDisplayPrimary) -> Unit,
    btcPrice: Double?,
    fiatCurrencyCode: String,
    useBitcoinSymbol: Boolean,
    formatter: AmountFormatter,
    onContinue: () -> Unit,
) {
    val mintBalance = mint?.balance ?: 0L
    val validation = UnifiedSendAmountEntry.validation(amountSats, mintBalance)
    val insufficient = validation == UnifiedSendAmountValidation.InsufficientBalance
    val isFiatEntry = entryPrimary == AmountDisplayPrimary.Fiat
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = CashuTheme.spacing.comfortable),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        val reduceMotion = rememberReducedMotion()
        // One flexible cell: the amount centered in it, the notice *overlaid* at
        // its bottom (iOS SendView's ZStack, and Send Ecash's twin). As a sibling
        // the notice shoved the amount up by its full height the instant it
        // appeared, with no transition at all.
        Box(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            contentAlignment = Alignment.Center,
        ) {
            AmountFlipDisplay(
                amountSats = amountSats,
                primary = entryPrimary,
                onFlip = onFlipEntryPrimary,
                btcPrice = btcPrice,
                currencyCode = fiatCurrencyCode,
                useBitcoinSymbol = useBitcoinSymbol,
                entryRaw = amount,
                primaryAccessibilityPrefix = "Send amount",
            )
            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(bottom = CashuTheme.spacing.default),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                AnimatedVisibility(
                    visible = insufficient,
                    enter = if (reduceMotion) {
                        fadeIn(spring(stiffness = Spring.StiffnessMedium))
                    } else {
                        fadeIn(spring(stiffness = Spring.StiffnessMedium)) + scaleIn(
                            animationSpec = spring(stiffness = Spring.StiffnessMedium),
                            initialScale = 0.95f,
                        )
                    },
                    exit = fadeOut(spring(stiffness = Spring.StiffnessMedium)),
                ) {
                    // The mint selector states the available balance, so
                    // repeating it in this notice would add visual noise.
                    InlineNotice(
                        text = "Insufficient balance",
                        detail = null,
                        severity = NoticeSeverity.Caution,
                        showsContainer = false,
                        centered = true,
                    )
                }
            }
        }
        // Under the amount, over the keypad (Send Ecash / Receive parity).
        if (mint != null) {
            MintSelectorRow(
                direction = MintSelectorDirection.Source,
                mint = mint,
                balanceText = balanceText,
                showBalance = true,
                onPickMint = onPickMint,
                // Gated on a spendable balance, the way Send Ecash already does
                // it — an empty mint offered a Max that filled in zero.
                onUseMax = onUseMax.takeIf { mintBalance > 0L },
            )
            Spacer(Modifier.height(CashuTheme.spacing.snug))
        }
        NumberPadFooter(
            amount = amount,
            onAmountChange = onAmountChange,
            buttonText = "Continue",
            onButtonClick = onContinue,
            decimals = if (isFiatEntry) 2 else 0,
            buttonEnabled = validation == UnifiedSendAmountValidation.Valid,
        )
    }
}

@Composable
private fun ConfirmFace(
    rail: LockedRail?,
    cashuRoute: CashuPaymentRequestRoute?,
    amountSats: Long,
    mint: MintInfo?,
    onPickMint: () -> Unit,
    canPickMint: Boolean,
    onCreateTopUp: (mintUrl: String, requestedAmountSats: Long) -> Unit,
    quote: MeltQuoteInfo?,
    cashuRequestFeeEstimate: CashuRequestFeeEstimate,
    quoteError: String?,
    // The quote failure was the mint refusing for balance — gets a real
    // recovery CTA, never a futile Retry Quote.
    quoteErrorInsufficient: Boolean,
    onRetryQuote: () -> Unit,
    // Returns to the amount keypad; null when the invoice fixes the amount
    // (no amount step behind this confirm).
    onChangeAmount: (() -> Unit)?,
    confirmError: String?,
    mintBalance: Long,
    formatter: AmountFormatter,
    useBitcoinSymbol: Boolean,
    preferredPrimary: String,
    showFiat: Boolean,
    btcPrice: Double?,
    currencyCode: String,
    topUpLoading: Boolean,
    topUpError: String?,
    onPay: () -> Unit,
) {
    val isMelt = rail is LockedRail.Melt
    val isOnchain = (rail as? LockedRail.Melt)?.decoded is PaymentRequestDecodeResult.Onchain
    val cashuAmountLabel = (rail as? LockedRail.Creq)?.decoded?.summary?.let(PaymentRequestDecoder::amountLabel)
    val amountUnit = (rail as? LockedRail.Creq)?.decoded?.summary?.unit ?: "sat"
    val creqDescription = (rail as? LockedRail.Creq)?.decoded?.summary?.description
    val hideCreqDestination = (rail as? LockedRail.Creq)?.fromScan == true
    val total = quote?.totalAmount ?: amountSats
    val insufficient = isMelt && quote != null && total > mintBalance
    val canPayCashuRequest = cashuRoute == null ||
        cashuRoute is CashuPaymentRequestRoute.PayWithEcash ||
        cashuRoute is CashuPaymentRequestRoute.PayBolt11Fallback ||
        cashuRoute is CashuPaymentRequestRoute.AddMintToPay
    val unsupportedCashuRequestUnit =
        stringResource(R.string.send_cashu_request_unsupported_unit)
    val lightningFallback =
        stringResource(R.string.send_cashu_request_lightning_fallback)
    val quoteLoading = isMelt && quote == null && quoteError == null
    val quoteFailed = isMelt && quote == null && quoteError != null
    // Both shortfall shapes — the mint refusing the quote for balance, and a
    // landed quote the balance can't cover — share one recovery CTA (iOS
    // parity): re-fetching the same quote can never fix either.
    val shortfall = insufficient || (quoteFailed && quoteErrorInsufficient)
    // Status-terminal skeleton (PaymentStatusScreen parity): fixed top
    // fraction, a hero band that swaps amount / spinner / caution face in
    // place, details beneath, CTA pinned at the bottom. The From selector
    // floats over the anchored column (iOS topAccessory) so its presence
    // never shifts the hero; the pinned "To" row sits above this whole face.
    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val scaffoldHeight = maxHeight
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = CashuTheme.spacing.comfortable),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
        Spacer(Modifier.height(scaffoldHeight * ConfirmTopFraction))
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = ConfirmHeroMinHeight),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            when {
                // One centered spinner — the same wait animation, size, and
                // position the status terminal uses. No skeleton rows.
                quoteLoading -> SpinnerRing(
                    size = ConfirmGlyphSize,
                    color = MaterialTheme.colorScheme.primary,
                )
                // Preflight failure wears the status faces' anatomy: glyph +
                // centered message where the amount sits, never a corner notice.
                quoteFailed -> ConfirmCautionFace(
                    message = quoteError.orEmpty(),
                    detail = if (quoteErrorInsufficient && mint != null) {
                        "You have ${formatter.formatWalletSats(mintBalance, useBitcoinSymbol)} in ${mint.name}."
                    } else {
                        null
                    },
                )
                // A quote that exceeds the mint's balance is the same user
                // situation as a refused quote — the same face, not a banner
                // (iOS renders the identical treatment).
                insufficient -> ConfirmCautionFace(
                    message = "Not enough balance.",
                    detail = "This mint holds ${formatter.formatWalletSats(mintBalance, useBitcoinSymbol)}; " +
                        "the payment reserves up to ${formatter.formatWalletSats(total, useBitcoinSymbol)}.",
                )
                else -> PaymentConfirmationAmount(
                    amount = amountSats,
                    unit = amountUnit,
                    preferredPrimary = preferredPrimary,
                    showFiat = showFiat,
                    btcPrice = btcPrice,
                    currencyCode = currencyCode,
                    useBitcoinSymbol = useBitcoinSymbol,
                    formatter = formatter,
                )
            }
        }
        if (!quoteLoading && !quoteFailed && !insufficient) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = CashuTheme.spacing.snug),
        ) {
            if (isMelt) {
                if (isOnchain && rail != null) {
                    InspectorRow(
                        label = "To",
                        value = PaymentRequestDecoder.shortRepresentation(
                            "",
                            (rail as LockedRail.Melt).decoded,
                        ),
                        valueMonospaced = true,
                    )
                }
                quote?.let {
                    InspectorRow(
                        label = "Network fee",
                        value = formatter.formatWalletSats(it.feeReserve, useBitcoinSymbol),
                        valueMonospaced = true,
                    )
                    InspectorRow(
                        label = "Total",
                        value = formatter.formatWalletSats(it.totalAmount, useBitcoinSymbol),
                        valueMonospaced = true,
                    )
                }
            } else {
                InspectorRow(
                    label = "Amount",
                    value = cashuAmountLabel
                        ?: formatter.formatWalletSats(amountSats, useBitcoinSymbol),
                    valueMonospaced = true,
                )
                if (mint != null) {
                    InspectorRow(
                        label = "Mint",
                        value = mint.name,
                    )
                }
                if (!creqDescription.isNullOrBlank()) {
                    InspectorRow(label = "Memo", value = creqDescription)
                }
                val feePresentation = cashuRequestFeeEstimate.presentation { fee ->
                    formatter.formatWalletSats(fee, useBitcoinSymbol)
                }
                InspectorRow(
                    label = "Fee",
                    value = feePresentation.value,
                    valueMonospaced = feePresentation.valueMonospaced,
                    loading = feePresentation.loading,
                )
                when (val route = cashuRoute) {
                    is CashuPaymentRequestRoute.PayWithEcash -> {
                        InspectorRow(label = "Route", value = "Pay from ${route.mint.name}")
                    }
                    is CashuPaymentRequestRoute.PayBolt11Fallback -> {
                        InspectorRow(label = "Route", value = "Use Lightning fallback")
                    }
                    is CashuPaymentRequestRoute.AddMintToPay -> {
                        InspectorRow(label = "Route", value = "Add requested mint")
                    }
                    is CashuPaymentRequestRoute.NeedsExternalTopUp -> {
                        InspectorRow(label = "Route", value = "Top up target mint")
                    }
                    CashuPaymentRequestRoute.MissingAmount,
                    is CashuPaymentRequestRoute.UnsupportedUnit,
                    null -> Unit
                }
            }
        }
        when (cashuRoute) {
            is CashuPaymentRequestRoute.UnsupportedUnit -> {
                Spacer(Modifier.height(CashuTheme.spacing.default))
                InlineNotice(
                    text = unsupportedCashuRequestUnit,
                    severity = NoticeSeverity.Caution,
                )
            }
            CashuPaymentRequestRoute.MissingAmount -> {
                Spacer(Modifier.height(CashuTheme.spacing.default))
                InlineNotice(
                    text = "This Cashu Request does not include an amount. Enter an amount before paying.",
                    severity = NoticeSeverity.Caution,
                )
            }
            is CashuPaymentRequestRoute.AddMintToPay -> {
                Spacer(Modifier.height(CashuTheme.spacing.default))
                InlineNotice(
                    text = "This request asks for a mint you have not added yet. It will be added before payment.",
                    severity = NoticeSeverity.Info,
                )
            }
            is CashuPaymentRequestRoute.NeedsExternalTopUp -> {
                Spacer(Modifier.height(CashuTheme.spacing.default))
                InlineNotice(
                    text = "The compatible mint does not hold enough ecash for this request.",
                    severity = NoticeSeverity.Caution,
                )
                cashuRoute.mintUrl?.let { mintUrl ->
                    GhostButton(
                        text = if (topUpLoading) "Creating top-up..." else "Create top-up QR",
                        onClick = { onCreateTopUp(mintUrl, cashuRoute.amountSats) },
                        enabled = !topUpLoading,
                    )
                }
                GhostButton(text = "Choose another mint", onClick = onPickMint)
            }
            is CashuPaymentRequestRoute.PayBolt11Fallback -> {
                Spacer(Modifier.height(CashuTheme.spacing.default))
                InlineNotice(
                    text = lightningFallback,
                    severity = NoticeSeverity.Info,
                )
            }
            is CashuPaymentRequestRoute.PayWithEcash,
            null -> Unit
        }
        if (topUpError != null) {
            Spacer(Modifier.height(CashuTheme.spacing.default))
            InlineNotice(text = topUpError, severity = NoticeSeverity.Error)
        }
        if (confirmError != null) {
            Spacer(Modifier.height(CashuTheme.spacing.default))
            InlineNotice(text = confirmError, severity = NoticeSeverity.Error)
        }
        }
        }
        // CTA slot. During the quote fetch the footprint is reserved invisibly
        // (status-terminal parity) — the hero spinner owns the wait, so no
        // second spinner in the button.
        when {
            quoteLoading -> PrimaryButton(
                text = " ",
                onClick = {},
                enabled = false,
                modifier = Modifier
                    .graphicsLayer { alpha = 0f }
                    .clearAndSetSemantics {},
            )
            // A balance shortfall gets the recovery that actually works:
            // re-enter an amount that leaves room for the fee, or — when the
            // invoice fixes the amount — a mint that can cover it (picking
            // re-fetches the quote). Neither state offers a futile retry.
            shortfall && onChangeAmount != null -> PrimaryButton(
                text = "Change Amount",
                onClick = onChangeAmount,
            )
            shortfall && canPickMint -> PrimaryButton(
                text = "Choose Another Mint",
                onClick = onPickMint,
            )
            // Retry only where it can work (network, mint down).
            quoteFailed && !quoteErrorInsufficient -> PrimaryButton(
                text = "Retry Quote",
                onClick = onRetryQuote,
            )
            else -> PrimaryButton(
                text = "Pay ${cashuAmountLabel ?: formatter.formatWalletSats(amountSats, useBitcoinSymbol)}",
                onClick = onPay,
                modifier = Modifier.testTag(UiTestTags.SendPaymentSubmit),
                enabled = if (isMelt) {
                    quote != null && !insufficient && quoteError == null
                } else {
                    canPayCashuRequest && quoteError == null
                },
            )
        }
        Spacer(Modifier.navigationBarsPadding())
        }
        // Floating From selector (iOS topAccessory): overlaid so its presence
        // never shifts the anchored hero band below it.
        if (mint != null) {
            MintSelectorRow(
                direction = MintSelectorDirection.Source,
                mint = mint,
                balanceText = formatter.formatWalletSats(mintBalance, useBitcoinSymbol),
                onPickMint = onPickMint.takeIf { canPickMint },
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(horizontal = CashuTheme.spacing.comfortable),
            )
        }
    }
}

/**
 * Preflight caution, in the status faces' hero anatomy — glyph over a centered
 * message where the amount sits (iOS `confirmCautionFace` parity). Always the
 * orange warning triangle: a quote failure or balance shortfall spends
 * nothing, so it never wears the terminal failures' red. The recovery CTA
 * lives in the pinned bottom slot.
 */
@Composable
private fun ConfirmCautionFace(message: String, detail: String? = null) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
    ) {
        Box(
            modifier = Modifier.size(ConfirmGlyphSlotSize),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Rounded.Warning,
                contentDescription = null,
                tint = CashuTheme.colors.pending,
                modifier = Modifier.size(ConfirmGlyphSize),
            )
        }
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
        ) {
            Text(
                text = message,
                style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = CashuTheme.spacing.page),
            )
            detail?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = CashuTheme.spacing.page),
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TopUpQuoteSheet(
    quote: MintQuoteInfo,
    formatter: AmountFormatter,
    useBitcoinSymbol: Boolean,
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
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
        ) {
            Text(
                text = "Top up mint",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            quote.amount?.let { amount ->
                AmountText(
                    text = formatter.formatWalletSats(amount, useBitcoinSymbol),
                    style = MaterialTheme.typography.headlineSmall.withMonoDigits(),
                )
            }
            QrCard(content = quote.request, shareSubject = "Top-up request", staticOnly = true)
            Text(
                text = "Pay this invoice, then try the Cashu Request again after the mint settles.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            PrimaryButton(text = "Done", onClick = onDismiss)
        }
    }
}
