package com.cashu.me.ui.journeys

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.Core.NPCQuote
import com.cashu.me.test.UiFailureArtifactsRule
import com.cashu.me.test.WalletJourneyRobot
import com.cashu.me.test.fixtures.*
import com.cashu.me.ui.testing.UiTestTags
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AdvancedSettingsJourneyTest {
    @get:Rule(order = 0) val compose = createEmptyComposeRule()
    @get:Rule(order = 1) val artifacts = UiFailureArtifactsRule(compose) { fixture?.close() }
    private val robot by lazy { WalletJourneyRobot(compose) }
    private var fixture: LaunchedFixture? = null

    private fun nostr(): LaunchedFixture = AppTestFixture.launch(FixtureMode.SeededWithMint).also {
        fixture = it
        robot.awaitTag(UiTestTags.WalletScreen).tapDescription("Settings")
            .scrollToText(UiTestTags.SettingsList, "Nostr").tapText("Nostr")
    }

    @Test fun walletConnectLimitAndResetHavePersistentEffects() {
        val app = nostr()
        compose.onNodeWithText("Wallet Connect").performScrollTo().performClick()
        compose.onNode(hasText("Enable Wallet Connect") and isToggleable()).performClick()
        compose.waitUntil { app.container.nwcManager.state.value.isRunning }
        val original = checkNotNull(app.container.nwcManager.state.value.connectionUri)
        robot.awaitDescription("Copy connection code")
        compose.onNodeWithText("Payment limit").performScrollTo().performClick()
        compose.onNode(hasSetTextAction()).performTextReplacement("250")
        robot.tapText("Save")
        compose.waitUntil { app.container.nwcManager.state.value.budgetSats == 250L }
        app.scenario.recreate()
        robot.awaitDescription("Copy connection code")
        assertEquals(250L, app.container.nwcManager.state.value.budgetSats)
        compose.onNodeWithText("Reset connection").performScrollTo().performClick()
        robot.awaitText("Reset connection?").tapText("Cancel")
        assertEquals(original, app.container.nwcManager.state.value.connectionUri)
        compose.onNodeWithText("Reset connection").performScrollTo().performClick()
        robot.tapText("Delete")
        compose.waitUntil { app.container.nwcManager.state.value.connectionUri != original }
        assertEquals(250L, app.container.nwcManager.state.value.budgetSats)
        compose.onNode(hasText("Enable Wallet Connect") and isToggleable()).performScrollTo().performClick()
        compose.waitUntil { !app.container.nwcManager.state.value.isRunning }
        robot.assertTextDoesNotExist("Copy connection code")
    }

    @Test fun relayAddDuplicateAndRemovePersist() {
        val app = nostr()
        val before = app.container.settingsManager.state.value.nostrRelays
        val field = compose.onNode(hasSetTextAction())
        field.performScrollTo().performTextInput("wss://relay.test")
        robot.tapDescription("Add relay")
        compose.waitUntil { "wss://relay.test" in app.container.settingsManager.state.value.nostrRelays }
        field.performTextInput("wss://relay.test")
        robot.tapDescription("Add relay")
        assertEquals(1, app.container.settingsManager.state.value.nostrRelays.count { it == "wss://relay.test" })
        app.scenario.recreate()
        compose.onNodeWithText("wss://relay.test").performScrollTo().assertIsDisplayed()
        // The native relay list appends new entries; its unmerged remove icons
        // have the same label and the merged tree flattens all rows together.
        compose.onAllNodesWithContentDescription("Remove relay")
            .assertCountEquals(before.size + 1)[before.size].performClick()
        compose.waitUntil { app.container.settingsManager.state.value.nostrRelays == before }
    }

    @Test fun lightningAddressManualCheckClaimsPaymentOnlyOnce() {
        var quotes = emptyList<NPCQuote>()
        fixture = AppTestFixture.launch(FixtureMode.SeededWithMint, npcQuotes = { quotes })
        val app = fixture!!
        robot.awaitTag(UiTestTags.WalletScreen).tapDescription("Settings").tapText("Lightning")
        compose.onNode(hasText("Enable Lightning Address") and isToggleable()).performClick()
        compose.waitUntil { app.container.npcService.state.value.isConnected }
        compose.runOnIdle {
            quotes = listOf(NPCQuote(id = "address-payment", amount = 21,
                mintUrl = FakeWalletGateway.TestMintUrl, state = "PAID", locked = false,
                createdAtEpochSeconds = null, paidAtEpochSeconds = null))
        }
        compose.onNodeWithText("Check for payments").performScrollTo().performClick()
        compose.waitUntil(20_000) { app.container.walletManager.state.value.balance == 21L }
        compose.onNodeWithText("Check for payments").performScrollTo().performClick()
        compose.waitUntil { !app.container.npcService.state.value.isCheckingPayments }
        assertEquals(21L, app.container.walletManager.state.value.balance)
        compose.onNode(hasText("Enable Lightning Address") and isToggleable()).performScrollTo().performClick()
        compose.waitUntil { !app.container.npcService.state.value.isEnabled }
        app.scenario.recreate()
        compose.onNode(hasText("Enable Lightning Address") and isToggleable()).assertIsOff()
    }

    @Test fun cancellingNostrIdentityReplacementKeepsIdentity() {
        val app = nostr()
        val before = app.container.nostrService.state.value.publicKeyHex
        // The currently selected signer and the replacement confirmation remain native UI.
        compose.onNodeWithText("Generate new key").performScrollTo().performClick()
        robot.awaitText("Generate new key?").tapText("Cancel")
        assertEquals(before, app.container.nostrService.state.value.publicKeyHex)
    }
}
