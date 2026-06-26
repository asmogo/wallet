package org.cashu.wallet.Models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class PaymentMethodKind {
    @SerialName("bolt11")
    Bolt11,

    @SerialName("bolt12")
    Bolt12,

    @SerialName("onchain")
    Onchain;

    val rawValue: String
        get() = when (this) {
            Bolt11 -> "bolt11"
            Bolt12 -> "bolt12"
            Onchain -> "onchain"
        }

    val displayName: String
        get() = when (this) {
            Bolt11 -> "BOLT11"
            Bolt12 -> "BOLT12"
            Onchain -> "On-chain"
        }

    val symbol: String
        get() = when (this) {
            Bolt11 -> "\u26A1"
            Bolt12 -> "\uD83D\uDD17"
            Onchain -> "\u20BF"
        }

    val requestDisplayName: String
        get() = when (this) {
            Bolt11 -> "Invoice"
            Bolt12 -> "Offer"
            Onchain -> "Address"
        }

    val sortOrder: Int
        get() = when (this) {
            Bolt11 -> 0
            Bolt12 -> 1
            Onchain -> 2
        }

    val requiresMintAmount: Boolean
        get() = this != Bolt12

    val supportsOptionalMintAmount: Boolean
        get() = this == Bolt12

    companion object {
        fun fromRaw(value: String?): PaymentMethodKind? = when (value?.lowercase()) {
            "bolt11" -> Bolt11
            "bolt12" -> Bolt12
            "onchain" -> Onchain
            else -> null
        }
    }
}
