package com.cashu.me.Core

import com.cashu.me.Core.Wallet.WalletMessage
import com.cashu.me.Core.Wallet.walletMessage
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
 * A History row is a pending sent token when CDK reports the outgoing ecash
 * transaction as still pending (unclaimed). CDK 0.18 owns this lifecycle
 * state; the attached token string lets the detail view re-present it
 * (iOS `isPendingSentToken` parity).
 */
internal fun isPendingSentToken(transaction: WalletTransaction): Boolean =
    transaction.type == TransactionType.Outgoing &&
        transaction.kind == TransactionKind.Ecash &&
        transaction.status == TransactionStatus.Pending &&
        transaction.token != null

internal fun shouldOfferManualClaimCheck(
    automaticChecksEnabled: Boolean,
    transaction: WalletTransaction,
): Boolean = !automaticChecksEnabled && isPendingSentToken(transaction)
