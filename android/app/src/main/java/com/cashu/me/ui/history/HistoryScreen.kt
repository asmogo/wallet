package com.cashu.me.ui.history

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Box
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.spring
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.input.nestedscroll.nestedScroll
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.displayMintUnitAmount
import com.cashu.me.Core.CashuRequestStore
import com.cashu.me.Core.HistoryFilter
import com.cashu.me.Core.PriceService
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.TransactionDisplay
import com.cashu.me.Core.WalletManager
import com.cashu.me.Core.displayText
import com.cashu.me.Models.CashuRequest
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.WalletTransaction
import com.cashu.me.ui.components.CashuRequestRow
import com.cashu.me.ui.components.requestRowDisplay
import com.cashu.me.ui.components.CashuSearchBar
import com.cashu.me.ui.components.EmptyState
import com.cashu.me.ui.components.IconSwap
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.TabTopBar
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.components.TransactionRow
import com.cashu.me.ui.components.TransactionRowModel
import com.cashu.me.ui.components.formatRelativeTimestamp
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.testing.UiTestTags

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
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
    var requestPendingDelete by remember { mutableStateOf<CashuRequest?>(null) }
    val searchFocusRequester = remember { FocusRequester() }
    val keyboardController = LocalSoftwareKeyboardController.current

    LaunchedEffect(Unit) {
        // Show the current ledger immediately, then quietly re-check pending
        // mint quotes (throttled) so a paid BOLT12 offer lands in history just
        // by opening the tab — no pull-to-refresh (iOS HistoryView parity).
        walletManager.loadTransactions()
        walletManager.syncPendingMintQuotesIfStale()
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
            .testTag(UiTestTags.HistoryScreen)
            .padding(contentPadding)
            // The shell scaffold's padding already carries the status-bar inset;
            // consume it so the nested TopAppBar doesn't apply it a second time.
            .consumeWindowInsets(contentPadding)
            .nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            TabTopBar(
                title = "History",
                scrollBehavior = scrollBehavior,
                actions = {
                    // Toggle search — same as iOS History toolbar Search
                    // (press again to hide; clears query on dismiss).
                    IconButton(
                        onClick = {
                            if (searching) {
                                searching = false
                                query = ""
                                keyboardController?.hide()
                            } else {
                                searching = true
                            }
                        },
                    ) {
                        ToolbarIcon(
                            imageVector = Icons.Outlined.Search,
                            contentDescription = if (searching) "Hide search" else "Search history",
                        )
                    }
                    Box {
                        IconButton(onClick = { filterMenuOpen = true }) {
                            // Outlined ↔ filled glyph swap animates (symbol-replace parity).
                            IconSwap(
                                icon = if (filter == HistoryFilter.All)
                                    Icons.Outlined.FilterList else Icons.Filled.FilterList,
                                contentDescription = "Filter",
                                iconSize = CashuTheme.iconSizes.toolbar,
                            )
                        }
                        DropdownMenu(
                            expanded = filterMenuOpen,
                            onDismissRequest = { filterMenuOpen = false },
                            shape = MaterialTheme.shapes.large,
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
                    // Manual re-check lives here (iOS parity): resume unissued
                    // mint quotes and pending (NUT-05) melts, then re-verify
                    // pending sent tokens.
                    runCatching {
                        walletManager.syncPendingMintQuotes(force = true)
                        walletManager.syncPendingMeltQuotes()
                        walletManager.loadTransactions()
                        walletManager.checkAllPendingTokens()
                    }
                    refreshing = false
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // The search field lives outside the list so it survives an
            // empty result set (searching to zero matches must not unmount
            // the field mid-typing) — iOS History search toggle parity.
            Column(modifier = Modifier.fillMaxSize()) {
                AnimatedVisibility(
                    visible = searching,
                    enter = expandVertically(spring(stiffness = Spring.StiffnessMediumLow, visibilityThreshold = IntSize.VisibilityThreshold)) + fadeIn(),
                    exit = shrinkVertically(spring(stiffness = Spring.StiffnessMediumLow, visibilityThreshold = IntSize.VisibilityThreshold)) + fadeOut(),
                ) {
                    CashuSearchBar(
                        value = query,
                        onValueChange = { query = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(
                                horizontal = CashuTheme.spacing.comfortable,
                                vertical = CashuTheme.spacing.snug,
                            )
                            .testTag(UiTestTags.HistorySearch)
                            .focusRequester(searchFocusRequester),
                        placeholder = "Search history",
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        keyboardActions = KeyboardActions(
                            onSearch = { keyboardController?.hide() },
                        ),
                    )
                    // Focus + keyboard once the field is attached after the
                    // enter animation starts (iOS .searchFocused parity).
                    LaunchedEffect(Unit) {
                        delay(50)
                        searchFocusRequester.requestFocus()
                        keyboardController?.show()
                    }
                }
                if (sections.isEmpty()) {
                    HistoryEmptyState(
                        filter = filter,
                        hasQuery = query.isNotBlank(),
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth(),
                    )
                } else {
                    val listState = rememberLazyListState()
                    // Filter switches snap the list back to the top with motion
                    // (iOS: withAnimation(.snappy) { proxy.scrollTo(first, .top) }).
                    LaunchedEffect(filter) {
                        if (listState.firstVisibleItemIndex > 0 ||
                            listState.firstVisibleItemScrollOffset > 0
                        ) {
                            listState.animateScrollToItem(0)
                        }
                    }
                    LazyColumn(
                        state = listState,
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(
                            top = CashuTheme.spacing.snug,
                            bottom = CashuTheme.spacing.section,
                        ),
                    ) {
                        sections.forEach { section ->
                            item(key = "header-${section.title}") {
                                SectionHeader(section.title.uppercase())
                            }
                            items(section.items, key = { it.key }) { item ->
                                // Spring-animated placement on filter/search changes.
                                Column(modifier = Modifier.animateItem()) {
                                when (item) {
                                    is HistoryItem.Tx -> {
                                        val tx = item.transaction
                                        val amountDisplay = formatter.displayMintUnitAmount(
                                            amount = tx.amount,
                                            unit = tx.unit,
                                            preferredPrimary = settings.amountDisplayPrimary,
                                            showFiat = settings.showFiatBalance,
                                            btcPrice = priceState.btcPrice,
                                            currencyCode = settings.bitcoinPriceCurrency,
                                            useBitcoinSymbol = settings.useBitcoinSymbol,
                                        )
                                        TransactionRow(
                                            model = TransactionRowModel(
                                                transaction = tx,
                                                title = TransactionDisplay.title(tx),
                                                timestamp = formatRelativeTimestamp(tx.dateEpochMillis),
                                                primaryAmount = amountDisplay.primary,
                                                secondaryAmount = amountDisplay.secondary,
                                            ),
                                            onClick = { onOpenTransaction(tx) },
                                            modifier = Modifier.testTag(
                                                UiTestTags.transactionRow(tx.id),
                                            ),
                                        )
                                    }
                                    is HistoryItem.Req -> {
                                        val amountDisplay = requestRowDisplay(
                                            request = item.request,
                                            formatter = formatter,
                                            preferredPrimary = settings.amountDisplayPrimary,
                                            showFiat = settings.showFiatBalance,
                                            btcPrice = priceState.btcPrice,
                                            currencyCode = settings.bitcoinPriceCurrency,
                                            useBitcoinSymbol = settings.useBitcoinSymbol,
                                        )
                                        CashuRequestRow(
                                            request = item.request,
                                            timestamp = formatRelativeTimestamp(item.request.createdAtEpochMillis),
                                            primaryAmountText = amountDisplay?.primary,
                                            secondaryAmountText = amountDisplay?.secondary,
                                            onClick = { onOpenCashuRequest(item.request) },
                                            onLongClick = { requestPendingDelete = item.request },
                                        )
                                    }
                                }
                                }
                            }
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
private fun HistoryEmptyState(
    filter: HistoryFilter,
    hasQuery: Boolean,
    modifier: Modifier = Modifier,
) {
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
            Icons.Outlined.History,
            "No Activity Yet",
            "Your first payment will show up here.",
        )
    }
    EmptyState(
        icon = icon,
        title = title,
        supporting = supporting,
        modifier = modifier,
    )
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
                item.request.displayTitle.contains(query, ignoreCase = true) ||
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
