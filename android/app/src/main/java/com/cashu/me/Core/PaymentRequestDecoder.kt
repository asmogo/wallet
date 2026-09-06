package com.cashu.me.Core

import com.cashu.me.Models.PaymentMethodKind
import org.cashudevkit.CurrencyUnit as CdkCurrencyUnit
import org.cashudevkit.PaymentType as CdkPaymentType
import org.cashudevkit.decodeInvoice
import org.cashudevkit.decodePaymentRequest
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.Base64

data class CashuPaymentRequestSummary(
    val encoded: String,
    val amount: Long? = null,
    val unit: String? = null,
    val description: String? = null,
    val mints: List<String> = emptyList(),
) {
    val isSatUnit: Boolean get() = unit?.lowercase() == null || unit.lowercase() == "sat"
}

sealed interface PaymentRequestDecodeResult {
    data class LightningAddress(val address: String) : PaymentRequestDecodeResult
    data class Bolt11(val amountSats: Long?, val description: String?) : PaymentRequestDecodeResult
    data class Bolt12(val amountSats: Long?, val description: String?) : PaymentRequestDecodeResult
    data class Onchain(val address: String) : PaymentRequestDecodeResult
    data class CashuPaymentRequest(val summary: CashuPaymentRequestSummary) : PaymentRequestDecodeResult
    data object Unrecognized : PaymentRequestDecodeResult
}

object PaymentRequestParser {
    fun normalizeLightningRequest(request: String): String {
        val trimmed = request.trim()
        return when {
            trimmed.startsWith("lightning://", ignoreCase = true) -> trimmed.drop("lightning://".length)
            trimmed.startsWith("lightning:", ignoreCase = true) -> trimmed.drop("lightning:".length)
            else -> trimmed
        }
    }

    fun normalizeBitcoinRequest(request: String): String {
        val trimmed = request.trim()
        val withoutScheme = when {
            trimmed.startsWith("bitcoin://", ignoreCase = true) -> trimmed.drop("bitcoin://".length)
            trimmed.startsWith("bitcoin:", ignoreCase = true) -> trimmed.drop("bitcoin:".length)
            else -> trimmed
        }
        return withoutScheme.substringBefore("?")
    }

    fun isBitcoinAddress(request: String): Boolean =
        BitcoinAddressValidator.isValidAddress(normalizeBitcoinRequest(request))

    fun isHumanReadableLightningAddress(request: String): Boolean {
        val trimmed = request.trim()
        val atIndex = trimmed.indexOf('@')
        if (atIndex <= 0 || atIndex == trimmed.lastIndex) return false
        val domain = trimmed.substring(atIndex + 1)
        return "." in domain && !domain.startsWith(".") && !domain.endsWith(".")
    }

    fun paymentMethod(request: String): PaymentMethodKind? {
        if (isHumanReadableLightningAddress(request)) return null
        val normalized = PaymentRequestDecoder.encodedLightningRequest(request) ?: normalizeLightningRequest(request)
        runCatching { decodeInvoice(normalized) }.getOrNull()?.let { decoded ->
            return when (decoded.paymentType) {
                CdkPaymentType.BOLT11 -> PaymentMethodKind.Bolt11
                CdkPaymentType.BOLT12 -> PaymentMethodKind.Bolt12
            }
        }
        if (LightningRequestParser.parseBolt12Offer(normalized) != null) {
            return PaymentMethodKind.Bolt12
        }
        if (isBitcoinAddress(request)) return PaymentMethodKind.Onchain
        return null
    }
}

object PaymentRequestDecoder {
    /** Recover immutable descriptions from persisted invoices, including older history. */
    fun description(raw: String?): String? {
        if (raw.isNullOrBlank()) return null
        LightningRequestParser.parseBolt12Offer(raw)?.let { return it.description?.takeIf(String::isNotBlank) }
        return when (val decoded = decode(raw, includeCashuPaymentRequests = true)) {
            is PaymentRequestDecodeResult.Bolt11 -> decoded.description
            is PaymentRequestDecodeResult.Bolt12 -> decoded.description
            is PaymentRequestDecodeResult.CashuPaymentRequest -> decoded.summary.description
            else -> null
        }?.takeIf(String::isNotBlank)
    }

    private const val CREQ_A_PREFIX = "creqA"

    fun decode(
        raw: String,
        includeCashuPaymentRequests: Boolean = false,
        preferCashuPaymentRequests: Boolean = false,
    ): PaymentRequestDecodeResult {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return PaymentRequestDecodeResult.Unrecognized

        if (includeCashuPaymentRequests && preferCashuPaymentRequests) {
            cashuPaymentRequestSummary(trimmed)?.let { return PaymentRequestDecodeResult.CashuPaymentRequest(it) }
        }

        decodedLightningRequest(trimmed)?.let { return it }

        if (PaymentRequestParser.isHumanReadableLightningAddress(trimmed)) {
            return PaymentRequestDecodeResult.LightningAddress(trimmed)
        }

        if (PaymentRequestParser.isBitcoinAddress(trimmed)) {
            return PaymentRequestDecodeResult.Onchain(PaymentRequestParser.normalizeBitcoinRequest(trimmed))
        }

        if (includeCashuPaymentRequests) {
            cashuPaymentRequestSummary(trimmed)?.let { return PaymentRequestDecodeResult.CashuPaymentRequest(it) }
        }

        return PaymentRequestDecodeResult.Unrecognized
    }

    fun encodedLightningRequest(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        bitcoinPaymentURI(trimmed)?.lightning?.let { embedded ->
            val normalized = PaymentRequestParser.normalizeLightningRequest(embedded)
            return LightningRequestParser.parseBolt12Offer(normalized)?.request ?: normalized
        }
        val normalized = PaymentRequestParser.normalizeLightningRequest(trimmed)
        LightningRequestParser.parseBolt12Offer(normalized)?.let { return it.request }
        return if (runCatching { decodeInvoice(normalized) }.isSuccess) normalized else null
    }

    fun encodedCashuPaymentRequest(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        bitcoinPaymentURI(trimmed)?.creq?.let { return it }
        val withoutCashuScheme = stripSchemePrefixes(listOf("cashu://", "cashu:"), trimmed)
        val lower = withoutCashuScheme.lowercase()
        return if (lower.startsWith("creqa") || lower.startsWith("creqb1")) withoutCashuScheme else null
    }

    fun cdkCompatibleCashuPaymentRequest(raw: String): String? {
        val encoded = encodedCashuPaymentRequest(raw) ?: return null
        return if (encoded.startsWith(CREQ_A_PREFIX, ignoreCase = true)) {
            val payload = encoded.drop(CREQ_A_PREFIX.length).trimEnd('=')
            val padding = (4 - payload.length % 4) % 4
            CREQ_A_PREFIX + payload + "=".repeat(padding)
        } else {
            encoded
        }
    }

    fun cashuPaymentRequestSummary(raw: String): CashuPaymentRequestSummary? {
        val encoded = encodedCashuPaymentRequest(raw) ?: return null
        val cdkEncoded = cdkCompatibleCashuPaymentRequest(encoded) ?: encoded
        runCatching { decodePaymentRequest(cdkEncoded) }.getOrNull()?.let { request ->
            return CashuPaymentRequestSummary(
                encoded = cdkEncoded,
                amount = request.amount()?.value?.toLong(),
                unit = request.unit()?.toDomainUnit(),
                description = request.description(),
                mints = request.mints(),
            )
        }
        return legacyCreqASummary(cdkEncoded)
    }

    private fun decodedLightningRequest(raw: String): PaymentRequestDecodeResult? {
        val normalized = encodedLightningRequest(raw) ?: return null
        runCatching { decodeInvoice(normalized) }.getOrNull()?.let { decoded ->
            val amountSats = decoded.amountMsat?.let { (it.toLong() + 999) / 1000 }
            return when (decoded.paymentType) {
                CdkPaymentType.BOLT11 -> PaymentRequestDecodeResult.Bolt11(amountSats, decoded.description)
                CdkPaymentType.BOLT12 -> PaymentRequestDecodeResult.Bolt12(amountSats, decoded.description)
            }
        }
        val offer = LightningRequestParser.parseBolt12Offer(normalized) ?: return null
        return PaymentRequestDecodeResult.Bolt12(offer.amountSats, offer.description)
    }

    fun amountLocked(result: PaymentRequestDecodeResult): Boolean = when (result) {
        is PaymentRequestDecodeResult.Bolt11 -> result.amountSats != null
        is PaymentRequestDecodeResult.Bolt12 -> result.amountSats != null
        else -> false
    }

    fun typeLabel(result: PaymentRequestDecodeResult): String = when (result) {
        is PaymentRequestDecodeResult.LightningAddress -> "Lightning address"
        is PaymentRequestDecodeResult.Bolt11 -> "BOLT11 invoice"
        is PaymentRequestDecodeResult.Bolt12 -> "BOLT12 offer"
        is PaymentRequestDecodeResult.Onchain -> "Bitcoin address"
        is PaymentRequestDecodeResult.CashuPaymentRequest -> "Cashu request"
        PaymentRequestDecodeResult.Unrecognized -> "Unrecognized"
    }

    fun shortRepresentation(raw: String, result: PaymentRequestDecodeResult): String = when (result) {
        is PaymentRequestDecodeResult.LightningAddress -> result.address
        is PaymentRequestDecodeResult.CashuPaymentRequest ->
            result.summary.description ?: amountLabel(result.summary) ?: "Cashu payment request"
        else -> {
            val trimmed = raw.trim()
            if (trimmed.length > 16) "${trimmed.take(8)}...${trimmed.takeLast(6)}" else trimmed
        }
    }

    fun amountLabel(summary: CashuPaymentRequestSummary): String? =
        summary.amount?.let { "$it ${summary.unit ?: "sat"}" }

    private fun bitcoinPaymentURI(raw: String): BitcoinPaymentURI? {
        val body = when {
            raw.startsWith("bitcoin://", ignoreCase = true) -> raw.drop("bitcoin://".length)
            raw.startsWith("bitcoin:", ignoreCase = true) -> raw.drop("bitcoin:".length)
            else -> return null
        }
        val query = body.substringAfter("?", missingDelimiterValue = "")
        if (query.isEmpty()) return BitcoinPaymentURI(creq = null, lightning = null)
        val parameters = query.split("&").mapNotNull { entry ->
            val key = entry.substringBefore("=", missingDelimiterValue = "").decodeQueryComponent().trim()
            if (key.isEmpty()) return@mapNotNull null
            val value = entry.substringAfter("=", missingDelimiterValue = "").decodeQueryComponent().trim()
            key to value
        }
        val creq = parameters
            .firstOrNull { (key, _) -> key.equals("creq", ignoreCase = true) }
            ?.second
        val lightning = parameters
            .firstOrNull { (key, _) -> key.equals("lightning", ignoreCase = true) || key.equals("lightninginvoice", ignoreCase = true) }
            ?.second
        return BitcoinPaymentURI(creq = creq, lightning = lightning)
    }

    private fun stripSchemePrefixes(prefixes: List<String>, input: String): String {
        val prefix = prefixes.firstOrNull { input.startsWith(it, ignoreCase = true) }
        return if (prefix == null) input else input.drop(prefix.length)
    }

    private fun legacyCreqASummary(encoded: String): CashuPaymentRequestSummary? {
        if (!encoded.startsWith(CREQ_A_PREFIX, ignoreCase = true)) return null
        val payload = encoded.drop(CREQ_A_PREFIX.length)
        val bytes = runCatching { Base64.getUrlDecoder().decode(payload) }.getOrNull() ?: return null
        val fields = (runCatching { CborReader(bytes).readValue() }.getOrNull() as? CborValue.Map)
            ?.entries
            ?.mapNotNull { (key, value) -> (key as? CborValue.Text)?.value?.let { it to value } }
            ?.toMap()
            ?: return null
        val mints = (fields["m"] as? CborValue.Array)
            ?.values
            ?.mapNotNull { (it as? CborValue.Text)?.value }
            .orEmpty()
        return CashuPaymentRequestSummary(
            encoded = encoded,
            amount = (fields["a"] as? CborValue.UInt)?.value,
            unit = (fields["u"] as? CborValue.Text)?.value,
            description = (fields["d"] as? CborValue.Text)?.value,
            mints = mints,
        )
    }

    private data class BitcoinPaymentURI(val creq: String?, val lightning: String?)

    private sealed interface CborValue {
        data class UInt(val value: Long) : CborValue
        data class Text(val value: String) : CborValue
        data class Bool(val value: Boolean) : CborValue
        data class Array(val values: List<CborValue>) : CborValue
        data class Map(val entries: List<Pair<CborValue, CborValue>>) : CborValue
        data object Null : CborValue
    }

    private class CborReader(private val bytes: ByteArray) {
        private var position = 0

        fun readValue(): CborValue {
            val initial = readByte()
            val major = initial shr 5
            val additional = initial and 0x1F
            return when (major) {
                0 -> CborValue.UInt(readLength(additional))
                3 -> CborValue.Text(readBytes(readLength(additional).toInt()).toString(Charsets.UTF_8))
                4 -> CborValue.Array(List(readLength(additional).toInt()) { readValue() })
                5 -> CborValue.Map(List(readLength(additional).toInt()) { readValue() to readValue() })
                7 -> when (additional) {
                    20 -> CborValue.Bool(false)
                    21 -> CborValue.Bool(true)
                    22 -> CborValue.Null
                    else -> error("Unsupported CBOR simple value.")
                }
                else -> error("Unsupported CBOR major type.")
            }
        }

        private fun readLength(additional: Int): Long = when {
            additional < 24 -> additional.toLong()
            additional == 24 -> readByte().toLong()
            additional == 25 -> ((readByte() shl 8) or readByte()).toLong()
            additional == 26 -> (0 until 4).fold(0L) { acc, _ -> (acc shl 8) or readByte().toLong() }
            additional == 27 -> (0 until 8).fold(0L) { acc, _ -> (acc shl 8) or readByte().toLong() }
            else -> error("Unsupported CBOR length.")
        }

        private fun readBytes(length: Int): ByteArray {
            require(length >= 0 && position + length <= bytes.size) { "Truncated CBOR payload." }
            return bytes.copyOfRange(position, position + length).also { position += length }
        }

        private fun readByte(): Int {
            require(position < bytes.size) { "Truncated CBOR payload." }
            return bytes[position++].toInt() and 0xFF
        }
    }

    private fun String.decodeQueryComponent(): String =
        runCatching { URLDecoder.decode(this, StandardCharsets.UTF_8.name()) }.getOrDefault(this)

    private fun CdkCurrencyUnit.toDomainUnit(): String = when (this) {
        CdkCurrencyUnit.Sat -> "sat"
        CdkCurrencyUnit.Msat -> "msat"
        CdkCurrencyUnit.Usd -> "usd"
        CdkCurrencyUnit.Eur -> "eur"
        CdkCurrencyUnit.Auth -> "auth"
        is CdkCurrencyUnit.Custom -> unit
    }
}
