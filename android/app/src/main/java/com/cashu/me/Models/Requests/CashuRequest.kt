package com.cashu.me.Models

import java.util.UUID
import kotlinx.serialization.Serializable
import com.cashu.me.Core.PaymentRequestDecoder

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
    val lastPresentedAtEpochMillis: Long? = null,
    val quoteId: String? = null,
    val quoteKind: String? = null,
    val receivedPayments: List<CashuRequestPayment> = emptyList(),
    val receivedPaymentIds: List<String> = emptyList(),
) {
    val displayDescription: String?
        get() = memo?.takeIf(String::isNotBlank) ?: PaymentRequestDecoder.description(encoded)

    val totalReceived: Long get() = receivedPayments.sumOf { it.amount }

    val isEcashRequest: Boolean get() = quoteKind == null

    val displayTitle: String
        get() = when (quoteKind?.lowercase()) {
            "bolt12" -> "Reusable Invoice"
            "bolt11" -> if (receivedPayments.isEmpty()) "Lightning invoice" else "Lightning received"
            "onchain" -> if (receivedPayments.isEmpty()) "Bitcoin Address" else "Bitcoin received"
            else -> "Cashu Request"
        }

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
