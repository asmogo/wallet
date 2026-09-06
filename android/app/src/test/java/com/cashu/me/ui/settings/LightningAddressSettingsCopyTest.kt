package com.cashu.me.ui.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class LightningAddressSettingsCopyTest {
    @Test
    fun statusOnlySaysConnectingWhileARequestIsRunning() {
        val state = com.cashu.me.Core.NPCState(isEnabled = true, isInitialized = true)
        assertEquals("Not connected", npcStatusLabel(state))
        assertEquals("Connecting", npcStatusLabel(state.copy(isLoading = true)))
        assertEquals("Connected", npcStatusLabel(state.copy(isConnected = true)))
        assertEquals("Offline", npcStatusLabel(state.copy(errorMessage = "Offline")))
    }

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
    fun preferencesCopyMatchesIos() {
        assertEquals(
            "Incoming payments are minted as ecash at your chosen mint.",
            LightningAddressSettingsCopy.PreferencesFooter,
        )
        assertEquals("Receiving mint", LightningAddressSettingsCopy.ReceivingMintTitle)
        assertEquals("Select a mint", LightningAddressSettingsCopy.SelectMintFallback)
        assertEquals("Check for payments", LightningAddressSettingsCopy.CheckPaymentsTitle)
        assertEquals("Not checked yet", LightningAddressSettingsCopy.NeverCheckedCaption)
        assertEquals(
            "To check for payments, allow incoming invoice checks in Privacy settings.",
            LightningAddressSettingsCopy.ChecksOffFooter,
        )
    }

    @Test
    fun primarySettingsCopyDoesNotExposeImplementationTerms() {
        val primaryCopy = listOf(
            LightningAddressSettingsCopy.EnableTitle,
            LightningAddressSettingsCopy.EnableSubtitle,
            LightningAddressSettingsCopy.AutomaticClaimTitle,
            LightningAddressSettingsCopy.PreferencesFooter,
            LightningAddressSettingsCopy.ReceivingMintTitle,
            LightningAddressSettingsCopy.SelectMintFallback,
            LightningAddressSettingsCopy.CheckPaymentsTitle,
            LightningAddressSettingsCopy.NeverCheckedCaption,
            LightningAddressSettingsCopy.ChecksOffFooter,
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
