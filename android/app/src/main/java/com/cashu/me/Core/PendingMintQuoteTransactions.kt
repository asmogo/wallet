package com.cashu.me.Core

import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.Models.MintQuoteState
import com.cashu.me.Models.PaymentMethodKind
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction

internal fun pendingMintQuoteTransactions(
    quotes: List<MintQuoteInfo>,
    trackedMintUrls: Set<String>,
    quoteIdsWithTransactions: Set<String>,
    timestamps: MutableMap<String, Long>,
    nowEpochMillis: Long,
): List<WalletTransaction> =
    quotes.mapNotNull { quote ->
        val mintUrl = quote.mintUrl?.takeIf { it in trackedMintUrls } ?: return@mapNotNull null
        // Once CDK has a transaction for this quote — pending while a mint is
        // in flight, completed afterwards — the CDK row is authoritative and
        // the quote-backed row would only duplicate it. (BOLT12 offers always
        // stay in the unissued list: `amount_issued = 0 OR method = 'bolt12'`.)
        if (quote.id in quoteIdsWithTransactions) {
            return@mapNotNull null
        }

        val amount = quote.amount
            ?: quote.amountPaid.takeIf { it > 0 }
            ?: quote.amountIssued.takeIf { it > 0 }
            ?: return@mapNotNull null
        if (amount <= 0) return@mapNotNull null

        // CDK 0.18 quotes carry `updatedAt` (creation time for an untouched
        // quote); the local first-seen map only backfills legacy rows that
        // predate the column.
        val timestamp = if (quote.updatedAtEpochSeconds > 0) {
            quote.updatedAtEpochSeconds * 1000
        } else {
            timestamps.getOrPut(quote.id) { nowEpochMillis }
        }
        // A paid-but-unissued quote stays Pending even past expiry: the invoice
        // settled, and NUT-04 lets the wallet mint it after the invoice expires.
        val isPaid = quote.state == MintQuoteState.Paid ||
            quote.state == MintQuoteState.Issued ||
            quote.amountPaid > 0
        val isUnpaidBolt11 = quote.paymentMethod == PaymentMethodKind.Bolt11 && !isPaid
        val expiry = quote.expiryEpochSeconds ?: 0
        val isExpiredUnpaidInvoice = isUnpaidBolt11 && expiry > 0 && nowEpochMillis / 1000 > expiry
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
            status = when {
                quote.state == MintQuoteState.Issued || quote.amountIssued >= amount ->
                    TransactionStatus.Completed
                isExpiredUnpaidInvoice -> TransactionStatus.Expired
                else -> TransactionStatus.Pending
            },
            mintUrl = mintUrl,
            invoice = quote.request,
            quoteId = quote.id,
            unit = quote.unit,
            isUnpaidInvoice = isUnpaidBolt11,
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
