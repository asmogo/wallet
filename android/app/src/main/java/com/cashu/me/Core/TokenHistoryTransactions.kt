package com.cashu.me.Core

import com.cashu.me.Models.PendingReceiveToken
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction

/**
 * Unclaimed incoming ecash ("Receive Later" tokens and NUT-18 payments held
 * for approval) has no CDK counterpart until it's claimed, so each entry is
 * its own pending incoming row (iOS TransactionService parity).
 */
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
            statusNote = "Not claimed yet",
            mintUrl = token.mintUrl,
            token = token.token,
            unit = token.unit,
            cashuRequestId = token.cashuRequestId,
            isPendingReceiveToken = true,
        )
    }
