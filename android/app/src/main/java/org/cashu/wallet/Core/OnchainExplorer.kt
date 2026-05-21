package org.cashu.wallet.Core

import java.net.URI
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

data class OnchainPaymentObservation(
    val txid: String,
    val amount: Long,
    val confirmed: Boolean,
    val confirmations: Int?,
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

object OnchainExplorer {
    private val json = Json { ignoreUnknownKeys = true }

    fun addressWebUrl(address: String, mintUrl: String?): String? {
        val descriptor = descriptor(address = address, mintUrl = mintUrl) ?: return null
        val normalized = PaymentRequestParser.normalizeBitcoinRequest(address)
        return "${descriptor.webBaseUrl}/address/$normalized"
    }

    fun transactionWebUrl(txid: String, address: String? = null, mintUrl: String?): String? {
        val descriptor = descriptor(address = address, mintUrl = mintUrl) ?: return null
        return "${descriptor.webBaseUrl}/tx/$txid"
    }

    suspend fun observePayment(
        address: String,
        mintUrl: String?,
        expectedAmount: Long,
        createdAfterEpochMillis: Long,
    ): OnchainPaymentObservation? {
        val descriptor = descriptor(address = address, mintUrl = mintUrl) ?: return null
        val normalizedAddress = PaymentRequestParser.normalizeBitcoinRequest(address)
        val transactionsUrl = "${descriptor.apiBaseUrl}/address/$normalizedAddress/txs"
        val body = httpGet(transactionsUrl) ?: return null
        return runCatching {
            val transactions = json.decodeFromString<List<ExplorerTransaction>>(body)
            val tipHeight = currentTipHeight(descriptor)
            val earliestBlockTime = createdAfterEpochMillis / 1000
            val normalizedLower = normalizedAddress.lowercase()

            transactions.firstNotNullOfOrNull { transaction ->
                val matchingAmount = transaction.vout
                    .filter { it.scriptpubkeyAddress?.lowercase() == normalizedLower }
                    .maxOfOrNull { it.value } ?: 0
                if (matchingAmount < expectedAmount) return@firstNotNullOfOrNull null

                val status = freshStatusIfNeeded(transaction, descriptor)
                if (status.blockTime != null && status.blockTime < earliestBlockTime) {
                    return@firstNotNullOfOrNull null
                }

                OnchainPaymentObservation(
                    txid = transaction.txid,
                    amount = matchingAmount,
                    confirmed = status.confirmed,
                    confirmations = confirmations(status.confirmed, status.blockHeight, tipHeight),
                )
            }
        }.onFailure { error ->
            AppLogger.wallet.error("Failed to inspect on-chain address activity", error)
        }.getOrNull()
    }

    internal fun addressTransactionsApiUrl(address: String, mintUrl: String?): String? {
        val descriptor = descriptor(address = address, mintUrl = mintUrl) ?: return null
        val normalized = PaymentRequestParser.normalizeBitcoinRequest(address)
        return "${descriptor.apiBaseUrl}/address/$normalized/txs"
    }

    internal fun cacheBustedUrl(url: String, nowEpochMillis: Long): String {
        val separator = if (url.contains("?")) "&" else "?"
        return "$url${separator}_=$nowEpochMillis"
    }

    internal fun confirmations(confirmed: Boolean, blockHeight: Int?, tipHeight: Int?): Int? {
        if (!confirmed) return null
        if (blockHeight == null || tipHeight == null || tipHeight < blockHeight) return 1
        return tipHeight - blockHeight + 1
    }

    private fun descriptor(address: String?, mintUrl: String?): ExplorerDescriptor? {
        val mintHost = mintUrl?.let {
            runCatching { URI.create(it).host?.lowercase() }.getOrNull()
        }
        if (mintHost == "onchain.cashudevkit.org") {
            return ExplorerDescriptor(webBaseUrl = "https://mutinynet.com", apiBaseUrl = "https://mutinynet.com/api")
        }

        val normalizedAddress = address
            ?.let(PaymentRequestParser::normalizeBitcoinRequest)
            ?.lowercase()
            .orEmpty()

        if (
            normalizedAddress.startsWith("bc1") ||
            normalizedAddress.startsWith("1") ||
            normalizedAddress.startsWith("3")
        ) {
            return ExplorerDescriptor(webBaseUrl = "https://mempool.space", apiBaseUrl = "https://mempool.space/api")
        }

        if (
            normalizedAddress.startsWith("tb1") ||
            normalizedAddress.startsWith("m") ||
            normalizedAddress.startsWith("n") ||
            normalizedAddress.startsWith("2")
        ) {
            return ExplorerDescriptor(
                webBaseUrl = "https://mempool.space/signet",
                apiBaseUrl = "https://mempool.space/signet/api",
            )
        }

        if (mintHost == null) return null
        return ExplorerDescriptor(
            webBaseUrl = "https://mempool.space/signet",
            apiBaseUrl = "https://mempool.space/signet/api",
        )
    }

    private suspend fun currentTipHeight(descriptor: ExplorerDescriptor): Int? {
        httpGet("${descriptor.apiBaseUrl}/blocks/tip/height")
            ?.trim()
            ?.toIntOrNull()
            ?.let { return it }

        val body = httpGet("${descriptor.apiBaseUrl}/blocks") ?: return null
        return runCatching {
            json.decodeFromString<List<ExplorerBlock>>(body).maxOfOrNull { it.height }
        }.getOrNull()
    }

    private suspend fun freshStatusIfNeeded(
        transaction: ExplorerTransaction,
        descriptor: ExplorerDescriptor,
    ): ExplorerTransactionStatus {
        if (!transaction.status.confirmed || transaction.status.blockHeight != null) {
            return transaction.status
        }

        val body = httpGet("${descriptor.apiBaseUrl}/tx/${transaction.txid}/status") ?: return transaction.status
        return runCatching {
            json.decodeFromString<ExplorerTransactionStatus>(body)
        }.getOrDefault(transaction.status)
    }

    private suspend fun httpGet(url: String): String? = withContext(Dispatchers.IO) {
        val connection = (URL(cacheBustedUrl(url, System.currentTimeMillis())).openConnection() as HttpURLConnection)
            .apply {
                requestMethod = "GET"
                connectTimeout = 10_000
                readTimeout = 10_000
                setRequestProperty("Cache-Control", "no-cache")
                setRequestProperty("Pragma", "no-cache")
            }
        try {
            if (connection.responseCode !in 200..299) return@withContext null
            connection.inputStream.bufferedReader().use { it.readText() }
        } catch (error: Throwable) {
            AppLogger.wallet.error("Failed to load on-chain explorer URL $url", error)
            null
        } finally {
            connection.disconnect()
        }
    }

    private data class ExplorerDescriptor(
        val webBaseUrl: String,
        val apiBaseUrl: String,
    )

    @Serializable
    private data class ExplorerTransaction(
        val txid: String,
        val status: ExplorerTransactionStatus,
        val vout: List<ExplorerTransactionOutput> = emptyList(),
    )

    @Serializable
    private data class ExplorerTransactionStatus(
        val confirmed: Boolean = false,
        @SerialName("block_height") val blockHeight: Int? = null,
        @SerialName("block_time") val blockTime: Long? = null,
    )

    @Serializable
    private data class ExplorerTransactionOutput(
        @SerialName("scriptpubkey_address") val scriptpubkeyAddress: String? = null,
        val value: Long = 0,
    )

    @Serializable
    private data class ExplorerBlock(val height: Int)
}
