package org.cashu.wallet.Core

import org.cashu.wallet.Models.PaymentMethodKind
import org.cashudevkit.CurrencyUnit as CdkCurrencyUnit
import org.cashudevkit.PaymentType as CdkPaymentType
import org.cashudevkit.decodeInvoice
import org.cashudevkit.decodePaymentRequest
import java.net.URLDecoder
import java.nio.charset.StandardCharsets

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
        if (isBitcoinAddress(request)) return PaymentMethodKind.Onchain
        return null
    }
}

object PaymentRequestDecoder {
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
        bitcoinPaymentURI(trimmed)?.lightning?.let { return PaymentRequestParser.normalizeLightningRequest(it) }
        val normalized = PaymentRequestParser.normalizeLightningRequest(trimmed)
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

    fun cashuPaymentRequestSummary(raw: String): CashuPaymentRequestSummary? {
        val encoded = encodedCashuPaymentRequest(raw) ?: return null
        val request = runCatching { decodePaymentRequest(encoded) }.getOrNull() ?: return null
        return CashuPaymentRequestSummary(
            encoded = encoded,
            amount = request.amount()?.value?.toLong(),
            unit = request.unit()?.toDomainUnit(),
            description = request.description(),
            mints = request.mints(),
        )
    }

    private fun decodedLightningRequest(raw: String): PaymentRequestDecodeResult? {
        val normalized = encodedLightningRequest(raw) ?: return null
        val decoded = runCatching { decodeInvoice(normalized) }.getOrNull() ?: return null
        val amountSats = decoded.amountMsat?.let { (it.toLong() + 999) / 1000 }
        return when (decoded.paymentType) {
            CdkPaymentType.BOLT11 -> PaymentRequestDecodeResult.Bolt11(amountSats, decoded.description)
            CdkPaymentType.BOLT12 -> PaymentRequestDecodeResult.Bolt12(amountSats, decoded.description)
        }
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

    private data class BitcoinPaymentURI(val creq: String?, val lightning: String?)

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
