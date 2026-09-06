package com.cashu.me.Models

import kotlinx.serialization.Serializable
import java.security.MessageDigest

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

    companion object {
        fun idFor(token: String): String = MessageDigest.getInstance("SHA-256")
            .digest(token.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

        /** Compare the complete bearer token, including entries saved with legacy prefix IDs. */
        fun upsert(current: List<PendingReceiveToken>, token: PendingReceiveToken): List<PendingReceiveToken> =
            current.filterNot { it.token == token.token } + token.copy(tokenId = idFor(token.token))
    }
}
