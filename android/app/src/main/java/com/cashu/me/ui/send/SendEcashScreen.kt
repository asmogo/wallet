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
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material.icons.outlined.LockOpen
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.Receipt
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
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.Wallet.isInsufficientBalance
import com.cashu.me.Core.Wallet.userFacingWalletMessage
import com.cashu.me.Core.WalletManager
import com.cashu.me.Models.SendTokenResult
import com.cashu.me.ui.components.AmountEntryHero
import com.cashu.me.ui.components.CashuTextField
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
    const val RecipientEffect = "Only the recipient with this public key can claim it."
    const val RecipientKeyLabel = "Recipient public key (P2PK)"
    const val InvalidRecipientKey =
        "Enter a valid recipient public key: 64 hex characters, or 66 beginning with 02 or 03."

    fun stateDescription(locked: Boolean): String = if (locked) {
        "On. Only the recipient with the selected key can claim it."
    } else {
        "Off. Anyone with the ecash token can claim it."
    }
}

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

@Composable
fun SendEcashScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    priceService: com.cashu.me.Core.PriceService,
    onBack: () -> Unit,
    onClose: () -> Unit,
    onDismissLockChanged: (Boolean) -> Unit = {},
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val priceState by priceService.state.collectAsState()
    val formatter = remember { AmountFormatter() }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    var face: SendFace by remember { mutableStateOf(SendFace.Input) }
    var amount by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }
    var pickerOpen by remember { mutableStateOf(false) }
    var selectedMintUrl by remember { mutableStateOf<String?>(null) }
    var unitPickerOpen by remember { mutableStateOf(false) }
    var selectedUnit by remember { mutableStateOf<String?>(null) }
    var nonSatBalance by remember { mutableStateOf<Long?>(null) }
    var p2pkOn by remember { mutableStateOf(false) }
    var p2pkInput by remember { mutableStateOf("") }
    var p2pkInputError by remember { mutableStateOf<String?>(null) }
    var p2pkEditing by remember { mutableStateOf(true) }

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

    // Normalize and validate the P2PK input only when the lock is on.
    val validatedP2pkPubkey: String? = remember(p2pkOn, p2pkInput) {
        if (!p2pkOn) null
        else runCatching {
            com.cashu.me.Core.SettingsManager.normalizeP2PKPublicKeyForSend(p2pkInput)
        }.getOrNull()
    }
    val primaryP2pkPublicKey = settingsManager.primaryP2PKKeyInfo()?.publicKey
    val p2pkRecipientIsOwnKey = validatedP2pkPubkey?.let { recipient ->
        isOwnP2pkRecipient(
            recipient = recipient,
            ownPublicKeys = buildList {
                primaryP2pkPublicKey?.let(::add)
                addAll(settings.p2pkKeys.map { it.publicKey })
            },
        )
    } == true
    LaunchedEffect(p2pkOn, validatedP2pkPubkey) {
        when {
            !p2pkOn -> p2pkEditing = true
            validatedP2pkPubkey != null -> p2pkEditing = false
        }
    }
    LaunchedEffect(p2pkOn, p2pkInput) {
        if (!p2pkOn) {
            p2pkInputError = null
            return@LaunchedEffect
        }
        val trimmed = p2pkInput.trim()
        if (trimmed.isEmpty()) {
            p2pkInputError = null
            return@LaunchedEffect
        }
        p2pkInputError = runCatching {
            com.cashu.me.Core.SettingsManager.normalizeP2PKPublicKeyForSend(trimmed)
        }.exceptionOrNull()?.let { LockEcashCopy.InvalidRecipientKey }
    }

    // Generation counts as money-in-motion: block sheet dismissal.
    LaunchedEffect(sending) { onDismissLockChanged(sending) }

    // System back mirrors the header chevron: Generated → Input, Input → the
    // Send surface. Swallow back while a token is being generated.
    BackHandler(enabled = true) {
        when {
            sending -> Unit
            face is SendFace.Generated -> face = SendFace.Input
            else -> onBack()
        }
    }

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
                        locked = p2pkOn,
                        onToggle = { p2pkOn = !p2pkOn },
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
                    p2pkOn = p2pkOn,
                    p2pkInput = p2pkInput,
                    onP2pkInputChange = { p2pkInput = it },
                    p2pkInputError = p2pkInputError,
                    confirmedP2pkPubkey = validatedP2pkPubkey?.takeUnless { p2pkEditing },
                    p2pkRecipientIsOwnKey = p2pkRecipientIsOwnKey,
                    onEditP2pkRecipient = { p2pkEditing = true },
                    onRemoveP2pkRecipient = {
                        p2pkInput = ""
                        p2pkOn = false
                    },
                    // iOS "Lock to my key" shortcut: opt-in via the Locked Ecash
                    // toggle, and it targets the seed-derived primary key.
                    p2pkMyKeyHex = if (settings.showP2PKButtonInDrawer) {
                        primaryP2pkPublicKey
                    } else null,
                    onUseMyP2pkKey = {
                        primaryP2pkPublicKey?.let { p2pkInput = it }
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
                            errorText = p2pkInputError ?: LockEcashCopy.InvalidRecipientKey
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
    p2pkOn: Boolean,
    p2pkInput: String,
    onP2pkInputChange: (String) -> Unit,
    p2pkInputError: String?,
    confirmedP2pkPubkey: String?,
    p2pkRecipientIsOwnKey: Boolean,
    onEditP2pkRecipient: () -> Unit,
    onRemoveP2pkRecipient: () -> Unit,
    p2pkMyKeyHex: String?,
    onUseMyP2pkKey: () -> Unit,
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

        AnimatedVisibility(visible = p2pkOn) {
            P2pkLockSection(
                input = p2pkInput,
                onInputChange = onP2pkInputChange,
                inputError = p2pkInputError,
                confirmedPubkey = confirmedP2pkPubkey,
                recipientIsOwnKey = p2pkRecipientIsOwnKey,
                onEditRecipient = onEditP2pkRecipient,
                onRemoveRecipient = onRemoveP2pkRecipient,
                myKeyHex = p2pkMyKeyHex,
                onUseMyKey = onUseMyP2pkKey,
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
    locked: Boolean,
    onToggle: () -> Unit,
) {
    IconButton(
        onClick = onToggle,
        modifier = Modifier
            .testTag(UiTestTags.LockEcashToggle)
            .semantics {
                stateDescription = LockEcashCopy.stateDescription(locked)
            },
    ) {
        ToolbarIcon(
            imageVector = if (locked) Icons.Filled.Lock else Icons.Outlined.LockOpen,
            contentDescription = LockEcashCopy.Label,
            tint = if (locked) MaterialTheme.colorScheme.onSurface
            else MaterialTheme.colorScheme.onSurfaceVariant,
        )
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
    var copied by remember { mutableStateOf(false) }
    var claimState: ClaimState by remember(result.token) { mutableStateOf(ClaimState.Pending) }
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
        if (!pollingEnabled) return@LaunchedEffect
        claimState = ClaimState.Checking
        var interval = 5_000L
        repeat(10) {
            delay(interval)
            // checkTokenSpent returns true once any proof is spent (redeemed);
            // null means the check failed — keep watching, never fake a claim.
            val spent = runCatching {
                walletManager.checkTokenSpent(result.token, mintUrl)
            }.getOrNull()
            if (spent == true) {
                claimState = ClaimState.Claimed
                return@LaunchedEffect
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
        // Gray tonal fill instead of the inverted-ink primary — the analog of
        // iOS's non-prominent glass capsule; adapts to light/dark.
        PrimaryButton(
            text = if (copied) "Copied" else "Copy",
            onClick = {
                clipboard.setText(AnnotatedString(result.token))
                copied = true
            },
            colors = neutralActionButtonColors(),
            modifier = Modifier.padding(
                start = CashuTheme.spacing.comfortable,
                end = CashuTheme.spacing.comfortable,
                top = CashuTheme.spacing.micro,
                bottom = CashuTheme.spacing.comfortable,
            ),
        )
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
private fun ClaimStatusRow(claimState: ClaimState) {
    AnimatedContent(
        targetState = claimState,
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
