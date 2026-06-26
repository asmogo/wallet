package org.cashu.wallet.Models

import kotlinx.serialization.Serializable

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
