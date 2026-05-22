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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material.icons.outlined.CalendarToday
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.CurrencyExchange
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.delay
import org.cashu.wallet.Core.AmountFormatter
import org.cashu.wallet.Core.CashuRequestStore
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.ui.components.AmountText
import org.cashu.wallet.ui.components.CanvasDivider
import org.cashu.wallet.ui.components.DestructiveTextButton
import org.cashu.wallet.ui.components.GhostButton
import org.cashu.wallet.ui.components.InspectorRow
import org.cashu.wallet.ui.components.PrimaryButton
import org.cashu.wallet.ui.components.QrCard
import org.cashu.wallet.ui.components.SectionHeader
import org.cashu.wallet.ui.components.shareText
import org.cashu.wallet.ui.theme.CashuTheme
import org.cashu.wallet.ui.theme.withMonoDigits

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CashuRequestDetailScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    cashuRequestStore: CashuRequestStore,
    requestId: String,
    onClose: () -> Unit,
) {
    val storeState by cashuRequestStore.state.collectAsState()
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val formatter = remember { AmountFormatter() }
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current

    val request = storeState.requests.firstOrNull { it.id == requestId }
    var copied by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }

    LaunchedEffect(copied) {
        if (copied) {
            delay(2000)
            copied = false
        }
    }

    // Track payment count changes for celebration animation.
    val paymentCount = request?.receivedPayments?.size ?: 0
    var previousCount by remember(requestId) { mutableStateOf(paymentCount) }
    var celebrate by remember { mutableStateOf(false) }
    LaunchedEffect(paymentCount) {
        if (paymentCount > previousCount && previousCount >= 0) {
            celebrate = true
            delay(2500)
            celebrate = false
        }
        previousCount = paymentCount
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Cashu Request", style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Outlined.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
                actions = {
                    if (request != null) {
                        IconButton(onClick = {
                            context.shareText(request.encoded, subject = "Cashu Request")
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
        if (request == null) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text(
                    text = "Request not found",
                    style = MaterialTheme.typography.titleMedium,
                )
                Spacer(Modifier.height(16.dp))
                GhostButton(text = "Back", onClick = onClose)
            }
            return@Scaffold
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(8.dp))
            QrCard(content = request.encoded, shareSubject = "Cashu Request", staticOnly = true)

            if (request.amount != null && request.amount > 0L) {
                AmountText(
                    text = formatter.formatWalletSats(request.amount, settings.useBitcoinSymbol),
                    style = MaterialTheme.typography.headlineSmall.withMonoDigits(),
                )
            }

            StatusBlock(
                received = request.receivedPayments.isNotEmpty(),
                paymentCount = paymentCount,
                celebrate = celebrate,
            )

            SectionHeader("Details")
            Column(modifier = Modifier.fillMaxWidth()) {
                val activeMintUrl = request.mints.firstOrNull()
                val mintLabel = activeMintUrl?.let { url ->
                    walletState.mints.firstOrNull { it.url == url }?.name ?: url
                } ?: "Any mint"
                InspectorRow(
                    label = "Mint",
                    value = mintLabel,
                    leadingIcon = Icons.Outlined.AccountBalance,
                )
                CanvasDivider(leadingInset = 16)
                InspectorRow(
                    label = "Amount",
                    value = request.amount?.let { "$it sat" } ?: "Any",
                    leadingIcon = Icons.Outlined.AccountBalanceWallet,
                    valueMonospaced = true,
                )
                CanvasDivider(leadingInset = 16)
                InspectorRow(
                    label = "Unit",
                    value = request.unit.uppercase(),
                    leadingIcon = Icons.Outlined.CurrencyExchange,
                )
                CanvasDivider(leadingInset = 16)
                InspectorRow(
                    label = "Created",
                    value = formatDate(request.createdAtEpochMillis),
                    leadingIcon = Icons.Outlined.CalendarToday,
                )
                if (request.totalReceived > 0L) {
                    CanvasDivider(leadingInset = 16)
                    InspectorRow(
                        label = "Total received",
                        value = formatter.formatWalletSats(request.totalReceived, settings.useBitcoinSymbol),
                        leadingIcon = Icons.Outlined.CheckCircle,
                        valueMonospaced = true,
                    )
                }
            }

            Spacer(Modifier.height(8.dp))
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                PrimaryButton(
                    text = if (copied) "Copied" else "Copy request",
                    onClick = {
                        clipboard.setText(AnnotatedString(request.encoded))
                        copied = true
                    },
                )
                DestructiveTextButton(
                    text = "Remove from history",
                    onClick = { confirmDelete = true },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Remove from history?") },
            text = {
                Text(
                    "The request will be removed from this device. Any payments already received stay in your wallet.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    cashuRequestStore.delete(request!!.id)
                    onClose()
                }) {
                    Text("Remove", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun StatusBlock(received: Boolean, paymentCount: Int, celebrate: Boolean) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (received) {
            AnimatedVisibility(
                visible = celebrate,
                enter = scaleIn(spring(dampingRatio = Spring.DampingRatioMediumBouncy)) + fadeIn(),
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
                text = when {
                    celebrate -> "Payment received!"
                    paymentCount == 1 -> "1 payment received"
                    else -> "$paymentCount payments received"
                },
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
    }
}

private fun formatDate(epochMillis: Long): String =
    DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(epochMillis))
