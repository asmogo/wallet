package com.cashu.me.ui.receive

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
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
import androidx.compose.ui.platform.testTag
import kotlinx.coroutines.launch
import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.PriceService
import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.WalletManager
import com.cashu.me.Models.PendingReceiveToken
import com.cashu.me.ui.components.AmountFlipDisplay
import com.cashu.me.ui.components.AmountText
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.PaymentStatusPhase
import com.cashu.me.ui.components.PaymentStatusScreen
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.ToolbarIcon
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withMonoDigits
import com.cashu.me.ui.testing.UiTestTags

/**
 * Full-screen "Receive Ecash" page — the iOS `ReceiveTokenDetailView`
 * presented via `.fullScreenCover`. Used for every token that arrives from
 * *outside* the paste flow: the scanner, a `cashu:` deep link, or a token
 * pasted into Send. (Pasting inside the Receive sheet keeps the sheet's
 * Review face — iOS parity.)
 *
 * Composition mirrors iOS: X close (top-left, disabled mid-claim), centered
 * "Receive Ecash" title, hero amount with the unit-flip pill, Fee/Mint rows
 * (fee skeleton while the preview loads), Receive CTA + "Receive later", and
 * a full-height claim terminal.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReceiveEcashDetailScreen(
    walletManager: WalletManager,
    settingsManager: SettingsManager,
    priceService: PriceService,
    payload: String,
    onDone: () -> Unit,
    onDismissLockChanged: (Boolean) -> Unit = {},
    claimPendingReceiveToken: suspend (PendingReceiveToken) -> Long =
        walletManager::claimPendingReceiveToken,
    onDeclinePendingReceiveToken: (PendingReceiveToken) -> Unit =
        { walletManager.removePendingReceiveToken(it.tokenId) },
) {
    val settings by settingsManager.state.collectAsState()
    val walletState by walletManager.state.collectAsState()
    val priceState by priceService.state.collectAsState()
    val formatter = remember { AmountFormatter() }
    val scope = rememberCoroutineScope()

    // Parse synchronously so the hero renders on the first frame (iOS parses
    // eagerly in init — no spurious 0 → N roll on mount).
    val parsed = remember(payload) { parseToken(payload) }
    var review by remember(payload) { mutableStateOf<TokenReview?>(null) }
    var status by remember(payload) { mutableStateOf<TokenClaimStatus?>(null) }

    // Fee preview + P2PK lock check land async; the fee row shows the
    // skeleton fill-in until then.
    LaunchedEffect(parsed) {
        val ok = parsed as? TokenParseOutcome.Ok ?: return@LaunchedEffect
        review = tokenReviewDetails(
            token = ok.token,
            info = ok.info,
            walletManager = walletManager,
            settingsManager = settingsManager,
        )
    }

    // The shell's overlay BackHandler owns dismissal; it consults this lock.
    LaunchedEffect(status) {
        onDismissLockChanged(status == TokenClaimStatus.Claiming)
    }
    // Belt-and-braces: swallow back directly while the redeem is in flight.
    BackHandler(enabled = status == TokenClaimStatus.Claiming) {}

    fun claim(target: TokenReview) {
        if (status != null) return
        status = TokenClaimStatus.Claiming
        scope.launch {
            status = claimToken(target, walletManager, claimPendingReceiveToken)
        }
    }

    val heldPayment = walletState.pendingReceiveTokens.firstOrNull {
        it.token == (parsed as? TokenParseOutcome.Ok)?.token && it.isCashuRequestPayment
    }

    // Surface (not a bare Box): the overlay renders outside any Material
    // container, so this also establishes LocalContentColor = onBackground —
    // without it, default content color is black on the dark canvas.
    Surface(
        modifier = Modifier
            .fillMaxSize()
            .testTag(UiTestTags.ReceiveEcashDetail),
        color = MaterialTheme.colorScheme.background,
    ) {
        when (val current = status) {
            // Claiming / success / failure own the whole screen (iOS: the
            // full-screen page morphs to PaymentStatusView).
            is TokenClaimStatus -> TokenClaimTerminal(
                status = current,
                formatter = formatter,
                useBitcoinSymbol = settings.useBitcoinSymbol,
                onDone = onDone,
                onRetry = { status = null },
            )

            null -> when (parsed) {
                is TokenParseOutcome.Invalid -> PaymentStatusScreen(
                    phase = PaymentStatusPhase.Failure,
                    title = "Couldn't read token",
                    detail = parsed.message,
                    onDone = onDone,
                )

                is TokenParseOutcome.Ok -> ConfirmContent(
                    parsed = parsed,
                    review = review,
                    formatter = formatter,
                    fiatPrice = if (settings.showFiatBalance) priceState.btcPrice.takeIf { it > 0 } else null,
                    currencyCode = settings.bitcoinPriceCurrency,
                    useBitcoinSymbol = settings.useBitcoinSymbol,
                    amountPrimary = AmountDisplayPrimary.fromRaw(settings.amountDisplayPrimary),
                    onFlipPrimary = { settingsManager.setAmountDisplayPrimary(it.rawValue) },
                    onClose = onDone,
                    onReceive = { review?.let(::claim) },
                    secondaryActionText = if (heldPayment != null) "Decline" else "Receive later",
                    onSecondaryAction = {
                        if (heldPayment != null) {
                            onDeclinePendingReceiveToken(heldPayment)
                            onDone()
                        } else {
                            review?.let {
                                val alreadyPending = walletManager.state.value.pendingReceiveTokens
                                    .any { pending -> pending.token == it.token }
                                if (!alreadyPending) {
                                    walletManager.savePendingReceiveToken(pendingReceiveTokenFrom(it))
                                }
                                onDone()
                            }
                        }
                    },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ConfirmContent(
    parsed: TokenParseOutcome.Ok,
    review: TokenReview?,
    formatter: AmountFormatter,
    fiatPrice: Double?,
    currencyCode: String,
    useBitcoinSymbol: Boolean,
    amountPrimary: AmountDisplayPrimary,
    onFlipPrimary: (AmountDisplayPrimary) -> Unit,
    onClose: () -> Unit,
    onReceive: () -> Unit,
    secondaryActionText: String,
    onSecondaryAction: () -> Unit,
) {
    val info = parsed.info
    val isSatToken = info.unit.equals("sat", ignoreCase = true)
    // Hero shows what claiming will actually credit; until the fee preview
    // lands it shows the gross amount, then rolls to net (keyed digit ticker).
    val fee = review?.fee
    val netAmount = info.amount - (fee ?: 0L).coerceIn(0L, info.amount)
    Column(modifier = Modifier.fillMaxSize()) {
        CenterAlignedTopAppBar(
            title = { Text("Receive Ecash", style = MaterialTheme.typography.titleMedium) },
            navigationIcon = {
                IconButton(onClick = onClose) {
                    ToolbarIcon(Icons.Outlined.Close, contentDescription = "Close")
                }
            },
            colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                containerColor = MaterialTheme.colorScheme.background,
            ),
        )
        // Hero sits in the upper third (iOS PayFlowScaffold proportions).
        Spacer(Modifier.weight(HeroTopWeight))
        Box(
            modifier = Modifier.fillMaxWidth(),
            contentAlignment = Alignment.Center,
        ) {
            if (isSatToken) {
                AmountFlipDisplay(
                    amountSats = netAmount,
                    primary = amountPrimary,
                    onFlip = onFlipPrimary,
                    btcPrice = fiatPrice,
                    currencyCode = currencyCode,
                    useBitcoinSymbol = useBitcoinSymbol,
                )
            } else {
                // Non-sat units render plainly in their own currency — eur is
                // already fiat, nothing to flip to (iOS parity).
                AmountText(
                    text = CurrencyAmount(
                        netAmount,
                        CurrencyRegistry.currencyForMintUnit(info.unit),
                    ).formatted(),
                    style = MaterialTheme.typography.displayMedium.withMonoDigits(),
                )
            }
        }
        Spacer(Modifier.weight(HeroBottomWeight))
        TokenInspectorRows(
            info = info,
            fee = fee,
            p2pkLock = review?.p2pkLock,
            modifier = Modifier.padding(horizontal = CashuTheme.spacing.comfortable),
        )
        Spacer(Modifier.weight(FooterWeight))
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = CashuTheme.spacing.comfortable),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            PrimaryButton(
                text = "Receive",
                onClick = onReceive,
                // Disabled until the fee/lock preview lands (net amount must be
                // known before committing) and while P2PK-locked to foreign keys.
                enabled = review?.canClaim == true,
                // The app's one inverted-ink CTA — mirrors iOS's sole
                // .glassButton(prominent: true) on the receive commit
                // (ReceiveView.swift); every other bottom CTA is neutral gray.
                colors = ButtonDefaults.buttonColors(),
            )
            Spacer(Modifier.height(CashuTheme.spacing.snug))
            GhostButton(
                text = secondaryActionText,
                onClick = onSecondaryAction,
            )
            Spacer(Modifier.navigationBarsPadding())
        }
    }
}

// Vertical rhythm of the confirm page (approximates the iOS screenshot:
// hero ~1/3 down, rows mid, CTA bottom-anchored).
private const val HeroTopWeight = 0.8f
private const val HeroBottomWeight = 0.6f
private const val FooterWeight = 1.4f
