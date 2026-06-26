package org.cashu.wallet.Models

import kotlinx.serialization.Serializable

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
