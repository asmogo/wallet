package org.cashu.wallet.ui.send

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material.icons.outlined.UnfoldMore
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.cashu.wallet.Core.AmountFormatter
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Models.SendTokenResult
import org.cashu.wallet.ui.components.AmountText
import org.cashu.wallet.ui.components.MintPickerSheet
import org.cashu.wallet.ui.components.NumberPad
import org.cashu.wallet.ui.components.PrimaryButton
import org.cashu.wallet.ui.components.QrCard
import org.cashu.wallet.ui.components.TwoFaceScreen
import org.cashu.wallet.ui.components.shareText
import org.cashu.wallet.ui.theme.withMonoDigits

private sealed interface SendFace {
    data object Input : SendFace
    data class Generated(val result: SendTokenResult) : SendFace
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SendEcashScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    onClose: () -> Unit,
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val formatter = remember { AmountFormatter() }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    var face: SendFace by remember { mutableStateOf(SendFace.Input) }
    var amount by remember { mutableStateOf("") }
    var memo by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }
    var pickerOpen by remember { mutableStateOf(false) }
    var selectedMintUrl by remember { mutableStateOf<String?>(null) }

    val activeMintUrl = selectedMintUrl ?: walletState.activeMint?.url
    val activeMint = walletState.mints.firstOrNull { it.url == activeMintUrl } ?: walletState.activeMint
    val amountValue = amount.toLongOrNull() ?: 0L

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        when (face) {
                            SendFace.Input -> "Send ecash"
                            is SendFace.Generated -> "Pending ecash"
                        },
                        style = MaterialTheme.typography.titleMedium,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = {
                        when (face) {
                            SendFace.Input -> onClose()
                            is SendFace.Generated -> face = SendFace.Input
                        }
                    }) {
                        Icon(
                            imageVector = when (face) {
                                SendFace.Input -> Icons.Outlined.Close
                                is SendFace.Generated -> Icons.AutoMirrored.Outlined.ArrowBack
                            },
                            contentDescription = "Close",
                        )
                    }
                },
                actions = {
                    val current = face
                    if (current is SendFace.Generated) {
                        IconButton(onClick = {
                            context.shareText(current.result.token, subject = "Cashu token")
                        }) {
                            Icon(Icons.Outlined.IosShare, contentDescription = "Share")
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
            label = "send-ecash-face",
        ) { current ->
            when (current) {
                is SendFace.Input -> InputFace(
                    amount = amount,
                    onAmountChange = {
                        amount = it
                        errorText = null
                    },
                    memo = memo,
                    onMemoChange = { memo = it },
                    activeMintName = activeMint?.name ?: "No mint",
                    mintCount = walletState.mints.size,
                    onPickMint = { pickerOpen = true },
                    amountValue = amountValue,
                    balanceText = formatter.formatWalletSats(walletState.balance, settings.useBitcoinSymbol),
                    sending = sending,
                    errorText = errorText,
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
                        sending = true
                        scope.launch {
                            try {
                                val result = walletManager.sendTokens(
                                    amount = amountValue,
                                    memo = memo.ifBlank { null },
                                    p2pkPubkey = null,
                                    mintUrl = mintUrl,
                                )
                                face = SendFace.Generated(result)
                                amount = ""
                                memo = ""
                            } catch (t: Throwable) {
                                errorText = t.message ?: "Could not generate token."
                            } finally {
                                sending = false
                            }
                        }
                    },
                )

                is SendFace.Generated -> GeneratedFace(
                    result = current.result,
                    amountLabel = formatter.formatWalletSats(amountValue.takeIf { it > 0 } ?: 0L, settings.useBitcoinSymbol),
                    onSendAnother = { face = SendFace.Input },
                )
            }
        }
    }

    if (pickerOpen) {
        MintPickerSheet(
            mints = walletState.mints,
            activeMintUrl = activeMintUrl,
            onSelect = { selectedMintUrl = it.url; pickerOpen = false },
            onDismiss = { pickerOpen = false },
        )
    }
}

@Composable
private fun InputFace(
    amount: String,
    onAmountChange: (String) -> Unit,
    memo: String,
    onMemoChange: (String) -> Unit,
    activeMintName: String,
    mintCount: Int,
    onPickMint: () -> Unit,
    amountValue: Long,
    balanceText: String,
    sending: Boolean,
    errorText: String?,
    onSend: () -> Unit,
) {
    val canSend = amountValue > 0 && !sending
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp)
            .imePadding(),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(4.dp))
        MintSelectorChip(name = activeMintName, mintCount = mintCount, onClick = onPickMint)

        Text(
            text = "Balance $balanceText",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(Modifier.height(8.dp))
        AmountText(
            text = if (amount.isEmpty()) "0" else amount,
            style = MaterialTheme.typography.displayMedium.withMonoDigits(),
        )
        Text(
            text = "sat",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        OutlinedTextField(
            value = memo,
            onValueChange = onMemoChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Memo (optional)") },
            singleLine = true,
            shape = MaterialTheme.shapes.medium,
            colors = TextFieldDefaults.colors(
                focusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
            ),
            keyboardOptions = KeyboardOptions.Default,
        )

        if (errorText != null) {
            Text(
                text = errorText,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }

        Spacer(modifier = Modifier.weight(1f, fill = true))

        NumberPad(amount = amount, onAmountChange = onAmountChange)

        Spacer(Modifier.height(4.dp))
        PrimaryButton(
            text = if (sending) "Sending…" else "Send",
            onClick = onSend,
            enabled = canSend,
            loading = sending,
        )
        Spacer(modifier = Modifier
            .height(0.dp)
            .navigationBarsPadding())
    }
}

@Composable
internal fun MintSelectorChip(
    name: String,
    mintCount: Int,
    onClick: () -> Unit,
) {
    androidx.compose.material3.AssistChip(
        onClick = onClick,
        enabled = mintCount > 0,
        label = { Text(name) },
        leadingIcon = {
            Icon(
                imageVector = Icons.Outlined.AccountBalance,
                contentDescription = null,
            )
        },
        trailingIcon = {
            Icon(
                imageVector = Icons.Outlined.UnfoldMore,
                contentDescription = null,
            )
        },
    )
}

@Composable
private fun GeneratedFace(
    result: SendTokenResult,
    amountLabel: String,
    onSendAnother: () -> Unit,
) {
    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            delay(2000)
            copied = false
        }
    }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        QrCard(
            content = result.token,
            shareSubject = "Cashu token",
        )
        Text(
            text = amountLabel,
            style = MaterialTheme.typography.headlineSmall.withMonoDigits(),
            color = MaterialTheme.colorScheme.onSurface,
        )
        if (result.fee > 0L) {
            Text(
                text = "Fee ${result.fee} sat",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        PrimaryButton(
            text = if (copied) "Copied" else "Copy token",
            onClick = {
                clipboard.setText(AnnotatedString(result.token))
                copied = true
            },
        )
        PrimaryButton(
            text = "Send another",
            onClick = onSendAnother,
        )
        Spacer(modifier = Modifier.navigationBarsPadding())
    }
}
