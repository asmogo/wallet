package org.cashu.wallet.ui.receive

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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.Receipt
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
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
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.Core.TokenParser
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Models.TokenInfo
import org.cashu.wallet.ui.components.AmountText
import org.cashu.wallet.ui.components.CanvasDivider
import org.cashu.wallet.ui.components.GhostButton
import org.cashu.wallet.ui.components.InspectorRow
import org.cashu.wallet.ui.components.PrimaryButton
import org.cashu.wallet.ui.components.TwoFaceScreen
import org.cashu.wallet.ui.theme.withMonoDigits

private sealed interface ReceiveFace {
    data object Paste : ReceiveFace
    data class Review(val token: String, val info: TokenInfo, val fee: Long, val locked: Boolean) : ReceiveFace
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReceiveEcashScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    onClose: () -> Unit,
    onScan: () -> Unit,
    prefilledPayload: String? = null,
    onPrefilledConsumed: () -> Unit = {},
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val formatter = remember { AmountFormatter() }
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current

    var face: ReceiveFace by remember { mutableStateOf(ReceiveFace.Paste) }
    var input by remember { mutableStateOf("") }
    var validating by remember { mutableStateOf(false) }
    var receiving by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }

    fun validateAndReview(raw: String) {
        errorText = null
        val token = TokenParser.extractToken(raw)
        if (token == null) {
            errorText = TokenParser.malformedTokenMessage(raw) ?: "Couldn't read token."
            return
        }
        val info = TokenInfo.parse(token)
        if (info == null) {
            errorText = "Couldn't decode token."
            return
        }
        validating = true
        scope.launch {
            try {
                val fee = runCatching { walletManager.calculateReceiveFee(token) }.getOrDefault(0L)
                val locks = TokenParser.p2pkPubkeys(token)
                val unlocked = if (locks.isEmpty()) {
                    true
                } else {
                    settingsManager.p2pkSigningKeysFor(locks).isNotEmpty()
                }
                face = ReceiveFace.Review(token = token, info = info, fee = fee, locked = !unlocked)
            } catch (t: Throwable) {
                errorText = t.message ?: "Validation failed."
            } finally {
                validating = false
            }
        }
    }

    LaunchedEffect(prefilledPayload) {
        val pre = prefilledPayload?.takeIf { it.isNotBlank() } ?: return@LaunchedEffect
        input = pre
        validateAndReview(pre)
        onPrefilledConsumed()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        when (face) {
                            ReceiveFace.Paste -> "Receive ecash"
                            is ReceiveFace.Review -> "Review token"
                        },
                        style = MaterialTheme.typography.titleMedium,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = {
                        when (face) {
                            ReceiveFace.Paste -> onClose()
                            is ReceiveFace.Review -> face = ReceiveFace.Paste
                        }
                    }) {
                        Icon(Icons.Outlined.Close, contentDescription = "Close")
                    }
                },
                actions = {
                    if (face is ReceiveFace.Paste) {
                        IconButton(onClick = onScan) {
                            Icon(Icons.Outlined.QrCodeScanner, contentDescription = "Scan")
                        }
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
            label = "receive-ecash-face",
        ) { current ->
            when (current) {
                is ReceiveFace.Paste -> PasteFace(
                    input = input,
                    onInputChange = { input = it; errorText = null },
                    onPaste = {
                        val clip = clipboard.getText()?.text
                        if (!clip.isNullOrBlank()) input = clip
                    },
                    onContinue = { validateAndReview(input) },
                    busy = validating,
                    errorText = errorText,
                    canContinue = input.isNotBlank() && !validating,
                )

                is ReceiveFace.Review -> ReviewFace(
                    info = current.info,
                    fee = current.fee,
                    locked = current.locked,
                    receiving = receiving,
                    formatter = formatter,
                    useBitcoinSymbol = settings.useBitcoinSymbol,
                    onReceive = {
                        receiving = true
                        errorText = null
                        scope.launch {
                            try {
                                walletManager.receiveTokens(current.token)
                                onClose()
                            } catch (t: Throwable) {
                                errorText = t.message ?: "Could not receive."
                            } finally {
                                receiving = false
                            }
                        }
                    },
                    onReceiveLater = {
                        val pending = org.cashu.wallet.Models.PendingReceiveToken(
                            tokenId = current.token.take(64),
                            token = current.token,
                            amount = current.info.amount,
                            mintUrl = current.info.mint,
                            dateEpochMillis = System.currentTimeMillis(),
                        )
                        walletManager.savePendingReceiveToken(pending)
                        onClose()
                    },
                    errorText = errorText,
                )
            }
        }
    }
}

@Composable
private fun PasteFace(
    input: String,
    onInputChange: (String) -> Unit,
    onPaste: () -> Unit,
    onContinue: () -> Unit,
    busy: Boolean,
    errorText: String?,
    canContinue: Boolean,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp)
            .imePadding(),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = "Paste an ecash token to redeem it.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        OutlinedTextField(
            value = input,
            onValueChange = onInputChange,
            modifier = Modifier
                .fillMaxWidth()
                .heightFor(180),
            label = { Text("cashuA… / cashuB…") },
            placeholder = { Text("Token") },
            shape = MaterialTheme.shapes.medium,
            colors = TextFieldDefaults.colors(
                focusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
            ),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
        )
        GhostButton(text = "Paste from clipboard", onClick = onPaste)
        if (errorText != null) {
            Text(
                text = errorText,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
        Spacer(modifier = Modifier.weight(1f, fill = true))
        PrimaryButton(
            text = if (busy) "Reading…" else "Continue",
            onClick = onContinue,
            enabled = canContinue,
            loading = busy,
        )
        Spacer(Modifier.navigationBarsPadding())
    }
}

@Composable
private fun ReviewFace(
    info: TokenInfo,
    fee: Long,
    locked: Boolean,
    receiving: Boolean,
    formatter: AmountFormatter,
    useBitcoinSymbol: Boolean,
    onReceive: () -> Unit,
    onReceiveLater: () -> Unit,
    errorText: String?,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        AmountText(
            text = formatter.formatWalletSats(info.amount, useBitcoinSymbol),
            style = MaterialTheme.typography.displayMedium.withMonoDigits(),
        )
        Column(modifier = Modifier.fillMaxWidth()) {
            InspectorRow(
                label = "Fee",
                value = if (fee == 0L) "Free" else "${fee} sat",
                leadingIcon = Icons.Outlined.Receipt,
            )
            CanvasDivider(leadingInset = 16)
            InspectorRow(
                label = "Mint",
                value = info.mint,
                leadingIcon = Icons.Outlined.AccountBalance,
            )
            if (locked) {
                CanvasDivider(leadingInset = 16)
                InspectorRow(
                    label = "P2PK",
                    value = "Requires your key",
                    leadingIcon = Icons.Outlined.Lock,
                )
            }
            if (info.memo != null) {
                CanvasDivider(leadingInset = 16)
                InspectorRow(
                    label = "Memo",
                    value = info.memo,
                )
            }
        }
        if (errorText != null) {
            Text(
                text = errorText,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        PrimaryButton(
            text = if (receiving) "Receiving…" else "Receive",
            onClick = onReceive,
            enabled = !locked && !receiving,
            loading = receiving,
        )
        GhostButton(
            text = "Receive later",
            onClick = onReceiveLater,
            enabled = !receiving,
        )
        Spacer(modifier = Modifier.navigationBarsPadding())
    }
}

private fun Modifier.heightFor(height: Int): Modifier =
    this.then(Modifier.height(height.dp))
