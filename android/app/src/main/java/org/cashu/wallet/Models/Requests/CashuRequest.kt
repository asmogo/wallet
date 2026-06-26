package org.cashu.wallet.Models

import java.util.UUID
import kotlinx.serialization.Serializable

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
