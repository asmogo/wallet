package org.cashu.wallet.Models

import kotlinx.serialization.Serializable

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
    val isPendingToken: Boolean = false,
    val quoteId: String? = null,
    val cashuRequestId: String? = null,
) {
    val displayStatusText: String
        get() = if (status == TransactionStatus.Pending) statusNote ?: status.displayText else status.displayText
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
    Failed;

    val displayText: String
        get() = when (this) {
            Pending -> "Pending"
            Completed -> "Completed"
            Failed -> "Failed"
        }
}
