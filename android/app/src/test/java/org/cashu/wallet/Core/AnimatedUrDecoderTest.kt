package org.cashu.wallet.Core

import com.gorunjinian.bcur.Cbor
import com.gorunjinian.bcur.UR
import com.gorunjinian.bcur.UREncoder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AnimatedUrDecoderTest {
    @Test
    fun decodesSinglePartBytesUr() {
        val payload = "cashu-test-token"
        val ur = UR("bytes", Cbor.wrapInByteString(payload.toByteArray()))
        val part = UREncoder.encode(ur)

        val update = AnimatedUrDecoder().receivePart(part)

        assertEquals(payload, update.content)
        assertEquals(1f, update.progress)
        assertNull(update.errorMessage)
    }

    @Test
    fun reassemblesMultipartBytesUr() {
        val payload = "cashuA" + "0123456789abcdef".repeat(40)
        val ur = UR("bytes", Cbor.wrapInByteString(payload.toByteArray()))
        val encoder = UREncoder(ur, maxFragmentLen = 80)
        val decoder = AnimatedUrDecoder()

        var decoded: String? = null
        repeat(20) {
            val update = decoder.receivePart(encoder.nextPart())
            assertNull(update.errorMessage)
            assertTrue(update.progress in 0f..1f)
            decoded = update.content ?: decoded
            if (decoded != null) return@repeat
        }

        assertEquals(payload, decoded)
    }
}
