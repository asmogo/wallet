package org.cashu.wallet.Core

import org.cashu.wallet.Models.ClaimedToken
import org.cashu.wallet.Models.PendingReceiveToken
import org.cashu.wallet.Models.PendingToken
import org.cashu.wallet.Models.TransactionKind
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.TransactionType
import org.cashu.wallet.Models.WalletTransaction

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
            status = TransactionStatus.Pending,
            mintUrl = token.mintUrl,
            token = token.token,
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
        )
    }

