package org.cashu.wallet.ui.receive

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
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
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
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import org.cashu.wallet.Core.AmountFormatter
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Models.MintQuoteInfo
import org.cashu.wallet.Models.MintQuoteState
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashu.wallet.ui.components.AmountText
import org.cashu.wallet.ui.components.GhostButton
import org.cashu.wallet.ui.components.NumberPad
import org.cashu.wallet.ui.components.PrimaryButton
import org.cashu.wallet.ui.components.QrCard
import org.cashu.wallet.ui.components.TwoFaceScreen
import org.cashu.wallet.ui.components.shareText
import org.cashu.wallet.ui.theme.CashuTheme
import org.cashu.wallet.ui.theme.withMonoDigits

private sealed interface ReceiveLnFace {
    data object Input : ReceiveLnFace
    data class Display(val quote: MintQuoteInfo) : ReceiveLnFace
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReceiveLightningScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    onClose: () -> Unit,
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val formatter = remember { AmountFormatter() }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current

    var face: ReceiveLnFace by remember { mutableStateOf(ReceiveLnFace.Input) }
    var amount by remember { mutableStateOf("") }
    var method by remember { mutableStateOf(PaymentMethodKind.Bolt11) }
    var creating by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }
    var paymentJustReceived by remember { mutableStateOf(false) }

    val activeMint = walletState.activeMint
    val supportedMethods = activeMint?.supportedMintMethods?.ifEmpty { listOf(PaymentMethodKind.Bolt11) }
        ?: listOf(PaymentMethodKind.Bolt11)

    LaunchedEffect(activeMint) {
        if (method !in supportedMethods) method = supportedMethods.first()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    val current = face
                    val title = when (current) {
                        ReceiveLnFace.Input -> "Receive"
                        is ReceiveLnFace.Display -> when (current.quote.paymentMethod) {
                            PaymentMethodKind.Bolt11 -> "Lightning invoice"
                            PaymentMethodKind.Bolt12 -> "Lightning offer"
                            PaymentMethodKind.Onchain -> "Bitcoin address"
                        }
                    }
                    Text(title, style = MaterialTheme.typography.titleMedium)
                },
                navigationIcon = {
                    IconButton(onClick = {
                        when (face) {
                            ReceiveLnFace.Input -> onClose()
                            is ReceiveLnFace.Display -> face = ReceiveLnFace.Input
                        }
                    }) {
                        Icon(
                            imageVector = when (face) {
                                ReceiveLnFace.Input -> Icons.Outlined.Close
                                is ReceiveLnFace.Display -> Icons.AutoMirrored.Outlined.ArrowBack
                            },
                            contentDescription = "Close",
                        )
                    }
                },
                actions = {
                    val current = face
                    if (current is ReceiveLnFace.Display) {
                        IconButton(onClick = {
                            context.shareText(current.quote.request, subject = "Payment request")
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
            label = "receive-lightning-face",
        ) { current ->
            when (current) {
                ReceiveLnFace.Input -> InputFace(
                    amount = amount,
                    onAmountChange = { amount = it; errorText = null },
                    supportedMethods = supportedMethods,
                    selectedMethod = method,
                    onMethodChange = { method = it },
                    creating = creating,
                    activeMintName = activeMint?.name ?: "No mint",
                    errorText = errorText,
                    onCreate = {
                        val explicit = amount.toLongOrNull()
                        val needsAmount = method != PaymentMethodKind.Bolt12
                        if (needsAmount && (explicit == null || explicit <= 0L)) {
                            errorText = "Enter an amount."
                            return@InputFace
                        }
                        if (activeMint == null) {
                            errorText = "Add a mint first."
                            return@InputFace
                        }
                        creating = true
                        scope.launch {
                            try {
                                val quote = walletManager.createMintQuote(
                                    amount = if (needsAmount) explicit else explicit?.takeIf { it > 0 },
                                    method = method,
                                )
                                face = ReceiveLnFace.Display(quote)
                            } catch (t: Throwable) {
                                errorText = t.message ?: "Could not create request."
                            } finally {
                                creating = false
                            }
                        }
                    },
                )

                is ReceiveLnFace.Display -> {
                    var liveQuote by remember(current.quote.id) { mutableStateOf(current.quote) }
                    LaunchedEffect(current.quote.id) {
                        walletManager.subscribeToMintQuote(current.quote.id)
                            .catch { /* swallow; we'll fall back to manual polling */ }
                            .collectLatest { liveQuote = it }
                    }
                    LaunchedEffect(current.quote.id) {
                        while (true) {
                            delay(15_000)
                            runCatching { walletManager.pollMintQuote(current.quote.id) }
                                .getOrNull()
                                ?.let { liveQuote = it }
                        }
                    }
                    LaunchedEffect(liveQuote.state) {
                        if (liveQuote.state == MintQuoteState.Paid) {
                            runCatching { walletManager.mintTokens(liveQuote.id) }
                            paymentJustReceived = true
                            delay(2_500)
                            paymentJustReceived = false
                        }
                    }
                    DisplayFace(
                        quote = liveQuote,
                        amountLabel = liveQuote.amount?.let {
                            formatter.formatWalletSats(it, settings.useBitcoinSymbol)
                        },
                        showCelebration = paymentJustReceived,
                        onCopy = { clipboard.setText(AnnotatedString(liveQuote.request)) },
                    )
                }
            }
        }
    }
}

@Composable
private fun InputFace(
    amount: String,
    onAmountChange: (String) -> Unit,
    supportedMethods: List<PaymentMethodKind>,
    selectedMethod: PaymentMethodKind,
    onMethodChange: (PaymentMethodKind) -> Unit,
    creating: Boolean,
    activeMintName: String,
    errorText: String?,
    onCreate: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp)
            .imePadding(),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(4.dp))
        Text(
            text = activeMintName,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        if (supportedMethods.size > 1) {
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                supportedMethods.forEachIndexed { index, kind ->
                    SegmentedButton(
                        shape = SegmentedButtonDefaults.itemShape(
                            index = index,
                            count = supportedMethods.size,
                        ),
                        selected = kind == selectedMethod,
                        onClick = { onMethodChange(kind) },
                    ) {
                        Text(kind.displayName)
                    }
                }
            }
        }

        AmountText(
            text = amount.ifEmpty { "0" },
            style = MaterialTheme.typography.displayMedium.withMonoDigits(),
        )
        Text(
            text = "sat",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
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
            text = if (creating) "Creating…" else "Create request",
            onClick = onCreate,
            enabled = !creating,
            loading = creating,
        )
        Spacer(Modifier.navigationBarsPadding())
    }
}

@Composable
private fun DisplayFace(
    quote: MintQuoteInfo,
    amountLabel: String?,
    showCelebration: Boolean,
    onCopy: () -> Unit,
) {
    val isPaid = quote.state == MintQuoteState.Paid ||
        quote.state == MintQuoteState.Issued ||
        quote.amountIssued > 0L
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
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        QrCard(content = quote.request, shareSubject = "Payment request", staticOnly = true)
        if (amountLabel != null) {
            AmountText(
                text = amountLabel,
                style = MaterialTheme.typography.headlineSmall.withMonoDigits(),
            )
        }
        QuoteStatusRow(isPaid = isPaid, showCelebration = showCelebration)
        Spacer(Modifier.height(8.dp))
        PrimaryButton(
            text = if (copied) "Copied" else "Copy request",
            onClick = {
                onCopy()
                copied = true
            },
        )
        GhostButton(
            text = "Done",
            onClick = onCopy,
            enabled = isPaid,
        )
        Spacer(Modifier.navigationBarsPadding())
    }
}

@Composable
private fun QuoteStatusRow(isPaid: Boolean, showCelebration: Boolean) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Spacer(modifier = Modifier.weight(1f))
        if (isPaid) {
            AnimatedVisibility(
                visible = showCelebration,
                enter = scaleIn(animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy)) + fadeIn(),
                exit = fadeOut(),
            ) {
                Icon(
                    imageVector = Icons.Outlined.CheckCircle,
                    contentDescription = null,
                    tint = CashuTheme.colors.received,
                    modifier = Modifier.size(20.dp),
                )
            }
            Icon(
                imageVector = Icons.Outlined.CheckCircle,
                contentDescription = null,
                tint = CashuTheme.colors.received,
                modifier = Modifier.size(20.dp),
            )
            Text(
                text = if (showCelebration) "Payment received!" else "Paid",
                style = MaterialTheme.typography.titleMedium,
                color = CashuTheme.colors.received,
            )
        } else {
            val transition = rememberInfiniteTransition(label = "waiting-pulse")
            val alpha by transition.animateFloat(
                initialValue = 1f,
                targetValue = 0.4f,
                animationSpec = infiniteRepeatable(
                    animation = tween(1100),
                    repeatMode = RepeatMode.Reverse,
                ),
                label = "waiting-pulse-alpha",
            )
            Box(modifier = Modifier.alpha(alpha)) {
                Icon(
                    imageVector = Icons.Outlined.Schedule,
                    contentDescription = null,
                    tint = CashuTheme.colors.pending,
                    modifier = Modifier.size(20.dp),
                )
            }
            Text(
                text = "Waiting for payment…",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
        Spacer(modifier = Modifier.weight(1f))
    }
}
