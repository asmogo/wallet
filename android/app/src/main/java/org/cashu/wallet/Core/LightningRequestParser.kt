package org.cashu.wallet.Core

import org.cashu.wallet.Models.PaymentMethodKind

data class ParsedLightningRequest(
    val request: String,
    val method: PaymentMethodKind,
    val amountSats: Long? = null,
    val description: String? = null,
)

object LightningRequestParser {
    private val bolt11Prefixes = listOf("lnbc", "lntb", "lnbcrt", "lnsb")
    private val bolt12Prefixes = listOf("lno", "lni")

    fun parse(raw: String): ParsedLightningRequest {
        val request = PaymentRequestParser.normalizeLightningRequest(raw)
        return when {
            isBolt12(request) -> ParsedLightningRequest(request, PaymentMethodKind.Bolt12)
            isBolt11(request) -> ParsedLightningRequest(
                request = request,
                method = PaymentMethodKind.Bolt11,
                amountSats = parseBolt11AmountSats(request),
            )
            else -> throw IllegalArgumentException("Unsupported Lightning request")
        }
    }

    fun isLightningRequest(raw: String): Boolean = isBolt11(raw) || isBolt12(raw)

    fun isBolt11(raw: String): Boolean {
        val lower = PaymentRequestParser.normalizeLightningRequest(raw).lowercase()
        return bolt11Prefixes.any { lower.startsWith(it) }
    }

    fun isBolt12(raw: String): Boolean {
        val lower = PaymentRequestParser.normalizeLightningRequest(raw).lowercase()
        return bolt12Prefixes.any { lower.startsWith(it) }
    }

    private fun parseBolt11AmountSats(invoice: String): Long? {
        val lower = invoice.lowercase()
        val prefix = bolt11Prefixes.firstOrNull { lower.startsWith(it) } ?: return null
        val rest = lower.drop(prefix.length)
        val amountPart = rest.takeWhile { it.isDigit() || it in setOf('m', 'u', 'n', 'p') }
        if (amountPart.isEmpty()) return null
        val unit = amountPart.last()
        val numberPart = if (unit.isLetter()) amountPart.dropLast(1) else amountPart
        val number = numberPart.toLongOrNull() ?: return null
        val btc = when (unit) {
            'm' -> number / 1_000.0
            'u' -> number / 1_000_000.0
            'n' -> number / 1_000_000_000.0
            'p' -> number / 1_000_000_000_000.0
            else -> number.toDouble()
        }
        return (btc * 100_000_000L).toLong().takeIf { it > 0 }
    }
}
