package org.cashu.wallet.Core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TokenParserTest {
    @Test
    fun normalizedTokenStripsCashuSchemesAndWhitespace() {
        assertEquals("cashuAabc", TokenParser.normalizedToken("  cashu:cashuAabc  "))
        assertEquals("cashuBabc", TokenParser.normalizedToken("cashu://cashuBabc"))
        assertEquals("CASHUCabc", TokenParser.normalizedToken("CASHU:CASHUCabc"))
    }

    @Test
    fun tokenRecognitionIsCaseInsensitiveAndRejectsOtherPayloads() {
        assertTrue(TokenParser.isCashuToken("cashu://CASHUAabc"))
        assertTrue(TokenParser.isCashuToken("cashuBabc"))
        assertFalse(TokenParser.isCashuToken("lnbc1invoice"))
        assertFalse(TokenParser.isCashuToken("creqArequest"))
    }

    @Test
    fun malformedTokenMessageExplainsUnsupportedPrefixes() {
        assertNull(TokenParser.malformedTokenMessage(""))
        assertNull(TokenParser.malformedTokenMessage("cashu:cashuAabc"))
        assertEquals(
            "Token must start with cashuA, cashuB, or cashuC.",
            TokenParser.malformedTokenMessage("not-a-token"),
        )
    }
}
