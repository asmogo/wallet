package org.cashu.wallet.Models

import kotlinx.serialization.Serializable

@Serializable
data class P2PKKeyInfo(
    val id: String,
    val publicKey: String,
    val label: String,
    val createdAtEpochMillis: Long = System.currentTimeMillis(),
    val used: Boolean = false,
    val usedCount: Int = 0,
)
