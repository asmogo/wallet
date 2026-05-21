package org.cashu.wallet.Core

object Bech32 {
    private const val alphabet = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    private val values = alphabet.withIndex().associate { it.value to it.index }
    private val generator = intArrayOf(0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3)

    fun encode(hrp: String, data: ByteArray): String {
        require(hrp.isNotBlank()) { "Bech32 HRP is required." }
        val lowerHrp = hrp.lowercase()
        val words = convertBits(data.map { it.toInt() and 0xff }, fromBits = 8, toBits = 5, pad = true)
        val checksum = createChecksum(lowerHrp, words)
        return lowerHrp + "1" + (words + checksum).joinToString("") { alphabet[it].toString() }
    }

    fun decode(expectedHrp: String, bech32: String): ByteArray {
        val trimmed = bech32.trim()
        require(trimmed.isNotEmpty()) { "Bech32 value is empty." }
        val hasLowercase = trimmed.any { it.isLowerCase() }
        val hasUppercase = trimmed.any { it.isUpperCase() }
        require(!(hasLowercase && hasUppercase)) { "Mixed-case Bech32 values are invalid." }
        val lower = trimmed.lowercase()
        val separator = lower.lastIndexOf('1')
        require(separator > 0 && separator + 7 <= lower.length) { "Invalid Bech32 separator." }
        val hrp = lower.substring(0, separator)
        require(hrp == expectedHrp.lowercase()) { "Unexpected Bech32 prefix." }
        val data = lower.substring(separator + 1).map { values[it] ?: error("Invalid Bech32 character.") }
        require(verifyChecksum(hrp, data)) { "Invalid Bech32 checksum." }
        val payload = data.dropLast(6)
        return convertBits(payload, fromBits = 5, toBits = 8, pad = false)
            .map { it.toByte() }
            .toByteArray()
    }

    private fun createChecksum(hrp: String, data: List<Int>): List<Int> {
        val values = hrpExpand(hrp) + data + List(6) { 0 }
        val polymod = polymod(values) xor 1
        return (0 until 6).map { index -> (polymod shr (5 * (5 - index))) and 31 }
    }

    private fun verifyChecksum(hrp: String, data: List<Int>): Boolean =
        polymod(hrpExpand(hrp) + data) == 1

    private fun hrpExpand(hrp: String): List<Int> =
        hrp.map { it.code shr 5 } + listOf(0) + hrp.map { it.code and 31 }

    private fun polymod(values: List<Int>): Int {
        var checksum = 1
        for (value in values) {
            val top = checksum shr 25
            checksum = ((checksum and 0x1ffffff) shl 5) xor value
            for (index in 0 until 5) {
                if (((top shr index) and 1) == 1) checksum = checksum xor generator[index]
            }
        }
        return checksum
    }

    private fun convertBits(data: List<Int>, fromBits: Int, toBits: Int, pad: Boolean): List<Int> {
        var accumulator = 0
        var bits = 0
        val result = mutableListOf<Int>()
        val maxValue = (1 shl toBits) - 1
        val maxAccumulator = (1 shl (fromBits + toBits - 1)) - 1
        for (value in data) {
            require(value >= 0 && (value shr fromBits) == 0) { "Invalid bit group." }
            accumulator = ((accumulator shl fromBits) or value) and maxAccumulator
            bits += fromBits
            while (bits >= toBits) {
                bits -= toBits
                result += (accumulator shr bits) and maxValue
            }
        }
        if (pad) {
            if (bits > 0) result += (accumulator shl (toBits - bits)) and maxValue
        } else {
            require(bits < fromBits && ((accumulator shl (toBits - bits)) and maxValue) == 0) {
                "Invalid padding."
            }
        }
        return result
    }
}
