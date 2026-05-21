package org.cashu.wallet.Core

import java.security.MessageDigest

object BitcoinAddressValidator {
    private const val base58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    private const val bech32Alphabet = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    private val bech32Generator = intArrayOf(0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3)
    private val base58VersionBytes = setOf(0x00, 0x05, 0x6f, 0xc4)
    private val bech32Hrp = setOf("bc", "tb", "bcrt")
    private val base58Values = base58Alphabet.withIndex().associate { it.value to it.index }
    private val bech32Values = bech32Alphabet.withIndex().associate { it.value to it.index }

    fun isValidAddress(address: String): Boolean {
        val trimmed = address.trim()
        if (trimmed.isEmpty() || trimmed.any { it.isWhitespace() } || trimmed.contains("@")) return false
        return isValidBech32Address(trimmed) || isValidBase58CheckAddress(trimmed)
    }

    private fun isValidBase58CheckAddress(address: String): Boolean {
        val decoded = decodeBase58(address) ?: return false
        if (decoded.size != 25) return false
        val payload = decoded.take(21).map { it.toByte() }.toByteArray()
        val checksum = decoded.takeLast(4)
        val version = payload.firstOrNull()?.toInt()?.and(0xff) ?: return false
        if (version !in base58VersionBytes) return false
        val secondHash = sha256(sha256(payload)).map { it.toInt().and(0xff) }
        return secondHash.take(4) == checksum
    }

    private fun decodeBase58(address: String): List<Int>? {
        val bytes = mutableListOf<Int>()
        for (character in address) {
            val value = base58Values[character] ?: return null
            var carry = value
            for (index in bytes.indices.reversed()) {
                val total = bytes[index] * 58 + carry
                bytes[index] = total and 0xff
                carry = total shr 8
            }
            while (carry > 0) {
                bytes.add(0, carry and 0xff)
                carry = carry shr 8
            }
        }
        val leadingZeroes = address.takeWhile { it == '1' }.length
        return List(leadingZeroes) { 0 } + bytes
    }

    private fun isValidBech32Address(address: String): Boolean {
        if (address.any { it.code < 33 || it.code > 126 }) return false
        val hasLowercase = address.any { it.isLowerCase() }
        val hasUppercase = address.any { it.isUpperCase() }
        if (hasLowercase && hasUppercase) return false

        val lower = address.lowercase()
        val separator = lower.lastIndexOf('1')
        if (separator < 1) return false
        val hrp = lower.substring(0, separator)
        val dataPart = lower.substring(separator + 1)
        if (hrp !in bech32Hrp || dataPart.length < 7) return false
        val dataValues = dataPart.map { bech32Values[it] ?: return false }
        val checksum = bech32Polymod(hrpExpand(hrp) + dataValues)
        val encodingIsBech32 = checksum == 1
        val encodingIsBech32m = checksum == 0x2bc830a3
        if (!encodingIsBech32 && !encodingIsBech32m) return false

        val witnessData = dataValues.dropLast(6)
        val version = witnessData.firstOrNull() ?: return false
        if (version > 16) return false
        val program = convertBits(witnessData.drop(1), fromBits = 5, toBits = 8, pad = false) ?: return false
        if (program.size !in 2..40) return false
        return if (version == 0) {
            encodingIsBech32 && (program.size == 20 || program.size == 32)
        } else {
            encodingIsBech32m
        }
    }

    private fun hrpExpand(hrp: String): List<Int> {
        val scalars = hrp.map { it.code }
        return scalars.map { it shr 5 } + listOf(0) + scalars.map { it and 31 }
    }

    private fun bech32Polymod(values: List<Int>): Int {
        var checksum = 1
        for (value in values) {
            val top = checksum shr 25
            checksum = ((checksum and 0x1ffffff) shl 5) xor value
            for (index in 0 until 5) {
                if (((top shr index) and 1) == 1) checksum = checksum xor bech32Generator[index]
            }
        }
        return checksum
    }

    private fun convertBits(data: List<Int>, fromBits: Int, toBits: Int, pad: Boolean): List<Int>? {
        var accumulator = 0
        var bits = 0
        val result = mutableListOf<Int>()
        val maxValue = (1 shl toBits) - 1
        val maxAccumulator = (1 shl (fromBits + toBits - 1)) - 1
        for (value in data) {
            if (value < 0 || (value shr fromBits) != 0) return null
            accumulator = ((accumulator shl fromBits) or value) and maxAccumulator
            bits += fromBits
            while (bits >= toBits) {
                bits -= toBits
                result += (accumulator shr bits) and maxValue
            }
        }
        if (pad) {
            if (bits > 0) result += (accumulator shl (toBits - bits)) and maxValue
        } else if (bits >= fromBits || ((accumulator shl (toBits - bits)) and maxValue) != 0) {
            return null
        }
        return result
    }

    private fun sha256(bytes: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(bytes)
}
