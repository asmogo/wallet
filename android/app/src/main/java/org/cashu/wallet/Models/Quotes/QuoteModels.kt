package org.cashu.wallet.Models

import kotlinx.serialization.Serializable

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
