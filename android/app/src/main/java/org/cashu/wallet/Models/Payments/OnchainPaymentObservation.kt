package org.cashu.wallet.Models

import kotlinx.serialization.Serializable

@Serializable
data class OnchainPaymentObservation(
    val txid: String,
    val amount: Long,
    val confirmed: Boolean,
    val confirmations: Int? = null,
) {
    val statusText: String
        get() = when {
            confirmations != null && confirmations > 0 -> {
                val suffix = if (confirmations == 1) "" else "s"
                "Payment confirmed on-chain ($confirmations confirmation$suffix)"
            }
            confirmed -> "Payment detected on-chain"
            else -> "Payment seen in mempool"
        }
}
