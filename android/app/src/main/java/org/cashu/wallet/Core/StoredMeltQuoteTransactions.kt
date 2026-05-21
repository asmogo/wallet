package org.cashu.wallet.Core

import org.cashu.wallet.Models.MeltQuoteInfo
import org.cashu.wallet.Models.MeltQuoteState
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashu.wallet.Models.TransactionKind
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.TransactionType
import org.cashu.wallet.Models.WalletTransaction

internal fun storedMeltQuoteTransactions(
    quotes: List<MeltQuoteInfo>,
    trackedMintUrls: Set<String>,
    completedQuoteIds: Set<String>,
    timestamps: MutableMap<String, Long>,
    nowEpochMillis: Long,
    preimages: Map<String, String>,
    fees: Map<String, Long>,
): List<WalletTransaction> =
    quotes.mapNotNull { quote ->
        val mintUrl = quote.mintUrl.takeIf { it.isNotBlank() && it in trackedMintUrls } ?: return@mapNotNull null
        if (quote.id in completedQuoteIds || quote.amount <= 0) return@mapNotNull null

        val status = when (quote.state) {
            MeltQuoteState.Paid -> TransactionStatus.Completed
            MeltQuoteState.Pending -> TransactionStatus.Pending
            MeltQuoteState.Failed -> TransactionStatus.Failed
            MeltQuoteState.Unpaid, MeltQuoteState.Unknown -> return@mapNotNull null
        }

        WalletTransaction(
            id = quote.id,
            amount = quote.amount,
            type = TransactionType.Outgoing,
            kind = if (quote.paymentMethod == PaymentMethodKind.Onchain) {
                TransactionKind.Onchain
            } else {
                TransactionKind.Lightning
            },
            dateEpochMillis = timestamps.getOrPut(quote.id) { nowEpochMillis },
            status = status,
            mintUrl = mintUrl,
            preimage = quote.paymentProof ?: preimages[quote.id],
            invoice = quote.request,
            fee = fees[quote.id] ?: quote.feeReserve,
            quoteId = quote.id,
        )
    }

