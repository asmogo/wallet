package com.cashu.me.Models

import kotlinx.serialization.Serializable

@Serializable
data class SendTokenResult(
    val token: String,
    val fee: Long,
    /** CDK transaction id (saga-derived) recorded for this send, when known.
     * The token string is stored under this id so History can re-display it
     * and claim checks can resolve the operation. */
    val transactionId: String? = null,
)

@Serializable
data class PendingReceiveToken(
    val tokenId: String,
    val token: String,
    val amount: Long,
    val dateEpochMillis: Long,
    val mintUrl: String,
    val unit: String = "sat",
    val cashuRequestId: String? = null,
    val processedId: String? = null,
    val memo: String? = null,
) {
    val id: String get() = tokenId
    val isCashuRequestPayment: Boolean get() = cashuRequestId != null || processedId != null
}
