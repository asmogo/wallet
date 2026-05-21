package org.cashu.wallet.Views.Components

import org.cashu.wallet.Core.AnimatedUrDecoder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class QRCodeViewTest {
    @Test
    fun staticOnlyKeepsPayloadUnchanged() {
        val sequence = qrFrameSequence(
            content = "lnbc1static",
            staticOnly = true,
            chunkSize = QRSize.Small.chunkSize,
        )

        assertEquals("lnbc1static", sequence.firstFrame)
        assertEquals(1, sequence.totalParts)
        assertNull(sequence.encoder)
    }

    @Test
    fun longPayloadUsesAnimatedBytesUrFrames() {
        val content = "cashuA" + "abcdef0123456789".repeat(30)
        val sequence = qrFrameSequence(
            content = content,
            staticOnly = false,
            chunkSize = QRSize.Small.chunkSize,
        )

        assertTrue(sequence.firstFrame.startsWith("ur:bytes/", ignoreCase = true))
        assertTrue(sequence.totalParts > 1)

        val decoder = AnimatedUrDecoder()
        var decoded = decoder.receivePart(sequence.firstFrame).content
        repeat(sequence.totalParts + 8) {
            decoded = decoded ?: decoder.receivePart(sequence.encoder!!.nextPart()).content
        }

        assertEquals(content, decoded)
    }
}
