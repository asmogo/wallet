package org.cashu.wallet.Models

import kotlinx.serialization.Serializable

@Serializable
data class MintInfo(
    val url: String,
    val name: String = "Unknown Mint",
    val description: String? = null,
    val isActive: Boolean = true,
    val balance: Long = 0,
    val iconUrl: String? = null,
    val units: List<String> = listOf("sat"),
    val supportedMintMethods: List<PaymentMethodKind> = listOf(PaymentMethodKind.Bolt11),
    val supportedMeltMethods: List<PaymentMethodKind> = listOf(PaymentMethodKind.Bolt11),
    val onchainMintConfirmations: Int? = null,
    val lastUpdatedEpochMillis: Long = System.currentTimeMillis(),
) {
    val id: String get() = url
}
