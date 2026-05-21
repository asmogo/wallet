package org.cashu.wallet.Views.History

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.cashu.wallet.Core.AmountFormatter
import org.cashu.wallet.Core.HistoryFilter
import org.cashu.wallet.Core.OnchainExplorer
import org.cashu.wallet.Core.TransactionDisplay
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Core.filterTransactions
import org.cashu.wallet.Core.groupTransactionsByDate
import org.cashu.wallet.Core.maxHistoryPages
import org.cashu.wallet.Core.paginateTransactions
import org.cashu.wallet.Core.pendingMintQuoteRefreshMessage
import org.cashu.wallet.Core.pendingTokenRefreshMessage
import org.cashu.wallet.Core.isPendingMintQuoteTransaction
import org.cashu.wallet.Models.TransactionKind
import org.cashu.wallet.Models.WalletTransaction
import org.cashu.wallet.Views.Components.CopyShareRow
import org.cashu.wallet.Views.Components.KeyValueRow
import org.cashu.wallet.Views.Components.QRCodeView
import org.cashu.wallet.Views.Components.QuietCard
import org.cashu.wallet.Views.Components.SecondaryActionButton
import org.cashu.wallet.Views.Components.cashuTokenShareContent
import org.cashu.wallet.Views.Components.openUrl

@Composable
fun HistoryView(
    walletManager: WalletManager,
    contentPadding: PaddingValues,
) {
    val state by walletManager.state.collectAsState()
    val formatter = AmountFormatter()
    var selectedTransactionId by remember { mutableStateOf<String?>(null) }
    var filter by remember { mutableStateOf(HistoryFilter.All) }
    var currentPage by remember { mutableStateOf(1) }
    var pendingRefreshMessage by remember { mutableStateOf<String?>(null) }
    var isPullRefreshing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) {
        walletManager.loadTransactions()
    }
    LaunchedEffect(filter) {
        currentPage = 1
        selectedTransactionId = null
    }
    val filteredTransactions = remember(state.transactions, filter) {
        filterTransactions(state.transactions, filter)
    }
    val maxPages = remember(filteredTransactions.size) { maxHistoryPages(filteredTransactions.size) }
    val visibleTransactions = remember(filteredTransactions, currentPage) {
        paginateTransactions(filteredTransactions, currentPage)
    }
    val historySections = remember(visibleTransactions) {
        groupTransactionsByDate(visibleTransactions, System.currentTimeMillis())
    }
    val hasPendingMintQuotes = remember(state.transactions) {
        state.transactions.any(::isPendingMintQuoteTransaction)
    }
    fun refreshHistory() {
        if (isPullRefreshing) return
        scope.launch {
            isPullRefreshing = true
            val messages = mutableListOf<String>()
            runCatching {
                walletManager.loadTransactions()
                if (hasPendingMintQuotes) {
                    messages += pendingMintQuoteRefreshMessage(walletManager.syncPendingMintQuotes())
                }
                if (state.pendingTokens.isNotEmpty()) {
                    messages += pendingTokenRefreshMessage(walletManager.checkAllPendingTokens())
                }
            }.onSuccess {
                pendingRefreshMessage = messages.joinToString(" ").takeIf { it.isNotBlank() }
            }.onFailure { error ->
                pendingRefreshMessage = error.message ?: "Unable to refresh history."
            }
            isPullRefreshing = false
        }
    }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(contentPadding)
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("History", style = MaterialTheme.typography.headlineSmall)
        HistoryFilterRow(selected = filter, onSelect = { filter = it })
        if (state.pendingTokens.isNotEmpty() || hasPendingMintQuotes) {
            SecondaryActionButton(
                text = if (state.isLoading) "Checking pending..." else "Refresh pending status",
                enabled = !state.isLoading,
                onClick = ::refreshHistory,
            )
        }
        pendingRefreshMessage?.let {
            Text(it, color = MaterialTheme.colorScheme.secondary, style = MaterialTheme.typography.bodySmall)
        }
        PullToRefreshBox(
            isRefreshing = isPullRefreshing,
            onRefresh = ::refreshHistory,
            modifier = Modifier
                .fillMaxSize()
                .weight(1f),
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                if (filteredTransactions.isEmpty()) {
                    item {
                        Text(
                            if (state.transactions.isEmpty()) {
                                "No transactions yet."
                            } else {
                                "No ${filter.label.lowercase()} transactions."
                            },
                            color = MaterialTheme.colorScheme.secondary,
                        )
                    }
                }
                historySections.forEach { section ->
                    item(key = "section-${section.title}") {
                        Text(
                            text = section.title.uppercase(),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.secondary,
                            modifier = Modifier.padding(top = 8.dp),
                        )
                    }
                    items(section.transactions, key = { it.id }) { transaction ->
                        TransactionHistoryCard(
                            transaction = transaction,
                            amountFormatter = formatter,
                            expanded = selectedTransactionId == transaction.id,
                            walletManager = walletManager,
                            isLoading = state.isLoading,
                            onToggle = {
                                selectedTransactionId = if (selectedTransactionId == transaction.id) null else transaction.id
                            },
                        )
                    }
                }
                if (maxPages > 1) {
                    item {
                        HistoryPaginationRow(
                            currentPage = currentPage,
                            maxPages = maxPages,
                            onPrevious = { currentPage = (currentPage - 1).coerceAtLeast(1) },
                            onNext = { currentPage = (currentPage + 1).coerceAtMost(maxPages) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun HistoryFilterRow(
    selected: HistoryFilter,
    onSelect: (HistoryFilter) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        HistoryFilter.entries.forEach { filter ->
            OutlinedButton(
                onClick = { onSelect(filter) },
                modifier = Modifier.weight(1f),
            ) {
                Text(
                    text = filter.label,
                    color = if (selected == filter) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    },
                )
            }
        }
    }
}

@Composable
private fun HistoryPaginationRow(
    currentPage: Int,
    maxPages: Int,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        OutlinedButton(
            onClick = onPrevious,
            enabled = currentPage > 1,
            modifier = Modifier.weight(1f),
        ) {
            Text("Previous")
        }
        Text(
            text = "$currentPage / $maxPages",
            modifier = Modifier
                .weight(1f)
                .padding(top = 12.dp),
            style = MaterialTheme.typography.bodyMedium,
        )
        OutlinedButton(
            onClick = onNext,
            enabled = currentPage < maxPages,
            modifier = Modifier.weight(1f),
        ) {
            Text("Next")
        }
    }
}

@Composable
private fun TransactionHistoryCard(
    transaction: WalletTransaction,
    amountFormatter: AmountFormatter,
    expanded: Boolean,
    walletManager: WalletManager,
    isLoading: Boolean,
    onToggle: () -> Unit,
) {
    QuietCard(modifier = Modifier.clickable(onClick = onToggle)) {
        KeyValueRow(
            label = TransactionDisplay.title(transaction),
            value = amountFormatter.formatSats(transaction.amount),
        )
        Text(
            text = TransactionDisplay.statusText(transaction),
            color = MaterialTheme.colorScheme.secondary,
            style = MaterialTheme.typography.bodySmall,
        )
        if (expanded) {
            TransactionDetailContent(
                transaction = transaction,
                amountFormatter = amountFormatter,
                walletManager = walletManager,
                isLoading = isLoading,
            )
        }
    }
}

@Composable
private fun TransactionDetailContent(
    transaction: WalletTransaction,
    amountFormatter: AmountFormatter,
    walletManager: WalletManager,
    isLoading: Boolean,
) {
    val context = LocalContext.current
    val qrContent = TransactionDisplay.qrContent(transaction)
    val qrLabel = TransactionDisplay.qrLabel(transaction)
    val explorerUrl = remember(transaction.kind, transaction.preimage, transaction.invoice, transaction.mintUrl) {
        if (transaction.kind != TransactionKind.Onchain) {
            null
        } else {
            transaction.preimage?.let {
                OnchainExplorer.transactionWebUrl(
                    txid = it,
                    address = transaction.invoice,
                    mintUrl = transaction.mintUrl,
                )
            } ?: transaction.invoice?.let {
                OnchainExplorer.addressWebUrl(address = it, mintUrl = transaction.mintUrl)
            }
        }
    }
    val dateText = remember(transaction.dateEpochMillis) {
        DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
            .withZone(ZoneId.systemDefault())
            .format(Instant.ofEpochMilli(transaction.dateEpochMillis))
    }

    KeyValueRow("Amount", amountFormatter.formatSats(transaction.amount))
    KeyValueRow("Date", dateText)
    TransactionDisplay.detailFields(transaction).forEach { field ->
        if (field.value.length > 48) {
            OutlinedTextField(
                value = field.value,
                onValueChange = {},
                readOnly = true,
                label = { Text(field.label) },
                minLines = 2,
                modifier = Modifier.fillMaxWidth(),
                textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
            )
        } else {
            KeyValueRow(field.label, field.value)
        }
    }
    qrContent?.let { content ->
        val shareContent = if (transaction.kind == TransactionKind.Ecash) {
            cashuTokenShareContent(content)
        } else {
            content
        }
        QRCodeView(
            content = content,
            modifier = Modifier.fillMaxWidth(),
            staticOnly = transaction.kind != TransactionKind.Ecash,
        )
        OutlinedTextField(
            value = content,
            onValueChange = {},
            readOnly = true,
            label = { Text(qrLabel) },
            minLines = 2,
            modifier = Modifier.fillMaxWidth(),
            textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
        )
        CopyShareRow(label = qrLabel, content = content, shareContent = shareContent)
    }
    explorerUrl?.let { url ->
        SecondaryActionButton("Open block explorer") {
            context.openUrl(url)
        }
    }
    if (isPendingMintQuoteTransaction(transaction)) {
        SecondaryActionButton(
            text = if (isLoading) "Refreshing quote..." else "Refresh quote status",
            enabled = !isLoading,
        ) {
            walletManager.launch {
                walletManager.refreshPendingMintQuote(transaction.quoteId ?: transaction.id)
            }
        }
    }
}
