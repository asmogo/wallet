package com.cashu.me.Core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Host-side coverage for the NUT-16 decoder wrapper. The full encode/decode
 * round-trip needs the CDK native library and is exercised on-device in
 * `AnimatedUrDecoderInstrumentedTest`.
 */
class AnimatedUrDecoderTest {
    @Test
    fun rejectsNonUrContentWithoutTouchingNativeCode() {
        val update = AnimatedUrDecoder().receivePart("cashuAnotaur")

        assertNull(update.content)
        assertEquals("Not a UR fragment.", update.errorMessage)
        assertEquals(0f, update.progress)
    }
}
