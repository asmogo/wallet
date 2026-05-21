package org.cashu.wallet.Views.Send

import java.net.URI
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import org.cashu.wallet.Core.CashuPaymentRequestSummary
import org.cashu.wallet.Core.PaymentRequestDecodeResult
import org.cashu.wallet.Core.PaymentRequestDecoder
import org.cashu.wallet.Core.PriceService
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Core.compatibleMintsForCashuPaymentRequest
import org.cashu.wallet.Core.compatibleMintsForMeltPayment
import org.cashu.wallet.Core.mintCanCoverAmount
import org.cashu.wallet.Core.mintsIncludingActive
import org.cashu.wallet.Core.rankedMintsForDisplay
import org.cashu.wallet.Core.recommendedSendMint
import org.cashu.wallet.Core.selectMintForCashuPaymentRequest
import org.cashu.wallet.Core.selectMintForMeltPayment
import org.cashu.wallet.Models.MeltQuoteInfo
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Models.P2PKKeyInfo
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashu.wallet.Models.PendingToken
import org.cashu.wallet.Models.SendTokenResult
import org.cashu.wallet.Models.TransactionKind
import org.cashu.wallet.Models.TransactionType
import org.cashu.wallet.Views.Components.ClipboardSuggestionChip
import org.cashu.wallet.Views.Components.CopyShareRow
import org.cashu.wallet.Views.Components.KeyValueRow
import org.cashu.wallet.Views.Components.PrimaryActionButton
import org.cashu.wallet.Views.Components.QRCodeView
import org.cashu.wallet.Views.Components.QuietCard
import org.cashu.wallet.Views.Components.SecondaryActionButton
import org.cashu.wallet.Views.Components.cashuTokenShareContent
import org.cashu.wallet.Views.Send.Components.AuthorizingOverlay
import org.cashu.wallet.Views.Send.Components.AuthorizingOverlayState
import org.cashu.wallet.Views.Send.Components.AuthorizingPayment
import org.cashu.wallet.Views.Components.rememberClipboardText
import org.cashu.wallet.Views.Send.Components.NumberPadAmountInput

@Composable
fun SendView(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    priceService: PriceService,
    contentPadding: PaddingValues,
    scannedPayload: String? = null,
    onScannedPayloadConsumed: () -> Unit = {},
    onScan: () -> Unit = {},
) {
    val state by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val priceState by priceService.state.collectAsState()
    var amountInput by remember { mutableStateOf("") }
    var memo by remember { mutableStateOf("") }
    var request by remember { mutableStateOf("") }
    var selectedMintUrl by remember { mutableStateOf<String?>(null) }
    var sendMintUserSelected by remember { mutableStateOf(false) }
    var selectedPaymentMintUrl by remember { mutableStateOf<String?>(null) }
    var paymentMintUserSelected by remember { mutableStateOf(false) }
    var lockWithP2PK by remember { mutableStateOf(false) }
    var p2pkPubkeyInput by remember { mutableStateOf("") }
    var generatedToken by remember { mutableStateOf<SendTokenResult?>(null) }
    var meltQuote by remember { mutableStateOf<MeltQuoteInfo?>(null) }
    var paymentResult by remember { mutableStateOf<String?>(null) }
    var authorizingPayment by remember { mutableStateOf<AuthorizingPayment?>(null) }
    var pendingTokenMessage by remember { mutableStateOf<String?>(null) }
    var dismissedClipboardSuggestion by remember { mutableStateOf(false) }
    LaunchedEffect(scannedPayload) {
        val payload = scannedPayload?.trim().orEmpty()
        if (payload.isNotEmpty()) {
            request = payload
            onScannedPayloadConsumed()
        }
    }
    LaunchedEffect(Unit) {
        walletManager.loadTransactions()
    }
    val decoded = remember(request) {
        PaymentRequestDecoder.decode(request, includeCashuPaymentRequests = true, preferCashuPaymentRequests = true)
    }
    val clipboardText = rememberClipboardText()
    val clipboardPaymentSuggestion = remember(clipboardText) {
        clipboardText?.let {
            PaymentRequestDecoder.decode(it, includeCashuPaymentRequests = true, preferCashuPaymentRequests = true)
        }?.takeUnless { it == PaymentRequestDecodeResult.Unrecognized }
    }
    val recentRecipients = remember(state.transactions) {
        state.transactions
            .asSequence()
            .filter {
                it.type == TransactionType.Outgoing &&
                    (it.kind == TransactionKind.Lightning || it.kind == TransactionKind.Onchain) &&
                    !it.invoice.isNullOrBlank()
            }
            .sortedByDescending { it.dateEpochMillis }
            .distinctBy { it.invoice }
            .take(3)
            .map { RecentRecipient(it.id, it.invoice.orEmpty(), it.kind, it.amount) }
            .toList()
    }
    LaunchedEffect(clipboardText) {
        dismissedClipboardSuggestion = false
    }
    val cashuPaymentRequest = decoded as? PaymentRequestDecodeResult.CashuPaymentRequest
    val parsedAmount = amountInput.toLongOrNull()
    val availableSendMints = remember(state.mints, state.activeMint) {
        mintsIncludingActive(state.mints, state.activeMint)
    }
    LaunchedEffect(availableSendMints, state.activeMint?.url, parsedAmount, sendMintUserSelected) {
        val selectedStillExists = selectedMintUrl != null && availableSendMints.any { it.url == selectedMintUrl }
        val selectedCanCover = mintCanCoverAmount(
            availableSendMints.firstOrNull { it.url == selectedMintUrl },
            parsedAmount,
        )
        if (!selectedStillExists || (!sendMintUserSelected && !selectedCanCover)) {
            selectedMintUrl = recommendedSendMint(availableSendMints, state.activeMint?.url, parsedAmount)?.url
        }
    }
    val selectedMint = remember(availableSendMints, selectedMintUrl) {
        availableSendMints.firstOrNull { it.url == selectedMintUrl }
    }
    val cashuPaymentAmount = cashuPaymentRequest?.summary?.amount ?: parsedAmount
    val cashuCompatibleMints = remember(cashuPaymentRequest, availableSendMints) {
        cashuPaymentRequest?.summary?.let {
            compatibleMintsForCashuPaymentRequest(it, availableSendMints)
        }.orEmpty()
    }
    val cashuSelectedMint = remember(
        cashuPaymentRequest,
        availableSendMints,
        selectedMintUrl,
        state.activeMint?.url,
        cashuPaymentAmount,
    ) {
        cashuPaymentRequest?.summary?.let {
            selectMintForCashuPaymentRequest(
                request = it,
                mints = availableSendMints,
                selectedMintUrl = selectedMintUrl,
                activeMintUrl = state.activeMint?.url,
                amountSats = cashuPaymentAmount,
            )
        }
    }
    val paymentMethod = remember(decoded) {
        when (decoded) {
            is PaymentRequestDecodeResult.Bolt12 -> PaymentMethodKind.Bolt12
            is PaymentRequestDecodeResult.Onchain -> PaymentMethodKind.Onchain
            else -> PaymentMethodKind.Bolt11
        }
    }
    val paymentKnownAmount = remember(decoded, parsedAmount) {
        when (val current = decoded) {
            is PaymentRequestDecodeResult.Bolt11 -> current.amountSats ?: parsedAmount
            is PaymentRequestDecodeResult.Bolt12 -> current.amountSats ?: parsedAmount
            is PaymentRequestDecodeResult.LightningAddress,
            is PaymentRequestDecodeResult.Onchain -> parsedAmount
            else -> parsedAmount
        }
    }
    val paymentCompatibleMints = remember(availableSendMints, paymentMethod) {
        compatibleMintsForMeltPayment(availableSendMints, paymentMethod)
    }
    LaunchedEffect(paymentCompatibleMints, paymentMethod, paymentKnownAmount, paymentMintUserSelected, state.activeMint?.url) {
        val selected = paymentCompatibleMints.firstOrNull { it.url == selectedPaymentMintUrl }
        val selectedCanCover = mintCanCoverAmount(selected, paymentKnownAmount)
        if (selected == null || (!paymentMintUserSelected && !selectedCanCover)) {
            selectedPaymentMintUrl = selectMintForMeltPayment(
                mints = availableSendMints,
                selectedMintUrl = selectedPaymentMintUrl,
                activeMintUrl = state.activeMint?.url,
                paymentMethod = paymentMethod,
                minimumAmount = paymentKnownAmount,
            )?.url
        }
    }
    val selectedPaymentMint = remember(
        availableSendMints,
        selectedPaymentMintUrl,
        state.activeMint?.url,
        paymentMethod,
        paymentKnownAmount,
    ) {
        selectMintForMeltPayment(
            mints = availableSendMints,
            selectedMintUrl = selectedPaymentMintUrl,
            activeMintUrl = state.activeMint?.url,
            paymentMethod = paymentMethod,
            minimumAmount = paymentKnownAmount,
        )
    }
    val normalizedP2PKPubkey = remember(lockWithP2PK, p2pkPubkeyInput) {
        if (!lockWithP2PK) {
            null
        } else {
            runCatching { SettingsManager.normalizeP2PKPublicKeyForSend(p2pkPubkeyInput) }.getOrNull()
        }
    }
    val p2pkInputIsInvalid = lockWithP2PK &&
        p2pkPubkeyInput.trim().isNotEmpty() &&
        normalizedP2PKPubkey == null
    val selectedMintHasBalance = selectedMint != null &&
        (parsedAmount == null || parsedAmount <= selectedMint.balance)
    val canCreateToken = selectedMint != null &&
        !state.isLoading &&
        parsedAmount != null &&
        parsedAmount > 0 &&
        selectedMintHasBalance &&
        (!lockWithP2PK || normalizedP2PKPubkey != null)
    val paymentAmountRequired = decoded is PaymentRequestDecodeResult.LightningAddress ||
        decoded is PaymentRequestDecodeResult.Onchain
    val canCreatePaymentQuote = request.isNotBlank() &&
        !state.isLoading &&
        (!paymentAmountRequired || (parsedAmount != null && parsedAmount > 0))
    fun startAuthorizing(amountSats: Long, recipient: String, recipientCaption: String?) {
        authorizingPayment = AuthorizingPayment(
            amountSats = amountSats,
            recipient = recipient,
            recipientCaption = recipientCaption,
            state = AuthorizingOverlayState.Authorizing,
        )
    }
    fun setAuthorizingState(nextState: AuthorizingOverlayState) {
        authorizingPayment = authorizingPayment?.copy(state = nextState)
    }
    fun paymentErrorMessage(error: Throwable): String =
        error.message ?: "Payment failed."
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(contentPadding),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Send", style = MaterialTheme.typography.headlineSmall)
        OutlinedTextField(
            value = amountInput,
            onValueChange = { amountInput = it.filter(Char::isDigit) },
            label = { Text("Amount") },
            suffix = { Text("sat") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        )
        NumberPadAmountInput(
            amount = amountInput,
            onAmountChange = { amountInput = it },
        )
        OutlinedTextField(
            value = memo,
            onValueChange = { memo = it },
            label = { Text("Memo") },
        )
        SendMintSelector(
            selectedMint = selectedMint,
            mints = rankedMintsForDisplay(availableSendMints, selectedMintUrl, parsedAmount),
            amount = parsedAmount,
            onSelect = {
                selectedMintUrl = it.url
                sendMintUserSelected = true
            },
            onUseMax = { mint -> amountInput = mint.balance.toString() },
        )
        P2PKLockSection(
            lockWithP2PK = lockWithP2PK,
            onLockChanged = { lockWithP2PK = it },
            publicKeyInput = p2pkPubkeyInput,
            onPublicKeyInputChanged = { p2pkPubkeyInput = it },
            storedKeys = settings.p2pkKeys,
            inputIsInvalid = p2pkInputIsInvalid,
            onStoredKeySelected = {
                p2pkPubkeyInput = it.publicKey
                lockWithP2PK = true
            },
        )
        PrimaryActionButton(
            text = "Create ecash token",
            enabled = canCreateToken,
        ) {
            val amount = parsedAmount
            val p2pkPubkey = if (lockWithP2PK) normalizedP2PKPubkey else null
            val mintUrl = selectedMint?.url
            if (amount != null && mintUrl != null && (!lockWithP2PK || p2pkPubkey != null)) {
                walletManager.launch {
                    generatedToken = walletManager.sendTokens(amount, memo.ifBlank { null }, p2pkPubkey, mintUrl)
                    pendingTokenMessage = null
                }
            }
        }
        generatedToken?.let { result ->
            GeneratedTokenCard(result)
        }
        if (state.pendingTokens.isNotEmpty()) {
            PendingSentTokensSection(
                tokens = state.pendingTokens,
                isLoading = state.isLoading,
                onCheckStatus = { token ->
                    walletManager.launch {
                        val claimed = walletManager.checkPendingTokenStatus(token)
                        pendingTokenMessage = if (claimed) "Token claimed" else "Still pending"
                    }
                },
                onReclaim = { token ->
                    walletManager.launch {
                        val amount = walletManager.reclaimPendingToken(token)
                        pendingTokenMessage = "Reclaimed $amount sat"
                    }
                },
                onRemove = { token -> walletManager.removePendingToken(token.tokenId) },
            )
        }
        pendingTokenMessage?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
        SecondaryActionButton("Scan payment request", enabled = !state.isLoading, onClick = onScan)
        if (
            request.isBlank() &&
            clipboardText != null &&
            clipboardPaymentSuggestion != null &&
            !dismissedClipboardSuggestion
        ) {
            ClipboardSuggestionChip(
                title = "On clipboard",
                detail = "${PaymentRequestDecoder.typeLabel(clipboardPaymentSuggestion)} · ${
                    PaymentRequestDecoder.shortRepresentation(clipboardText, clipboardPaymentSuggestion)
                }",
                onUse = {
                    request = clipboardText
                    dismissedClipboardSuggestion = true
                },
                onDismiss = { dismissedClipboardSuggestion = true },
            )
        }
        if (request.isBlank() && recentRecipients.isNotEmpty()) {
            RecentRecipientsSection(
                recipients = recentRecipients,
                onSelect = { recipient -> request = recipient.invoice },
            )
        }
        OutlinedTextField(
            value = request,
            onValueChange = { request = it },
            label = { Text("Invoice, address, or Cashu request") },
            minLines = 3,
        )
        Text(PaymentRequestDecoder.typeLabel(decoded), color = MaterialTheme.colorScheme.secondary)
        if (paymentAmountRequired && parsedAmount == null) {
            Text(
                "Enter an amount for address payments.",
                color = MaterialTheme.colorScheme.secondary,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        cashuPaymentRequest?.let { requestResult ->
            CashuPaymentRequestCard(
                request = requestResult.summary,
                amountInput = amountInput,
                selectedMint = cashuSelectedMint,
                hasCompatibleMint = cashuCompatibleMints.isNotEmpty(),
                isLoading = state.isLoading,
                onPay = {
                    val amount = requestResult.summary.amount ?: amountInput.toLongOrNull()
                    if (amount == null) return@CashuPaymentRequestCard
                    startAuthorizing(
                        amountSats = amount,
                        recipient = PaymentRequestDecoder.shortRepresentation(
                            requestResult.summary.encoded,
                            requestResult,
                        ),
                        recipientCaption = "Cashu payment request",
                    )
                    walletManager.launch {
                        runCatching {
                            walletManager.payCashuPaymentRequest(
                                encoded = requestResult.summary.encoded,
                                customAmountSats = if (requestResult.summary.amount == null) amount else null,
                                preferredMintURL = cashuSelectedMint?.url,
                            )
                        }.onSuccess {
                            paymentResult = "Cashu request paid"
                            setAuthorizingState(AuthorizingOverlayState.Sent)
                        }.onFailure { error ->
                            setAuthorizingState(AuthorizingOverlayState.Error(paymentErrorMessage(error)))
                        }
                    }
                },
            )
        } ?: run {
            if (request.isNotBlank() && decoded != PaymentRequestDecodeResult.Unrecognized) {
                SendMintSelector(
                    title = "Payment mint",
                    selectedMint = selectedPaymentMint,
                    mints = rankedMintsForDisplay(paymentCompatibleMints, selectedPaymentMint?.url, paymentKnownAmount),
                    amount = paymentKnownAmount,
                    onSelect = {
                        selectedPaymentMintUrl = it.url
                        paymentMintUserSelected = true
                    },
                    onUseMax = { mint -> amountInput = mint.balance.toString() },
                )
            }
            SecondaryActionButton(
                text = "Create payment quote",
                enabled = canCreatePaymentQuote && selectedPaymentMint != null,
            ) {
                walletManager.launch {
                    meltQuote = walletManager.createMeltQuote(
                        request = request,
                        amountSats = parsedAmount,
                        preferredMintURL = selectedPaymentMint?.url,
                    )
                }
            }
        }
        meltQuote?.let { quote ->
            MeltQuoteCard(
                quote = quote,
                isLoading = state.isLoading,
                onPay = {
                    startAuthorizing(
                        amountSats = quote.amount,
                        recipient = PaymentRequestDecoder.shortRepresentation(request, decoded),
                        recipientCaption = quote.paymentMethod.displayName,
                    )
                    walletManager.launch {
                        runCatching {
                            walletManager.meltTokens(quote.id, quote.mintUrl)
                        }.onSuccess { result ->
                            paymentResult = "Paid ${result.amount} sat with ${result.feePaid} sat fee"
                            meltQuote = null
                            setAuthorizingState(AuthorizingOverlayState.Sent)
                        }.onFailure { error ->
                            setAuthorizingState(AuthorizingOverlayState.Error(paymentErrorMessage(error)))
                        }
                    }
                },
            )
        }
        paymentResult?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
            state.errorMessage?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
        authorizingPayment?.let { payment ->
            AuthorizingOverlay(
                payment = payment,
                settings = settings,
                priceState = priceState,
                onDismiss = { authorizingPayment = null },
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

@Composable
private fun SendMintSelector(
    title: String = "Mint",
    selectedMint: MintInfo?,
    mints: List<MintInfo>,
    amount: Long?,
    onSelect: (MintInfo) -> Unit,
    onUseMax: (MintInfo) -> Unit,
) {
    var mintMenuExpanded by remember { mutableStateOf(false) }
    QuietCard {
        Text(title, style = MaterialTheme.typography.titleMedium)
        if (selectedMint == null) {
            Text("No mint available", color = MaterialTheme.colorScheme.error)
            return@QuietCard
        }
        KeyValueRow("Selected", selectedMint.displayName())
        KeyValueRow("Balance", "${selectedMint.balance} sat")
        if (amount != null && amount > selectedMint.balance) {
            Text(
                "Insufficient balance at selected mint",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        Box(Modifier.fillMaxWidth()) {
            SecondaryActionButton("Choose mint", enabled = mints.isNotEmpty()) {
                mintMenuExpanded = true
            }
            DropdownMenu(
                expanded = mintMenuExpanded,
                onDismissRequest = { mintMenuExpanded = false },
            ) {
                mints.forEach { mint ->
                    DropdownMenuItem(
                        text = { Text("${mint.displayName()} (${mint.balance} sat)") },
                        onClick = {
                            mintMenuExpanded = false
                            onSelect(mint)
                        },
                    )
                }
            }
        }
        SecondaryActionButton(
            text = "Use max",
            enabled = selectedMint.balance > 0,
            onClick = { onUseMax(selectedMint) },
        )
    }
}

@Composable
private fun P2PKLockSection(
    lockWithP2PK: Boolean,
    onLockChanged: (Boolean) -> Unit,
    publicKeyInput: String,
    onPublicKeyInputChanged: (String) -> Unit,
    storedKeys: List<P2PKKeyInfo>,
    inputIsInvalid: Boolean,
    onStoredKeySelected: (P2PKKeyInfo) -> Unit,
) {
    var storedKeyMenuExpanded by remember { mutableStateOf(false) }
    QuietCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Lock with P2PK", style = MaterialTheme.typography.titleMedium)
                Text(
                    text = if (lockWithP2PK) "Recipient key required" else "Unlocked ecash token",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.secondary,
                )
            }
            Switch(checked = lockWithP2PK, onCheckedChange = onLockChanged)
        }

        if (lockWithP2PK) {
            OutlinedTextField(
                value = publicKeyInput,
                onValueChange = onPublicKeyInputChanged,
                label = { Text("Recipient public key") },
                isError = inputIsInvalid,
                modifier = Modifier.fillMaxWidth(),
                textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
                minLines = 2,
            )
            if (inputIsInvalid) {
                Text(
                    "Invalid P2PK key format",
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            if (storedKeys.isNotEmpty()) {
                Box(Modifier.fillMaxWidth()) {
                    SecondaryActionButton("Use stored P2PK key") {
                        storedKeyMenuExpanded = true
                    }
                    DropdownMenu(
                        expanded = storedKeyMenuExpanded,
                        onDismissRequest = { storedKeyMenuExpanded = false },
                    ) {
                        storedKeys.asReversed().forEach { key ->
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        "${key.label.ifBlank { "P2PK key" }} (${shortP2PKKey(key.publicKey)})",
                                    )
                                },
                                onClick = {
                                    storedKeyMenuExpanded = false
                                    onStoredKeySelected(key)
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun GeneratedTokenCard(result: SendTokenResult) {
    QuietCard {
        Text("Ecash token", style = MaterialTheme.typography.titleMedium)
        KeyValueRow("Fee", "${result.fee} sat")
        QRCodeView(content = result.token, modifier = Modifier.fillMaxWidth(), showControls = false)
        OutlinedTextField(
            value = result.token,
            onValueChange = {},
            readOnly = true,
            label = { Text("Token") },
            minLines = 3,
            modifier = Modifier.fillMaxWidth(),
        )
        CopyShareRow(
            label = "Ecash token",
            content = result.token,
            shareContent = cashuTokenShareContent(result.token),
        )
    }
}

private fun shortP2PKKey(publicKey: String): String {
    val trimmed = publicKey.trim()
    return if (trimmed.length > 18) {
        "${trimmed.take(8)}...${trimmed.takeLast(8)}"
    } else {
        trimmed
    }
}

@Composable
private fun RecentRecipientsSection(
    recipients: List<RecentRecipient>,
    onSelect: (RecentRecipient) -> Unit,
) {
    QuietCard {
        Text("Recent", style = MaterialTheme.typography.titleMedium)
        recipients.forEach { recipient ->
            KeyValueRow(
                label = recipient.kind.displayName,
                value = "${recipient.amount} sat",
            )
            SecondaryActionButton(
                text = shortPaymentTarget(recipient.invoice),
                onClick = { onSelect(recipient) },
            )
        }
    }
}

@Composable
private fun PendingSentTokensSection(
    tokens: List<PendingToken>,
    isLoading: Boolean,
    onCheckStatus: (PendingToken) -> Unit,
    onReclaim: (PendingToken) -> Unit,
    onRemove: (PendingToken) -> Unit,
) {
    QuietCard {
        Text("Pending sent", style = MaterialTheme.typography.titleMedium)
        tokens.sortedByDescending { it.dateEpochMillis }.forEach { token ->
            KeyValueRow("Amount", "${token.amount} sat")
            KeyValueRow("Fee", "${token.fee} sat")
            KeyValueRow("Mint", shortMintUrl(token.mintUrl))
            token.memo?.takeIf { it.isNotBlank() }?.let { KeyValueRow("Memo", it) }
            PrimaryActionButton(
                text = "Check status",
                enabled = !isLoading,
                onClick = { onCheckStatus(token) },
            )
            SecondaryActionButton(
                text = "Reclaim token",
                enabled = !isLoading,
                onClick = { onReclaim(token) },
            )
            SecondaryActionButton(
                text = "Remove",
                enabled = !isLoading,
                onClick = { onRemove(token) },
            )
        }
    }
}

private fun shortMintUrl(url: String): String {
    return runCatching { URI.create(url).host }
        .getOrNull()
        ?.takeIf { it.isNotBlank() }
        ?: url
}

private fun MintInfo.displayName(): String {
    return name.takeIf { it.isNotBlank() && it != "Unknown Mint" } ?: shortMintUrl(url)
}

private data class RecentRecipient(
    val id: String,
    val invoice: String,
    val kind: TransactionKind,
    val amount: Long,
)

private fun shortPaymentTarget(target: String): String {
    val trimmed = target.trim()
    return if (trimmed.length > 24) {
        "${trimmed.take(12)}...${trimmed.takeLast(8)}"
    } else {
        trimmed
    }
}

@Composable
private fun CashuPaymentRequestCard(
    request: CashuPaymentRequestSummary,
    amountInput: String,
    selectedMint: MintInfo?,
    hasCompatibleMint: Boolean,
    isLoading: Boolean,
    onPay: () -> Unit,
) {
    val requiresAmount = request.amount == null
    val customAmount = amountInput.toLongOrNull()
    val amountIsValid = !requiresAmount || (customAmount != null && customAmount > 0)
    QuietCard {
        Text(request.description ?: "Cashu payment request", style = MaterialTheme.typography.titleMedium)
        KeyValueRow("Amount", request.amount?.let { "$it ${request.unit ?: "sat"}" } ?: "Custom")
        if (request.mints.isNotEmpty()) {
            KeyValueRow("Mint", request.mints.first())
        }
        KeyValueRow("Pay from", selectedMint?.displayName() ?: "No compatible mint")
        if (!request.isSatUnit) {
            Text(
                "Only sat Cashu payment requests are supported.",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        if (!amountIsValid) {
            Text(
                "Enter an amount to pay this request.",
                color = MaterialTheme.colorScheme.secondary,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        if (!hasCompatibleMint) {
            Text(
                "No compatible local mint.",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        } else if (selectedMint == null) {
            Text(
                "No compatible mint has enough balance.",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        PrimaryActionButton(
            text = "Pay Cashu request",
            enabled = !isLoading && request.isSatUnit && amountIsValid && selectedMint != null,
            onClick = onPay,
        )
    }
}

@Composable
private fun MeltQuoteCard(
    quote: MeltQuoteInfo,
    isLoading: Boolean,
    onPay: () -> Unit,
) {
    QuietCard {
        Text("Payment quote", style = MaterialTheme.typography.titleMedium)
        KeyValueRow("Method", quote.paymentMethod.displayName)
        KeyValueRow("Amount", "${quote.amount} sat")
        KeyValueRow("Fee reserve", "${quote.feeReserve} sat")
        KeyValueRow("Total", "${quote.totalAmount} sat")
        KeyValueRow("State", quote.state.name)
        KeyValueRow("Mint", quote.mintUrl)
        PrimaryActionButton(
            text = "Pay quote",
            enabled = !isLoading,
            onClick = onPay,
        )
    }
}
