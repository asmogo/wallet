package com.cashu.me.ui.receive

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.WarningAmber
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
import com.cashu.me.ui.components.InspectorRow
import com.cashu.me.ui.components.PaymentStatusPhase
import com.cashu.me.ui.components.PaymentStatusScreen
import com.cashu.me.ui.settings.P2PKKeyDisplay
import com.cashu.me.ui.theme.CashuTheme

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
    val p2pkLock: P2PKLockState,
) {
    val canClaim: Boolean
        get() = p2pkLock !is P2PKLockState.Locked || p2pkLock.claimable
}

/**
 * Explicit P2PK review state. Keeping the public targets is important: a
 * claimability boolean alone cannot tell the user who the token was locked to.
 */
internal sealed interface P2PKLockState {
    data object Unlocked : P2PKLockState

    data class Locked(
        val targets: List<String>,
        val claimable: Boolean,
    ) : P2PKLockState {
        init {
            require(targets.isNotEmpty()) { "A locked token must identify a P2PK target." }
        }
    }
}

/** Display-safe projection shared by the Compose rows and focused UI tests. */
internal data class P2PKLockPresentation(
    val targetLabels: List<String>,
    val statusText: String,
    val claimable: Boolean,
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
 * Parses the token's public P2PK targets and resolves whether this wallet has a
 * usable signing key. The callback boundary keeps private key material out of
 * the review state and makes held/unheld behavior independently testable.
 */
internal fun p2pkLockState(
    token: String,
    hasSigningKey: (List<String>) -> Boolean,
): P2PKLockState = p2pkLockStateForTargets(
    targets = TokenParser.p2pkPubkeys(token),
    hasSigningKey = hasSigningKey,
)

/** Pure state seam used to verify held/unheld behavior without native CDK I/O. */
internal fun p2pkLockStateForTargets(
    targets: List<String>,
    hasSigningKey: (List<String>) -> Boolean,
): P2PKLockState {
    val canonicalTargets = targets
        .map(P2PKKeyDisplay::canonical)
        .filter(String::isNotEmpty)
        .distinctBy(SettingsManager::normalizeP2PKPublicKeyForComparison)
    return if (canonicalTargets.isEmpty()) {
        P2PKLockState.Unlocked
    } else {
        P2PKLockState.Locked(
            targets = canonicalTargets,
            claimable = hasSigningKey(canonicalTargets),
        )
    }
}

internal fun P2PKLockState.presentation(): P2PKLockPresentation? = when (this) {
    P2PKLockState.Unlocked -> null
    is P2PKLockState.Locked -> P2PKLockPresentation(
        targetLabels = targets.map(P2PKKeyDisplay::shortLabel),
        statusText = if (claimable) {
            "Claimable · Your key"
        } else {
            "Unclaimable · Key unavailable"
        },
        claimable = claimable,
    )
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
    val p2pkLock = p2pkLockState(token) { targets ->
        // p2pkSigningKeysFor deliberately throws when no usable matching key is
        // held. Convert that expected guard into stable review state so an
        // unclaimable token can still identify its recipient before action.
        runCatching {
            settingsManager.p2pkSigningKeysFor(targets).isNotEmpty()
        }.getOrDefault(false)
    }
    return TokenReview(token = token, info = info, fee = fee, p2pkLock = p2pkLock)
}

/**
 * The claim terminal state (iOS ReceiveTokenDetailView phase): once Receive is
 * tapped, the surface swaps to the shared PaymentStatusScreen — spinner →
 * green check with Amount/Fee/Mint rows, or red X with mapped error copy.
 */
internal sealed interface TokenClaimStatus {
    data object Claiming : TokenClaimStatus
    data class Claimed(val amount: Long, val fee: Long, val unit: String, val mint: String) : TokenClaimStatus

    /** Carries the review preview so the failure screen shows the same
     * Amount/Fee/Mint rows as success (iOS passes successRows for every
     * phase). Amount is the net estimate (token value − previewed fee),
     * matching iOS `claimedAmount ?? netReceiveAmount`. */
    data class Failed(
        val message: WalletMessage,
        val amount: Long,
        val fee: Long,
        val unit: String,
        val mint: String,
    ) : TokenClaimStatus
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
        onFailure = {
            TokenClaimStatus.Failed(
                message = it.walletMessage,
                amount = (review.info.amount.coerceAtLeast(0L) - review.fee).coerceAtLeast(0L),
                fee = review.fee,
                unit = review.info.unit,
                mint = review.info.mint,
            )
        },
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
        memo = review.info.memo,
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
    p2pkLock: P2PKLockState?,
    modifier: Modifier = Modifier,
) {
    val isSatToken = info.unit.equals("sat", ignoreCase = true)
    val tokenCurrency = CurrencyRegistry.currencyForMintUnit(info.unit)
    val lockPresentation = p2pkLock?.presentation()
    Column(modifier = modifier.fillMaxWidth()) {
        InspectorRow(
            label = "Fee",
            value = when {
                fee == null -> ""
                // Prospective charge (docs/product/copy-guidance.md): a
                // charge-absence phrase, never a bare "0 sat".
                fee == 0L -> "No fee"
                isSatToken -> "$fee sat"
                else -> CurrencyAmount(fee, tokenCurrency).formatted()
            },
            loading = fee == null,
        )
        InspectorRow(
            label = "Mint",
            value = info.mint,
        )
        lockPresentation?.let { lock ->
            lock.targetLabels.forEachIndexed { index, target ->
                InspectorRow(
                    label = if (index == 0) "Locked to" else "Also locked to",
                    value = target,
                    valueMonospaced = true,
                )
            }
            val statusColor = if (lock.claimable) {
                CashuTheme.colors.received
            } else {
                CashuTheme.colors.pending
            }
            InspectorRow(
                label = "Status",
                value = lock.statusText,
                trailingIcon = if (lock.claimable) {
                    Icons.Outlined.CheckCircle
                } else {
                    Icons.Outlined.WarningAmber
                },
                trailingIconTint = statusColor,
                valueColor = statusColor,
            )
        }
        if (info.memo != null) {
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
    // Amount/Fee/Mint rows render for success and failure alike (iOS passes
    // successRows for every phase). On failure they're the review preview:
    // net estimate and prospective fee; a zero fee omits the row.
    val rowData: ClaimRows? = when (status) {
        TokenClaimStatus.Claiming -> null
        is TokenClaimStatus.Claimed -> ClaimRows(status.amount, status.fee, status.unit, status.mint)
        is TokenClaimStatus.Failed -> ClaimRows(status.amount, status.fee, status.unit, status.mint)
    }
    PaymentStatusScreen(
        phase = phase,
        title = when (status) {
            TokenClaimStatus.Claiming -> "Claiming…"
            is TokenClaimStatus.Claimed -> "Payment Received!"
            is TokenClaimStatus.Failed -> "Couldn't Receive"
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
        rows = rowData?.let { data ->
            {
                val isSat = data.unit.equals("sat", ignoreCase = true)
                val currency = CurrencyRegistry.currencyForMintUnit(data.unit)
                fun formatted(value: Long): String = if (isSat) {
                    formatter.formatWalletSats(value, useBitcoinSymbol)
                } else {
                    CurrencyAmount(value, currency).formatted()
                }
                InspectorRow(
                    label = "Amount",
                    value = formatted(data.amount),
                )
                if (data.fee > 0L) {
                    InspectorRow(
                        label = "Fee",
                        value = formatted(data.fee),
                    )
                }
                if (data.mint.isNotEmpty()) {
                    InspectorRow(
                        label = "Mint",
                        value = data.mint,
                    )
                }
            }
        },
    )
}

private data class ClaimRows(val amount: Long, val fee: Long, val unit: String, val mint: String)
