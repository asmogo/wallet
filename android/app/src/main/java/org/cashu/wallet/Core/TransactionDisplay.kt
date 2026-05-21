package org.cashu.wallet.Core

import java.net.URI
import org.cashu.wallet.Models.TransactionKind
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.TransactionType
import org.cashu.wallet.Models.WalletTransaction

data class TransactionDetailField(
    val label: String,
    val value: String,
)

object TransactionDisplay {
    fun title(transaction: WalletTransaction): String = when (transaction.kind) {
        TransactionKind.Lightning -> if (transaction.type == TransactionType.Incoming) {
            "Lightning request"
        } else {
            "Lightning payment"
        }
        TransactionKind.Onchain -> if (transaction.type == TransactionType.Incoming) {
            "On-chain receive"
        } else {
            "On-chain payment"
        }
        TransactionKind.Ecash -> if (transaction.status == TransactionStatus.Pending) {
            "Pending ecash"
        } else {
            "Ecash"
        }
    }

    fun statusText(transaction: WalletTransaction): String = when (transaction.status) {
        TransactionStatus.Completed -> when (transaction.kind) {
            TransactionKind.Ecash -> if (transaction.type == TransactionType.Incoming) "Received" else "Sent"
            TransactionKind.Lightning -> if (transaction.type == TransactionType.Incoming) "Received" else "Paid"
            TransactionKind.Onchain -> if (transaction.type == TransactionType.Incoming) "Received" else "Sent"
        }
        TransactionStatus.Pending -> transaction.displayStatusText
        TransactionStatus.Failed -> "Failed"
    }

    fun qrContent(transaction: WalletTransaction): String? =
        transaction.token ?: transaction.invoice

    fun qrLabel(transaction: WalletTransaction): String = when (transaction.kind) {
        TransactionKind.Ecash -> "Ecash token"
        TransactionKind.Lightning -> "Payment request"
        TransactionKind.Onchain -> if (transaction.preimage == null) "Bitcoin address" else "On-chain request"
    }

    fun detailFields(transaction: WalletTransaction, unitLabel: String = "SAT"): List<TransactionDetailField> =
        buildList {
            add(TransactionDetailField("Type", transaction.kind.displayName))
            add(TransactionDetailField("Direction", transaction.type.name))
            if (transaction.fee > 0) add(TransactionDetailField("Fee", "${transaction.fee} sat"))
            add(TransactionDetailField("Unit", unitLabel.uppercase()))
            add(TransactionDetailField("State", statusText(transaction)))
            transaction.mintUrl?.let { add(TransactionDetailField("Mint", mintHost(it))) }
            transaction.memo?.takeIf { it.isNotBlank() }?.let { add(TransactionDetailField("Memo", it)) }
            transaction.invoice?.let {
                add(
                    TransactionDetailField(
                        label = if (transaction.kind == TransactionKind.Onchain) "Address" else "Request",
                        value = it,
                    ),
                )
            }
            transaction.preimage?.let {
                add(
                    TransactionDetailField(
                        label = if (transaction.kind == TransactionKind.Onchain) "Transaction ID" else "Payment Proof",
                        value = it,
                    ),
                )
            }
            transaction.quoteId?.takeIf { it != transaction.id }?.let {
                add(TransactionDetailField("Quote ID", it))
            }
        }

    private fun mintHost(url: String): String =
        runCatching { URI.create(url).host }
            .getOrNull()
            ?.takeIf { it.isNotBlank() }
            ?: url
}
