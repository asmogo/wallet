package org.cashu.wallet.ui.send

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Cancel
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.CurrencyBitcoin
import androidx.compose.material.icons.outlined.Receipt
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
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
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.cashu.wallet.Core.AmountFormatter
import org.cashu.wallet.Core.PaymentRequestDecodeResult
import org.cashu.wallet.Core.PaymentRequestDecoder
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Models.MeltPaymentResult
import org.cashu.wallet.ui.components.AmountText
import org.cashu.wallet.ui.components.CanvasDivider
import org.cashu.wallet.ui.components.CashuTextField
import org.cashu.wallet.ui.components.GhostButton
import org.cashu.wallet.ui.components.InspectorRow
import org.cashu.wallet.ui.components.NumberPad
import org.cashu.wallet.ui.components.PrimaryButton
import org.cashu.wallet.ui.components.TwoFaceScreen
import org.cashu.wallet.ui.theme.CashuTheme
import org.cashu.wallet.ui.theme.withMonoDigits

// Multi-line paste area for invoices / addresses; large enough to fit a BOLT12 string at body size.
private val DESTINATION_FIELD_HEIGHT = 160.dp
// Hero status icon on Done/Failed screens — much larger than the inline 20dp icons.
private val STATUS_HERO_ICON = 56.dp

private sealed interface PayFace {
    data object Input : PayFace
    data class Confirm(val raw: String, val decoded: PaymentRequestDecodeResult, val amount: Long?) : PayFace
    data class Paying(val raw: String) : PayFace
    data class Done(val result: MeltPaymentResult?) : PayFace
    data class Failed(val reason: String) : PayFace
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SendLightningScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    onClose: () -> Unit,
    prefilledPayload: String? = null,
    onPrefilledConsumed: () -> Unit = {},
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val formatter = remember { AmountFormatter() }
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current

    var face: PayFace by remember { mutableStateOf(PayFace.Input) }
    var input by remember { mutableStateOf("") }
    var amount by remember { mutableStateOf("") }
    var errorText by remember { mutableStateOf<String?>(null) }

    fun decode(raw: String) {
        errorText = null
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) {
            errorText = "Paste an invoice or address."
            return
        }
        val decoded = PaymentRequestDecoder.decode(
            trimmed,
            includeCashuPaymentRequests = true,
            preferCashuPaymentRequests = true,
        )
        if (decoded is PaymentRequestDecodeResult.Unrecognized) {
            errorText = "Couldn't read that. Paste a Lightning invoice, BOLT12 offer, on-chain address, Lightning address, or Cashu request."
            return
        }
        val knownAmount = decoded.knownAmountSats()
        face = PayFace.Confirm(raw = trimmed, decoded = decoded, amount = knownAmount)
        if (knownAmount != null) amount = knownAmount.toString()
    }

    LaunchedEffect(prefilledPayload) {
        val pre = prefilledPayload?.takeIf { it.isNotBlank() } ?: return@LaunchedEffect
        input = pre
        decode(pre)
        onPrefilledConsumed()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        when (face) {
                            PayFace.Input -> "Send Bitcoin"
                            is PayFace.Confirm -> "Confirm payment"
                            is PayFace.Paying -> "Sending"
                            is PayFace.Done -> "Sent"
                            is PayFace.Failed -> "Failed"
                        },
                        style = MaterialTheme.typography.titleMedium,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = {
                        when (face) {
                            PayFace.Input -> onClose()
                            is PayFace.Confirm -> face = PayFace.Input
                            is PayFace.Paying -> Unit
                            is PayFace.Done -> onClose()
                            is PayFace.Failed -> face = PayFace.Input
                        }
                    }) {
                        Icon(Icons.Outlined.Close, contentDescription = "Close")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { padding ->
        TwoFaceScreen(
            targetState = face,
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            forward = { initial, target -> faceOrdinal(target) >= faceOrdinal(initial) },
            label = "send-lightning-face",
        ) { current ->
            when (current) {
                PayFace.Input -> InputFace(
                    input = input,
                    onInputChange = { input = it; errorText = null },
                    onPaste = {
                        val clip = clipboard.getText()?.text
                        if (!clip.isNullOrBlank()) input = clip
                    },
                    onContinue = { decode(input) },
                    errorText = errorText,
                )

                is PayFace.Confirm -> ConfirmFace(
                    decoded = current.decoded,
                    amountInput = amount,
                    onAmountChange = { amount = it },
                    activeMintName = walletState.activeMint?.name ?: "No mint",
                    balanceText = formatter.formatWalletSats(walletState.balance, settings.useBitcoinSymbol),
                    onPay = {
                        val explicitAmount = amount.toLongOrNull()
                        if (current.amount == null && (explicitAmount == null || explicitAmount <= 0L)) {
                            errorText = "Enter an amount."
                            return@ConfirmFace
                        }
                        errorText = null
                        face = PayFace.Paying(current.raw)
                        scope.launch {
                            try {
                                val mintUrl = walletState.activeMint?.url
                                val effectiveAmount = current.amount ?: explicitAmount
                                if (current.decoded is PaymentRequestDecodeResult.CashuPaymentRequest) {
                                    walletManager.payCashuPaymentRequest(current.raw, effectiveAmount, mintUrl)
                                    face = PayFace.Done(result = null)
                                } else {
                                    val quote = walletManager.createMeltQuote(
                                        request = current.raw,
                                        amountSats = effectiveAmount,
                                        preferredMintURL = mintUrl,
                                    )
                                    val result = walletManager.meltTokens(quote.id, mintUrl)
                                    face = PayFace.Done(result = result)
                                }
                            } catch (t: Throwable) {
                                face = PayFace.Failed(t.message ?: "Payment failed.")
                            }
                        }
                    },
                    errorText = errorText,
                )

                is PayFace.Paying -> PayingFace()
                is PayFace.Done -> DoneFace(result = current.result, onClose = onClose)
                is PayFace.Failed -> FailedFace(reason = current.reason, onRetry = { face = PayFace.Input })
            }
        }
    }
}

private fun faceOrdinal(face: PayFace): Int = when (face) {
    PayFace.Input -> 0
    is PayFace.Confirm -> 1
    is PayFace.Paying -> 2
    is PayFace.Done -> 3
    is PayFace.Failed -> 3
}

private fun PaymentRequestDecodeResult.knownAmountSats(): Long? = when (this) {
    is PaymentRequestDecodeResult.Bolt11 -> amountSats
    is PaymentRequestDecodeResult.Bolt12 -> amountSats
    is PaymentRequestDecodeResult.CashuPaymentRequest -> summary.amount.takeIf { summary.isSatUnit }
    is PaymentRequestDecodeResult.LightningAddress -> null
    is PaymentRequestDecodeResult.Onchain -> null
    PaymentRequestDecodeResult.Unrecognized -> null
}

@Composable
private fun InputFace(
    input: String,
    onInputChange: (String) -> Unit,
    onPaste: () -> Unit,
    onContinue: () -> Unit,
    errorText: String?,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = CashuTheme.spacing.comfortable)
            .imePadding(),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        Text(
            text = "Paste a Lightning invoice, BOLT12 offer, on-chain address, or Lightning address.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        CashuTextField(
            value = input,
            onValueChange = onInputChange,
            modifier = Modifier
                .fillMaxWidth()
                .height(DESTINATION_FIELD_HEIGHT),
            label = "Destination",
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
        )
        GhostButton(text = "Paste from clipboard", onClick = onPaste)
        if (errorText != null) {
            Text(errorText, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
        Spacer(Modifier.weight(1f, fill = true))
        PrimaryButton(
            text = "Continue",
            onClick = onContinue,
            enabled = input.isNotBlank(),
        )
        Spacer(Modifier.navigationBarsPadding())
    }
}

@Composable
private fun ConfirmFace(
    decoded: PaymentRequestDecodeResult,
    amountInput: String,
    onAmountChange: (String) -> Unit,
    activeMintName: String,
    balanceText: String,
    onPay: () -> Unit,
    errorText: String?,
) {
    val knownAmount = decoded.knownAmountSats()
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(
                horizontal = CashuTheme.spacing.comfortable,
                vertical = CashuTheme.spacing.default,
            ),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            InspectorRow(
                label = "Type",
                value = PaymentRequestDecoder.typeLabel(decoded),
                leadingIcon = when (decoded) {
                    is PaymentRequestDecodeResult.Onchain -> Icons.Outlined.CurrencyBitcoin
                    else -> Icons.Outlined.Bolt
                },
            )
            CanvasDivider(leadingInset = 16)
            InspectorRow(
                label = "Destination",
                value = PaymentRequestDecoder.shortRepresentation("", decoded),
                valueMonospaced = true,
            )
            CanvasDivider(leadingInset = 16)
            InspectorRow(
                label = "Mint",
                value = activeMintName,
                leadingIcon = Icons.Outlined.AccountBalance,
            )
        }

        if (knownAmount != null) {
            AmountText(
                text = "$knownAmount",
                style = MaterialTheme.typography.displayMedium.withMonoDigits(),
            )
            Text(
                "sat",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            Text(
                "Enter amount",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            AmountText(
                text = amountInput.ifEmpty { "0" },
                style = MaterialTheme.typography.displayMedium.withMonoDigits(),
            )
            NumberPad(amount = amountInput, onAmountChange = onAmountChange)
        }

        Text(
            text = "Balance $balanceText",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        if (errorText != null) {
            Text(errorText, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }

        PrimaryButton(text = "Pay", onClick = onPay)
        Spacer(Modifier.navigationBarsPadding())
    }
}

@Composable
private fun PayingFace() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = CashuTheme.spacing.section),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        androidx.compose.material3.CircularProgressIndicator()
        Spacer(Modifier.height(CashuTheme.spacing.comfortable))
        Text(
            text = "Sending payment…",
            style = MaterialTheme.typography.titleMedium,
        )
    }
}

@Composable
private fun DoneFace(
    result: MeltPaymentResult?,
    onClose: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(
                horizontal = CashuTheme.spacing.section,
                vertical = CashuTheme.spacing.section,
            ),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            imageVector = Icons.Outlined.CheckCircle,
            contentDescription = null,
            tint = CashuTheme.colors.received,
            modifier = Modifier.size(STATUS_HERO_ICON),
        )
        Text(
            text = "Payment sent",
            style = MaterialTheme.typography.headlineSmall,
        )
        if (result != null) {
            Column(modifier = Modifier.fillMaxWidth()) {
                InspectorRow(
                    label = "Amount",
                    value = "${result.amount} sat",
                    leadingIcon = Icons.Outlined.Bolt,
                    valueMonospaced = true,
                )
                CanvasDivider(leadingInset = 16)
                InspectorRow(
                    label = "Fee",
                    value = "${result.feePaid} sat",
                    leadingIcon = Icons.Outlined.Receipt,
                    valueMonospaced = true,
                )
                if (result.preimage != null) {
                    CanvasDivider(leadingInset = 16)
                    InspectorRow(
                        label = "Preimage",
                        value = result.preimage,
                        valueMonospaced = true,
                    )
                }
            }
        }
        Spacer(Modifier.weight(1f, fill = true))
        PrimaryButton(text = "Done", onClick = onClose)
        Spacer(Modifier.navigationBarsPadding())
    }
}

@Composable
private fun FailedFace(reason: String, onRetry: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(CashuTheme.spacing.section),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            imageVector = Icons.Outlined.Cancel,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.error,
            modifier = Modifier.size(STATUS_HERO_ICON),
        )
        Text(
            "Payment failed",
            style = MaterialTheme.typography.headlineSmall,
        )
        Text(
            reason,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.weight(1f, fill = true))
        PrimaryButton(text = "Try again", onClick = onRetry)
        Spacer(Modifier.navigationBarsPadding())
    }
}
