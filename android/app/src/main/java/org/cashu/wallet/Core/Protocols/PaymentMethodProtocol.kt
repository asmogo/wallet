package org.cashu.wallet.Core.Protocols

import org.cashu.wallet.Models.PaymentMethodKind

interface PaymentRail {
    val kind: PaymentMethodKind
    val isAvailable: Boolean

    val identifier: String
        get() = kind.rawValue

    val displayName: String
        get() = kind.displayName

    val iconName: String
        get() = kind.iconName

    suspend fun createPaymentRequest(amount: CurrencyAmount, memo: String? = null): PaymentRequest
    suspend fun pay(request: PaymentRequest): PaymentResult
    suspend fun checkPaymentStatus(paymentId: String): PaymentStatus
}

interface PaymentMethodSupport {
    fun supportsMint(method: PaymentMethodKind): Boolean
    fun supportsMelt(method: PaymentMethodKind): Boolean
}

data class PaymentRequest(
    val id: String,
    val paymentRail: String,
    val amount: CurrencyAmount,
    val encodedRequest: String,
    val memo: String? = null,
    val expiresAtEpochMillis: Long? = null,
) {
    fun isExpired(nowEpochMillis: Long = System.currentTimeMillis()): Boolean {
        val expiresAt = expiresAtEpochMillis ?: return false
        return nowEpochMillis > expiresAt
    }
}

data class PaymentResult(
    val success: Boolean,
    val paymentId: String,
    val amount: CurrencyAmount,
    val fee: CurrencyAmount,
    val preimage: String? = null,
    val errorMessage: String? = null,
)

sealed class PaymentStatus {
    data object Pending : PaymentStatus()
    data class Completed(val preimage: String? = null) : PaymentStatus()
    data class Failed(val reason: String) : PaymentStatus()
    data object Expired : PaymentStatus()

    val isPending: Boolean
        get() = this is Pending

    val isCompleted: Boolean
        get() = this is Completed
}

val PaymentMethodKind.iconName: String
    get() = when (this) {
        PaymentMethodKind.Bolt11 -> "bolt"
        PaymentMethodKind.Bolt12 -> "bolt12"
        PaymentMethodKind.Onchain -> "bitcoin"
    }

val PaymentMethodKind.capabilityLabel: String
    get() = when (this) {
        PaymentMethodKind.Bolt11 -> "Lightning invoice"
        PaymentMethodKind.Bolt12 -> "Reusable offer"
        PaymentMethodKind.Onchain -> "Bitcoin address"
    }
