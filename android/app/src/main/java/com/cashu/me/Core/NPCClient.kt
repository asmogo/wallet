package com.cashu.me.Core

import org.cashudevkit.NpubCashClient

/** The service's transport boundary, allowing lifecycle tests without network or native FFI. */
internal interface NPCClient : AutoCloseable {
    suspend fun getQuotes(): List<NPCQuote>
    suspend fun setMintUrl(mintUrl: String): String
}

internal class CdkNPCClient(baseUrl: String, secretKey: String) : NPCClient {
    private val client = NpubCashClient(baseUrl = baseUrl, nostrSecretKey = secretKey)
    override suspend fun getQuotes(): List<NPCQuote> =
        client.getQuotes(since = null).map(NPCService::fromCdkQuote)

    override suspend fun setMintUrl(mintUrl: String): String {
        val response = client.setMintUrl(mintUrl = mintUrl)
        if (response.error) error("Failed to change mint.")
        return response.mintUrl ?: mintUrl
    }

    override fun close() = client.close()
}
