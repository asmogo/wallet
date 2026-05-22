package org.cashu.wallet.Models

import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import org.cashu.wallet.Core.TokenParser

@Serializable
enum class PaymentMethodKind {
    @SerialName("bolt11")
    Bolt11,

    @SerialName("bolt12")
    Bolt12,

    @SerialName("onchain")
    Onchain;

    val rawValue: String
        get() = when (this) {
            Bolt11 -> "bolt11"
            Bolt12 -> "bolt12"
            Onchain -> "onchain"
        }

    val displayName: String
        get() = when (this) {
            Bolt11 -> "BOLT11"
            Bolt12 -> "BOLT12"
            Onchain -> "On-chain"
        }

    val symbol: String
        get() = when (this) {
            Bolt11 -> "\u26A1"
            Bolt12 -> "\uD83D\uDD17"
            Onchain -> "\u20BF"
        }

    val requestDisplayName: String
        get() = when (this) {
            Bolt11 -> "Invoice"
            Bolt12 -> "Offer"
            Onchain -> "Address"
        }

    val sortOrder: Int
        get() = when (this) {
            Bolt11 -> 0
            Bolt12 -> 1
            Onchain -> 2
        }

    val requiresMintAmount: Boolean
        get() = this != Bolt12

    val supportsOptionalMintAmount: Boolean
        get() = this == Bolt12

    companion object {
        fun fromRaw(value: String?): PaymentMethodKind? = when (value?.lowercase()) {
            "bolt11" -> Bolt11
            "bolt12" -> Bolt12
            "onchain" -> Onchain
            else -> null
        }
    }
}

@Serializable
data class OnchainPaymentObservation(
    val txid: String,
    val amount: Long,
    val confirmed: Boolean,
    val confirmations: Int? = null,
) {
    val statusText: String
        get() = when {
            confirmations != null && confirmations > 0 -> {
                val suffix = if (confirmations == 1) "" else "s"
                "Payment confirmed on-chain ($confirmations confirmation$suffix)"
            }
            confirmed -> "Payment detected on-chain"
            else -> "Payment seen in mempool"
        }
}

@Serializable
data class MintInfo(
    val url: String,
    val name: String = "Unknown Mint",
    val description: String? = null,
    val isActive: Boolean = true,
    val balance: Long = 0,
    val iconUrl: String? = null,
    val units: List<String> = listOf("sat"),
    val supportedMintMethods: List<PaymentMethodKind> = listOf(PaymentMethodKind.Bolt11),
    val supportedMeltMethods: List<PaymentMethodKind> = listOf(PaymentMethodKind.Bolt11),
    val onchainMintConfirmations: Int? = null,
    val lastUpdatedEpochMillis: Long = System.currentTimeMillis(),
) {
    val id: String get() = url
}

@Serializable
enum class MintQuoteState {
    Unpaid,
    Pending,
    Paid,
    Issued,
    Failed,
    Unknown,
}

@Serializable
data class MintQuoteInfo(
    val id: String,
    val request: String,
    val amount: Long?,
    val paymentMethod: PaymentMethodKind,
    val state: MintQuoteState,
    val expiryEpochSeconds: Long?,
    val mintUrl: String? = null,
    val amountPaid: Long = 0,
    val amountIssued: Long = 0,
) {
    val isExpired: Boolean
        get() = expiryEpochSeconds != null &&
            expiryEpochSeconds > 0 &&
            System.currentTimeMillis() / 1000 > expiryEpochSeconds
}

@Serializable
enum class MeltQuoteState {
    Unpaid,
    Pending,
    Paid,
    Failed,
    Unknown,
}

@Serializable
data class MeltQuoteInfo(
    val id: String,
    val mintUrl: String,
    val amount: Long,
    val feeReserve: Long,
    val paymentMethod: PaymentMethodKind,
    val state: MeltQuoteState,
    val expiryEpochSeconds: Long?,
    val request: String? = null,
    val paymentProof: String? = null,
) {
    val totalAmount: Long get() = amount + feeReserve
    val isExpired: Boolean
        get() = expiryEpochSeconds != null &&
            expiryEpochSeconds > 0 &&
            System.currentTimeMillis() / 1000 > expiryEpochSeconds
}

@Serializable
data class MeltPaymentResult(
    val preimage: String?,
    val amount: Long,
    val feePaid: Long,
    val mintUrl: String,
    val paymentMethod: PaymentMethodKind? = null,
    val request: String? = null,
)

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

@Serializable
data class SendTokenResult(
    val token: String,
    val fee: Long,
)

@Serializable
data class PendingToken(
    val tokenId: String,
    val token: String,
    val amount: Long,
    val fee: Long,
    val dateEpochMillis: Long,
    val mintUrl: String,
    val memo: String? = null,
) {
    val id: String get() = tokenId
}

@Serializable
data class PendingReceiveToken(
    val tokenId: String,
    val token: String,
    val amount: Long,
    val dateEpochMillis: Long,
    val mintUrl: String,
) {
    val id: String get() = tokenId
}

@Serializable
data class CashuRequestPayment(
    val transactionId: String,
    val amount: Long,
    val receivedAtEpochMillis: Long,
)

@Serializable
data class CashuRequest(
    val id: String = newId(),
    val encoded: String,
    val amount: Long? = null,
    val unit: String = "sat",
    val mints: List<String> = emptyList(),
    val memo: String? = null,
    val createdAtEpochMillis: Long = System.currentTimeMillis(),
    val receivedPayments: List<CashuRequestPayment> = emptyList(),
    val receivedPaymentIds: List<String> = emptyList(),
) {
    val totalReceived: Long get() = receivedPayments.sumOf { it.amount }

    fun withLegacyPaymentFallback(): CashuRequest {
        if (receivedPayments.isNotEmpty() || receivedPaymentIds.isEmpty()) return this
        return copy(
            receivedPayments = receivedPaymentIds.map { id ->
                CashuRequestPayment(
                    transactionId = id,
                    amount = 0,
                    receivedAtEpochMillis = createdAtEpochMillis,
                )
            },
            receivedPaymentIds = emptyList(),
        )
    }

    companion object {
        fun newId(): String = UUID.randomUUID().toString().substringBefore("-")
    }
}

@Serializable
data class ClaimedToken(
    val tokenId: String,
    val token: String,
    val amount: Long,
    val fee: Long,
    val dateEpochMillis: Long,
    val mintUrl: String,
    val memo: String? = null,
    val claimedDateEpochMillis: Long,
) {
    val id: String get() = tokenId
}

@Serializable
data class RestoreMintResult(
    val mintUrl: String,
    val mintName: String,
    val spent: Long,
    val unspent: Long,
    val pending: Long,
) {
    val id: String get() = mintUrl
    val totalRecovered: Long get() = unspent + pending
}

@Serializable
data class TokenInfo(
    val amount: Long,
    val mint: String,
    val unit: String,
    val memo: String?,
    val proofCount: Int,
) {
    companion object {
        fun parse(tokenString: String): TokenInfo? = TokenParser.tokenInfo(tokenString)
    }
}

@Serializable
data class NwcConnection(
    val id: String,
    val name: String,
    val walletPublicKey: String,
    val connectionPublicKey: String,
    val allowanceSats: Long?,
    val createdAtEpochMillis: Long = System.currentTimeMillis(),
)

@Serializable
data class P2PKKeyInfo(
    val id: String,
    val publicKey: String,
    val label: String,
    val createdAtEpochMillis: Long = System.currentTimeMillis(),
    val used: Boolean = false,
    val usedCount: Int = 0,
)
