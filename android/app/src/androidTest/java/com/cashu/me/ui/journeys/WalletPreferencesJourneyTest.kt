package com.cashu.me.ui.journeys

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.Core.SettingsStore
import com.cashu.me.test.UiFailureArtifactsRule
import com.cashu.me.test.WalletJourneyRobot
import com.cashu.me.test.fixtures.AppTestFixture
import com.cashu.me.test.fixtures.FixtureMode
import com.cashu.me.test.fixtures.LaunchedFixture
import com.cashu.me.ui.testing.UiTestTags
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Production settings journeys; rates are injected at the service boundary. */
@RunWith(AndroidJUnit4::class)
class WalletPreferencesJourneyTest {
    @get:Rule(order = 0) val compose = createEmptyComposeRule()
    @get:Rule(order = 1) val artifacts = UiFailureArtifactsRule(compose) { fixture?.close() }
    private val robot by lazy { WalletJourneyRobot(compose) }
    private var fixture: LaunchedFixture? = null

    private fun settings(): LaunchedFixture = AppTestFixture.launch(FixtureMode.FundedWithHistory).also {
        fixture = it
        robot.awaitTag(UiTestTags.WalletScreen).tapDescription("Settings").awaitTag(UiTestTags.SettingsScreen)
    }

    @Test fun currencySelectionChangesRateAndPersistsWithoutChangingWalletFunds() {
        val app = settings()
        val originalBalance = app.container.walletManager.state.value.balance
        for ((code, rate) in listOf("EUR" to 80_000.0, "USD" to 100_000.0)) {
            robot.tapText("Currency").tapText(code).awaitTag(UiTestTags.SettingsScreen)
            compose.waitUntil { app.container.priceService.state.value.btcPrice == rate }
            assertEquals(code, app.container.settingsManager.state.value.bitcoinPriceCurrency)
            assertEquals(originalBalance, app.container.walletManager.state.value.balance)
            // A new store instance reads the persisted preference, not a ViewModel cache.
            val stored = SettingsStore(ApplicationProvider.getApplicationContext())
            assertTrue(stored.showFiatBalance)
            assertEquals(code, stored.bitcoinPriceCurrency)
            app.scenario.recreate()
            robot.awaitTag(UiTestTags.SettingsScreen).awaitText(code)
        }
        robot.tapText("Currency").tapText("Off").awaitTag(UiTestTags.SettingsScreen).awaitText("Off")
        assertFalse(SettingsStore(ApplicationProvider.getApplicationContext()).showFiatBalance)
        assertEquals(originalBalance, app.container.walletManager.state.value.balance)
    }

    @Test fun dismissCurrencyPickerPreservesSelection() {
        val app = settings()
        val before = app.container.settingsManager.state.value.bitcoinPriceCurrency
        robot.tapText("Currency").pressSystemBack().awaitTag(UiTestTags.SettingsScreen)
        assertEquals(before, app.container.settingsManager.state.value.bitcoinPriceCurrency)
    }

    @Test fun privacyDependenciesAndWebSocketsPersistIndependently() {
        val app = settings()
        robot.scrollToText(UiTestTags.SettingsList, "Privacy").tapText("Privacy")
        setSwitch("Check incoming invoice", false)
        compose.onNode(hasText("Check all invoices") and isToggleable()).assertIsNotEnabled()
        setSwitch("Check sent ecash", false)
        setSwitch("Use WebSockets", true)
        app.scenario.recreate()
        compose.onNode(hasText("Check incoming invoice") and isToggleable()).assertIsOff()
        compose.onNode(hasText("Check sent ecash") and isToggleable()).assertIsOff()
        compose.onNode(hasText("Use WebSockets") and isToggleable()).assertIsOn().assertIsEnabled()
        setSwitch("Check incoming invoice", true)
        compose.onNode(hasText("Check all invoices") and isToggleable()).assertIsEnabled()
    }

    @Test fun automaticReceiveRequiresListeningAndPreservesItsPreference() {
        settings()
        robot.scrollToText(UiTestTags.SettingsList, "Privacy").tapText("Privacy")
        setSwitch("Listen for payment requests", true)
        setSwitch("Claim received ecash automatically", true)
        setSwitch("Listen for payment requests", false)
        compose.onNode(hasText("Claim received ecash automatically") and isToggleable())
            .performScrollTo().assertIsNotEnabled().assertIsOn()
        setSwitch("Listen for payment requests", true)
        compose.onNode(hasText("Claim received ecash automatically") and isToggleable()).assertIsEnabled().assertIsOn()
    }

    @Test fun walletConnectWithoutMintExplainsRequirement() {
        fixture = AppTestFixture.launch(FixtureMode.SeededWithoutMint)
        robot.awaitTag(UiTestTags.WalletScreen).tapDescription("Settings")
            .scrollToText(UiTestTags.SettingsList, "Nostr").tapText("Nostr")
        compose.onNodeWithText("Wallet Connect").performScrollTo().performClick()
        robot.awaitText("Add a mint first to use Wallet Connect.")
        compose.onNode(hasText("Enable Wallet Connect") and isToggleable()).assertIsNotEnabled()
    }

    private fun setSwitch(label: String, on: Boolean) {
        val node = compose.onNode(hasText(label) and isToggleable())
        node.performScrollTo()
        val expected = if (on) isOn() else isOff()
        if (!expected.matches(node.fetchSemanticsNode())) node.performClick()
        node.assert(expected)
    }
}
