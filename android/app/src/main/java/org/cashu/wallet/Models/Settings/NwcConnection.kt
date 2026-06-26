package org.cashu.wallet.Models

import kotlinx.serialization.Serializable

@Serializable
data class NwcConnection(
    val id: String,
    val name: String,
    val walletPublicKey: String,
    val connectionPublicKey: String,
    val allowanceSats: Long?,
    val createdAtEpochMillis: Long = System.currentTimeMillis(),
)
