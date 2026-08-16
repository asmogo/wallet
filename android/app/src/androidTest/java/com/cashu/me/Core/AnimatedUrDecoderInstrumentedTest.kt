package com.cashu.me.Core

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.cashudevkit.Token as CdkToken
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * On-device NUT-16 coverage: CDK's own fountain encoder produces the frames,
 * the scanner-side decoder wrapper reassembles them.
 */
@RunWith(AndroidJUnit4::class)
class AnimatedUrDecoderInstrumentedTest {
    @Test
    fun decodesSinglePartBytesUr() {
        val encoder = CdkToken.decode(TOKEN).urEncoder(maxFragmentLength = 1000u)
        assertTrue(encoder.isSingleFragment())

        val update = AnimatedUrDecoder().receivePart(encoder.nextPart())

        assertNull(update.errorMessage)
        assertEquals(canonicalToken, update.content)
        assertEquals(1f, update.progress)
    }

    @Test
    fun reassemblesMultipartBytesUr() {
        val encoder = CdkToken.decode(TOKEN).urEncoder(maxFragmentLength = 80u)
        assertTrue("test token must span several frames", encoder.fragmentCount() > 1u)

        val decoder = AnimatedUrDecoder()

        var decoded: String? = null
        // Fountain parts guarantee completion shortly after fragmentCount.
        repeat(encoder.fragmentCount().toInt() * 2) {
            val update = decoder.receivePart(encoder.nextPart())
            assertNull(update.errorMessage)
            assertTrue(update.progress in 0f..1f)
            decoded = update.content ?: decoded
            if (decoded != null) return@repeat
        }

        assertNotNull(decoded)
        assertEquals(canonicalToken, decoded)
    }

    @Test
    fun toleratesOutOfOrderAndDuplicateFrames() {
        val encoder = CdkToken.decode(TOKEN).urEncoder(maxFragmentLength = 80u)
        val frames = (0 until encoder.fragmentCount().toInt()).map { encoder.nextPart() }
        val decoder = AnimatedUrDecoder()

        var decoded: String? = null
        // Feed frames shuffled with duplicates, as a camera stream would.
        (frames.reversed() + frames).forEach { frame ->
            decoded = decoder.receivePart(frame).content ?: decoded
        }

        assertEquals(canonicalToken, decoded)
    }

    @Test
    fun rejectsWrongUrType() {
        val update = AnimatedUrDecoder().receivePart("ur:crypto-psbt/1-1/lpadaxcswtcyztyalnwe")

        assertNull(update.content)
    }

    private companion object {
        // Valid V4 token from CDK's own NUT-16 test vector.
        const val TOKEN = "cashuBpGF0gaJhaUgArSaMTR9YJmFwgaNhYQFhc3hAOWE2ZGJiODQ3YmQyMzJiYTc2ZGIwZGYxOTcyMTZiMjlkM2I4Y2MxNDU1M2NkMjc4MjdmYzFjYzk0MmZlZGI0ZWFjWCEDhhhUP_trhpXfStS6vN6So0qWvc2X3O4NfM-Y1HISZ5JhZGlUaGFuayB5b3VhbXVodHRwOi8vbG9jYWxob3N0OjMzMzhhdWNzYXQ="

        // Token re-serialization is not byte-identical to the input (key
        // ordering), so compare against CDK's canonical re-encoding.
        val canonicalToken: String get() = CdkToken.decode(TOKEN).encode()
    }
}
