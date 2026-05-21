package org.cashu.wallet.Views.Receive

import java.net.URI
import java.util.UUID
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.Core.TokenParser
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Core.quoteExpiryText
import org.cashu.wallet.Core.shouldPollMintQuote
import org.cashu.wallet.Models.MintQuoteInfo
import org.cashu.wallet.Models.MintQuoteState
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashu.wallet.Models.PendingReceiveToken
import org.cashu.wallet.Models.TokenInfo
import org.cashu.wallet.Views.Components.ClipboardSuggestionChip
import org.cashu.wallet.Views.Components.CopyShareRow
import org.cashu.wallet.Views.Components.KeyValueRow
import org.cashu.wallet.Views.Components.PrimaryActionButton
import org.cashu.wallet.Views.Components.QRCodeView
import org.cashu.wallet.Views.Components.QuietCard
import org.cashu.wallet.Views.Components.SecondaryActionButton
import org.cashu.wallet.Views.Components.rememberClipboardText

@Composable
fun ReceiveView(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    contentPadding: PaddingValues,
    scannedPayload: String? = null,
    onScannedPayloadConsumed: () -> Unit = {},
    onScan: () -> Unit = {},
) {
    val state by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    var tokenInput by remember { mutableStateOf("") }
    var amountInput by remember { mutableStateOf("") }
    var generatedQuote by remember { mutableStateOf<MintQuoteInfo?>(null) }
    var receivedAmount by remember { mutableStateOf<Long?>(null) }
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
                        walletManager.mintTokens(quote.id)
                        generatedQuote = null
                    }
                },
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
        PrimaryActionButton(
            text = "Receive token",
            enabled = tokenInput.isNotBlank() && !state.isLoading && tokenLockedToKnownKey && tokenSpent != true,
        ) {
            if (tokenLockedToKnownKey && tokenSpent != true) {
                walletManager.launch {
                    receivedAmount = walletManager.receiveTokens(tokenInput)
                    pendingReceiveMessage = null
                    tokenInput = ""
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
                receivedAmount = null
                pendingReceiveMessage = "Saved token for later"
            }
        }
        receivedAmount?.let { amount ->
            Text("Received $amount sat", color = MaterialTheme.colorScheme.primary)
        }
        pendingReceiveMessage?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
        if (state.pendingReceiveTokens.isNotEmpty()) {
            PendingReceiveTokensSection(
                tokens = state.pendingReceiveTokens,
                isLoading = state.isLoading,
                onClaim = { token ->
                    walletManager.launch {
                        receivedAmount = walletManager.claimPendingReceiveToken(token)
                        pendingReceiveMessage = null
                    }
                },
                onRemove = { token -> walletManager.removePendingReceiveToken(token.tokenId) },
            )
        }
        state.errorMessage?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }
}

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
