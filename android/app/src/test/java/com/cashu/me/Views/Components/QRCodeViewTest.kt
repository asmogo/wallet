package com.cashu.me.Views.Components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Host-side QR frame tests. The animated (NUT-16) path needs the CDK native
 * library and is exercised on-device in `QRCodeViewInstrumentedTest`.
 */
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
    fun shortPayloadStaysASingleStaticFrame() {
        val content = "cashuAshort"
        val sequence = qrFrameSequence(
            content = content,
            staticOnly = false,
            chunkSize = QRSize.Large.chunkSize,
        )

        assertEquals(content, sequence.firstFrame)
        assertEquals(1, sequence.totalParts)
        assertNull(sequence.encoder)
    }

    @Test
    fun longNonTokenPayloadFallsBackToStatic() {
        // NUT-16 envelopes only carry Cashu tokens; a long non-token string
        // (no valid token encoding) must not be UR-fragmented.
        val content = "lnbc1" + "abcdef0123456789".repeat(30)
        val sequence = qrFrameSequence(
            content = content,
            staticOnly = false,
            chunkSize = QRSize.Small.chunkSize,
        )

        assertEquals(content, sequence.firstFrame)
        assertEquals(1, sequence.totalParts)
        assertNull(sequence.encoder)
    }
}
