package org.cashu.wallet.Core

internal fun quoteExpiryText(expiryEpochSeconds: Long?, nowEpochSeconds: Long): String? {
    val expiry = mintQuoteDisplayExpiry(expiryEpochSeconds) ?: return null
    val remaining = expiry - nowEpochSeconds
    if (remaining <= 0) return "Expired"

    val hours = remaining / 3_600
    val minutes = (remaining % 3_600) / 60
    val seconds = remaining % 60
    return when {
        hours > 0 -> "${hours}h ${minutes}m"
        minutes > 0 -> "${minutes}m ${seconds}s"
        else -> "${seconds}s"
    }
}
