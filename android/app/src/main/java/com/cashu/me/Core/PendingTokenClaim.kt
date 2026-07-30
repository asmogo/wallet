package com.cashu.me.Core

import com.cashu.me.Core.Wallet.WalletMessage
import com.cashu.me.Core.Wallet.walletMessage
import com.cashu.me.Models.PendingToken
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import kotlinx.coroutines.CancellationException

/**
 * Result of a user-initiated spent-status probe.
 *
 * "Not claimed" is a successful response from the mint, distinct from a
 * transport or wallet failure. Keeping those outcomes separate lets the UI
 * acknowledge a completed check while still offering a safe retry on errors.
 */
internal sealed interface PendingTokenClaimCheckResult {
    data object Claimed : PendingTokenClaimCheckResult
    data object NotClaimed : PendingTokenClaimCheckResult
    data class Failed(val message: WalletMessage) : PendingTokenClaimCheckResult
}

internal suspend fun runPendingTokenClaimCheck(
    check: suspend () -> Boolean,
): PendingTokenClaimCheckResult =
    try {
        if (check()) {
            PendingTokenClaimCheckResult.Claimed
        } else {
            PendingTokenClaimCheckResult.NotClaimed
        }
    } catch (cancellation: CancellationException) {
        throw cancellation
    } catch (error: Throwable) {
        PendingTokenClaimCheckResult.Failed(error.walletMessage)
    }

/**
 * Resolve the local pending-token record behind a History row.
 *
 * CDK transaction IDs can replace the local token ID during history merging,
 * so the encoded token is the stable first choice and the ID is a legacy
 * fallback.
 */
internal fun pendingSentTokenFor(
    transaction: WalletTransaction,
    pendingTokens: List<PendingToken>,
): PendingToken? {
    if (
        transaction.type != TransactionType.Outgoing ||
        transaction.kind != TransactionKind.Ecash ||
        transaction.status != TransactionStatus.Pending ||
        !transaction.isPendingToken
    ) {
        return null
    }
    return pendingTokens.firstOrNull { it.token == transaction.token }
        ?: pendingTokens.firstOrNull { it.tokenId == transaction.id }
}

internal fun shouldOfferManualClaimCheck(
    automaticChecksEnabled: Boolean,
    pendingToken: PendingToken?,
): Boolean = !automaticChecksEnabled && pendingToken != null
