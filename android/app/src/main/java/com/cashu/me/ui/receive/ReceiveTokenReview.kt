package com.cashu.me.ui.receive

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountBalance
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.Receipt
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry
import com.cashu.me.Core.SettingsManager
import com.cashu.me.Core.TokenParser
import com.cashu.me.Core.Wallet.WalletMessage
import com.cashu.me.Core.Wallet.walletMessage
import com.cashu.me.Core.WalletManager
import com.cashu.me.Models.PendingReceiveToken
import com.cashu.me.Models.TokenInfo
import com.cashu.me.ui.components.CanvasDivider
import com.cashu.me.ui.components.InspectorRow
import com.cashu.me.ui.components.PaymentStatusPhase
import com.cashu.me.ui.components.PaymentStatusScreen

/**
 * Shared review/claim core for ecash tokens — one implementation behind both
 * surfaces (iOS ReceiveTokenDetailView):
 *  - the Receive *sheet*'s Review face (paste flow, and its in-sheet scan)
 *  - the full-screen Receive Ecash page (scanned / deep-linked / Send-bounced
 *    tokens)
 * Extracted so the two presentations can't drift apart.
 */

/** A validated token ready to claim. */
internal data class TokenReview(
    val token: String,
    val info: TokenInfo,
    val fee: Long,
    val locked: Boolean,
)

internal sealed interface TokenParseOutcome {
    data class Ok(val token: String, val info: TokenInfo) : TokenParseOutcome
    data class Invalid(val message: String) : TokenParseOutcome
}

/** Synchronous decode — cheap, safe to run in composition via `remember`. */
internal fun parseToken(raw: String): TokenParseOutcome {
    val token = TokenParser.extractToken(raw)
        ?: return TokenParseOutcome.Invalid(
            TokenParser.malformedTokenMessage(raw) ?: "Couldn't read token.",
        )
    val info = TokenInfo.parse(token)
        ?: return TokenParseOutcome.Invalid("Couldn't decode token.")
    return TokenParseOutcome.Ok(token = token, info = info)
}

/**
 * Async half of validation: receive-swap fee preview + P2PK lock check.
 * Fee failures degrade to 0 (matching the historical sheet behavior); the
 * redeem itself is the source of truth.
 */
internal suspend fun tokenReviewDetails(
    token: String,
    info: TokenInfo,
    walletManager: WalletManager,
    settingsManager: SettingsManager,
): TokenReview {
    val fee = runCatching { walletManager.calculateReceiveFee(token) }.getOrDefault(0L)
    val locks = TokenParser.p2pkPubkeys(token)
    val unlocked = if (locks.isEmpty()) {
        true
    } else {
        settingsManager.p2pkSigningKeysFor(locks).isNotEmpty()
    }
    return TokenReview(token = token, info = info, fee = fee, locked = !unlocked)
}

/**
 * The claim terminal state (iOS ReceiveTokenDetailView phase): once Receive is
 * tapped, the surface swaps to the shared PaymentStatusScreen — spinner →
 * green check with Amount/Fee/Mint rows, or red X with mapped error copy.
 */
internal sealed interface TokenClaimStatus {
    data object Claiming : TokenClaimStatus
    data class Claimed(val amount: Long, val fee: Long, val unit: String, val mint: String) : TokenClaimStatus
    data class Failed(val message: WalletMessage) : TokenClaimStatus
}

/**
 * Reconciles the receive preview with CDK's settled credit.
 *
 * The decoded token amount is gross while [creditedAmount] is the exact net
 * amount added to the wallet. Clamp only for the subtraction so a malformed
 * value cannot produce a negative fee; the receipt still reports the
 * non-negative credited amount returned by settlement.
 */
internal fun settledTokenClaim(
    review: TokenReview,
    creditedAmount: Long,
): TokenClaimStatus.Claimed {
    val grossAmount = review.info.amount.coerceAtLeast(0L)
    val safeCreditedAmount = creditedAmount.coerceAtLeast(0L)
    val paidFee = grossAmount - safeCreditedAmount.coerceAtMost(grossAmount)
    return TokenClaimStatus.Claimed(
        amount = safeCreditedAmount,
        fee = paidFee,
        unit = review.info.unit,
        mint = review.info.mint,
    )
}

// iOS ReceiveTokenDetailView: floor the redeem at 500ms so the "Claiming…"
// spinner is legible on instant redeems. Not a fake delay — the redeem itself
// hits the mint; we only pad the *display* of an early result.
internal const val MinClaimingBeatMillis = 500L

/** Runs the redeem with the minimum "Claiming…" beat; never returns Claiming. */
internal suspend fun claimToken(
    review: TokenReview,
    walletManager: WalletManager,
    claimPendingReceiveToken: suspend (PendingReceiveToken) -> Long =
        walletManager::claimPendingReceiveToken,
): TokenClaimStatus {
    val startedAt = System.currentTimeMillis()
    val result = try {
        val pending = walletManager.state.value.pendingReceiveTokens
            .firstOrNull { it.token == review.token }
        Result.success(
            if (pending != null) {
                claimPendingReceiveToken(pending)
            } else {
                walletManager.receiveTokens(review.token)
            },
        )
    } catch (c: CancellationException) {
        throw c
    } catch (t: Throwable) {
        Result.failure(t)
    }
    // Hold the "Claiming…" beat so the spinner never flashes for a frame.
    val elapsed = System.currentTimeMillis() - startedAt
    if (elapsed < MinClaimingBeatMillis) delay(MinClaimingBeatMillis - elapsed)
    return result.fold(
        // The gateway's exact net credit supersedes the preview. Reconcile the
        // receipt from gross − credited so both amount and fee describe the
        // same settlement.
        onSuccess = { credited -> settledTokenClaim(review, credited) },
        onFailure = { TokenClaimStatus.Failed(it.walletMessage) },
    )
}

/** "Receive later": persist the token for a future claim. */
internal fun pendingReceiveTokenFrom(review: TokenReview): PendingReceiveToken =
    PendingReceiveToken(
        tokenId = review.token.take(64),
        token = review.token,
        amount = review.info.amount,
        mintUrl = review.info.mint,
        dateEpochMillis = System.currentTimeMillis(),
        unit = review.info.unit,
    )

/**
 * Fee / Mint / P2PK / Memo inspector rows shared by the sheet Review face and
 * the full-screen detail page. A null [fee] renders the skeleton fill-in
 * (iOS: fee row spinner while the preview loads).
 */
@Composable
internal fun TokenInspectorRows(
    info: TokenInfo,
    fee: Long?,
    locked: Boolean,
    modifier: Modifier = Modifier,
) {
    val isSatToken = info.unit.equals("sat", ignoreCase = true)
    val tokenCurrency = CurrencyRegistry.currencyForMintUnit(info.unit)
    Column(modifier = modifier.fillMaxWidth()) {
        InspectorRow(
            label = "Fee",
            value = when {
                fee == null -> ""
                fee == 0L -> "Free"
                isSatToken -> "$fee sat"
                else -> CurrencyAmount(fee, tokenCurrency).formatted()
            },
            leadingIcon = Icons.Outlined.Receipt,
            loading = fee == null,
        )
        CanvasDivider(leadingInset = 16.dp)
        InspectorRow(
            label = "Mint",
            value = info.mint,
            leadingIcon = Icons.Outlined.AccountBalance,
        )
        if (locked) {
            CanvasDivider(leadingInset = 16.dp)
            InspectorRow(
                label = "P2PK",
                value = "Requires your key",
                leadingIcon = Icons.Outlined.Lock,
            )
        }
        if (info.memo != null) {
            CanvasDivider(leadingInset = 16.dp)
            InspectorRow(
                label = "Memo",
                value = info.memo,
            )
        }
    }
}

/**
 * Maps a [TokenClaimStatus] to the shared [PaymentStatusScreen] terminal.
 * The caller decides the container (pinned sheet height vs. full screen).
 *
 * One call site for every status: the terminal stays mounted across
 * Claiming → Claimed/Failed, so the entrance animation runs once and the
 * spinner morphs into the check/X in place instead of a full re-entrance.
 */
@Composable
internal fun TokenClaimTerminal(
    status: TokenClaimStatus,
    formatter: AmountFormatter,
    useBitcoinSymbol: Boolean,
    onDone: () -> Unit,
    onRetry: () -> Unit,
) {
    val phase = when (status) {
        TokenClaimStatus.Claiming -> PaymentStatusPhase.Processing
        is TokenClaimStatus.Claimed -> PaymentStatusPhase.Success
        is TokenClaimStatus.Failed -> PaymentStatusPhase.Failure
    }
    PaymentStatusScreen(
        phase = phase,
        title = when (status) {
            TokenClaimStatus.Claiming -> "Claiming…"
            is TokenClaimStatus.Claimed -> "Payment received"
            is TokenClaimStatus.Failed -> "Couldn't receive"
        },
        detail = (status as? TokenClaimStatus.Failed)?.message?.text,
        // Terminal outcomes (already redeemed) can't be retried — offer Done;
        // anything else returns to Review for another attempt.
        doneLabel = if (status is TokenClaimStatus.Failed && !status.message.isTerminal) {
            "Try again"
        } else {
            "Done"
        },
        onDone = when (status) {
            TokenClaimStatus.Claiming -> null
            is TokenClaimStatus.Claimed -> onDone
            is TokenClaimStatus.Failed -> {
                { if (status.message.isTerminal) onDone() else onRetry() }
            }
        },
        rows = (status as? TokenClaimStatus.Claimed)?.let { claimed ->
            {
                val isSat = claimed.unit.equals("sat", ignoreCase = true)
                val currency = CurrencyRegistry.currencyForMintUnit(claimed.unit)
                fun formatted(value: Long): String = if (isSat) {
                    formatter.formatWalletSats(value, useBitcoinSymbol)
                } else {
                    CurrencyAmount(value, currency).formatted()
                }
                InspectorRow(
                    label = "Amount",
                    value = formatted(claimed.amount),
                    leadingIcon = Icons.Outlined.Payments,
                )
                if (claimed.fee > 0L) {
                    CanvasDivider(leadingInset = 16.dp)
                    InspectorRow(
                        label = "Fee",
                        value = formatted(claimed.fee),
                        leadingIcon = Icons.Outlined.Receipt,
                    )
                }
                CanvasDivider(leadingInset = 16.dp)
                InspectorRow(
                    label = "Mint",
                    value = claimed.mint,
                    leadingIcon = Icons.Outlined.AccountBalance,
                )
            }
        },
    )
}
