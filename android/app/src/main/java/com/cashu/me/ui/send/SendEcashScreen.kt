package com.cashu.me.ui.send

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsBottomHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.LockOpen
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.Receipt
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.AccessibilityAction
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.cashu.me.Views.Components.ScannerQuickAction
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.WalletHaptic
import com.cashu.me.Core.rememberWalletHaptics
import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.PendingTokenClaimCheckResult
import com.cashu.me.Core.runPendingTokenClaimCheck
import com.cashu.me.Core.Wallet.isInsufficientBalance
import com.cashu.me.Core.Wallet.userFacingWalletMessage
import com.cashu.me.Core.WalletManager
import com.cashu.me.Models.SendTokenResult
import com.cashu.me.ui.components.AmountEntryHero
import com.cashu.me.ui.components.CashuTextField
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.InlineNotice
import com.cashu.me.ui.components.NoticeSeverity
import com.cashu.me.ui.components.MintPickerSheet
import com.cashu.me.ui.components.MintSelectorRow
import com.cashu.me.ui.components.NumberPadFooter
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.neutralActionButtonColors
import com.cashu.me.ui.components.QrCard
import com.cashu.me.ui.components.SheetHeader
import com.cashu.me.ui.components.TwoFaceScreen
import com.cashu.me.ui.components.UnitPickerSheet
import com.cashu.me.ui.components.shareText
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.settings.P2PKKeyDisplay
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.rememberReducedMotion
import com.cashu.me.ui.theme.withMonoDigits
import com.cashu.me.ui.testing.UiTestTags

// Inline status icons inside dense rows — smaller than the standard 20dp body icon.
private val STATUS_ICON_SMALL = 18.dp
private val CHECKING_PROGRESS_SIZE = 14.dp

internal object LockEcashCopy {
    const val Label = "Lock ecash"
    const val Hint = "Lock this ecash to a public key"
    const val InvalidRecipientKey = "That's not a valid public key."
    const val RecipientEffect = "Only the recipient with this public key can claim it."
    const val RecipientKeyLabel = "Recipient public key (P2PK)"
    const val ScanPrompt = "Scan a public key to lock to"
}

/**
 * Entry state parked in the shell while this sheet yields to the full-screen
 * P2PK key scanner, then restored when the flow reopens. Without it the typed
 * amount evaporates on every "Lock ecash" scan.
 */
data class SendEcashDraft(
    val amount: String,
    val mintUrl: String?,
    val unit: String?,
    val p2pkOn: Boolean,
    val p2pkInput: String,
)

private sealed interface SendFace {
    data object Input : SendFace

    // Unit and amount are captured at generation time so the token face keeps
    // rendering correctly after the entry state resets.
    data class Generated(
        val result: SendTokenResult,
        val mintUrl: String,
        val unit: String,
        val amount: Long,
    ) : SendFace
}

internal data class P2PKRecipientKeyValidation(
    val normalizedKey: String?,
    val errorMessage: String?,
)

/**
 * The single validation path for every P2PK recipient-key intake: typing,
 * clipboard paste, camera scan, and the wallet's own-key shortcut.
 */
internal fun validateP2PKRecipientKey(raw: String): P2PKRecipientKeyValidation {
    if (raw.isBlank()) return P2PKRecipientKeyValidation(normalizedKey = null, errorMessage = null)

    return runCatching {
        SettingsManager.normalizeP2PKPublicKeyForSend(raw)
    }.fold(
        onSuccess = { P2PKRecipientKeyValidation(normalizedKey = it, errorMessage = null) },
        onFailure = {
            P2PKRecipientKeyValidation(
                normalizedKey = null,
                errorMessage = LockEcashCopy.InvalidRecipientKey,
            )
        },
    )
}

@Composable
fun SendEcashScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    priceService: com.cashu.me.Core.PriceService,
    onBack: () -> Unit,
    onClose: () -> Unit,
    onScanP2pk: (SendEcashDraft) -> Unit = {},
    initialDraft: SendEcashDraft? = null,
    prefilledP2pkKey: String? = null,
    onPrefilledP2pkConsumed: () -> Unit = {},
    onDismissLockChanged: (Boolean) -> Unit = {},
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val priceState by priceService.state.collectAsState()
    val formatter = remember { AmountFormatter() }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val haptics = rememberWalletHaptics()

    var face: SendFace by remember { mutableStateOf(SendFace.Input) }
    var amount by remember { mutableStateOf(initialDraft?.amount ?: "") }
    var sending by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }
    var pickerOpen by remember { mutableStateOf(false) }
    var selectedMintUrl by remember { mutableStateOf(initialDraft?.mintUrl) }
    var unitPickerOpen by remember { mutableStateOf(false) }
    var selectedUnit by remember { mutableStateOf(initialDraft?.unit) }
    var nonSatBalance by remember { mutableStateOf<Long?>(null) }
    var p2pkOn by remember { mutableStateOf(initialDraft?.p2pkOn ?: false) }
    var p2pkInput by remember { mutableStateOf(initialDraft?.p2pkInput ?: "") }

    val activeMintUrl = selectedMintUrl ?: walletState.activeMint?.url
    val activeMint = walletState.mints.firstOrNull { it.url == activeMintUrl } ?: walletState.activeMint

    // Effective send unit: explicit pick when the mint offers it, else the
    // default unit that actually holds balance (a USD-only wallet opens on USD).
    val effectiveUnit = run {
        val units = activeMint?.units ?: listOf("sat")
        val explicit = selectedUnit?.takeIf { units.contains(it) }
        explicit ?: run {
            fun holdsBalance(unit: String): Boolean = if (unit.equals("sat", ignoreCase = true)) {
                (activeMint?.balance ?: 0L) > 0L
            } else {
                (walletState.balancesByUnit[unit] ?: 0L) > 0L
            }
            val fallback = activeMint?.defaultUnit ?: "sat"
            if (holdsBalance(fallback)) fallback
            else units.firstOrNull(::holdsBalance) ?: fallback
        }
    }
    val currency = CurrencyRegistry.currencyForMintUnit(effectiveUnit)
    val isSatUnit = effectiveUnit.equals("sat", ignoreCase = true)
    val amountEntryContext = SendEcashAmountEntry.context(
        unit = effectiveUnit,
        unitDecimals = currency.decimals,
        preferredPrimary = settings.amountDisplayPrimary,
        btcPrice = priceState.btcPrice,
    )
    var previousAmountEntryContext by remember { mutableStateOf(amountEntryContext) }
    val amountValue = amountEntryContext.amountBaseUnits(amount)

    // Per-(mint, unit) spendable balance. Sat answers from cache; non-sat loads
    // through the CDK unit wallet on demand.
    LaunchedEffect(activeMintUrl, effectiveUnit) {
        nonSatBalance = null
        if (!isSatUnit && activeMintUrl != null) {
            nonSatBalance = walletManager.unitBalance(activeMintUrl, effectiveUnit)
        }
    }
    val mintBalance = if (isSatUnit) activeMint?.balance ?: 0L else nonSatBalance ?: 0L
    val balanceLoading = !isSatUnit && nonSatBalance == null

    // Re-express a live sat amount when fiat entry becomes available or the
    // saved primary changes. The conversion boundary preserves its sat value.
    LaunchedEffect(amountEntryContext) {
        amount = SendEcashAmountEntry.convert(
            raw = amount,
            from = previousAmountEntryContext,
            to = amountEntryContext,
        )
        previousAmountEntryContext = amountEntryContext
    }

    // Scan, paste, and the own-key shortcut all update [p2pkInput], so
    // normalization and error copy cannot diverge by source.
    val p2pkValidation = remember(p2pkInput) { validateP2PKRecipientKey(p2pkInput) }
    val validatedP2pkPubkey = p2pkValidation.normalizedKey.takeIf { p2pkOn }
    val primaryP2pkPublicKey = settingsManager.primaryP2PKKeyInfo()?.publicKey
    val p2pkRecipientIsPrimaryKey = validatedP2pkPubkey?.let { recipient ->
        isPrimaryP2pkRecipient(
            recipient = recipient,
            primaryPublicKey = primaryP2pkPublicKey,
        )
    } == true
    fun selectP2pkRecipient(raw: String) {
        val validation = validateP2PKRecipientKey(raw)
        val normalized = validation.normalizedKey
        if (normalized != null) {
            p2pkInput = normalized
            p2pkOn = true
            errorText = null
            haptics.perform(WalletHaptic.Success)
        } else {
            errorText = validation.errorMessage ?: LockEcashCopy.InvalidRecipientKey
            haptics.perform(WalletHaptic.Error)
        }
    }

    // The key scanned (or shortcut-picked) on the shell's full-screen scanner
    // arrives here when the flow reopens — the single validation path judges
    // it, so an invalid code surfaces as the usual inline error.
    LaunchedEffect(prefilledP2pkKey) {
        val key = prefilledP2pkKey?.takeIf { it.isNotBlank() } ?: return@LaunchedEffect
        selectP2pkRecipient(key)
        onPrefilledP2pkConsumed()
    }

    fun currentDraft() = SendEcashDraft(
        amount = amount,
        mintUrl = selectedMintUrl,
        unit = selectedUnit,
        p2pkOn = p2pkOn,
        p2pkInput = p2pkInput,
    )

    // Generation counts as money-in-motion: block sheet dismissal.
    LaunchedEffect(sending) { onDismissLockChanged(sending) }

    // Dismissal contract: system back = swipe = abandon to the wallet, so the
    // sheet handles it. The header chevron owns internal step-back (Generated →
    // Input → Send). Swallow back only while a token is being generated.
    BackHandler(enabled = sending) {}

    Column(
        modifier = Modifier
            .fillMaxHeight()
            .testTag(UiTestTags.SendEcashScreen),
    ) {
        SheetHeader(
            title = when (face) {
                SendFace.Input -> "Send Ecash"
                is SendFace.Generated -> "Pending Ecash"
            },
            navigationIcon = Icons.AutoMirrored.Outlined.ArrowBack,
            navigationContentDescription = "Back",
            onNavigationClick = {
                when (face) {
                    SendFace.Input -> onBack()
                    is SendFace.Generated -> face = SendFace.Input
                }
            },
            actions = {
                val current = face
                if (current is SendFace.Generated) {
                    IconButton(onClick = {
                        context.shareText(current.result.token, subject = "Cashu token")
                    }) {
                        ToolbarIcon(Icons.Outlined.IosShare, contentDescription = "Share")
                    }
                } else if (current is SendFace.Input) {
                    // iOS toolbar order: lock, then unit (unit sits to the lock's right).
                    LockEcashToolbarAction(
                        onClick = { onScanP2pk(currentDraft()) },
                    )
                    if (activeMint?.supportsMultipleUnits == true) {
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
            forward = { initial, target ->
                initial is SendFace.Input && target is SendFace.Generated
            },
            label = "send-ecash-face",
        ) { current ->
            when (current) {
                is SendFace.Input -> InputFace(
                    amount = amount,
                    onAmountChange = {
                        amount = it
                        errorText = null
                    },
                    activeMint = activeMint,
                    onPickMint = { pickerOpen = true },
                    onUseMax = {
                        if (mintBalance > 0L) {
                            amount = amountEntryContext.maxRawForBalance(mintBalance)
                        }
                    },
                    canUseMax = mintBalance > 0L,
                    amountValue = amountValue,
                    mintBalance = mintBalance,
                    balanceLoading = balanceLoading,
                    // Per-mint spendable balance, shown under the mint name
                    // inside the selector card (iOS MintAmountSelectorRow).
                    balanceText = when {
                        balanceLoading -> "…"
                        isSatUnit -> formatter.formatWalletSats(mintBalance, settings.useBitcoinSymbol)
                        else -> CurrencyAmount(mintBalance, currency).formatted()
                    },
                    isSat = isSatUnit && !amountEntryContext.isFiatEntry,
                    unit = if (amountEntryContext.isFiatEntry) {
                        priceState.currencyCode
                    } else {
                        effectiveUnit
                    },
                    useBitcoinSymbol = settings.useBitcoinSymbol,
                    formatter = formatter,
                    decimals = amountEntryContext.keypadDecimals,
                    fiatCurrencyCode = priceState.currencyCode.takeIf {
                        amountEntryContext.isFiatEntry
                    },
                    sending = sending,
                    errorText = errorText,
                    confirmedP2pkPubkey = validatedP2pkPubkey,
                    p2pkRecipientIsPrimaryKey = p2pkRecipientIsPrimaryKey,
                    onEditP2pkRecipient = { onScanP2pk(currentDraft()) },
                    onRemoveP2pkRecipient = {
                        p2pkInput = ""
                        p2pkOn = false
                        errorText = null
                    },
                    canSendWithP2pk = !p2pkOn || validatedP2pkPubkey != null,
                    onSend = {
                        val mintUrl = activeMintUrl ?: walletState.activeMint?.url
                        if (mintUrl == null) {
                            errorText = "Add a mint first."
                            return@InputFace
                        }
                        if (amountValue <= 0L) {
                            errorText = "Enter an amount."
                            return@InputFace
                        }
                        if (p2pkOn && validatedP2pkPubkey == null) {
                            errorText = LockEcashCopy.InvalidRecipientKey
                            return@InputFace
                        }
                        sending = true
                        scope.launch {
                            try {
                                val result = walletManager.sendTokens(
                                    amount = amountValue,
                                    // iOS Send Ecash has no memo field — always nil.
                                    memo = null,
                                    p2pkPubkey = validatedP2pkPubkey,
                                    mintUrl = mintUrl,
                                    unit = effectiveUnit,
                                )
                                face = SendFace.Generated(result, mintUrl, effectiveUnit, amountValue)
                                amount = ""
                            } catch (t: Throwable) {
                                errorText = if (t.isInsufficientBalance && amountValue <= mintBalance) {
                                    // The balance covers the amount, but the
                                    // swap that makes change for it carries a
                                    // fee the remainder can't absorb — the
                                    // plain "Not enough balance." reads as a
                                    // wallet bug when the user typed exactly
                                    // what the screen says they hold.
                                    "Not enough balance to cover the mint fee. Try Send Max."
                                } else {
                                    t.userFacingWalletMessage
                                }
                            } finally {
                                sending = false
                            }
                        }
                    },
                )

                is SendFace.Generated -> GeneratedFace(
                    walletManager = walletManager,
                    result = current.result,
                    mintUrl = current.mintUrl,
                    unit = current.unit,
                    pollingEnabled = settings.checkSentTokens,
                    amountPresentation = paymentConfirmationAmountPresentation(
                        amount = current.amount,
                        unit = current.unit,
                        preferredPrimary = settings.amountDisplayPrimary,
                        showFiat = settings.showFiatBalance,
                        btcPrice = priceState.btcPrice,
                        currencyCode = priceState.currencyCode,
                        useBitcoinSymbol = settings.useBitcoinSymbol,
                        formatter = formatter,
                    ),
                    fiatLabel = if (current.unit.equals("sat", ignoreCase = true) &&
                        settings.showFiatBalance && priceState.btcPrice > 0
                    ) {
                        formatter.formatFiat(
                            current.amount,
                            priceState.btcPrice,
                            priceState.currencyCode,
                        )
                    } else {
                        null
                    },
                    onDone = onClose,
                )
            }
        }
    }

    if (pickerOpen) {
        MintPickerSheet(
            mints = walletState.mints,
            activeMintUrl = activeMintUrl,
            onSelect = { mint ->
                mint?.let { selectedMintUrl = it.url }
                selectedUnit = null
                amount = ""
                nonSatBalance = null
                errorText = null
                pickerOpen = false
            },
            onDismiss = { pickerOpen = false },
        )
    }

    if (unitPickerOpen) {
        UnitPickerSheet(
            units = activeMint?.units ?: listOf("sat"),
            selectedUnit = effectiveUnit,
            onSelect = {
                selectedUnit = it
                amount = ""
                nonSatBalance = null
                errorText = null
                unitPickerOpen = false
            },
            onDismiss = { unitPickerOpen = false },
        )
    }
}

@Composable
private fun InputFace(
    amount: String,
    onAmountChange: (String) -> Unit,
    activeMint: com.cashu.me.Models.MintInfo?,
    onPickMint: () -> Unit,
    onUseMax: () -> Unit,
    canUseMax: Boolean,
    amountValue: Long,
    mintBalance: Long,
    balanceLoading: Boolean,
    balanceText: String,
    isSat: Boolean,
    unit: String,
    useBitcoinSymbol: Boolean,
    formatter: AmountFormatter,
    decimals: Int,
    fiatCurrencyCode: String?,
    sending: Boolean,
    errorText: String?,
    confirmedP2pkPubkey: String?,
    p2pkRecipientIsPrimaryKey: Boolean,
    onEditP2pkRecipient: () -> Unit,
    onRemoveP2pkRecipient: () -> Unit,
    canSendWithP2pk: Boolean,
    onSend: () -> Unit,
) {
    val canSend = amountValue in 1..mintBalance && !sending && !balanceLoading && canSendWithP2pk
    val insufficient = !balanceLoading && amountValue > 0 && amountValue > mintBalance
    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val compactHeight = maxHeight < 600.dp
        val noticeVisible = insufficient || errorText != null
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = CashuTheme.spacing.comfortable)
                .imePadding(),
            verticalArrangement = Arrangement.spacedBy(
                if (compactHeight) CashuTheme.spacing.micro else CashuTheme.spacing.default,
            ),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
        Spacer(Modifier.height(CashuTheme.spacing.micro))
        // One card: avatar + name + balance + Send Max pill + chevron
        // (iOS MintAmountSelectorRow parity).
        if (activeMint != null) {
            MintSelectorRow(
                mint = activeMint,
                balanceText = balanceText,
                onPickMint = onPickMint,
                onUseMax = if (canUseMax) onUseMax else null,
            )
        }

        // iOS SendView: mint row on top, amount vertically centered between
        // spacers, keypad pinned below. On compact sheets a visible notice
        // receives the upper flexible space so it cannot be clipped.
        if (!noticeVisible) {
            Spacer(Modifier.weight(1f, fill = true))
        }
        val amountColor by animateColorAsState(
            targetValue = if (insufficient) {
                MaterialTheme.colorScheme.onSurfaceVariant
            } else {
                MaterialTheme.colorScheme.onSurface
            },
            animationSpec = spring(stiffness = Spring.StiffnessMedium),
            label = "amount-color",
        )
        AmountEntryHero(
            entryRaw = amount,
            isSat = isSat,
            unit = unit,
            decimals = decimals,
            useBitcoinSymbol = useBitcoinSymbol,
            formatter = formatter,
            fiatCurrencyCode = fiatCurrencyCode,
            color = amountColor,
        )

        confirmedP2pkPubkey?.let { pubkey ->
            P2pkRecipientConfirmation(
                confirmedPubkey = pubkey,
                recipientIsPrimaryKey = p2pkRecipientIsPrimaryKey,
                onEditRecipient = onEditP2pkRecipient,
                onRemoveRecipient = onRemoveP2pkRecipient,
            )
        }

        val reduceMotion = rememberReducedMotion()
        Box(modifier = Modifier.weight(1f, fill = true).fillMaxWidth()) {
            // Fade+scale warning (iOS .transition(.opacity.combined(with: .scale))),
            // reduce-motion collapses to a plain fade. Drawn at the bottom of the
            // flexible gap so the amount above stays pinned.
            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth(),
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
                    // iOS SendView: tinted caution InlineNotice with balance detail.
                    val mintName = activeMint?.name
                    InlineNotice(
                        text = "Insufficient balance",
                        severity = NoticeSeverity.Warning,
                        detail = if (!compactHeight && mintName != null) {
                            "You have $balanceText in $mintName."
                        } else {
                            null
                        },
                        modifier = Modifier.padding(bottom = CashuTheme.spacing.snug),
                    )
                }
                if (errorText != null) {
                    InlineNotice(
                        text = errorText,
                        modifier = Modifier.padding(bottom = CashuTheme.spacing.snug),
                    )
                }
            }
        }

        NumberPadFooter(
            amount = amount,
            onAmountChange = onAmountChange,
            decimals = decimals,
            buttonText = if (sending) "Sending…" else "Send",
            onButtonClick = onSend,
            buttonEnabled = canSend,
            buttonLoading = sending,
            buttonModifier = Modifier.testTag(UiTestTags.SendEcashSubmit),
        )
        }
    }
}

/**
 * Quick actions for the full-screen P2PK key scanner the shell opens on this
 * sheet's behalf — the key shortcuts stay colocated with the flow. A selected
 * key takes the same return path as a scanned one.
 */
@Composable
internal fun rememberP2pkScannerQuickActions(
    settingsManager: SettingsManager,
    onSelectKey: (String) -> Unit,
): List<ScannerQuickAction> {
    val settings by settingsManager.state.collectAsState()
    val clipboard = LocalClipboardManager.current
    val haptics = rememberWalletHaptics()
    val primaryPublicKey = settingsManager.primaryP2PKKeyInfo()?.publicKey
    val validClipboardText = clipboard.getText()?.text?.takeIf {
        validateP2PKRecipientKey(it).normalizedKey != null
    }
    return buildList {
        if (settings.showP2PKButtonInDrawer && primaryPublicKey != null) {
            add(
                ScannerQuickAction("Lock to my key", Icons.Filled.Key) {
                    haptics.perform(WalletHaptic.Selection)
                    onSelectKey(primaryPublicKey)
                },
            )
        }
        if (validClipboardText != null) {
            add(
                ScannerQuickAction("Paste key", Icons.Outlined.ContentPaste) {
                    haptics.perform(WalletHaptic.Selection)
                    onSelectKey(validClipboardText)
                },
            )
        }
    }
}

internal fun isOwnP2pkRecipient(
    recipient: String,
    ownPublicKeys: Iterable<String>,
): Boolean {
    val comparableRecipient = SettingsManager.normalizeP2PKPublicKeyForComparison(recipient)
    return ownPublicKeys.any { ownKey ->
        SettingsManager.normalizeP2PKPublicKeyForComparison(ownKey) == comparableRecipient
    }
}

@Composable
internal fun LockEcashToolbarAction(
    onClick: () -> Unit,
) = LockEcashToolbarAction(onClick = onClick, legacyStateDescription = null)

@Composable
internal fun LockEcashToolbarAction(
    locked: Boolean,
    onToggle: () -> Unit,
) = LockEcashToolbarAction(
    onClick = onToggle,
    legacyStateDescription = if (locked) {
        "On. Only the recipient with the selected key can claim it."
    } else {
        "Off. Anyone with the ecash token can claim it."
    },
)

@Composable
private fun LockEcashToolbarAction(
    onClick: () -> Unit,
    legacyStateDescription: String?,
) {
    val haptics = rememberWalletHaptics()
    IconButton(
        onClick = {
            haptics.perform(WalletHaptic.Selection)
            onClick()
        },
        modifier = Modifier
            .testTag(UiTestTags.LockEcashToggle)
            .semantics {
                this[SemanticsActions.OnClick] = AccessibilityAction(LockEcashCopy.Hint, null)
                if (legacyStateDescription != null) {
                    stateDescription = legacyStateDescription
                }
            },
    ) {
        ToolbarIcon(
            imageVector = Icons.Outlined.Lock,
            contentDescription = LockEcashCopy.Label,
            tint = MaterialTheme.colorScheme.onSurface,
        )
    }
}

internal fun isPrimaryP2pkRecipient(
    recipient: String,
    primaryPublicKey: String?,
): Boolean {
    if (primaryPublicKey == null) return false
    val comparableRecipient = SettingsManager.normalizeP2PKPublicKeyForComparison(recipient)
    return SettingsManager.normalizeP2PKPublicKeyForComparison(primaryPublicKey) == comparableRecipient
}

@Composable
internal fun P2pkRecipientConfirmation(
    confirmedPubkey: String,
    recipientIsPrimaryKey: Boolean,
    onEditRecipient: () -> Unit,
    onRemoveRecipient: () -> Unit,
) {
    val haptics = rememberWalletHaptics()
    val recipientLabel = if (recipientIsPrimaryKey) "Your key" else P2PKKeyDisplay.shortLabel(confirmedPubkey)
    Surface(
        modifier = Modifier.fillMaxWidth().testTag(UiTestTags.P2pkRecipientConfirmation),
        shape = androidx.compose.foundation.shape.RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = 48.dp)
                    .clickable(onClickLabel = "Change the key") {
                        haptics.perform(WalletHaptic.Selection)
                        onEditRecipient()
                    }
                    .semantics { contentDescription = "Locked to public key" },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(30.dp)
                        .background(MaterialTheme.colorScheme.surfaceContainerHighest, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Filled.Lock, null, tint = MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(18.dp))
                }
                Column(Modifier.weight(1f)) {
                    Text("LOCKED TO", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 0.5.sp), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(recipientLabel, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium), color = MaterialTheme.colorScheme.onSurface, maxLines = 1, overflow = TextOverflow.MiddleEllipsis)
                }
            }
            IconButton(onClick = {
                haptics.perform(WalletHaptic.Selection)
                onRemoveRecipient()
            }) {
                Icon(Icons.Outlined.Close, "Remove lock", tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
            }
        }
    }
}

@Composable
internal fun P2pkLockSection(
    input: String,
    onInputChange: (String) -> Unit,
    inputError: String?,
    confirmedPubkey: String?,
    recipientIsOwnKey: Boolean,
    onEditRecipient: () -> Unit,
    onRemoveRecipient: () -> Unit,
    onScanKey: () -> Unit = {},
    onPasteKey: () -> Unit = {},
    canPasteKey: Boolean = false,
    myKeyHex: String?,
    onUseMyKey: () -> Unit,
) {
    if (confirmedPubkey != null) {
        val recipientLabel = if (recipientIsOwnKey) {
            "Your key"
        } else {
            P2PKKeyDisplay.shortLabel(confirmedPubkey)
        }
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .semantics {
                    contentDescription = "Locked ecash recipient: $recipientLabel"
                },
            shape = MaterialTheme.shapes.medium,
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 56.dp)
                    .padding(start = CashuTheme.spacing.default, end = CashuTheme.spacing.micro),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
            ) {
                Icon(
                    imageVector = Icons.Outlined.CheckCircle,
                    contentDescription = null,
                    tint = CashuTheme.colors.received,
                    modifier = Modifier.size(CashuTheme.spacing.comfortable),
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Locked to",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = recipientLabel,
                        style = MaterialTheme.typography.bodyMedium.copy(
                            fontFamily = if (recipientIsOwnKey) {
                                FontFamily.Default
                            } else {
                                FontFamily.Monospace
                            },
                        ),
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        overflow = TextOverflow.MiddleEllipsis,
                    )
                }
                IconButton(onClick = onEditRecipient) {
                    Icon(
                        imageVector = Icons.Outlined.Edit,
                        contentDescription = "Edit locked ecash recipient",
                    )
                }
                IconButton(onClick = onRemoveRecipient) {
                    Icon(
                        imageVector = Icons.Outlined.Close,
                        contentDescription = "Remove locked ecash recipient",
                    )
                }
            }
        }
        return
    }

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
    ) {
        Text(
            text = LockEcashCopy.Label,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            text = LockEcashCopy.RecipientEffect,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        CashuTextField(
            value = input,
            onValueChange = onInputChange,
            modifier = Modifier.fillMaxWidth(),
            label = LockEcashCopy.RecipientKeyLabel,
            placeholder = "02… or 64-character hex",
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                capitalization = androidx.compose.ui.text.input.KeyboardCapitalization.None,
            ),
            textStyle = MaterialTheme.typography.bodyMedium.copy(
                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
            ),
            isError = inputError != null && input.isNotBlank(),
        )
        if (inputError != null && input.isNotBlank()) {
            Text(
                text = inputError,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
        ) {
            com.cashu.me.ui.components.GhostButton(
                text = "Scan key",
                onClick = onScanKey,
                modifier = Modifier.weight(1f),
            )
            com.cashu.me.ui.components.GhostButton(
                text = "Paste key",
                onClick = onPasteKey,
                modifier = Modifier.weight(1f),
                enabled = canPasteKey,
            )
        }
        if (myKeyHex != null) {
            com.cashu.me.ui.components.GhostButton(
                text = "Lock ecash to my key",
                onClick = onUseMyKey,
            )
        }
    }
}

@Composable
private fun GeneratedFace(
    walletManager: com.cashu.me.Core.WalletManager,
    result: SendTokenResult,
    mintUrl: String,
    unit: String,
    pollingEnabled: Boolean,
    amountPresentation: PaymentConfirmationAmountPresentation,
    fiatLabel: String?,
    onDone: () -> Unit,
) {
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    var copied by remember { mutableStateOf(false) }
    var claimState: ClaimState by remember(result.token) { mutableStateOf(ClaimState.Pending) }
    var manualCheckResult: PendingTokenClaimCheckResult? by remember(result.token) {
        mutableStateOf(null)
    }
    LaunchedEffect(copied) {
        if (copied) {
            delay(2000)
            copied = false
        }
    }
    // Poll the mint to detect when the recipient redeems the token. Mirrors
    // iOS startClaimPolling: the spinner shows for the whole watch session
    // (flipping Pending↔Checking per probe made the row flicker), intervals
    // back off 5s → 15s, and after 10 checks the row rests at Pending.
    LaunchedEffect(result.token, mintUrl, pollingEnabled) {
        if (!pollingEnabled) {
            if (claimState != ClaimState.Claimed) claimState = ClaimState.Pending
            return@LaunchedEffect
        }
        claimState = ClaimState.Checking
        var interval = 5_000L
        repeat(10) {
            delay(interval)
            // A spent proof moves the tracked token to Claimed. Probe failures
            // stay Pending and the automatic watcher keeps trying.
            when (checkGeneratedTokenClaim(walletManager, result.token, mintUrl)) {
                PendingTokenClaimCheckResult.Claimed -> {
                    claimState = ClaimState.Claimed
                    return@LaunchedEffect
                }
                PendingTokenClaimCheckResult.NotClaimed -> Unit
                is PendingTokenClaimCheckResult.Failed -> Unit
            }
            interval = (interval + 1_000L).coerceAtMost(15_000L)
        }
        claimState = ClaimState.Pending
    }

    // Claimed resolves to the shared full-screen terminal (iOS parity), with
    // the same Amount/Fee/Mint facts shown while the token is pending.
    if (claimState == ClaimState.Claimed) {
        val receipt = buildSendEcashReceiptDetails(
            amountLabel = amountPresentation.primary,
            fee = result.fee,
            unit = unit,
            mintUrl = mintUrl,
        )
        com.cashu.me.ui.components.PaymentStatusScreen(
            phase = com.cashu.me.ui.components.PaymentStatusPhase.Success,
            title = "Claimed",
            onDone = onDone,
            rows = {
                com.cashu.me.ui.components.InspectorRow(
                    label = "Amount",
                    value = amountPresentation.primary,
                    leadingIcon = Icons.Outlined.Payments,
                )
                com.cashu.me.ui.components.CanvasDivider(leadingInset = 16.dp)
                receipt.fee?.let { feeLabel ->
                    com.cashu.me.ui.components.InspectorRow(
                        label = "Fee",
                        value = feeLabel,
                        valueMonospaced = true,
                        leadingIcon = Icons.Outlined.Receipt,
                    )
                    com.cashu.me.ui.components.CanvasDivider(leadingInset = 16.dp)
                }
                com.cashu.me.ui.components.InspectorRow(
                    label = "Mint",
                    value = receipt.mint,
                    leadingIcon = Icons.Outlined.AccountBalance,
                )
            },
        )
        return
    }

    // Scroll region + pinned footer, mirroring iOS (ScrollView with the Copy
    // button outside it) and TransactionDetailScreen's Copy action.
    Column(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(
                    horizontal = CashuTheme.spacing.comfortable,
                    vertical = CashuTheme.spacing.comfortable,
                ),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.loose),
        ) {
            QrCard(
                content = result.token,
                shareSubject = "Cashu token",
            )
            GeneratedEcashAmount(presentation = amountPresentation)
            ClaimStatusRow(claimState = claimState)
            if (!pollingEnabled) {
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
            // Detail rows: Fee -> Unit -> Fiat (sat-only) -> Mint (iOS order).
            Column(modifier = Modifier.fillMaxWidth()) {
                formatSendEcashFee(result.fee, unit)?.let { feeLabel ->
                    com.cashu.me.ui.components.InspectorRow(
                        label = "Fee",
                        value = feeLabel,
                        valueMonospaced = true,
                    )
                    com.cashu.me.ui.components.CanvasDivider(leadingInset = 16.dp)
                }
                com.cashu.me.ui.components.InspectorRow(
                    label = "Unit",
                    value = unit.uppercase(),
                )
                if (fiatLabel != null) {
                    com.cashu.me.ui.components.CanvasDivider(leadingInset = 16.dp)
                    com.cashu.me.ui.components.InspectorRow(
                        label = "Fiat",
                        value = fiatLabel,
                        valueMonospaced = true,
                    )
                }
                com.cashu.me.ui.components.CanvasDivider(leadingInset = 16.dp)
                com.cashu.me.ui.components.InspectorRow(
                    label = "Mint",
                    value = com.cashu.me.Core.shortenMintUrl(mintUrl),
                )
            }
        }
        Column(
            modifier = Modifier.padding(
                start = CashuTheme.spacing.comfortable,
                end = CashuTheme.spacing.comfortable,
                top = CashuTheme.spacing.micro,
                bottom = CashuTheme.spacing.comfortable,
            ),
        ) {
            // Gray tonal fill instead of the inverted-ink primary — the analog of
            // iOS's non-prominent glass capsule; adapts to light/dark.
            PrimaryButton(
                text = if (copied) "Copied" else "Copy",
                onClick = {
                    clipboard.setText(AnnotatedString(result.token))
                    copied = true
                },
                colors = neutralActionButtonColors(),
            )
            if (!pollingEnabled) {
                Spacer(Modifier.height(CashuTheme.spacing.tight))
                // Keep manual status checks with the pinned actions, rather
                // than inline beneath the QR code.
                PrimaryButton(
                    text = if (claimState == ClaimState.Checking) "Checking…" else "Check Status",
                    onClick = {
                        claimState = ClaimState.Checking
                        manualCheckResult = null
                        scope.launch {
                            val outcome = checkGeneratedTokenClaim(
                                walletManager = walletManager,
                                token = result.token,
                                mintUrl = mintUrl,
                            )
                            manualCheckResult = outcome
                            claimState = if (outcome == PendingTokenClaimCheckResult.Claimed) {
                                ClaimState.Claimed
                            } else {
                                ClaimState.Pending
                            }
                        }
                    },
                    loading = claimState == ClaimState.Checking,
                    modifier = Modifier.testTag(UiTestTags.SendEcashCheckStatus),
                )
            }
        }
        Spacer(Modifier.windowInsetsBottomHeight(WindowInsets.navigationBars))
    }
}

@Composable
private fun GeneratedEcashAmount(
    presentation: PaymentConfirmationAmountPresentation,
) {
    Column(
        modifier = Modifier.clearAndSetSemantics {
            contentDescription = presentation.talkBackDescription
        },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
    ) {
        Text(
            text = presentation.primary,
            style = MaterialTheme.typography.headlineMedium.withMonoDigits(),
            color = MaterialTheme.colorScheme.onSurface,
        )
        presentation.alternate?.let { alternate ->
            Surface(
                shape = CircleShape,
                color = MaterialTheme.colorScheme.surfaceVariant,
                contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
            ) {
                Text(
                    text = alternate,
                    modifier = Modifier.padding(
                        horizontal = CashuTheme.spacing.default,
                        vertical = CashuTheme.spacing.micro,
                    ),
                    style = MaterialTheme.typography.labelLarge.withMonoDigits(),
                )
            }
        }
    }
}

private enum class ClaimState { Pending, Checking, Claimed }

@Composable
private fun ClaimStatusRow(
    claimState: ClaimState,
    modifier: Modifier = Modifier,
) {
    AnimatedContent(
        targetState = claimState,
        modifier = modifier.semantics { liveRegion = LiveRegionMode.Polite },
        transitionSpec = { fadeIn(tween(220)) togetherWith fadeOut(tween(220)) },
        label = "claim-state",
    ) { state ->
        when (state) {
            ClaimState.Pending -> {
                val reducedMotion = rememberReducedMotion()
                val transition = rememberInfiniteTransition(label = "pending-pulse")
                val pulseAlpha by transition.animateFloat(
                    initialValue = 1f,
                    targetValue = 0.4f,
                    animationSpec = infiniteRepeatable(
                        animation = tween(1100),
                        repeatMode = RepeatMode.Reverse,
                    ),
                    label = "pending-alpha",
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
                    modifier = Modifier.alpha(if (reducedMotion) 1f else pulseAlpha),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Schedule,
                        contentDescription = null,
                        tint = com.cashu.me.ui.theme.CashuTheme.colors.pending,
                        modifier = Modifier.size(STATUS_ICON_SMALL),
                    )
                    Text(
                        text = "Pending",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                }
            }
            ClaimState.Checking -> {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
                ) {
                    LoadingIndicator(
                        modifier = Modifier.size(CHECKING_PROGRESS_SIZE),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = "Checking…",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            ClaimState.Claimed -> Unit
        }
    }
}

private suspend fun checkGeneratedTokenClaim(
    walletManager: WalletManager,
    token: String,
    mintUrl: String,
): PendingTokenClaimCheckResult = runPendingTokenClaimCheck {
    val walletState = walletManager.state.value
    when {
        walletState.claimedTokens.any { it.token == token } -> true
        else -> {
            val pending = walletState.pendingTokens.firstOrNull { it.token == token }
            if (pending != null) {
                // This path both checks the mint and moves the local History
                // record from Pending to Claimed when a proof is spent.
                walletManager.checkPendingTokenStatus(pending)
            } else {
                // Defensive fallback for a legacy/generated token with no local
                // pending record. New sends always take the tracked path above.
                walletManager.checkTokenSpent(token, mintUrl)
            }
        }
    }
}
