package com.cashu.me.Models

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
    // BOLT12 amountless offers may later display the amount received. Preserve
    // their original shape so they can still be reused after a payment.
    val isAmountless: Boolean = amount == null,
    val paymentMethod: PaymentMethodKind,
    val state: MintQuoteState,
    val expiryEpochSeconds: Long?,
    val mintUrl: String? = null,
    val amountPaid: Long = 0,
    val amountIssued: Long = 0,
    /** Last update timestamp (creation time for an untouched quote). 0 for
     * rows stored before CDK 0.18. */
    val updatedAtEpochSeconds: Long = 0,
    // Unit the quote mints into; poll/redeem must resolve the same-unit wallet.
    val unit: String = "sat",
) {
    val isExpired: Boolean
        get() = expiryEpochSeconds != null &&
            expiryEpochSeconds > 0 &&
            System.currentTimeMillis() / 1000 > expiryEpochSeconds

    /** NUT-25's authoritative amount still available for issuance. */
    val mintableAmount: Long
        get() = (amountPaid - amountIssued).coerceAtLeast(0)

    /** A payment is complete only after ecash issuance catches up. */
    val hasSettledPayment: Boolean
        get() = amountPaid > 0 && amountIssued >= amountPaid
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
enum class MeltSettlement {
    /** The mint paid out synchronously; preimage/fee are final. */
    Settled,

    /**
     * The mint accepted the melt for asynchronous (NUT-05) settlement —
     * typical for on-chain. Amount/fee are the quote's numbers (fee = reserve
     * upper bound) until the payment settles; the pending-melt watcher or
     * `syncPendingMeltQuotes` completes the bookkeeping (iOS parity).
     */
    Pending,
}

@Serializable
data class MeltPaymentResult(
    val preimage: String?,
    val amount: Long,
    val feePaid: Long,
    val mintUrl: String,
    val paymentMethod: PaymentMethodKind? = null,
    val request: String? = null,
    val settlement: MeltSettlement = MeltSettlement.Settled,
)
