package org.cashu.wallet.Core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MintUrlInputTest {
    @Test
    fun normalizeUserMintUrlAddsHttpsAndTrimsSlashAndQuotes() {
        assertEquals("https://mint.example.com/path", normalizeUserMintUrl(" 'mint.example.com/path/' "))
    }

    @Test
    fun normalizeUserMintUrlRejectsHttpAndMalformedUrls() {
        assertNull(normalizeUserMintUrl("http://mint.example.com"))
        assertNull(normalizeUserMintUrl("not a url"))
    }

    @Test
    fun mintUrlCandidatesParsesClipboardSeparatorsAndDeduplicates() {
        assertEquals(
            listOf("https://mint.one", "https://mint.two/path"),
            mintUrlCandidates("mint.one, https://mint.two/path/; mint.one\nhttp://insecure.example"),
        )
    }

    @Test
    fun shortenMintUrlRemovesSchemeAndTrailingSlash() {
        assertEquals("mint.example.com/path", shortenMintUrl("https://mint.example.com/path/"))
    }
}
