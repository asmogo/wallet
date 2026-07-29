package com.cashu.me.ui.home

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.AmountDisplayText
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.displayMintUnitAmount
import com.cashu.me.Core.HomeBalance
import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry
import com.cashu.me.Core.PriceService
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.TransactionDisplay
import com.cashu.me.Core.WalletManager
import com.cashu.me.Core.displayText
import com.cashu.me.Core.recentCompletedTransactions
import com.cashu.me.Models.WalletTransaction
import com.cashu.me.ui.components.BalanceDisplay
import com.cashu.me.ui.components.BalanceHeroHeight
import com.cashu.me.ui.components.EmptyState
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.MintChip
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.TransactionRow
import com.cashu.me.ui.components.TransactionRowModel
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.components.neutralActionButtonColors
import com.cashu.me.ui.components.formatRelativeTimestamp
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.testing.UiTestTags

private const val RECENT_LIMIT = 5

// iOS MainWalletView: the received-delta beat auto-dismisses after 2.5s.
private const val RECEIVED_DELTA_DISMISS_MS = 2_500L

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    priceService: PriceService,
    onOpenMints: () -> Unit,
    onOpenHistory: () -> Unit,
    onOpenTransaction: (WalletTransaction) -> Unit,
    onReceive: () -> Unit,
    onSend: () -> Unit,
    onOpenSettings: () -> Unit,
    onScan: () -> Unit,
    contentPadding: PaddingValues,
) {
    val walletState by walletManager.state.collectAsState()
    val settings by settingsManager.state.collectAsState()
    val priceState by priceService.state.collectAsState()
    val formatter = remember { AmountFormatter() }
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }

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
        recentCompletedTransactions(walletState.transactions, RECENT_LIMIT)
    }

    // Received-delta beat (iOS MainWalletView "payment-received celebration"):
    // when the balance rises while Home is composed (receives land behind the
    // flow sheet), a transient monochrome "+N" takes over the fiat slot for
    // 2.5s, then fiat fades back. Rapid receives coalesce last-write-wins (the
    // LaunchedEffect restart cancels the prior dismiss timer); a balance drop
    // clears the beat immediately. Tracking only starts once the wallet is
    // initialized and idle, so the startup 0 → N load can't fire a spurious
    // beat (iOS keys this off an explicit token-received notification instead).
    var lastObservedBalance by remember { mutableStateOf<Long?>(null) }
    var receivedDelta by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(walletState.balance, walletState.isInitialized, walletState.isLoading) {
        if (!walletState.isInitialized || walletState.isLoading) return@LaunchedEffect
        val previous = lastObservedBalance
        lastObservedBalance = walletState.balance
        if (previous != null && walletState.balance > previous) {
            receivedDelta = "+" + formatter.formatSats(
                walletState.balance - previous,
                includeUnit = false,
            )
            delay(RECEIVED_DELTA_DISMISS_MS)
            receivedDelta = null
        } else {
            receivedDelta = null
        }
    }

    // iOS parity: MainWalletView measures the pinned header (GeometryReader +
    // PreferenceKey) and derives the scroll inset + fade mask from the measured
    // height. SubcomposeLayout measures the pinned header *before* the list is
    // composed, so the very first frame lays out with the correct inset — this
    // replaces the old onSizeChanged + hide-first-frame alpha hack.
    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            if (!refreshing) {
                refreshing = true
                scope.launch {
                    try {
                        // Match iOS MainWalletView: pulling the wallet timeline
                        // re-checks pending receives and sent ecash, which also
                        // reloads the transactions shown in Recent.
                        walletManager.syncPendingMintQuotes(force = true)
                        walletManager.checkAllPendingTokens()
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Throwable) {
                        // WalletManager already publishes the operation error.
                    } finally {
                        refreshing = false
                    }
                }
            }
        },
        modifier = Modifier
            .fillMaxSize()
            .testTag(UiTestTags.WalletScreen)
            .padding(contentPadding)
            // The scaffold's contentPadding already carries the status-bar inset;
            // consume it so PinnedTop's statusBarsPadding() can't double-apply.
            .consumeWindowInsets(contentPadding),
    ) {
        SubcomposeLayout(modifier = Modifier.fillMaxSize()) { constraints ->
        // Pinned top section (mint chip + balance + triptych), measured first.
        val pinned = subcompose(HomeSlot.Pinned) {
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
                    HomeBalanceHero(
                        showsPager = HomeBalance.showsUnitPager(
                            activeMintSupportsMultipleUnits = walletState.activeMint?.supportsMultipleUnits == true,
                            balancesByUnit = walletState.balancesByUnit,
                        ),
                        balancesByUnit = walletState.balancesByUnit,
                        satAmount = balanceDisplay,
                        persistedUnit = settings.homeBalanceUnit,
                        onUnitSelected = settingsManager::setHomeBalanceUnit,
                        receivedDelta = receivedDelta,
                    )
                },
                triptych = {
                    ActionDuet(
                        // Receive opens the unified surface directly — no chooser.
                        onReceive = onReceive,
                        // Send opens the unified surface directly — no chooser.
                        onSend = onSend,
                        receiveEnabled = walletState.activeMint != null,
                        // iOS parity: Send is tappable at zero balance; the sheet shows
                        // "Nothing to send yet" with a Receive CTA instead of disabling here.
                        sendEnabled = walletState.activeMint != null,
                    )
                },
                onOpenSettings = onOpenSettings,
                onScan = onScan,
            )
        }.first().measure(constraints.copy(minHeight = 0))

        val pinnedTopPx = pinned.height
        val pinnedTopDp = pinnedTopPx.toDp()
        val viewportHeight = constraints.maxHeight.toDp()

        // Scrolling body sits behind the pinned top with a soft fade-mask at the
        // top edge so rows dissolve into the pinned region as they scroll up,
        // matching the iOS LinearGradient scroll mask.
        val body = subcompose(HomeSlot.Body) {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .graphicsLayer {
                        compositingStrategy = CompositingStrategy.Offscreen
                    }
                    .drawWithCache {
                        val fadeBandPx = FADE_BAND_HEIGHT.toPx()
                        val total = size.height.coerceAtLeast(1f)
                        val clearEnd = (pinnedTopPx / total).coerceIn(0f, 1f)
                        val opaqueAt = ((pinnedTopPx + fadeBandPx) / total).coerceIn(0f, 1f)
                        val brush = Brush.verticalGradient(
                            0f to Color.Transparent,
                            clearEnd to Color.Transparent,
                            opaqueAt to Color.Black,
                            1f to Color.Black,
                        )
                        onDrawWithContent {
                            drawContent()
                            drawRect(brush = brush, blendMode = BlendMode.DstIn)
                        }
                    },
                contentPadding = PaddingValues(
                    top = pinnedTopDp + CashuTheme.spacing.snug,
                    bottom = CashuTheme.spacing.section,
                ),
            ) {
                item("section-header") {
                    if (recentTransactions.isNotEmpty()) {
                        SectionHeader(text = "Recent")
                    }
                }
                if (recentTransactions.isEmpty()) {
                    item("empty") {
                        val hasMints = walletState.mints.isNotEmpty()
                        // iOS: a single quiet tray empty state, centered in the region
                        // below the pinned header (containerRelativeFrame parity) —
                        // sized from the measured header, not a hardcoded height.
                        val emptyHeight = (viewportHeight - pinnedTopDp - CashuTheme.spacing.section)
                            .coerceAtLeast(EMPTY_STATE_MIN_HEIGHT)
                        EmptyState(
                            icon = if (hasMints) Icons.Outlined.Inbox else Icons.Outlined.AccountBalance,
                            title = if (hasMints) "No Activity Yet" else "Add a mint to get started",
                            supporting = if (hasMints) "Your recent payments will show up here."
                            else "Mints custody your ecash. Add one to begin.",
                            actionLabel = if (!hasMints) "Add mint" else null,
                            onAction = if (!hasMints) onOpenMints else null,
                            modifier = Modifier.height(emptyHeight),
                        )
                    }
                } else {
                    items(recentTransactions, key = { it.id }) { tx ->
                        // Spring-animated placement when the timeline reshuffles
                        // as completed payments land — History parity.
                        Column(modifier = Modifier.animateItem()) {
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
                            )
                        }
                    }
                    item("view-all") {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = CashuTheme.spacing.snug),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center,
                        ) {
                            // Chevron lives inside the button so the whole affordance
                            // is one touch target (iOS: text + chevron in one Button).
                            GhostButton(
                                text = "View all activity",
                                onClick = onOpenHistory,
                                trailingIcon = Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                                textStyle = MaterialTheme.typography.bodyLarge,
                                contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }.first().measure(constraints)

            layout(constraints.maxWidth, constraints.maxHeight) {
                body.place(0, 0)
                pinned.place(0, 0)
            }
        }
    }
}

// iOS scrollFadeBand: rows dissolve over a 24pt band beneath the measured
// pinned-header bottom edge (MainWalletView.scrollFadeBand = 24).
private val FADE_BAND_HEIGHT = 24.dp
// Floor for the empty-state slot when the pinned header dominates the viewport
// (large font scales); keeps the tray glyph + copy visible and scrollable.
private val EMPTY_STATE_MIN_HEIGHT = 240.dp

/** SubcomposeLayout slots for the Home screen. */
private enum class HomeSlot { Pinned, Body }

@Composable
private fun PinnedTop(
    mintChip: @Composable () -> Unit,
    balance: @Composable () -> Unit,
    triptych: @Composable () -> Unit,
    onOpenSettings: () -> Unit,
    onScan: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            // Solid background; the fade effect lives on the LazyColumn mask below
            // (rows fade as they scroll up past the pinned region).
            .background(MaterialTheme.colorScheme.background)
            .statusBarsPadding()
            .padding(horizontal = CashuTheme.spacing.comfortable)
            .padding(top = CashuTheme.spacing.snug, bottom = CashuTheme.spacing.comfortable),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // Wallet-level navigation affordances: settings on the leading edge,
        // scanner on the trailing edge. IconButton preserves a 48dp touch target.
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            IconButton(onClick = onOpenSettings) {
                ToolbarIcon(
                    imageVector = Icons.Outlined.Settings,
                    contentDescription = "Settings",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            IconButton(
                onClick = onScan,
                modifier = Modifier.testTag(UiTestTags.WalletScan),
            ) {
                ToolbarIcon(
                    imageVector = Icons.Outlined.QrCodeScanner,
                    contentDescription = "Scan QR",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        // Mint chip + balance + Receive/Send — tighter vertical rhythm than the
        // older ~28dp gaps so the hero block reads as one unit under the nav row.
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                mintChip()
            }
            balance()
            triptych()
        }
    }
}

/**
 * Home balance hero with a fixed footprint: balance column + page-dot slot are
 * always the same height whether the mint is single-unit or multi-unit, so
 * switching mints never shoves Receive/Send / Recent up or down.
 *
 * Multi-unit (iOS MainWalletView.unitBalanceHero): swipeable pager, sat first
 * then held non-sat units. Sat keeps the ₿/fiat toggle + secondary/delta line;
 * non-sat pages show their own currency with no fiat conversion.
 */
@Composable
private fun HomeBalanceHero(
    showsPager: Boolean,
    balancesByUnit: Map<String, Long>,
    satAmount: AmountDisplayText,
    persistedUnit: String,
    onUnitSelected: (String) -> Unit,
    receivedDelta: String?,
) {
    val units = HomeBalance.homeBalanceUnits(balancesByUnit)
    val resolvedUnit = HomeBalance.resolvedUnit(persistedUnit, units)
    val pagerState = rememberPagerState(
        initialPage = units.indexOf(resolvedUnit).coerceAtLeast(0),
        pageCount = { units.size.coerceAtLeast(1) },
    )
    LaunchedEffect(pagerState.currentPage, units, showsPager) {
        if (!showsPager) return@LaunchedEffect
        units.getOrNull(pagerState.currentPage)?.let { current ->
            if (current != persistedUnit) onUnitSelected(current)
        }
    }
    // Keep the pager on the resolved unit when the held-unit list changes.
    LaunchedEffect(resolvedUnit, units, showsPager) {
        if (!showsPager) return@LaunchedEffect
        val target = units.indexOf(resolvedUnit).coerceAtLeast(0)
        if (pagerState.currentPage != target) {
            pagerState.scrollToPage(target)
        }
    }

    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(BalanceHeroHeight),
            contentAlignment = Alignment.Center,
        ) {
            if (showsPager) {
                HorizontalPager(
                    state = pagerState,
                    modifier = Modifier.fillMaxWidth(),
                    beyondViewportPageCount = (units.size - 1).coerceAtLeast(0),
                    key = { units.getOrElse(it) { "sat" } },
                ) { page ->
                    val unit = units.getOrElse(page) { "sat" }
                    val isSat = unit.equals("sat", ignoreCase = true)
                    BalanceDisplay(
                        amount = if (isSat) {
                            satAmount
                        } else {
                            AmountDisplayText(
                                primary = CurrencyAmount(
                                    balancesByUnit[unit] ?: 0L,
                                    CurrencyRegistry.currencyForMintUnit(unit),
                                ).formatted(),
                                secondary = null,
                                effectivePrimary = AmountDisplayPrimary.Sats,
                            )
                        },
                        receivedDelta = if (isSat) receivedDelta else null,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            } else {
                BalanceDisplay(
                    amount = satAmount,
                    receivedDelta = receivedDelta,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
        // Dot slot is always reserved (gap + dot height) so appearing/disappearing
        // indicators never reflow the actions below.
        Spacer(Modifier.height(CashuTheme.spacing.snug))
        Box(
            modifier = Modifier.height(PAGE_DOT_SIZE),
            contentAlignment = Alignment.Center,
        ) {
            if (showsPager) {
                Row(horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.tight)) {
                    units.forEachIndexed { index, _ ->
                        val selected = index == pagerState.currentPage
                        val dotWidth by animateDpAsState(
                            targetValue = if (selected) PAGE_DOT_SIZE * 2.5f else PAGE_DOT_SIZE,
                            animationSpec = spring(stiffness = Spring.StiffnessMediumLow),
                            label = "dot-width",
                        )
                        val dotColor by animateColorAsState(
                            targetValue = if (selected) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.outlineVariant
                            },
                            label = "dot-color",
                        )
                        Box(
                            modifier = Modifier
                                .height(PAGE_DOT_SIZE)
                                .width(dotWidth)
                                .background(color = dotColor, shape = CircleShape),
                        )
                    }
                }
            }
        }
    }
}

private val PAGE_DOT_SIZE = 6.dp

@Composable
private fun ActionDuet(
    onReceive: () -> Unit,
    onSend: () -> Unit,
    receiveEnabled: Boolean,
    sendEnabled: Boolean,
) {
    // Twin CTAs (iOS parity): Receive and Send carry equal weight on the home
    // canvas — no filled/tonal hierarchy between them. Styled as neutral
    // tonal pills (same fill/content colors as the history row's arrow
    // chips) rather than the inverted-ink PrimaryButton default, which reads
    // as too strong for a pair of equally-weighted actions.
    val actionColors = neutralActionButtonColors()
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        PrimaryButton(
            text = "Receive",
            onClick = onReceive,
            modifier = Modifier
                .weight(1f)
                .testTag(UiTestTags.WalletReceive),
            enabled = receiveEnabled,
            colors = actionColors,
        )
        PrimaryButton(
            text = "Send",
            onClick = onSend,
            modifier = Modifier
                .weight(1f)
                .testTag(UiTestTags.WalletSend),
            enabled = sendEnabled,
            colors = actionColors,
        )
    }
}
