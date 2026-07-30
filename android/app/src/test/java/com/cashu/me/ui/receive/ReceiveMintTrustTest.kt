package com.cashu.me.ui.receive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReceiveMintTrustTest {
    @Test
    fun unknownMintBlocksClaimUntilExplicitConfirmation() {
        val trust = receiveMintTrust(
            mintUrl = "https://new-mint.example/path/",
            knownMintUrls = listOf("https://trusted.example"),
        )

        assertTrue(trust.requiresConfirmation)
        assertEquals(
            ReceiveMintClaimAction.RequestConfirmation,
            trust.claimAction(userConfirmed = false),
        )
        assertEquals(
            ReceiveMintClaimAction.Claim,
            trust.claimAction(userConfirmed = true),
        )
    }

    @Test
    fun knownMintAvoidsUnnecessaryWarningAndClaimsImmediately() {
        val trust = receiveMintTrust(
            mintUrl = " HTTPS://MINT.EXAMPLE.COM/wallet/ ",
            knownMintUrls = listOf("https://mint.example.com/wallet"),
        )

        assertFalse(trust.requiresConfirmation)
        assertEquals(
            ReceiveMintClaimAction.Claim,
            trust.claimAction(userConfirmed = false),
        )
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
