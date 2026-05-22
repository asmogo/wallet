package org.cashu.wallet.ui.home

import android.content.Context
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import org.cashu.wallet.Core.AmountDisplayPrimary
import org.cashu.wallet.Core.AmountFormatter
import org.cashu.wallet.Core.PriceService
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Core.displayText
import org.cashu.wallet.Models.TransactionType
import org.cashu.wallet.Models.WalletTransaction
import org.cashu.wallet.ui.components.AmountText
import org.cashu.wallet.ui.components.BalanceDisplay
import org.cashu.wallet.ui.components.CanvasDivider
import org.cashu.wallet.ui.components.EmptyState
import org.cashu.wallet.ui.components.GhostButton
import org.cashu.wallet.ui.components.MintChip
import org.cashu.wallet.ui.components.TransactionRow
import org.cashu.wallet.ui.components.TransactionRowModel
import org.cashu.wallet.ui.components.formatRelativeTimestamp
import org.cashu.wallet.ui.theme.CashuTheme

private const val RECENT_LIMIT = 5

@Composable
fun HomeScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    priceService: PriceService,
    onOpenMints: () -> Unit,
    onOpenHistory: () -> Unit,
    onOpenTransaction: (WalletTransaction) -> Unit,
    onReceive: (ReceiveAction) -> Unit,
    onSend: (SendAction) -> Unit,
    onScan: () -> Unit,
    onContactless: () -> Unit,
    contentPadding: PaddingValues,
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val priceState by priceService.state.collectAsState()
    val formatter = remember { AmountFormatter() }

    val context = LocalContext.current
    val hasNfc = remember(context) { context.hasNfcFeature() }

    var receiveChooserOpen by remember { mutableStateOf(false) }
    var sendChooserOpen by remember { mutableStateOf(false) }

    val balanceDisplay = remember(walletState.balance, settings, priceState) {
        formatter.displayText(
            amountSats = walletState.balance,
            preferredPrimary = settings.amountDisplayPrimary,
            showFiat = settings.showFiatBalance && priceState.btcPrice > 0,
            btcPrice = priceState.btcPrice,
            currencyCode = settings.bitcoinPriceCurrency,
            useBitcoinSymbol = settings.useBitcoinSymbol,
        )
    }

    val recentTransactions = remember(walletState.transactions) {
        walletState.transactions.take(RECENT_LIMIT)
    }

    Box(modifier = Modifier.fillMaxSize().padding(contentPadding)) {
        // Scrolling body sits behind the pinned top.
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                top = PINNED_TOP_HEIGHT,
                bottom = 24.dp,
            ),
        ) {
            item("section-header") {
                if (recentTransactions.isNotEmpty()) {
                    Text(
                        text = "RECENT ACTIVITY",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier
                            .padding(start = 16.dp, end = 16.dp, top = 24.dp, bottom = 8.dp),
                    )
                }
            }
            if (recentTransactions.isEmpty()) {
                item("empty") {
                    val hasMints = walletState.mints.isNotEmpty()
                    EmptyState(
                        icon = if (hasMints) Icons.Outlined.History else Icons.Outlined.AccountBalance,
                        title = if (hasMints) "No transactions yet" else "Add a mint to get started",
                        supporting = if (hasMints) "Your activity will show up here."
                        else "Mints custody your ecash. Add one to begin.",
                        actionLabel = if (!hasMints) "Add mint" else null,
                        onAction = if (!hasMints) onOpenMints else null,
                        modifier = Modifier.heightIn(min = 320.dp),
                    )
                }
            } else {
                items(recentTransactions, key = { it.id }) { tx ->
                    TransactionRow(
                        model = TransactionRowModel(
                            transaction = tx,
                            title = tx.kind.displayName + if (tx.type == TransactionType.Incoming) " received" else " sent",
                            timestamp = formatRelativeTimestamp(tx.dateEpochMillis),
                            primaryAmount = formatter.formatWalletSats(tx.amount, settings.useBitcoinSymbol),
                            secondaryAmount = if (settings.showFiatBalance && priceState.btcPrice > 0)
                                formatter.formatFiat(tx.amount, priceState.btcPrice, settings.bitcoinPriceCurrency)
                            else null,
                        ),
                        onClick = { onOpenTransaction(tx) },
                    )
                    if (tx != recentTransactions.last()) CanvasDivider()
                }
                item("view-all") {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        GhostButton(text = "View all activity", onClick = onOpenHistory)
                    }
                }
            }
        }

        // Pinned top section (mint chip + balance + triptych).
        PinnedTop(
            mintChip = {
                MintChip(
                    activeMint = walletState.activeMint,
                    mints = walletState.mints,
                    onSelect = { mint -> walletManager.launch { walletManager.setActiveMint(mint) } },
                    onManage = onOpenMints,
                )
            },
            balance = {
                BalanceDisplay(
                    amount = balanceDisplay,
                    onTogglePrimary = { next ->
                        settingsManager.setAmountDisplayPrimary(next.rawValue)
                    },
                )
            },
            pending = {
                val pending = maxOf(walletState.pendingBalance, walletState.pendingTokens.sumOf { it.amount })
                AnimatedVisibility(
                    visible = pending > 0,
                    enter = fadeIn(),
                    exit = fadeOut(),
                ) {
                    PendingBalanceRow(
                        amountText = formatter.formatWalletSats(pending, settings.useBitcoinSymbol),
                        onClick = onOpenHistory,
                    )
                }
            },
            triptych = {
                ActionTriptych(
                    onReceive = { receiveChooserOpen = true },
                    onScan = onScan,
                    onSend = { sendChooserOpen = true },
                    receiveEnabled = walletState.activeMint != null,
                    sendEnabled = walletState.balance > 0,
                )
            },
        )
    }

    if (receiveChooserOpen) {
        ReceiveChooserSheet(
            onSelect = { action ->
                receiveChooserOpen = false
                onReceive(action)
            },
            onDismiss = { receiveChooserOpen = false },
        )
    }
    if (sendChooserOpen) {
        SendChooserSheet(
            showContactless = hasNfc,
            onSelect = { action ->
                sendChooserOpen = false
                when (action) {
                    SendAction.Ecash, SendAction.Bitcoin -> onSend(action)
                    SendAction.Contactless -> onContactless()
                }
            },
            onDismiss = { sendChooserOpen = false },
        )
    }
}

private val PINNED_TOP_HEIGHT = 280.dp

@Composable
private fun PinnedTop(
    mintChip: @Composable () -> Unit,
    balance: @Composable () -> Unit,
    pending: @Composable () -> Unit,
    triptych: @Composable () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                brush = Brush.verticalGradient(
                    0.85f to MaterialTheme.colorScheme.background,
                    1f to MaterialTheme.colorScheme.background.copy(alpha = 0f),
                ),
            )
            .statusBarsPadding()
            .padding(horizontal = 16.dp)
            .padding(top = 8.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterStart) {
            mintChip()
        }
        Spacer(Modifier.height(4.dp))
        balance()
        pending()
        Spacer(Modifier.height(4.dp))
        triptych()
    }
}

@Composable
private fun ActionTriptych(
    onReceive: () -> Unit,
    onScan: () -> Unit,
    onSend: () -> Unit,
    receiveEnabled: Boolean,
    sendEnabled: Boolean,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FilledTonalButton(
            onClick = onReceive,
            modifier = Modifier.weight(1f).heightIn(min = 52.dp),
            shape = MaterialTheme.shapes.extraLarge,
            enabled = receiveEnabled,
        ) {
            Text("Receive", style = MaterialTheme.typography.labelLarge)
        }
        FilledTonalIconButton(
            onClick = onScan,
            modifier = Modifier.size(52.dp),
            shape = CircleShape,
            colors = IconButtonDefaults.filledTonalIconButtonColors(),
        ) {
            Icon(
                imageVector = Icons.Outlined.QrCodeScanner,
                contentDescription = "Scan",
            )
        }
        FilledTonalButton(
            onClick = onSend,
            modifier = Modifier.weight(1f).heightIn(min = 52.dp),
            shape = MaterialTheme.shapes.extraLarge,
            enabled = sendEnabled,
        ) {
            Text("Send", style = MaterialTheme.typography.labelLarge)
        }
    }
}

@Composable
private fun PendingBalanceRow(
    amountText: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .background(
                color = CashuTheme.colors.pendingContainer,
                shape = MaterialTheme.shapes.large,
            )
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            imageVector = Icons.Outlined.History,
            contentDescription = null,
            tint = CashuTheme.colors.pending,
            modifier = Modifier.size(16.dp),
        )
        Text(
            text = "Pending",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        AmountText(
            text = amountText,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            animated = false,
        )
        GhostButton(text = "Open", onClick = onClick)
    }
}

private fun Context.hasNfcFeature(): Boolean {
    if (!packageManager.hasSystemFeature(PackageManager.FEATURE_NFC)) return false
    return NfcAdapter.getDefaultAdapter(this) != null
}
