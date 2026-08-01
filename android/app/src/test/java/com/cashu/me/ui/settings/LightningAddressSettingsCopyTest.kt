package com.cashu.me.ui.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class LightningAddressSettingsCopyTest {
    @Test
    fun enableControlLeadsWithTheUserOutcome() {
        assertEquals(
            "Enable Lightning Address",
            LightningAddressSettingsCopy.EnableTitle,
        )
        assertEquals(
            "Receive Lightning payments to your wallet using a Lightning address.",
            LightningAddressSettingsCopy.EnableSubtitle,
        )
    }

    @Test
    fun primarySettingsCopyDoesNotExposeImplementationTerms() {
        val primaryCopy = listOf(
            LightningAddressSettingsCopy.EnableTitle,
            LightningAddressSettingsCopy.EnableSubtitle,
            LightningAddressSettingsCopy.AutomaticClaimTitle,
            LightningAddressSettingsCopy.AutomaticClaimSubtitle,
        )
        val implementationTerms = listOf("Nostr", "NPC", "bridge", "quote", "handler")

        implementationTerms.forEach { term ->
            assertFalse(
                "Primary Lightning address copy must not expose '$term'",
                primaryCopy.any { it.contains(term, ignoreCase = true) },
            )
        }
    }
}
