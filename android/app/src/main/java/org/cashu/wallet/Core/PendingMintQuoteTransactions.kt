package org.cashu.wallet.Core

import org.cashu.wallet.Models.MintQuoteInfo
import org.cashu.wallet.Models.MintQuoteState
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashu.wallet.Models.TransactionKind
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.TransactionType
import org.cashu.wallet.Models.WalletTransaction

internal fun pendingMintQuoteTransactions(
    quotes: List<MintQuoteInfo>,
    trackedMintUrls: Set<String>,
    completedQuoteIds: Set<String>,
    timestamps: MutableMap<String, Long>,
    nowEpochMillis: Long,
): List<WalletTransaction> =
    quotes.mapNotNull { quote ->
        val mintUrl = quote.mintUrl?.takeIf { it in trackedMintUrls } ?: return@mapNotNull null
        if (quote.paymentMethod == PaymentMethodKind.Bolt12 &&
            quote.amountPaid > 0 &&
            quote.amountIssued >= quote.amountPaid &&
            quote.id in completedQuoteIds
        ) {
            return@mapNotNull null
        }

        val amount = quote.amount
            ?: quote.amountPaid.takeIf { it > 0 }
            ?: quote.amountIssued.takeIf { it > 0 }
            ?: return@mapNotNull null
        if (amount <= 0) return@mapNotNull null

        val timestamp = timestamps.getOrPut(quote.id) { nowEpochMillis }
        WalletTransaction(
            id = quote.id,
            amount = amount,
            type = TransactionType.Incoming,
            kind = if (quote.paymentMethod == PaymentMethodKind.Onchain) {
                TransactionKind.Onchain
            } else {
                TransactionKind.Lightning
            },
            dateEpochMillis = timestamp,
            status = if (quote.state == MintQuoteState.Issued || quote.amountIssued >= amount) {
                TransactionStatus.Completed
            } else {
                TransactionStatus.Pending
            },
            mintUrl = mintUrl,
            invoice = quote.request,
            quoteId = quote.id,
        )
    }

internal fun pruneMintQuoteTimestamps(
    transactions: List<WalletTransaction>,
    timestamps: Map<String, Long>,
): Map<String, Long> {
    val quoteIds = transactions
        .filter { transaction ->
            transaction.invoice != null &&
                (transaction.kind == TransactionKind.Lightning || transaction.kind == TransactionKind.Onchain)
        }
        .map { it.quoteId ?: it.id }
        .toSet()
    return timestamps.filterKeys { it in quoteIds }
}

internal fun isPendingMintQuoteTransaction(transaction: WalletTransaction): Boolean =
    transaction.type == TransactionType.Incoming &&
        transaction.status == TransactionStatus.Pending &&
        transaction.invoice != null &&
        (transaction.kind == TransactionKind.Lightning || transaction.kind == TransactionKind.Onchain)
