package org.cashu.wallet.Core

import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Models.PaymentMethodKind

internal class WalletMintMetadataFetcher {
    suspend fun fetchRawMintInfo(url: String): MintInfo = withContext(Dispatchers.IO) {
        val connection = (URL("$url/v1/info").openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 10_000
            readTimeout = 10_000
        }
        try {
            if (connection.responseCode !in 200..299) {
                throw IllegalStateException("Mint info HTTP ${connection.responseCode}")
            }
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            val root = Json.parseToJsonElement(body).jsonObject
            val name = root["name"]?.jsonPrimitive?.content ?: URL(url).host ?: "Unknown Mint"
            val description = root["description"]?.jsonPrimitive?.content
            val iconUrl = root["icon_url"]?.jsonPrimitive?.content
            val nuts = root["nuts"]?.jsonObject
            val nut04 = nuts?.get("4")?.jsonObject
            val methods = nut04?.get("methods")?.jsonArray.orEmpty()
            val supportsOnchain = methods.any { element ->
                element.jsonObject["method"]?.jsonPrimitive?.content?.lowercase() == "onchain"
            }
            MintInfo(
                url = url,
                name = name,
                description = description,
                iconUrl = iconUrl,
                supportedMintMethods = listOfNotNull(
                    PaymentMethodKind.Bolt11,
                    PaymentMethodKind.Onchain.takeIf { supportsOnchain },
                ),
            )
        } finally {
            connection.disconnect()
        }
    }

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
        if (parsed.protocol != "https") return "Mint URL must use HTTPS for security."
        return null
    }
}
