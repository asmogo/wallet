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
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.testTag as semanticsTestTag
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.AmountDisplayText
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.displayMintUnitAmount
import com.cashu.me.Core.HomeBalance
import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry
import com.cashu.me.Core.PriceService
import com.cashu.me.Core.ReceivedPaymentEvent
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.TransactionDisplay
import com.cashu.me.Core.WalletHaptic
import com.cashu.me.Core.WalletManager
import com.cashu.me.Core.displayText
import com.cashu.me.Core.recentCompletedTransactions
import com.cashu.me.Core.rememberWalletHaptics
import com.cashu.me.Models.WalletTransaction
import com.cashu.me.ui.components.BalanceDisplay
import com.cashu.me.ui.components.balanceHeroHeight
import com.cashu.me.ui.components.EmptyState
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.SectionHeader
import com.cashu.me.ui.components.scrollEdgeFade
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

internal object HomeActionAccessibility {
    const val ReceiveClickLabel =
        "open the unified flow for a pasted ecash token or a new Cashu Request, " +
            "Lightning invoice, BOLT12 offer, or Bitcoin address"
    const val SendClickLabel =
        "open the unified flow for ecash, Lightning addresses, BOLT11 invoices, " +
            "BOLT12 offers, Bitcoin addresses, or Cashu Requests"
}

internal const val PREPARING_WALLET_LABEL = "Preparing wallet…"

internal data class HomePaymentActionAvailability(
    val isPreparingWallet: Boolean,
    val receiveEnabled: Boolean,
    val sendEnabled: Boolean,
)

internal fun homePaymentActionAvailability(
    isRuntimeReady: Boolean,
): HomePaymentActionAvailability {
    return HomePaymentActionAvailability(
        isPreparingWallet = !isRuntimeReady,
        // Unified Receive always has mint-independent ecash paths.
        receiveEnabled = isRuntimeReady,
        // iOS parity: Send is tappable without a mint too — the sheet answers with
        // the connect-a-mint surface, which is more use than a dead button.
        sendEnabled = isRuntimeReady,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    priceService: PriceService,
    onAddMint: () -> Unit,
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
    val haptics = rememberWalletHaptics()
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    val paymentActions = homePaymentActionAvailability(
        isRuntimeReady = walletState.isRuntimeReady,
    )

    val balanceDisplay = remember(walletState.balance, settings, priceState) {
        formatter.displayText(
            amountSats = walletState.balance,
            preferredPrimary = settings.homeBalancePrimary,
            showFiat = settings.showFiatBalance && priceState.btcPrice > 0,
            btcPrice = priceState.btcPrice,
            currencyCode = settings.bitcoinPriceCurrency,
            useBitcoinSymbol = settings.useBitcoinSymbol,
        )
    }
    val onSatBalanceClick: (() -> Unit)? = balanceDisplay.secondary?.let {
        {
            haptics.perform(WalletHaptic.Selection)
            settingsManager.setHomeBalancePrimary(
                if (balanceDisplay.effectivePrimary == AmountDisplayPrimary.Sats) {
                    AmountDisplayPrimary.Fiat.rawValue
                } else {
                    AmountDisplayPrimary.Sats.rawValue
                },
            )
        }
    }

    val recentTransactions = remember(walletState.transactions) {
        recentCompletedTransactions(walletState.transactions, RECENT_LIMIT)
    }

    // Received-payment beat (iOS MainWalletView notification parity): collect
    // only explicit, confirmed credits from WalletManager. Balance refreshes,
    // restore, mint recovery, and reclaim therefore cannot trigger it.
    //
    // A receive flow owns its PaymentStatusScreen success haptic. Home performs
    // the success haptic only for passive receipts with no in-flow terminal.
    // collectLatest keeps rapid receipts last-write-wins and restarts the 2.5s
    // dismissal timer.
    var receivedPayment by remember { mutableStateOf<ReceivedPaymentEvent?>(null) }
    LaunchedEffect(walletManager) {
        walletManager.receivedPayments.collectLatest { event ->
            receivedPayment = event
            if (event.homeOwnsSuccessHaptic) {
                haptics.perform(WalletHaptic.Success)
            }
            delay(RECEIVED_DELTA_DISMISS_MS)
            receivedPayment = null
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
        // Pinned top section (balance + actions), measured first.
        val pinned = subcompose(HomeSlot.Pinned) {
            PinnedTop(
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
                        onSatBalanceClick = onSatBalanceClick,
                        receivedPayment = receivedPayment,
                        formatter = formatter,
                        statusMessage = PREPARING_WALLET_LABEL.takeIf {
                            paymentActions.isPreparingWallet
                        },
                    )
                },
                triptych = {
                    ActionDuet(
                        // Receive opens the unified surface directly — no chooser.
                        onReceive = onReceive,
                        // Send opens the unified surface directly — no chooser.
                        onSend = onSend,
                        // The unified Receive sheet always has mint-independent
                        // ecash paths (paste/scan and an any-mint NUT-18 request).
                        receiveEnabled = paymentActions.receiveEnabled,
                        // iOS parity: Send is tappable at zero balance; the sheet shows
                        // "Nothing to send yet" with a Receive CTA instead of disabling here.
                        sendEnabled = paymentActions.sendEnabled,
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
                    .scrollEdgeFade(top = pinnedTopDp),
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
                            onAction = if (!hasMints) onAddMint else null,
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
                                preferredPrimary = settings.homeBalancePrimary,
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

// Floor for the empty-state slot when the pinned header dominates the viewport
// (large font scales); keeps the tray glyph + copy visible and scrollable.
private val EMPTY_STATE_MIN_HEIGHT = 240.dp

/** SubcomposeLayout slots for the Home screen. */
private enum class HomeSlot { Pinned, Body }

@Composable
private fun PinnedTop(
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
        // Balance + Receive/Send — tighter vertical rhythm than the older ~28dp
        // gaps so the hero block reads as one unit under the nav row.
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
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
    onSatBalanceClick: (() -> Unit)?,
    receivedPayment: ReceivedPaymentEvent?,
    formatter: AmountFormatter,
    statusMessage: String?,
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
                .height(balanceHeroHeight()),
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
                    val receivedDelta = receivedPayment
                        ?.takeIf { it.unit.equals(unit, ignoreCase = true) }
                        ?.displayDelta(formatter)
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
                        receivedDelta = receivedDelta,
                        statusMessage = statusMessage,
                        onPrimaryClick = if (isSat) onSatBalanceClick else null,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            } else {
                BalanceDisplay(
                    amount = satAmount,
                    receivedDelta = receivedPayment
                        ?.takeIf { it.unit.equals("sat", ignoreCase = true) }
                        ?.displayDelta(formatter),
                    statusMessage = statusMessage,
                    onPrimaryClick = onSatBalanceClick,
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

private fun ReceivedPaymentEvent.displayDelta(formatter: AmountFormatter): String =
    if (unit.equals("sat", ignoreCase = true)) {
        "+" + formatter.formatSats(amount, includeUnit = false)
    } else {
        "+" + CurrencyAmount(
            amount,
            CurrencyRegistry.currencyForMintUnit(unit),
        ).formatted()
    }

private val PAGE_DOT_SIZE = 6.dp

@Composable
internal fun ActionDuet(
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
                .homeActionSemantics(
                    label = "Receive",
                    onClickLabel = HomeActionAccessibility.ReceiveClickLabel,
                    testTag = UiTestTags.WalletReceive,
                    enabled = receiveEnabled,
                    onClick = onReceive,
                ),
            enabled = receiveEnabled,
            colors = actionColors,
        )
        PrimaryButton(
            text = "Send",
            onClick = onSend,
            modifier = Modifier
                .weight(1f)
                .homeActionSemantics(
                    label = "Send",
                    onClickLabel = HomeActionAccessibility.SendClickLabel,
                    testTag = UiTestTags.WalletSend,
                    enabled = sendEnabled,
                    onClick = onSend,
                ),
            enabled = sendEnabled,
            colors = actionColors,
        )
    }
}

/**
 * Replaces the Button's descendant semantics with one TalkBack node: the
 * visible label is spoken once, while the click action describes the unified
 * destination and accepted inputs.
 */
private fun Modifier.homeActionSemantics(
    label: String,
    onClickLabel: String,
    testTag: String,
    enabled: Boolean,
    onClick: () -> Unit,
): Modifier = clearAndSetSemantics {
    contentDescription = label
    semanticsTestTag = testTag
    role = Role.Button
    if (enabled) {
        onClick(label = onClickLabel) {
            onClick()
            true
        }
    } else {
        disabled()
    }
}
