package com.cashu.me.ui.journeys

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
class MintSafetyJourneyTest {
    @get:Rule(order = 0) val compose = createEmptyComposeRule()
    @get:Rule(order = 1) val artifacts = UiFailureArtifactsRule(compose) { fixture?.close() }
    private val robot by lazy { WalletJourneyRobot(compose) }
    private var fixture: LaunchedFixture? = null

    private fun launch(mode: FixtureMode = FixtureMode.SeededWithMint): LaunchedFixture =
        AppTestFixture.launch(mode).also {
            fixture = it
            robot.awaitTag(UiTestTags.WalletScreen).tapText("Mints")
        }

    @Test fun invalidMintCanBeCorrectedWithoutLeavingSheet() {
        val app = launch()
        robot.tapDescription("Add mint").typeIntoTag(UiTestTags.AddMintUrl, "http://unsafe.example")
            .tapTag(UiTestTags.AddMintSubmit)
            .awaitText("That doesn't look like a mint address.", substring = true)
        assertEquals(1, app.container.walletManager.state.value.mints.size)
        robot.replaceTextInTag(UiTestTags.AddMintUrl, SecondMint).tapTag(UiTestTags.AddMintSubmit)
            .awaitTag(UiTestTags.mintRow(SecondMint))
        assertEquals(2, app.container.walletManager.state.value.mints.size)
    }

    @Test fun duplicateWithTrailingSlashDoesNotCreateAnotherMint() {
        val app = launch()
        robot.tapDescription("Add mint").typeIntoTag(UiTestTags.AddMintUrl, FakeWalletGateway.TestMintUrl + "/")
            .tapTag(UiTestTags.AddMintSubmit).awaitText("Mint already exists.")
        assertEquals(1, app.container.walletManager.state.value.mints.size)
        robot.pressSystemBack().awaitTag(UiTestTags.mintRow(FakeWalletGateway.TestMintUrl))
    }

    @Test fun removingLastMintReturnsToUsableEmptyWalletAfterRecreation() {
        val app = launch()
        openRemoval()
        robot.tapText("Remove").awaitTag(UiTestTags.MintsScreen)
            .assertTagDoesNotExist(UiTestTags.mintRow(FakeWalletGateway.TestMintUrl))
        assertTrue(app.container.walletManager.state.value.mints.isEmpty())
        assertNull(app.container.walletManager.state.value.activeMint)
        app.scenario.recreate()
        robot.awaitTag(UiTestTags.MintsScreen).tapText("Wallet").awaitText("Add a mint to get started")
            .tapTag(UiTestTags.WalletSend).awaitTag(UiTestTags.ConnectMintSheet)
    }

    @Test fun cancellingFundedMintRemovalPreservesFundsAndDefault() {
        val app = launch(FixtureMode.FundedWithHistory)
        openRemoval()
        robot.tapText("Cancel").awaitTag(UiTestTags.MintDetailScreen)
        assertEquals(500L, app.container.walletManager.state.value.balance)
        assertEquals(FakeWalletGateway.TestMintUrl, app.container.walletManager.state.value.activeMint?.url)
    }

    @Test fun multiUnitRemovalRefusalKeepsMintAndBalance() {
        val app = launch(FixtureMode.FundedWithHistory)
        runBlocking { checkNotNull(app.fakeGateway).ensureWallet(FakeWalletGateway.TestMintUrl, "eur") }
        openRemoval()
        robot.tapText("Remove").awaitTag(UiTestTags.MintDetailScreen)
        // Wait for the operation's visible failure before checking retained state.
        robot.awaitText("multiple currency units", substring = true)
        assertEquals(500L, app.container.walletManager.state.value.balance)
        assertEquals(1, app.container.walletManager.state.value.mints.size)
        robot.tapDescription("Back").awaitTag(UiTestTags.mintRow(FakeWalletGateway.TestMintUrl))
    }

    private fun openRemoval() {
        robot.tapTag(UiTestTags.mintRow(FakeWalletGateway.TestMintUrl))
            .scrollToText(UiTestTags.MintDetailContent, "Remove mint").tapText("Remove mint")
            .awaitText("Remove mint?")
    }

    companion object { private const val SecondMint = "https://second.test" }
}
