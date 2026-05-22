package org.cashu.wallet.Views.Receive

import java.net.URI
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.AllInclusive
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import org.cashu.wallet.Core.CashuRequestStore
import org.cashu.wallet.Core.NostrService
import org.cashu.wallet.Core.PaymentRequestBuilder
import org.cashu.wallet.Core.PriceService
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.Core.TokenParser
import org.cashu.wallet.Core.WalletHaptic
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Core.quoteExpiryText
import org.cashu.wallet.Core.rememberWalletHaptics
import org.cashu.wallet.Core.shouldPollMintQuote
import org.cashu.wallet.Models.CashuRequest
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Models.MintQuoteInfo
import org.cashu.wallet.Models.MintQuoteState
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashu.wallet.Models.PendingReceiveToken
import org.cashu.wallet.Models.TokenInfo
import org.cashu.wallet.Views.Components.ClipboardSuggestionChip
import org.cashu.wallet.Views.Components.CopyShareRow
import org.cashu.wallet.Views.Components.CurrencyAmountDisplay
import org.cashu.wallet.Views.Components.KeyValueRow
import org.cashu.wallet.Views.Components.NotificationBadgeView
import org.cashu.wallet.Views.Components.PrimaryActionButton
import org.cashu.wallet.Views.Components.QRCodeView
import org.cashu.wallet.Views.Components.QuietCard
import org.cashu.wallet.Views.Components.SecondaryActionButton
import org.cashu.wallet.Views.Components.rememberClipboardText
import org.cashu.wallet.Views.Send.Components.NumberPadAmountInput

@Composable
fun ReceiveView(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    priceService: PriceService,
    nostrService: NostrService,
    cashuRequestStore: CashuRequestStore,
    contentPadding: PaddingValues,
    scannedPayload: String? = null,
    onScannedPayloadConsumed: () -> Unit = {},
    onScan: () -> Unit = {},
) {
    val state by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val priceState by priceService.state.collectAsState()
    val nostrState by nostrService.state.collectAsState()
    val cashuRequestState by cashuRequestStore.state.collectAsState()
    val haptics = rememberWalletHaptics()
    var tokenInput by remember { mutableStateOf("") }
    var amountInput by remember { mutableStateOf("") }
    var cashuRequestAmountInput by remember { mutableStateOf("") }
    var cashuRequestMemoInput by remember { mutableStateOf("") }
    var restrictCashuRequestToActiveMint by remember { mutableStateOf(false) }
    var cashuRequestError by remember { mutableStateOf<String?>(null) }
    var editingCashuRequestAmount by remember { mutableStateOf<CashuRequest?>(null) }
    var editingCashuRequestMint by remember { mutableStateOf<CashuRequest?>(null) }
    var cashuRequestDetailId by remember { mutableStateOf<String?>(null) }
    var cashuPaymentJustReceivedRequestId by remember { mutableStateOf<String?>(null) }
    var observedCashuPaymentSignal by remember { mutableStateOf<Pair<String, Int>?>(null) }
    var generatedQuote by remember { mutableStateOf<MintQuoteInfo?>(null) }
    var receiveSuccess by remember { mutableStateOf<ReceiveSuccessNotification?>(null) }
    var pendingReceiveMessage by remember { mutableStateOf<String?>(null) }
    var receiveFee by remember { mutableStateOf<Long?>(null) }
    var isLoadingReceiveFee by remember { mutableStateOf(false) }
    var tokenSpent by remember { mutableStateOf<Boolean?>(null) }
    var isCheckingTokenSpent by remember { mutableStateOf(false) }
    var dismissedClipboardSuggestion by remember { mutableStateOf(false) }
    LaunchedEffect(scannedPayload) {
        val payload = scannedPayload?.trim().orEmpty()
        if (payload.isNotEmpty()) {
            tokenInput = payload
            onScannedPayloadConsumed()
        }
    }
    val clipboardText = rememberClipboardText()
    val clipboardToken = remember(clipboardText) { clipboardText?.let(TokenParser::extractToken) }
    LaunchedEffect(clipboardText) {
        dismissedClipboardSuggestion = false
    }
    LaunchedEffect(clipboardToken, settings.autoPasteEcashReceive) {
        val token = clipboardToken
        if (settings.autoPasteEcashReceive && tokenInput.isBlank() && token != null) {
            tokenInput = token
        }
    }
    val tokenForPreview = remember(tokenInput) { TokenParser.extractToken(tokenInput) }
    val tokenValidationMessage = remember(tokenInput) { TokenParser.malformedTokenMessage(tokenInput) }
    val tokenInfo = remember(tokenInput) { TokenParser.tokenInfo(tokenInput) }
    val tokenP2PKPubkeys = remember(tokenInput) { TokenParser.p2pkPubkeys(tokenInput) }
    val activeMintSupportsBolt12 = state.activeMint?.supportedMintMethods?.contains(PaymentMethodKind.Bolt12) == true
    val knownP2PKPubkeys = remember(settings.p2pkKeys) {
        settings.p2pkKeys.map { SettingsManager.normalizeP2PKPublicKeyForComparison(it.publicKey) }.toSet()
    }
    val tokenLockedToKnownKey = tokenP2PKPubkeys.isEmpty() ||
        tokenP2PKPubkeys.any { SettingsManager.normalizeP2PKPublicKeyForComparison(it) in knownP2PKPubkeys }
    LaunchedEffect(tokenForPreview) {
        if (tokenForPreview == null) {
            receiveFee = null
            isLoadingReceiveFee = false
            return@LaunchedEffect
        }
        isLoadingReceiveFee = true
        receiveFee = runCatching { walletManager.calculateReceiveFee(tokenForPreview) }.getOrDefault(0)
        isLoadingReceiveFee = false
    }
    LaunchedEffect(tokenForPreview, tokenInfo?.mint) {
        val token = tokenForPreview
        val mintUrl = tokenInfo?.mint
        if (token == null || mintUrl == null) {
            tokenSpent = null
            isCheckingTokenSpent = false
            return@LaunchedEffect
        }
        isCheckingTokenSpent = true
        tokenSpent = runCatching { walletManager.checkTokenSpent(token, mintUrl) }.getOrNull()
        isCheckingTokenSpent = false
    }
    LaunchedEffect(receiveSuccess?.id) {
        val notificationId = receiveSuccess?.id ?: return@LaunchedEffect
        delay(5_000)
        if (receiveSuccess?.id == notificationId) {
            receiveSuccess = null
        }
    }
    val currentCashuRequest = cashuRequestState.currentRequest ?: cashuRequestState.requests.firstOrNull()
    LaunchedEffect(currentCashuRequest?.id, currentCashuRequest?.receivedPayments?.size) {
        val request = currentCashuRequest ?: return@LaunchedEffect
        val count = request.receivedPayments.size
        val previous = observedCashuPaymentSignal
        if (previous?.first == request.id && count > previous.second) {
            haptics.perform(WalletHaptic.Success)
            cashuPaymentJustReceivedRequestId = request.id
        }
        observedCashuPaymentSignal = request.id to count
    }
    LaunchedEffect(cashuPaymentJustReceivedRequestId) {
        val requestId = cashuPaymentJustReceivedRequestId ?: return@LaunchedEffect
        delay(2_500)
        if (cashuPaymentJustReceivedRequestId == requestId) {
            cashuPaymentJustReceivedRequestId = null
        }
    }
    LaunchedEffect(generatedQuote?.id) {
        val quote = generatedQuote ?: return@LaunchedEffect
        if (quote.paymentMethod != PaymentMethodKind.Bolt12 && quote.paymentMethod != PaymentMethodKind.Onchain) {
            return@LaunchedEffect
        }
        runCatching {
            walletManager.subscribeToMintQuote(quote.id).collect { refreshed ->
                if (generatedQuote?.id == refreshed.id) generatedQuote = refreshed
            }
        }
    }
    LaunchedEffect(generatedQuote?.id) {
        while (true) {
            val current = generatedQuote ?: return@LaunchedEffect
            val now = System.currentTimeMillis() / 1000
            if (!shouldPollMintQuote(current.state, current.expiryEpochSeconds, now)) return@LaunchedEffect
            delay(15_000)
            val quoteAfterDelay = generatedQuote ?: return@LaunchedEffect
            if (quoteAfterDelay.id != current.id) return@LaunchedEffect
            val delayedNow = System.currentTimeMillis() / 1000
            if (!shouldPollMintQuote(quoteAfterDelay.state, quoteAfterDelay.expiryEpochSeconds, delayedNow)) {
                return@LaunchedEffect
            }
            runCatching { walletManager.pollMintQuote(quoteAfterDelay.id) }
                .onSuccess { refreshed ->
                    if (generatedQuote?.id == refreshed.id) generatedQuote = refreshed
                }
        }
    }
    fun createCashuRequest(amount: Long?, mints: List<String>, memo: String?) {
        val id = CashuRequest.newId()
        runCatching {
            PaymentRequestBuilder.build(
                id = id,
                amount = amount,
                unit = "sat",
                mints = mints,
                description = memo?.trim()?.takeIf { it.isNotEmpty() },
                nostrPubkeyHex = nostrState.publicKeyHex,
                relays = settings.nostrRelays,
            )
        }.onSuccess { encoded ->
            cashuRequestStore.createNew(
                id = id,
                amount = amount,
                unit = "sat",
                mints = mints,
                memo = memo?.trim()?.takeIf { it.isNotEmpty() },
                encoded = encoded,
            )
            cashuRequestDetailId = id
            cashuRequestError = null
        }.onFailure { error ->
            cashuRequestError = error.message ?: "Could not create Cashu request."
        }
    }
    editingCashuRequestAmount?.let { request ->
        CashuRequestAmountSheet(
            currentAmount = request.amount,
            settings = settings,
            priceState = priceState,
            onDismiss = { editingCashuRequestAmount = null },
            onSelect = { amount ->
                createCashuRequest(amount = amount, mints = request.mints, memo = request.memo)
                editingCashuRequestAmount = null
            },
        )
    }
    editingCashuRequestMint?.let { request ->
        CashuRequestMintSheet(
            mints = state.mints,
            currentMintUrl = request.mints.firstOrNull(),
            onDismiss = { editingCashuRequestMint = null },
            onSelect = { mintUrl ->
                createCashuRequest(
                    amount = request.amount,
                    mints = mintUrl?.let(::listOf).orEmpty(),
                    memo = request.memo,
                )
                editingCashuRequestMint = null
            },
        )
    }
    val cashuRequestForDetail = cashuRequestDetailId?.let { id ->
        cashuRequestState.requests.firstOrNull { it.id == id }
    }
    if (cashuRequestDetailId != null && cashuRequestForDetail == null) {
        LaunchedEffect(cashuRequestDetailId) { cashuRequestDetailId = null }
    }
    cashuRequestForDetail?.let { request ->
        CashuRequestDetailSheet(
            request = request,
            mints = state.mints,
            settings = settings,
            priceState = priceState,
            paymentJustReceived = cashuPaymentJustReceivedRequestId == request.id,
            onDismiss = { cashuRequestDetailId = null },
            onEditAmount = {
                cashuRequestDetailId = null
                editingCashuRequestAmount = request
            },
            onEditMint = {
                cashuRequestDetailId = null
                editingCashuRequestMint = request
            },
            onRegenerate = { createCashuRequest(request.amount, request.mints, request.memo) },
            onDelete = {
                cashuRequestStore.delete(request.id)
                cashuRequestDetailId = null
            },
        )
    }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(contentPadding)
            .padding(24.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Receive", style = MaterialTheme.typography.headlineSmall)
        OutlinedTextField(
            value = amountInput,
            onValueChange = { amountInput = it.filter(Char::isDigit) },
            label = { Text("Amount") },
            suffix = { Text("sat") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        )
        PrimaryActionButton(
            text = "Create invoice",
            enabled = state.activeMint != null && !state.isLoading && amountInput.toLongOrNull() != null,
        ) {
            walletManager.launch {
                generatedQuote = walletManager.createMintQuote(amountInput.toLong(), PaymentMethodKind.Bolt11)
            }
        }
        SecondaryActionButton(
            text = "Create on-chain address",
            enabled = state.activeMint != null && !state.isLoading && amountInput.toLongOrNull() != null,
        ) {
            walletManager.launch {
                generatedQuote = walletManager.createMintQuote(amountInput.toLong(), PaymentMethodKind.Onchain)
            }
        }
        SecondaryActionButton(
            text = "Create BOLT12 offer",
            enabled = state.activeMint != null && activeMintSupportsBolt12 && !state.isLoading,
        ) {
            walletManager.launch {
                generatedQuote = walletManager.createMintQuote(amountInput.toLongOrNull(), PaymentMethodKind.Bolt12)
            }
        }
        if (state.activeMint != null && !activeMintSupportsBolt12) {
            Text(
                "Active mint does not advertise BOLT12 receive.",
                color = MaterialTheme.colorScheme.secondary,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        CashuRequestCreationCard(
            amountInput = cashuRequestAmountInput,
            onAmountChange = { cashuRequestAmountInput = it.filter(Char::isDigit) },
            memoInput = cashuRequestMemoInput,
            onMemoChange = { cashuRequestMemoInput = it },
            activeMintUrl = state.activeMint?.url,
            restrictToActiveMint = restrictCashuRequestToActiveMint,
            onToggleMintRestriction = { restrictCashuRequestToActiveMint = !restrictCashuRequestToActiveMint },
            isNostrReady = nostrState.isInitialized && nostrState.publicKeyHex.isNotBlank(),
            isLoading = state.isLoading,
            error = cashuRequestError,
            onCreate = {
                val amount = cashuRequestAmountInput.toLongOrNull()?.takeIf { it > 0 }
                val mints = if (restrictCashuRequestToActiveMint) {
                    state.activeMint?.url?.let(::listOf).orEmpty()
                } else {
                    emptyList()
                }
                createCashuRequest(
                    amount = amount,
                    mints = mints,
                    memo = cashuRequestMemoInput,
                )
            },
        )
        currentCashuRequest?.let { request ->
            CashuRequestSummaryCard(
                request = request,
                onOpen = { cashuRequestDetailId = request.id },
                onRegenerate = { createCashuRequest(request.amount, request.mints, request.memo) },
                onDelete = { cashuRequestStore.delete(request.id) },
            )
        }
        generatedQuote?.let { quote ->
            MintQuoteCard(
                quote = quote,
                isLoading = state.isLoading,
                onRefreshQuote = {
                    walletManager.launch {
                        generatedQuote = walletManager.checkMintQuote(quote.id)
                    }
                },
                onMintPaidQuote = {
                    walletManager.launch {
                        runCatching { walletManager.mintTokens(quote.id) }
                            .onSuccess { amount ->
                                haptics.perform(WalletHaptic.Success)
                                receiveSuccess = ReceiveSuccessNotification(amount = amount, fee = null)
                                pendingReceiveMessage = null
                                generatedQuote = null
                            }
                            .onFailure { haptics.perform(WalletHaptic.Error) }
                    }
                },
            )
        }
        receiveSuccess?.let { notification ->
            NotificationBadgeView(
                message = "Received",
                amount = notification.amount,
                fee = notification.fee,
                onDismiss = { receiveSuccess = null },
            )
        }
        Spacer(Modifier.height(8.dp))
        SecondaryActionButton("Scan token or request", enabled = !state.isLoading, onClick = onScan)
        if (tokenInput.isBlank() && clipboardToken != null && !dismissedClipboardSuggestion) {
            ClipboardSuggestionChip(
                title = "Cashu token on clipboard",
                detail = shortToken(clipboardToken),
                onUse = {
                    tokenInput = clipboardToken
                    dismissedClipboardSuggestion = true
                },
                onDismiss = { dismissedClipboardSuggestion = true },
            )
        }
        OutlinedTextField(
            value = tokenInput,
            onValueChange = { tokenInput = it },
            label = { Text("Ecash token") },
            minLines = 3,
        )
        tokenInfo?.let { info ->
            TokenPreviewCard(
                info = info,
                receiveFee = receiveFee,
                isLoadingFee = isLoadingReceiveFee,
                isCheckingSpendability = isCheckingTokenSpent,
                tokenSpent = tokenSpent,
                p2pkPubkeys = tokenP2PKPubkeys,
                tokenLockedToKnownKey = tokenLockedToKnownKey,
            )
        }
        if (tokenP2PKPubkeys.isNotEmpty() && !tokenLockedToKnownKey) {
            Text(
                "This token is P2PK locked and requires a matching key from Settings > P2PK.",
                color = MaterialTheme.colorScheme.error,
            )
        }
        if (tokenSpent == true) {
            Text("This token appears to be spent.", color = MaterialTheme.colorScheme.error)
        }
        if (tokenValidationMessage != null) {
            Text(tokenValidationMessage, color = MaterialTheme.colorScheme.error)
        }
        PrimaryActionButton(
            text = "Receive token",
            enabled = tokenForPreview != null && !state.isLoading && tokenLockedToKnownKey && tokenSpent != true,
        ) {
            val parsedToken = tokenForPreview
            if (parsedToken != null && tokenLockedToKnownKey && tokenSpent != true) {
                walletManager.launch {
                    val fee = receiveFee?.takeIf { it > 0 }
                    runCatching { walletManager.receiveTokens(parsedToken) }
                        .onSuccess { amount ->
                            haptics.perform(WalletHaptic.Success)
                            receiveSuccess = ReceiveSuccessNotification(amount = amount, fee = fee)
                            pendingReceiveMessage = null
                            tokenInput = ""
                        }
                        .onFailure { haptics.perform(WalletHaptic.Error) }
                }
            }
        }
        SecondaryActionButton(
            text = "Receive later",
            enabled = tokenInfo != null && tokenForPreview != null && !state.isLoading,
        ) {
            val info = tokenInfo
            val token = tokenForPreview
            if (info != null && token != null) {
                walletManager.savePendingReceiveToken(
                    PendingReceiveToken(
                        tokenId = UUID.randomUUID().toString(),
                        token = token,
                        amount = info.amount,
                        dateEpochMillis = System.currentTimeMillis(),
                        mintUrl = info.mint,
                    ),
                )
                tokenInput = ""
                receiveSuccess = null
                pendingReceiveMessage = "Saved token for later"
            }
        }
        pendingReceiveMessage?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
        if (state.pendingReceiveTokens.isNotEmpty()) {
            PendingReceiveTokensSection(
                tokens = state.pendingReceiveTokens,
                isLoading = state.isLoading,
                onClaim = { token ->
                    walletManager.launch {
                        val fee = runCatching { walletManager.calculateReceiveFee(token.token) }
                            .getOrDefault(0)
                            .takeIf { it > 0 }
                        runCatching { walletManager.claimPendingReceiveToken(token) }
                            .onSuccess { amount ->
                                haptics.perform(WalletHaptic.Success)
                                receiveSuccess = ReceiveSuccessNotification(amount = amount, fee = fee)
                                pendingReceiveMessage = null
                            }
                            .onFailure { haptics.perform(WalletHaptic.Error) }
                    }
                },
                onRemove = { token -> walletManager.removePendingReceiveToken(token.tokenId) },
            )
        }
        state.errorMessage?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }
}

private data class ReceiveSuccessNotification(
    val amount: Long,
    val fee: Long?,
    val id: String = UUID.randomUUID().toString(),
)

@Composable
private fun TokenPreviewCard(
    info: TokenInfo,
    receiveFee: Long?,
    isLoadingFee: Boolean,
    isCheckingSpendability: Boolean,
    tokenSpent: Boolean?,
    p2pkPubkeys: List<String>,
    tokenLockedToKnownKey: Boolean,
) {
    QuietCard {
        Text("Ecash token", style = MaterialTheme.typography.titleMedium)
        KeyValueRow("Amount", "${info.amount} ${info.unit}")
        KeyValueRow("Fee", if (isLoadingFee) "Checking" else "${receiveFee ?: 0} sat")
        KeyValueRow(
            "Status",
            when {
                isCheckingSpendability -> "Checking"
                tokenSpent == true -> "Claimed"
                tokenSpent == false -> "Spendable"
                else -> "Unknown"
            },
        )
        KeyValueRow("Mint", shortMintUrl(info.mint))
        info.memo?.takeIf { it.isNotBlank() }?.let { KeyValueRow("Memo", it) }
        KeyValueRow("Proofs", info.proofCount.toString())
        if (p2pkPubkeys.isNotEmpty()) {
            KeyValueRow("P2PK", if (tokenLockedToKnownKey) "Your key" else "Unknown key")
        }
    }
}

@Composable
private fun PendingReceiveTokensSection(
    tokens: List<PendingReceiveToken>,
    isLoading: Boolean,
    onClaim: (PendingReceiveToken) -> Unit,
    onRemove: (PendingReceiveToken) -> Unit,
) {
    QuietCard {
        Text("Pending receive", style = MaterialTheme.typography.titleMedium)
        tokens.sortedByDescending { it.dateEpochMillis }.forEach { token ->
            KeyValueRow("Amount", "${token.amount} sat")
            KeyValueRow("Mint", shortMintUrl(token.mintUrl))
            PrimaryActionButton(
                text = "Claim token",
                enabled = !isLoading,
                onClick = { onClaim(token) },
            )
            SecondaryActionButton(
                text = "Remove",
                enabled = !isLoading,
                onClick = { onRemove(token) },
            )
        }
    }
}

@Composable
private fun CashuRequestCreationCard(
    amountInput: String,
    onAmountChange: (String) -> Unit,
    memoInput: String,
    onMemoChange: (String) -> Unit,
    activeMintUrl: String?,
    restrictToActiveMint: Boolean,
    onToggleMintRestriction: () -> Unit,
    isNostrReady: Boolean,
    isLoading: Boolean,
    error: String?,
    onCreate: () -> Unit,
) {
    QuietCard {
        Text("Cashu request", style = MaterialTheme.typography.titleMedium)
        OutlinedTextField(
            value = amountInput,
            onValueChange = onAmountChange,
            label = { Text("Amount") },
            suffix = { Text("sat") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = memoInput,
            onValueChange = onMemoChange,
            label = { Text("Memo") },
            modifier = Modifier.fillMaxWidth(),
        )
        SecondaryActionButton(
            text = if (restrictToActiveMint && activeMintUrl != null) {
                "Mint: ${shortMintUrl(activeMintUrl)}"
            } else {
                "Mint: Any"
            },
            enabled = activeMintUrl != null,
            onClick = onToggleMintRestriction,
        )
        PrimaryActionButton(
            text = "Create Cashu request",
            enabled = isNostrReady && !isLoading,
            onClick = onCreate,
        )
        if (!isNostrReady) {
            Text(
                "Nostr key is not ready.",
                color = MaterialTheme.colorScheme.secondary,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }
}

@Composable
private fun CashuRequestSummaryCard(
    request: CashuRequest,
    onOpen: () -> Unit,
    onRegenerate: () -> Unit,
    onDelete: () -> Unit,
) {
    QuietCard {
        Text("Current Cashu request", style = MaterialTheme.typography.titleMedium)
        KeyValueRow("Status", cashuRequestStatus(request))
        KeyValueRow("Amount", request.amount?.let { "$it ${request.unit}" } ?: "Any")
        KeyValueRow("Mint", request.mints.firstOrNull()?.let(::shortMintUrl) ?: "Any")
        request.memo?.takeIf { it.isNotBlank() }?.let { KeyValueRow("Memo", it) }
        PrimaryActionButton("View request", onClick = onOpen)
        SecondaryActionButton("New request", onClick = onRegenerate)
        SecondaryActionButton("Delete request", onClick = onDelete)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CashuRequestDetailSheet(
    request: CashuRequest,
    mints: List<MintInfo>,
    settings: org.cashu.wallet.Core.SettingsState,
    priceState: org.cashu.wallet.Core.PriceState,
    paymentJustReceived: Boolean,
    onDismiss: () -> Unit,
    onEditAmount: () -> Unit,
    onEditMint: () -> Unit,
    onRegenerate: () -> Unit,
    onDelete: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            SheetTitleRow(title = "Cashu Request", onDismiss = onDismiss)
            QRCodeView(
                content = request.encoded,
                modifier = Modifier.fillMaxWidth(),
                showControls = false,
                staticOnly = true,
            )
            request.amount?.takeIf { it > 0 }?.let { amount ->
                CurrencyAmountDisplay(
                    sats = amount,
                    settings = settings,
                    priceState = priceState,
                    primaryStyle = MaterialTheme.typography.headlineSmall,
                    horizontalAlignment = Alignment.CenterHorizontally,
                )
            }
            CashuRequestStatusBadge(
                request = request,
                paymentJustReceived = paymentJustReceived,
            )
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                CashuRequestEditableRow(
                    icon = Icons.Default.AccountBalance,
                    label = "Mint",
                    value = mintDisplayValue(request, mints),
                    onClick = onEditMint,
                )
                CashuRequestEditableRow(
                    icon = Icons.Default.Payments,
                    label = "Amount",
                    value = request.amount?.let { "$it ${request.unit}" } ?: "Any",
                    onClick = onEditAmount,
                )
                CashuRequestDetailRow(
                    icon = Icons.Default.QrCode,
                    label = "Unit",
                    value = request.unit.uppercase(),
                )
                CashuRequestDetailRow(
                    icon = Icons.Default.CalendarMonth,
                    label = "Created",
                    value = formatRequestDate(request.createdAtEpochMillis),
                )
                request.memo?.takeIf { it.isNotBlank() }?.let { memo ->
                    CashuRequestDetailRow(
                        icon = Icons.Default.Edit,
                        label = "Memo",
                        value = memo,
                    )
                }
                request.receivedPayments.forEachIndexed { index, payment ->
                    CashuRequestDetailRow(
                        icon = Icons.Default.CheckCircle,
                        label = "Payment ${index + 1}",
                        value = "${payment.amount} sat",
                    )
                }
            }
            OutlinedTextField(
                value = request.encoded,
                onValueChange = {},
                readOnly = true,
                label = { Text("Request") },
                minLines = 2,
                modifier = Modifier.fillMaxWidth(),
            )
            CopyShareRow(label = "Cashu request", content = request.encoded)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(modifier = Modifier.weight(1f)) {
                    SecondaryActionButton("New request", onClick = onRegenerate)
                }
                Box(modifier = Modifier.weight(1f)) {
                    SecondaryActionButton("Delete", onClick = onDelete)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CashuRequestAmountSheet(
    currentAmount: Long?,
    settings: org.cashu.wallet.Core.SettingsState,
    priceState: org.cashu.wallet.Core.PriceState,
    onDismiss: () -> Unit,
    onSelect: (Long?) -> Unit,
) {
    var amountInput by remember(currentAmount) { mutableStateOf(currentAmount?.toString().orEmpty()) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            SheetTitleRow(title = "Amount", onDismiss = onDismiss)
            CurrencyAmountDisplay(
                sats = amountInput.toLongOrNull() ?: 0,
                settings = settings,
                priceState = priceState,
                horizontalAlignment = Alignment.CenterHorizontally,
            )
            NumberPadAmountInput(
                amount = amountInput,
                onAmountChange = { amountInput = it.filter(Char::isDigit) },
            )
            PrimaryActionButton(
                text = "Done",
                onClick = { onSelect(amountInput.toLongOrNull()?.takeIf { it > 0 }) },
            )
            SecondaryActionButton(
                text = "Any amount",
                onClick = { onSelect(null) },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CashuRequestMintSheet(
    mints: List<MintInfo>,
    currentMintUrl: String?,
    onDismiss: () -> Unit,
    onSelect: (String?) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SheetTitleRow(title = "Mint", onDismiss = onDismiss)
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 480.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                CashuRequestMintOptionRow(
                    title = "Any mint",
                    subtitle = "Sender chooses the mint",
                    selected = currentMintUrl == null,
                    icon = Icons.Default.AllInclusive,
                    onClick = { onSelect(null) },
                )
                mints.forEach { mint ->
                    CashuRequestMintOptionRow(
                        title = mint.name,
                        subtitle = "${mint.balance} sat",
                        selected = currentMintUrl == mint.url,
                        icon = Icons.Default.AccountBalance,
                        onClick = { onSelect(mint.url) },
                    )
                }
            }
        }
    }
}

@Composable
private fun SheetTitleRow(title: String, onDismiss: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
        IconButton(onClick = onDismiss) {
            Icon(Icons.Default.Close, contentDescription = "Close")
        }
    }
}

@Composable
private fun CashuRequestStatusBadge(
    request: CashuRequest,
    paymentJustReceived: Boolean,
) {
    val receivedCount = request.receivedPayments.size
    val (icon, text, color) = when {
        paymentJustReceived -> Triple(
            Icons.Default.CheckCircle,
            "Payment received!",
            org.cashu.wallet.Resources.CashuGreen,
        )
        receivedCount > 0 -> Triple(
            Icons.Default.CheckCircle,
            if (receivedCount == 1) "1 payment received" else "$receivedCount payments received",
            org.cashu.wallet.Resources.CashuGreen,
        )
        else -> Triple(
            Icons.Default.Payments,
            "Waiting for payment",
            org.cashu.wallet.Resources.CashuOrange,
        )
    }
    Surface(
        shape = CircleShape,
        color = color.copy(alpha = 0.12f),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(18.dp))
            Text(text, color = color, style = MaterialTheme.typography.labelLarge)
        }
    }
}

@Composable
private fun CashuRequestEditableRow(
    icon: ImageVector,
    label: String,
    value: String,
    onClick: () -> Unit,
) {
    CashuRequestInfoRow(
        icon = icon,
        label = label,
        value = value,
        trailingIcon = Icons.Default.Edit,
        modifier = Modifier.clickable(onClick = onClick),
    )
}

@Composable
private fun CashuRequestDetailRow(
    icon: ImageVector,
    label: String,
    value: String,
) {
    CashuRequestInfoRow(icon = icon, label = label, value = value)
}

@Composable
private fun CashuRequestInfoRow(
    icon: ImageVector,
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    trailingIcon: ImageVector? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.secondary, modifier = Modifier.size(20.dp))
        Text(label, color = MaterialTheme.colorScheme.secondary)
        Spacer(Modifier.weight(1f))
        Text(
            text = value,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        trailingIcon?.let {
            Icon(it, contentDescription = null, tint = MaterialTheme.colorScheme.secondary, modifier = Modifier.size(16.dp))
        }
    }
}

@Composable
private fun CashuRequestMintOptionRow(
    title: String,
    subtitle: String,
    selected: Boolean,
    icon: ImageVector,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .background(MaterialTheme.colorScheme.surface, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.secondary, modifier = Modifier.size(22.dp))
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.secondary)
        }
        if (selected) {
            Icon(Icons.Default.Check, contentDescription = "Selected", tint = MaterialTheme.colorScheme.primary)
        }
    }
}

@Composable
private fun MintQuoteCard(
    quote: MintQuoteInfo,
    isLoading: Boolean,
    onRefreshQuote: () -> Unit,
    onMintPaidQuote: () -> Unit,
) {
    val label = quote.paymentMethod.requestDisplayName
    var nowEpochSeconds by remember(quote.id) { mutableStateOf(System.currentTimeMillis() / 1000) }
    LaunchedEffect(quote.id, quote.expiryEpochSeconds) {
        val expiry = quote.expiryEpochSeconds
        if (expiry == null || expiry <= 0) return@LaunchedEffect
        while (nowEpochSeconds < expiry) {
            delay(1_000)
            nowEpochSeconds = System.currentTimeMillis() / 1000
        }
    }
    val expiryText = quoteExpiryText(quote.expiryEpochSeconds, nowEpochSeconds)
    QuietCard {
        Text(label, style = MaterialTheme.typography.titleMedium)
        quote.amount?.let { KeyValueRow("Amount", "$it sat") }
        KeyValueRow("State", quote.state.name)
        expiryText?.let { KeyValueRow("Expires", it) }
        QRCodeView(
            content = quote.request,
            modifier = Modifier.fillMaxWidth(),
            showControls = false,
            staticOnly = true,
        )
        OutlinedTextField(
            value = quote.request,
            onValueChange = {},
            readOnly = true,
            label = { Text(label) },
            minLines = 2,
            modifier = Modifier.fillMaxWidth(),
        )
        CopyShareRow(label = label, content = quote.request)
        SecondaryActionButton(
            text = "Refresh status",
            enabled = !isLoading,
            onClick = onRefreshQuote,
        )
        PrimaryActionButton(
            text = "Mint paid quote",
            enabled = !isLoading && quote.state == MintQuoteState.Paid,
            onClick = onMintPaidQuote,
        )
    }
}

private fun cashuRequestStatus(request: CashuRequest): String {
    val count = request.receivedPayments.size
    return when {
        count == 0 -> "Waiting"
        count == 1 -> "1 payment received"
        else -> "$count payments received"
    }
}

private fun mintDisplayValue(request: CashuRequest, mints: List<MintInfo>): String {
    val mintUrl = request.mints.firstOrNull() ?: return "Any mint"
    return mints.firstOrNull { it.url == mintUrl }?.name ?: shortMintUrl(mintUrl)
}

private fun formatRequestDate(epochMillis: Long): String =
    DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
        .withZone(ZoneId.systemDefault())
        .format(Instant.ofEpochMilli(epochMillis))

private fun shortMintUrl(url: String): String {
    return runCatching { URI.create(url).host }
        .getOrNull()
        ?.takeIf { it.isNotBlank() }
        ?: url
}

private fun shortToken(token: String): String {
    return if (token.length > 22) {
        "${token.take(12)}...${token.takeLast(8)}"
    } else {
        token
    }
}
