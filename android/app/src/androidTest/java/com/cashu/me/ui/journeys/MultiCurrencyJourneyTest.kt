package com.cashu.me.ui.journeys

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.test.UiFailureArtifactsRule
import com.cashu.me.test.WalletJourneyRobot
import com.cashu.me.test.fixtures.*
import com.cashu.me.ui.testing.UiTestTags
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MultiCurrencyJourneyTest {
    @get:Rule(order = 0) val compose = createEmptyComposeRule()
    @get:Rule(order = 1) val artifacts = UiFailureArtifactsRule(compose) { fixture?.close() }
    private val robot by lazy { WalletJourneyRobot(compose) }
    private var fixture: LaunchedFixture? = null

    @Test fun usdSendUsesCentsAndLeavesSatAccountUnchanged() {
        val app = AppTestFixture.launch(FixtureMode.FundedWithHistory, supportedUnits = listOf("sat", "usd", "eur"))
        fixture = app
        val fake = app.fakeGateway!!
        runBlocking {
            fake.ensureWallet(FakeWalletGateway.TestMintUrl, "usd")
            fake.setUnitBalance(FakeWalletGateway.TestMintUrl, "usd", 1000)
            app.container.walletManager.refreshBalance()
        }
        robot.awaitTag(UiTestTags.WalletScreen).tapTag(UiTestTags.WalletSend)
            .tapDescription("Ecash. Create ecash").tapText("SAT").tapText("USD")
            .tapDescription("2").tapDescription("Decimal point").tapDescription("5").tapDescription("0")
            // An extra fraction digit must not silently turn $2.50 into $25.09.
            .tapDescription("9").tapText("USD")
        compose.onNode(hasText("USD") and hasText("US Dollar")).performClick()
        robot.tapTag(UiTestTags.SendEcashSubmit).awaitText("Pending Ecash")
        assertEquals("usd", fake.lastSentUnit)
        assertEquals(250L, fake.lastSentAmount)
        assertEquals(749L, runBlocking { fake.unitBalance(FakeWalletGateway.TestMintUrl, "usd") })
        assertEquals(500L, runBlocking { fake.totalBalance(FakeWalletGateway.TestMintUrl) })
    }

    @Test fun selectedDefaultMintIsUsedByNextSendAndSurvivesRecreation() {
        val app = AppTestFixture.launch(FixtureMode.FundedWithHistory)
        fixture = app
        val fake = app.fakeGateway!!
        robot.awaitTag(UiTestTags.WalletScreen).tapText("Mints").tapDescription("Add mint")
            .typeIntoTag(UiTestTags.AddMintUrl, SecondMint).tapTag(UiTestTags.AddMintSubmit)
            .awaitTag(UiTestTags.mintRow(SecondMint))
        runBlocking { fake.setBalance(SecondMint, 200); app.container.walletManager.refreshBalance() }
        robot.tapTag(UiTestTags.mintRow(SecondMint)).scrollToText(UiTestTags.MintDetailContent, "Set as Default")
            .tapText("Set as Default")
        compose.waitUntil { app.container.walletManager.state.value.activeMint?.url == SecondMint }
        app.scenario.recreate()
        robot.awaitTag(UiTestTags.MintDetailScreen).tapDescription("Back").tapText("Wallet")
            .tapTag(UiTestTags.WalletSend).tapDescription("Ecash. Create ecash")
            .tapDescription("2").tapDescription("5").tapTag(UiTestTags.SendEcashSubmit).awaitText("Pending Ecash")
        assertEquals(SecondMint, fake.lastSentMint)
        assertEquals(174L, runBlocking { fake.totalBalance(SecondMint) })
        assertEquals(500L, runBlocking { fake.totalBalance(FakeWalletGateway.TestMintUrl) })
    }

    companion object { private const val SecondMint = "https://second.test" }
}
