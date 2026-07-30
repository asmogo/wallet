package com.cashu.me.Core

import com.cashu.me.Models.ClaimedToken
import com.cashu.me.Models.PendingReceiveToken
import com.cashu.me.Models.PendingToken
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction

internal fun pendingSentTokenTransactions(tokens: List<PendingToken>): List<WalletTransaction> =
    tokens.map { token ->
        WalletTransaction(
            id = token.tokenId,
            amount = token.amount,
            type = TransactionType.Outgoing,
            kind = TransactionKind.Ecash,
            dateEpochMillis = token.dateEpochMillis,
            memo = token.memo,
            status = TransactionStatus.Pending,
            mintUrl = token.mintUrl,
            token = token.token,
            fee = token.fee,
            unit = token.unit,
            isPendingToken = true,
        )
    }

internal fun pendingReceiveTokenTransactions(tokens: List<PendingReceiveToken>): List<WalletTransaction> =
    tokens.map { token ->
        WalletTransaction(
            id = token.tokenId,
            amount = token.amount,
            type = TransactionType.Incoming,
            kind = TransactionKind.Ecash,
            dateEpochMillis = token.dateEpochMillis,
            memo = token.memo,
            status = TransactionStatus.Pending,
            mintUrl = token.mintUrl,
            token = token.token,
            unit = token.unit,
            isPendingToken = true,
        )
    }

internal fun claimedTokenTransactions(tokens: List<ClaimedToken>): List<WalletTransaction> =
    tokens.map { token ->
        WalletTransaction(
            id = token.tokenId,
            amount = token.amount,
            type = TransactionType.Outgoing,
            kind = TransactionKind.Ecash,
            dateEpochMillis = token.dateEpochMillis,
            memo = token.memo,
            status = TransactionStatus.Completed,
            mintUrl = token.mintUrl,
            token = token.token,
            fee = token.fee,
            unit = token.unit,
        )
    }

/**
 * Fold locally-tracked sent ecash tokens into the CDK transaction rows.
 *
 * CDK already records every send as its own outgoing-ecash transaction. The
 * local [PendingToken]/[ClaimedToken] store exists only to carry the token
 * string (for re-display/reclaim) and the unclaimed/claimed state, so emitting
 * it as a separate row duplicated each "Ecash sent" entry (iOS
 * TransactionService.mergeSentTokens parity).
 *
 * Each token is matched to a CDK row one-to-one by (mint, amount), choosing
 * the closest timestamp so repeated identical sends still line up. A pending
 * match flips its row to Pending and attaches the token string; a claimed
 * match just attaches the token. Any token with no CDK counterpart (older
 * data, or a send CDK didn't record) is appended as its own row so nothing is
 * lost.
 */
internal fun mergeSentTokenTransactions(
    transactions: List<WalletTransaction>,
    pendingTokens: List<PendingToken>,
    claimedTokens: List<ClaimedToken>,
): List<WalletTransaction> {
    val rows = transactions.toMutableList()
    val available = rows.indices
        .filter { rows[it].kind == TransactionKind.Ecash && rows[it].type == TransactionType.Outgoing }
        .toMutableSet()

    fun normalizedMint(url: String?): String =
        url.orEmpty().trim().trimEnd('/').lowercase()

    fun claimMatch(mintUrl: String, unit: String, amount: Long, dateEpochMillis: Long): Int? {
        val target = normalizedMint(mintUrl)
        val best = available
            .filter {
                rows[it].amount == amount &&
                    rows[it].unit.equals(unit, ignoreCase = true) &&
                    normalizedMint(rows[it].mintUrl) == target
            }
            .minByOrNull { kotlin.math.abs(rows[it].dateEpochMillis - dateEpochMillis) }
        if (best != null) available.remove(best)
        return best
    }

    val leftovers = mutableListOf<WalletTransaction>()

    pendingTokens.forEach { token ->
        val index = claimMatch(token.mintUrl, token.unit, token.amount, token.dateEpochMillis)
        if (index != null) {
            val row = rows[index]
            rows[index] = row.copy(
                status = TransactionStatus.Pending,
                isPendingToken = true,
                token = row.token ?: token.token,
                fee = if (row.fee == 0L) token.fee else row.fee,
            )
        } else {
            leftovers += pendingSentTokenTransactions(listOf(token))
        }
    }

    claimedTokens.forEach { token ->
        val index = claimMatch(token.mintUrl, token.unit, token.amount, token.dateEpochMillis)
        if (index != null) {
            val row = rows[index]
            rows[index] = row.copy(
                token = row.token ?: token.token,
                fee = if (row.fee == 0L) token.fee else row.fee,
            )
        } else {
            leftovers += claimedTokenTransactions(listOf(token))
        }
    }

    return rows + leftovers
}
