package org.cashu.wallet.Core

import com.gorunjinian.bcur.Cbor
import com.gorunjinian.bcur.ResultType
import com.gorunjinian.bcur.URDecoder

data class AnimatedUrDecodeUpdate(
    val content: String?,
    val progress: Float,
    val errorMessage: String? = null,
)

class AnimatedUrDecoder {
    private var decoder = URDecoder()
    private val seenSequenceNumbers = mutableSetOf<Int>()
    private var expectedSequenceCount: Int? = null

    fun reset() {
        decoder = URDecoder()
        seenSequenceNumbers.clear()
        expectedSequenceCount = null
    }

    fun receivePart(part: String): AnimatedUrDecodeUpdate {
        val trimmed = part.trim()
        if (!trimmed.startsWith("ur:", ignoreCase = true)) {
            return AnimatedUrDecodeUpdate(content = null, progress = progress(), errorMessage = "Not a UR fragment.")
        }

        parseSequence(trimmed)?.let { sequence ->
            expectedSequenceCount = sequence.count
            seenSequenceNumbers += sequence.number
        }

        return runCatching {
            decoder.receivePart(trimmed)
            val result = decoder.result
            if (result?.type == ResultType.SUCCESS) {
                val ur = result.ur ?: return@runCatching AnimatedUrDecodeUpdate(null, progress())
                val decoded = when {
                    ur.type.equals("bytes", ignoreCase = true) -> Cbor.unwrapByteString(ur.cborData)
                    else -> ur.cborData
                }.toString(Charsets.UTF_8)
                AnimatedUrDecodeUpdate(content = decoded, progress = 1f)
            } else {
                AnimatedUrDecodeUpdate(content = null, progress = progress())
            }
        }.getOrElse { error ->
            AnimatedUrDecodeUpdate(
                content = null,
                progress = progress(),
                errorMessage = error.message ?: "Unable to decode animated QR.",
            )
        }
    }

    private fun progress(): Float {
        val total = expectedSequenceCount ?: return 0f
        if (total <= 0) return 0f
        return (seenSequenceNumbers.size.toFloat() / total.toFloat()).coerceIn(0f, 0.99f)
    }

    private fun parseSequence(part: String): UrSequence? {
        val pieces = part.lowercase().split("/")
        if (pieces.size < 3) return null
        val sequence = pieces[1].split("-")
        if (sequence.size != 2) return null
        val number = sequence[0].toIntOrNull() ?: return null
        val count = sequence[1].toIntOrNull() ?: return null
        if (number <= 0 || count <= 0) return null
        return UrSequence(number, count)
    }

    private data class UrSequence(val number: Int, val count: Int)
}
