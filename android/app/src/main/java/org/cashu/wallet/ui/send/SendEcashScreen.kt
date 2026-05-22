package org.cashu.wallet.ui.send

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
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
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
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
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material.icons.outlined.LockOpen
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.draw.alpha
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
import org.cashu.wallet.ui.components.CashuTextField
import org.cashu.wallet.ui.components.MintPickerSheet
import org.cashu.wallet.ui.components.NumberPad
import org.cashu.wallet.ui.components.PrimaryButton
import org.cashu.wallet.ui.components.QrCard
import org.cashu.wallet.ui.components.TwoFaceScreen
import org.cashu.wallet.ui.components.shareText
import org.cashu.wallet.ui.theme.CashuTheme
import org.cashu.wallet.ui.theme.withMonoDigits

// Inline status icons inside dense rows — smaller than the standard 20dp body icon.
private val STATUS_ICON_SMALL = 18.dp
private val CHECKING_PROGRESS_SIZE = 14.dp

private sealed interface SendFace {
    data object Input : SendFace
    data class Generated(val result: SendTokenResult, val mintUrl: String) : SendFace
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
    var p2pkOn by remember { mutableStateOf(false) }
    var p2pkInput by remember { mutableStateOf("") }
    var p2pkInputError by remember { mutableStateOf<String?>(null) }

    val activeMintUrl = selectedMintUrl ?: walletState.activeMint?.url
    val activeMint = walletState.mints.firstOrNull { it.url == activeMintUrl } ?: walletState.activeMint
    val mintBalance = activeMint?.balance ?: 0L
    val amountValue = amount.toLongOrNull() ?: 0L

    // Normalize and validate the P2PK input only when the lock is on.
    val validatedP2pkPubkey: String? = remember(p2pkOn, p2pkInput) {
        if (!p2pkOn) null
        else runCatching {
            org.cashu.wallet.Core.SettingsManager.normalizeP2PKPublicKeyForSend(p2pkInput)
        }.getOrNull()
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
            org.cashu.wallet.Core.SettingsManager.normalizeP2PKPublicKeyForSend(trimmed)
        }.exceptionOrNull()?.message
    }

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
                    } else if (current is SendFace.Input) {
                        IconButton(onClick = { p2pkOn = !p2pkOn }) {
                            Icon(
                                imageVector = if (p2pkOn) Icons.Filled.Lock
                                else Icons.Outlined.LockOpen,
                                contentDescription = if (p2pkOn) "P2PK locked" else "P2PK off",
                                tint = if (p2pkOn) MaterialTheme.colorScheme.onSurface
                                else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
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
                    memo = memo,
                    onMemoChange = { memo = it },
                    activeMintName = activeMint?.name ?: "No mint",
                    mintCount = walletState.mints.size,
                    onPickMint = { pickerOpen = true },
                    onUseMax = {
                        if (mintBalance > 0L) amount = mintBalance.toString()
                    },
                    mintBalanceText = if (mintBalance > 0L) {
                        formatter.formatWalletSats(mintBalance, settings.useBitcoinSymbol)
                    } else null,
                    amountValue = amountValue,
                    balanceText = formatter.formatWalletSats(walletState.balance, settings.useBitcoinSymbol),
                    sending = sending,
                    errorText = errorText,
                    p2pkOn = p2pkOn,
                    p2pkInput = p2pkInput,
                    onP2pkInputChange = { p2pkInput = it },
                    p2pkInputError = p2pkInputError,
                    p2pkLatestKeyHex = settings.p2pkKeys.firstOrNull()?.publicKey,
                    onUseLatestP2pkKey = {
                        settings.p2pkKeys.firstOrNull()?.let { p2pkInput = it.publicKey }
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
                            errorText = p2pkInputError ?: "Enter a valid P2PK pubkey."
                            return@InputFace
                        }
                        sending = true
                        scope.launch {
                            try {
                                val result = walletManager.sendTokens(
                                    amount = amountValue,
                                    memo = memo.ifBlank { null },
                                    p2pkPubkey = validatedP2pkPubkey,
                                    mintUrl = mintUrl,
                                )
                                face = SendFace.Generated(result, mintUrl)
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
                    walletManager = walletManager,
                    result = current.result,
                    mintUrl = current.mintUrl,
                    pollingEnabled = settings.checkSentTokens,
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
    onUseMax: () -> Unit,
    mintBalanceText: String?,
    amountValue: Long,
    balanceText: String,
    sending: Boolean,
    errorText: String?,
    p2pkOn: Boolean,
    p2pkInput: String,
    onP2pkInputChange: (String) -> Unit,
    p2pkInputError: String?,
    p2pkLatestKeyHex: String?,
    onUseLatestP2pkKey: () -> Unit,
    canSendWithP2pk: Boolean,
    onSend: () -> Unit,
) {
    val canSend = amountValue > 0 && !sending && canSendWithP2pk
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = CashuTheme.spacing.comfortable)
            .imePadding(),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(CashuTheme.spacing.micro))
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
        ) {
            MintSelectorChip(name = activeMintName, mintCount = mintCount, onClick = onPickMint)
            if (mintBalanceText != null) {
                androidx.compose.material3.AssistChip(
                    onClick = onUseMax,
                    label = { Text("Use max", style = MaterialTheme.typography.labelSmall) },
                )
            }
        }

        Text(
            text = "Balance $balanceText",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(Modifier.height(CashuTheme.spacing.snug))
        AmountText(
            text = if (amount.isEmpty()) "0" else amount,
            style = MaterialTheme.typography.displayMedium.withMonoDigits(),
        )
        Text(
            text = "sat",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        CashuTextField(
            value = memo,
            onValueChange = onMemoChange,
            modifier = Modifier.fillMaxWidth(),
            label = "Memo (optional)",
            singleLine = true,
        )

        AnimatedVisibility(visible = p2pkOn) {
            P2pkLockSection(
                input = p2pkInput,
                onInputChange = onP2pkInputChange,
                inputError = p2pkInputError,
                latestKeyHex = p2pkLatestKeyHex,
                onUseLatestKey = onUseLatestP2pkKey,
            )
        }

        if (errorText != null) {
            Text(
                text = errorText,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }

        Spacer(modifier = Modifier.weight(1f, fill = true))

        NumberPad(amount = amount, onAmountChange = onAmountChange)

        Spacer(Modifier.height(CashuTheme.spacing.micro))
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
private fun P2pkLockSection(
    input: String,
    onInputChange: (String) -> Unit,
    inputError: String?,
    latestKeyHex: String?,
    onUseLatestKey: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
    ) {
        CashuTextField(
            value = input,
            onValueChange = onInputChange,
            modifier = Modifier.fillMaxWidth(),
            label = "Recipient P2PK pubkey",
            placeholder = "02… or 64-char hex",
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
        if (latestKeyHex != null) {
            org.cashu.wallet.ui.components.GhostButton(
                text = "Use my latest key",
                onClick = onUseLatestKey,
            )
        }
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
    walletManager: org.cashu.wallet.Core.WalletManager,
    result: SendTokenResult,
    mintUrl: String,
    pollingEnabled: Boolean,
    amountLabel: String,
    onSendAnother: () -> Unit,
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
    // Poll the mint every 4s to detect when the recipient redeems the token.
    LaunchedEffect(result.token, mintUrl, pollingEnabled) {
        if (!pollingEnabled) return@LaunchedEffect
        while (claimState != ClaimState.Claimed) {
            delay(4_000)
            claimState = ClaimState.Checking
            val stillSpendable = runCatching {
                walletManager.checkTokenSpent(result.token, mintUrl)
            }.getOrNull()
            claimState = when {
                stillSpendable == false -> ClaimState.Claimed
                else -> ClaimState.Pending
            }
        }
    }
    Column(
        modifier = Modifier
            .fillMaxSize()
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
        ClaimStatusRow(claimState = claimState)
        Spacer(modifier = Modifier.height(CashuTheme.spacing.micro))
        if (claimState != ClaimState.Claimed) {
            PrimaryButton(
                text = if (copied) "Copied" else "Copy token",
                onClick = {
                    clipboard.setText(AnnotatedString(result.token))
                    copied = true
                },
            )
        }
        PrimaryButton(
            text = if (claimState == ClaimState.Claimed) "Send another" else "Send another",
            onClick = onSendAnother,
        )
        Spacer(modifier = Modifier.navigationBarsPadding())
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
                val transition = rememberInfiniteTransition(label = "pending-pulse")
                val alpha by transition.animateFloat(
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
                    modifier = Modifier.alpha(alpha),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Schedule,
                        contentDescription = null,
                        tint = org.cashu.wallet.ui.theme.CashuTheme.colors.pending,
                        modifier = Modifier.size(STATUS_ICON_SMALL),
                    )
                    Text(
                        text = "Waiting for recipient",
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
                    CircularProgressIndicator(
                        modifier = Modifier.size(CHECKING_PROGRESS_SIZE),
                        strokeWidth = 1.5.dp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = "Checking…",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            ClaimState.Claimed -> {
                AnimatedVisibility(
                    visible = true,
                    enter = scaleIn(spring(dampingRatio = Spring.DampingRatioMediumBouncy)) + fadeIn(),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight),
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.CheckCircle,
                            contentDescription = null,
                            tint = org.cashu.wallet.ui.theme.CashuTheme.colors.received,
                            modifier = Modifier.size(CashuTheme.spacing.loose),
                        )
                        Text(
                            text = "Claimed",
                            style = MaterialTheme.typography.titleMedium,
                            color = org.cashu.wallet.ui.theme.CashuTheme.colors.received,
                        )
                    }
                }
            }
        }
    }
}
