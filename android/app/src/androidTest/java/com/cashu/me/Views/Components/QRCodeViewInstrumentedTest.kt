package com.cashu.me.Views.Components

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.Core.AnimatedUrDecoder
import org.cashudevkit.Token as CdkToken
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * On-device NUT-16 display-side coverage: CDK's fountain encoder produces the
 * frames shown by [QRCodeView]; the scanner-side decoder wrapper reassembles
 * them, proving the emitted frames stay scannable.
 */
@RunWith(AndroidJUnit4::class)
class QRCodeViewInstrumentedTest {
    @Test
    fun longTokenUsesAnimatedBytesUrFramesThatScanBack() {
        val sequence = qrFrameSequence(
            content = TOKEN,
            staticOnly = false,
            chunkSize = QRSize.Small.chunkSize,
        )

        assertTrue(sequence.firstFrame.startsWith("ur:bytes/", ignoreCase = true))
        assertTrue(sequence.totalParts > 1)
        assertNotNull(sequence.encoder)

        val decoder = AnimatedUrDecoder()
        var decoded = decoder.receivePart(sequence.firstFrame).content
        repeat(sequence.totalParts + 8) {
            decoded = decoded ?: decoder.receivePart(sequence.encoder!!.nextPart()).content
        }

        assertEquals(canonicalToken, decoded)
    }

    @Test
    fun tokenFittingOneFrameStaysStatic() {
        val sequence = qrFrameSequence(
            content = TOKEN,
            staticOnly = false,
            chunkSize = 4096,
        )

        assertEquals(TOKEN, sequence.firstFrame)
        assertEquals(1, sequence.totalParts)
        assertNull(sequence.encoder)
    }

    private companion object {
        // Valid V4 token from CDK's own NUT-16 test vector.
        const val TOKEN = "cashuBpGF0gaJhaUgArSaMTR9YJmFwgaNhYQFhc3hAOWE2ZGJiODQ3YmQyMzJiYTc2ZGIwZGYxOTcyMTZiMjlkM2I4Y2MxNDU1M2NkMjc4MjdmYzFjYzk0MmZlZGI0ZWFjWCEDhhhUP_trhpXfStS6vN6So0qWvc2X3O4NfM-Y1HISZ5JhZGlUaGFuayB5b3VhbXVodHRwOi8vbG9jYWxob3N0OjMzMzhhdWNzYXQ="

        // Token re-serialization is not byte-identical to the input (key
        // ordering), so compare against CDK's canonical re-encoding.
        val canonicalToken: String get() = CdkToken.decode(TOKEN).encode()
    }
}
