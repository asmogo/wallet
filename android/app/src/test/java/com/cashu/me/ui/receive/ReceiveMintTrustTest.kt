package com.cashu.me.ui.receive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReceiveMintTrustTest {
    @Test
    fun unknownMintShowsWarning() {
        val trust = receiveMintTrust(
            mintUrl = "https://new-mint.example/path/",
            knownMintUrls = listOf("https://trusted.example"),
        )

        assertTrue(trust.showWarning)
        assertEquals("new-mint.example", trust.host)
    }

    @Test
    fun knownMintSkipsWarning() {
        val trust = receiveMintTrust(
            mintUrl = " HTTPS://MINT.EXAMPLE.COM/wallet/ ",
            knownMintUrls = listOf("https://mint.example.com/wallet"),
        )

        assertFalse(trust.showWarning)
        assertEquals("mint.example.com", trust.host)
    }

    @Test
    fun mintHostIsNormalizedForTrustCopy() {
        assertEquals(
            "mint.example.com",
            normalizedMintHost("HTTPS://user@Mint.Example.COM.:443/nuts/path/"),
        )
        assertEquals(
            "mint.example.com",
            normalizedMintHost("Mint.Example.COM/nuts/path/"),
        )
    }
}
