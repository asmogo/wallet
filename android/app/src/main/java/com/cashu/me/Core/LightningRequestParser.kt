package com.cashu.me.Core

import com.cashu.me.Models.PaymentMethodKind
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

data class ParsedLightningRequest(
    val request: String,
    val method: PaymentMethodKind,
    val amountSats: Long? = null,
    val description: String? = null,
)

object LightningRequestParser {
    private val bolt11Prefixes = listOf("lnbc", "lntb", "lnbcrt", "lnsb")
    private const val bolt12Alphabet = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    private val bolt12Values = bolt12Alphabet.withIndex().associate { (index, character) -> character to index }
    private val knownOfferTypes = setOf(2uL, 4uL, 6uL, 8uL, 10uL, 12uL, 14uL, 16uL, 18uL, 20uL, 22uL)
    private const val maximumBitcoinAmountMsat = 2_100_000_000_000_000_000uL

    fun parse(raw: String): ParsedLightningRequest {
        val request = PaymentRequestParser.normalizeLightningRequest(raw)
        parseBolt12Offer(request)?.let { return it }
        return when {
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

    fun isBolt12(raw: String): Boolean = parseBolt12Offer(raw) != null

    /**
     * Parses the BOLT12 text envelope and the offer TLVs needed by Send. CDK's
     * decoder currently rejects valid amountless offers whose description is
     * empty, even though BOLT12 permits them. CDK still performs the final
     * protocol validation when the wallet requests a quote.
     */
    fun parseBolt12Offer(raw: String): ParsedLightningRequest? {
        val request = normalizeBolt12Offer(raw) ?: return null
        if (!request.startsWith("lno1")) return null
        val encoded = request.drop(4)
        if (encoded.isEmpty()) return null
        val values = encoded.map { bolt12Values[it] ?: return null }
        val bytes = convertBolt12Bits(values) ?: return null

        var cursor = 0
        var previousType: ULong? = null
        var amountMsat: ULong? = null
        var sawAmount = false
        var sawDescription = false
        var sawCurrency = false
        var description: String? = null
        var hasPaths = false
        var hasIssuerId = false

        while (cursor < bytes.size) {
            val (type, afterType) = readBigSize(bytes, cursor) ?: return null
            val (length, afterLength) = readBigSize(bytes, afterType) ?: return null
            if (previousType != null && type <= previousType) return null
            previousType = type
            if (type !in 1uL..79uL && type !in 1_000_000_000uL..1_999_999_999uL) return null
            // Unknown odd records are optional extensions; unknown even
            // records are mandatory and make the offer unreadable.
            if (type % 2uL == 0uL && type !in knownOfferTypes) return null
            if (length > (bytes.size - afterLength).toULong()) return null

            val fieldEnd = afterLength + length.toInt()
            val field = bytes.copyOfRange(afterLength, fieldEnd)
            cursor = fieldEnd

            when (type) {
                2uL -> if (field.isEmpty() || field.size % 32 != 0) return null
                6uL -> {
                    if (field.size != 3 || field.any { (it.toInt() and 0xff) !in 65..90 }) return null
                    sawCurrency = true
                }
                8uL -> {
                    val value = decodeTruncatedULong(field) ?: return null
                    if (value == 0uL || value > maximumBitcoinAmountMsat) return null
                    sawAmount = true
                    amountMsat = value
                }
                10uL -> {
                    val value = decodeUtf8(field) ?: return null
                    sawDescription = true
                    description = value.ifEmpty { null }
                }
                14uL, 20uL -> decodeTruncatedULong(field) ?: return null
                16uL -> hasPaths = field.isNotEmpty()
                18uL -> decodeUtf8(field) ?: return null
                22uL -> {
                    val prefix = field.firstOrNull()?.toInt()?.and(0xff)
                    if (field.size != 33 || prefix !in setOf(0x02, 0x03)) return null
                    hasIssuerId = true
                }
            }
        }

        if ((!hasPaths && !hasIssuerId) || (sawAmount && !sawDescription) || (sawCurrency && !sawAmount)) {
            return null
        }
        // Currency-denominated offer amounts are not millisatoshis. Leave
        // those to CDK rather than treating them as amountless.
        if (sawCurrency) return null

        val amountSats = amountMsat?.let { millisatoshis ->
            val sats = millisatoshis / 1_000uL + if (millisatoshis % 1_000uL == 0uL) 0uL else 1uL
            if (sats > Long.MAX_VALUE.toULong()) return null
            sats.toLong()
        }
        return ParsedLightningRequest(
            request = request,
            method = PaymentMethodKind.Bolt12,
            amountSats = amountSats,
            description = description,
        )
    }

    private fun normalizeBolt12Offer(raw: String): String? {
        val input = PaymentRequestParser.normalizeLightningRequest(raw).trim()
        if (input.isEmpty()) return null

        val compact = StringBuilder(input.length)
        var index = 0
        while (index < input.length) {
            val character = input[index]
            if (character == '+') {
                if (compact.isEmpty() || !isBolt12DataCharacter(compact.last())) return null
                index += 1
                while (index < input.length && input[index].isWhitespace()) index += 1
                if (index >= input.length || !isBolt12DataCharacter(input[index])) {
                    return null
                }
                continue
            }
            if (character.isWhitespace()) return null
            compact.append(character)
            index += 1
        }

        val text = compact.toString()
        if (text.any(Char::isLowerCase) && text.any(Char::isUpperCase)) return null
        return text.lowercase()
    }

    private fun isBolt12DataCharacter(character: Char): Boolean =
        character.lowercaseChar() in bolt12Alphabet

    private fun convertBolt12Bits(values: List<Int>): ByteArray? {
        var accumulator = 0
        var bitCount = 0
        val output = ArrayList<Byte>()
        values.forEach { value ->
            if (value !in 0..31) return null
            accumulator = ((accumulator shl 5) or value) and 0x0fff
            bitCount += 5
            while (bitCount >= 8) {
                bitCount -= 8
                output += ((accumulator shr bitCount) and 0xff).toByte()
            }
        }
        if (bitCount >= 5 || ((accumulator shl (8 - bitCount)) and 0xff) != 0) return null
        return output.toByteArray()
    }

    private fun readBigSize(bytes: ByteArray, start: Int): Pair<ULong, Int>? {
        if (start !in bytes.indices) return null
        val marker = bytes[start].toInt() and 0xff
        if (marker < 0xfd) return marker.toULong() to start + 1

        val byteCount = when (marker) {
            0xfd -> 2
            0xfe -> 4
            else -> 8
        }
        val end = start + 1 + byteCount
        if (end > bytes.size) return null
        var value = 0uL
        for (index in start + 1 until end) {
            value = (value shl 8) or (bytes[index].toInt() and 0xff).toULong()
        }
        val minimum = when (marker) {
            0xfd -> 0xfduL
            0xfe -> 0x1_0000uL
            else -> 0x1_0000_0000uL
        }
        return if (value >= minimum) value to end else null
    }

    private fun decodeTruncatedULong(bytes: ByteArray): ULong? {
        if (bytes.size > 8 || (bytes.isNotEmpty() && bytes.first() == 0.toByte())) return null
        return bytes.fold(0uL) { value, byte ->
            (value shl 8) or (byte.toInt() and 0xff).toULong()
        }
    }

    private fun decodeUtf8(bytes: ByteArray): String? = runCatching {
        Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes))
            .toString()
    }.getOrNull()

    private fun parseBolt11AmountSats(invoice: String): Long? {
        val lower = invoice.lowercase()
        val prefix = bolt11Prefixes.firstOrNull { lower.startsWith(it) } ?: return null
        val rest = lower.drop(prefix.length)
        val numberPart = rest.takeWhile { it.isDigit() }
        if (numberPart.isEmpty()) return null
        val number = numberPart.toLongOrNull() ?: return null
        val unit = rest.getOrNull(numberPart.length)
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
