package org.cashu.wallet.ui.history

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.cashu.wallet.Core.AmountFormatter
import org.cashu.wallet.Core.CashuRequestStore
import org.cashu.wallet.Core.HistoryFilter
import org.cashu.wallet.Core.PriceService
import org.cashu.wallet.Core.SettingsManager
import org.cashu.wallet.Core.TransactionDisplay
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Models.CashuRequest
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.WalletTransaction
import org.cashu.wallet.ui.components.CanvasDivider
import org.cashu.wallet.ui.components.CashuRequestRow
import org.cashu.wallet.ui.components.EmptyState
import org.cashu.wallet.ui.components.SectionHeader
import org.cashu.wallet.ui.components.TransactionRow
import org.cashu.wallet.ui.components.TransactionRowModel
import org.cashu.wallet.ui.components.formatRelativeTimestamp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    priceService: PriceService,
    cashuRequestStore: CashuRequestStore,
    onOpenTransaction: (WalletTransaction) -> Unit,
    onOpenCashuRequest: (CashuRequest) -> Unit,
    contentPadding: PaddingValues,
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val priceState by priceService.state.collectAsState()
    val requestState by cashuRequestStore.state.collectAsState()
    val formatter = remember { AmountFormatter() }
    val scope = rememberCoroutineScope()

    var filter by remember { mutableStateOf(HistoryFilter.All) }
    var filterMenuOpen by remember { mutableStateOf(false) }
    var searching by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var refreshing by remember { mutableStateOf(false) }
    var checkingTxId by remember { mutableStateOf<String?>(null) }
    var requestPendingDelete by remember { mutableStateOf<CashuRequest?>(null) }

    LaunchedEffect(Unit) {
        walletManager.loadTransactions()
    }

    // Unified, filtered, searched timeline merging transactions + Cashu Requests.
    val items by remember(walletState.transactions, requestState.requests, filter, query) {
        derivedStateOf {
            unifiedFiltered(
                transactions = walletState.transactions,
                requests = requestState.requests,
                filter = filter,
                query = query,
            )
        }
    }
    val sections by remember(items) {
        derivedStateOf { groupHistoryItems(items, System.currentTimeMillis()) }
    }

    val topBarState = rememberTopAppBarState()
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior(state = topBarState)

    Scaffold(
        modifier = Modifier
            .padding(contentPadding)
            .nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text("History", style = MaterialTheme.typography.headlineMedium) },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.largeTopAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                    scrolledContainerColor = MaterialTheme.colorScheme.background,
                ),
                actions = {
                    IconButton(onClick = { searching = !searching }) {
                        Icon(Icons.Outlined.Search, contentDescription = "Search")
                    }
                    Box {
                        IconButton(onClick = { filterMenuOpen = true }) {
                            Icon(
                                imageVector = if (filter == HistoryFilter.All)
                                    Icons.Outlined.FilterList else Icons.Filled.FilterList,
                                contentDescription = "Filter",
                            )
                        }
                        DropdownMenu(
                            expanded = filterMenuOpen,
                            onDismissRequest = { filterMenuOpen = false },
                        ) {
                            HistoryFilter.entries.forEach { entry ->
                                DropdownMenuItem(
                                    text = { Text(entry.label) },
                                    onClick = {
                                        filter = entry
                                        filterMenuOpen = false
                                    },
                                    trailingIcon = if (entry == filter) {
                                        { Icon(Icons.Outlined.Check, contentDescription = null) }
                                    } else null,
                                )
                            }
                        }
                    }
                },
            )
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                scope.launch {
                    refreshing = true
                    runCatching {
                        walletManager.loadTransactions()
                        if (walletState.pendingTokens.isNotEmpty()) {
                            walletManager.checkAllPendingTokens()
                        }
                    }
                    refreshing = false
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            if (sections.isEmpty()) {
                HistoryEmptyState(filter = filter, hasQuery = query.isNotBlank())
            } else {
                LazyColumn(modifier = Modifier.fillMaxSize()) {
                    if (searching) {
                        item("search") {
                            OutlinedTextField(
                                value = query,
                                onValueChange = { query = it },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 8.dp),
                                placeholder = { Text("Search history") },
                                singleLine = true,
                                shape = MaterialTheme.shapes.medium,
                                colors = TextFieldDefaults.colors(
                                    focusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                                    unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainer,
                                ),
                            )
                        }
                    }
                    sections.forEach { section ->
                        item(key = "header-${section.title}") {
                            SectionHeader(section.title.uppercase())
                        }
                        items(section.items, key = { it.key }) { item ->
                            when (item) {
                                is HistoryItem.Tx -> {
                                    val tx = item.transaction
                                    TransactionRow(
                                        model = TransactionRowModel(
                                            transaction = tx,
                                            title = TransactionDisplay.title(tx),
                                            timestamp = formatRelativeTimestamp(tx.dateEpochMillis),
                                            primaryAmount = formatter.formatWalletSats(
                                                tx.amount, settings.useBitcoinSymbol,
                                            ),
                                            secondaryAmount = if (settings.showFiatBalance && priceState.btcPrice > 0)
                                                formatter.formatFiat(
                                                    tx.amount,
                                                    priceState.btcPrice,
                                                    settings.bitcoinPriceCurrency,
                                                )
                                            else null,
                                        ),
                                        onClick = { onOpenTransaction(tx) },
                                        isChecking = checkingTxId == tx.id,
                                        onRefresh = if (tx.status == TransactionStatus.Pending) {
                                            {
                                                checkingTxId = tx.id
                                                walletManager.launch {
                                                    try {
                                                        walletManager.loadTransactions()
                                                    } finally {
                                                        checkingTxId = null
                                                    }
                                                }
                                            }
                                        } else null,
                                    )
                                }
                                is HistoryItem.Req -> {
                                    CashuRequestRow(
                                        request = item.request,
                                        timestamp = formatRelativeTimestamp(item.request.createdAtEpochMillis),
                                        primaryAmountText = when {
                                            item.request.totalReceived > 0L -> formatter.formatWalletSats(
                                                item.request.totalReceived, settings.useBitcoinSymbol,
                                            )
                                            item.request.amount != null && item.request.amount > 0L ->
                                                formatter.formatWalletSats(
                                                    item.request.amount, settings.useBitcoinSymbol,
                                                )
                                            else -> null
                                        },
                                        secondaryAmountText = null,
                                        onClick = { onOpenCashuRequest(item.request) },
                                        onLongClick = { requestPendingDelete = item.request },
                                    )
                                }
                            }
                            if (item != section.items.last()) CanvasDivider()
                        }
                    }
                }
            }
        }
    }

    requestPendingDelete?.let { req ->
        AlertDialog(
            onDismissRequest = { requestPendingDelete = null },
            title = { Text("Remove from history?") },
            text = {
                Text(
                    "Payments already received stay in your wallet; only the request entry is removed.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    cashuRequestStore.delete(req.id)
                    requestPendingDelete = null
                }) {
                    Text("Remove", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { requestPendingDelete = null }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun HistoryEmptyState(filter: HistoryFilter, hasQuery: Boolean) {
    val (icon, title, supporting) = when {
        hasQuery -> Triple(Icons.Outlined.Search, "No matches", null)
        filter == HistoryFilter.Pending -> Triple(
            Icons.Outlined.Schedule,
            "No pending transactions",
            null,
        )
        filter == HistoryFilter.Completed -> Triple(
            Icons.Outlined.Check,
            "No completed transactions",
            null,
        )
        else -> Triple(
            Icons.Filled.Bolt,
            "No activity yet",
            "Your first payment will show up here.",
        )
    }
    // Pulse the empty-state bolt to match iOS.
    val transition = rememberInfiniteTransition(label = "empty-pulse")
    val alpha by transition.animateFloat(
        initialValue = 0.4f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1200),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "empty-pulse-alpha",
    )
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .size(40.dp)
                    .alpha(if (icon == Icons.Filled.Bolt) alpha else 1f),
            )
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            if (supporting != null) {
                Text(
                    text = supporting,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/** Unified History timeline item. Mirrors iOS HistoryItem enum. */
internal sealed interface HistoryItem {
    val date: Long
    val key: String
    data class Tx(val transaction: WalletTransaction) : HistoryItem {
        override val date: Long get() = transaction.dateEpochMillis
        override val key: String get() = "tx:${transaction.id}"
    }
    data class Req(val request: CashuRequest) : HistoryItem {
        override val date: Long get() = request.createdAtEpochMillis
        override val key: String get() = "req:${request.id}"
    }
}

internal data class HistorySection2(
    val title: String,
    val items: List<HistoryItem>,
)

internal fun unifiedFiltered(
    transactions: List<WalletTransaction>,
    requests: List<CashuRequest>,
    filter: HistoryFilter,
    query: String,
): List<HistoryItem> {
    val claimedTxIds = buildSet {
        requests.forEach { req -> req.receivedPayments.forEach { add(it.transactionId) } }
    }
    val txItems = transactions
        .filterNot { it.id in claimedTxIds }
        .filter { tx ->
            when (filter) {
                HistoryFilter.All -> true
                HistoryFilter.Pending -> tx.status == TransactionStatus.Pending
                HistoryFilter.Completed -> tx.status == TransactionStatus.Completed
            }
        }
        .map { HistoryItem.Tx(it) as HistoryItem }
    val reqItems = requests
        .filter { req ->
            when (filter) {
                HistoryFilter.All -> true
                HistoryFilter.Pending -> req.receivedPayments.isEmpty()
                HistoryFilter.Completed -> req.receivedPayments.isNotEmpty()
            }
        }
        .map { HistoryItem.Req(it) as HistoryItem }
    val all = (txItems + reqItems).sortedByDescending { it.date }
    if (query.isBlank()) return all
    return all.filter { item ->
        when (item) {
            is HistoryItem.Tx -> {
                val tx = item.transaction
                TransactionDisplay.title(tx).contains(query, ignoreCase = true) ||
                    tx.amount.toString().contains(query) ||
                    tx.memo?.contains(query, ignoreCase = true) == true
            }
            is HistoryItem.Req -> {
                "cashu request".contains(query, ignoreCase = true) ||
                    (item.request.amount?.toString()?.contains(query) == true) ||
                    item.request.memo?.contains(query, ignoreCase = true) == true
            }
        }
    }
}

internal fun groupHistoryItems(
    items: List<HistoryItem>,
    nowEpochMillis: Long,
): List<HistorySection2> {
    if (items.isEmpty()) return emptyList()
    val zone = java.time.ZoneId.systemDefault()
    val today = java.time.Instant.ofEpochMilli(nowEpochMillis).atZone(zone).toLocalDate()
    val yesterday = today.minusDays(1)
    val weekStart = today.minusDays(today.dayOfWeek.value.toLong() - 1)
    val monthStart = today.withDayOfMonth(1)
    val buckets = linkedMapOf(
        "Today" to mutableListOf<HistoryItem>(),
        "Yesterday" to mutableListOf<HistoryItem>(),
        "This Week" to mutableListOf<HistoryItem>(),
        "This Month" to mutableListOf<HistoryItem>(),
        "Earlier" to mutableListOf<HistoryItem>(),
    )
    items.forEach { item ->
        val d = java.time.Instant.ofEpochMilli(item.date).atZone(zone).toLocalDate()
        val key = when {
            d == today -> "Today"
            d == yesterday -> "Yesterday"
            !d.isBefore(weekStart) -> "This Week"
            !d.isBefore(monthStart) -> "This Month"
            else -> "Earlier"
        }
        buckets.getValue(key).add(item)
    }
    return buckets.mapNotNull { (title, list) ->
        list.takeIf { it.isNotEmpty() }?.let { HistorySection2(title, it) }
    }
}

