package com.cashu.me.Models

import kotlinx.serialization.Serializable
import com.cashu.me.Core.PaymentRequestDecoder

@Serializable
data class WalletTransaction(
    val id: String,
    val amount: Long,
    val type: TransactionType,
    val kind: TransactionKind,
    val dateEpochMillis: Long,
    val memo: String? = null,
    val status: TransactionStatus,
    val statusNote: String? = null,
    val mintUrl: String? = null,
    val preimage: String? = null,
    val token: String? = null,
    val invoice: String? = null,
    val fee: Long = 0,
    /** Mint account unit for [amount] and [fee] (sat, usd, eur, or custom). */
    val unit: String = "sat",
    /**
     * CDK wallet-saga (operation) id backing this transaction, when the row
     * came from CDK. Pending sent tokens use it for claim checks / revoke;
     * null for app-synthesized rows (quotes, held receives).
     */
    val sagaId: String? = null,
    val quoteId: String? = null,
    val cashuRequestId: String? = null,
    /** Incoming ecash held for user approval ("Receive later" / NUT-18). Opens
     * the claim flow instead of a plain receipt. iOS parity. */
    val isPendingReceiveToken: Boolean = false,
    /** BOLT11 mint quote still awaiting payment — titles the row "Lightning invoice". */
    val isUnpaidInvoice: Boolean = false,
) {
    val displayDescription: String?
        get() = memo?.takeIf(String::isNotBlank) ?: PaymentRequestDecoder.description(invoice)

    val displayStatusText: String
        get() = if (status == TransactionStatus.Pending) statusNote ?: status.displayText else status.displayText

    /** Quiet Pending rule: expired never credited the balance, so it keeps the bare muted amount. */
    val isUnsettled: Boolean
        get() = status == TransactionStatus.Pending || status == TransactionStatus.Expired

    /**
     * Mint-quote id to re-check when opening this row's detail, if any.
     * Only unsettled incoming Lightning / on-chain mint quotes (not ecash,
     * not melts). Expired unpaid invoices are included so a late-paid NUT-04
     * quote can still mint after the invoice timer.
     */
    val mintQuoteIdForStatusRefresh: String?
        get() {
            if (type != TransactionType.Incoming) return null
            if (kind != TransactionKind.Lightning && kind != TransactionKind.Onchain) return null
            if (invoice == null) return null
            if (status != TransactionStatus.Pending && status != TransactionStatus.Expired) return null
            return quoteId ?: id
        }
}

@Serializable
enum class TransactionType {
    Incoming,
    Outgoing,
}

@Serializable
enum class TransactionKind {
    Ecash,
    Lightning,
    Onchain;

    val displayName: String
        get() = when (this) {
            Ecash -> "Ecash"
            Lightning -> "Lightning"
            Onchain -> "On-chain"
        }
}

@Serializable
enum class TransactionStatus {
    Pending,
    Completed,
    Failed,
    Expired;

    val displayText: String
        get() = when (this) {
            Pending -> "Pending"
            Completed -> "Completed"
            Failed -> "Failed"
            Expired -> "Expired"
        }
}

/**
 * Resolve the live row for a detail screen opened with [openId] (and the
 * open-time [openQuoteId]). Pending quote rows use `id == quoteId`; once
 * minting starts CDK replaces them with a saga-derived transaction id that
 * still carries `quoteId`, so fall back to the quoteId to keep following the
 * row as it flips Pending → Completed in place. Rows are newest-first, so a
 * reusable offer resolves to its latest payment. iOS `liveDetail` parity.
 */
internal fun List<WalletTransaction>.liveDetail(
    openId: String,
    openQuoteId: String? = null,
): WalletTransaction? =
    firstOrNull { it.id == openId }
        ?: firstOrNull { it.quoteId != null && it.quoteId == openQuoteId }

/** CDK may omit a mint transaction's memo and request after settlement. */
internal fun WalletTransaction.restoringDescription(requests: List<CashuRequest>): WalletTransaction {
    val description = displayDescription ?: requests.firstOrNull { request ->
        type == TransactionType.Incoming && unit.equals(request.unit, ignoreCase = true) &&
            (request.receivedPayments.any { it.transactionId == id } || cashuRequestId == request.id ||
                (quoteId != null && quoteId == request.quoteId &&
                    request.mints.any { it.trimEnd('/') == mintUrl?.trimEnd('/') }))
    }?.displayDescription
    return if (description == memo) this else copy(memo = description)
}
