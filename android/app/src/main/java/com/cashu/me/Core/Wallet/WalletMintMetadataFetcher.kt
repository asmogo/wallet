package com.cashu.me.Core

import java.net.URL

internal class WalletMintMetadataFetcher(
    private val allowCleartextLocalTestMints: Boolean = false,
) {
    fun normalizeMintUrl(url: String): String {
        var normalized = url.trim()
        if (!normalized.startsWith("http://") && !normalized.startsWith("https://")) {
            normalized = "https://$normalized"
        }
        return normalized.trimEnd('/')
    }

    fun validateMintUrl(url: String): String? {
        val parsed = runCatching { URL(url) }.getOrNull() ?: return "Invalid URL format."
        if (parsed.host.isNullOrBlank()) return "Invalid URL format."
        if (parsed.protocol != "https" &&
            !(allowCleartextLocalTestMints && parsed.protocol == "http" && parsed.host.isLocalTestHost())
        ) {
            return "Mint URL must use HTTPS for security."
        }
        return null
    }

    private fun String.isLocalTestHost(): Boolean =
        this == "localhost" ||
            this == "127.0.0.1" ||
            this == "10.0.2.2" ||
            this == "::1" ||
            this == "[::1]"
}
