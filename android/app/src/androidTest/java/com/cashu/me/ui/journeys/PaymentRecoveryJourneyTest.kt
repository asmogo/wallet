package com.cashu.me.ui.journeys

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.Models.*
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
class PaymentRecoveryJourneyTest {
    @get:Rule(order = 0) val compose = createEmptyComposeRule()
    @get:Rule(order = 1) val artifacts = UiFailureArtifactsRule(compose) { fixture?.close() }
    private val robot by lazy { WalletJourneyRobot(compose) }
    private var fixture: LaunchedFixture? = null

    private fun launch(mode: FixtureMode = FixtureMode.FundedWithHistory, token: String? = null): LaunchedFixture =
        AppTestFixture.launch(mode, deepLink = token?.let { "cashu:$it" }).also { fixture = it }

    @Test fun receiveLaterCanBeClaimedFromHistoryExactlyOnce() {
        val app = launch(FixtureMode.SeededWithMint, FakeWalletGateway.MemoDeterministicToken)
        robot.awaitTag(UiTestTags.ReceiveEcashDetail).tapText("Receive later").awaitTag(UiTestTags.WalletScreen)
        val pending = app.container.walletManager.state.value.pendingReceiveTokens.single()
        app.scenario.recreate()
        robot.awaitTag(UiTestTags.WalletScreen).tapText("History")
            .tapTag(UiTestTags.transactionRow(pending.tokenId)).tapText("Receive")
            .awaitTag(UiTestTags.ReceiveEcashDetail)
            .tapTextWithinTag(UiTestTags.ReceiveEcashDetail, "Receive").awaitText("Payment Received!")
            .tapText("Done").awaitTag(UiTestTags.HistoryScreen)
        compose.waitUntil { app.container.walletManager.state.value.pendingReceiveTokens.isEmpty() }
        assertEquals(25L, runBlocking { app.fakeGateway!!.totalBalance(FakeWalletGateway.TestMintUrl) })
        app.scenario.recreate()
        robot.awaitTag(UiTestTags.HistoryScreen)
        assertEquals(25L, app.container.walletManager.state.value.balance)
        assertTrue(app.container.walletManager.state.value.pendingReceiveTokens.isEmpty())
    }

    @Test fun editingAndCancellingEcashAmountDoesNotSpendFunds() {
        val app = launch()
        robot.awaitTag(UiTestTags.WalletScreen).tapTag(UiTestTags.WalletSend)
            .tapDescription("Ecash. Create ecash").awaitTag(UiTestTags.SendEcashScreen)
            .assertTagIsNotEnabled(UiTestTags.SendEcashSubmit)
            .tapDescription("2").tapDescription("5").tapDescription("Delete. Long press to clear.")
        compose.onNodeWithContentDescription("Delete. Long press to clear.", useUnmergedTree = true)
            .performTouchInput { longClick() }
        robot.assertTagIsNotEnabled(UiTestTags.SendEcashSubmit).tapDescription("9").tapDescription("9")
            .tapDescription("9").awaitText("Insufficient balance")
            .assertTagIsNotEnabled(UiTestTags.SendEcashSubmit).pressSystemBack()
        assertEquals(500L, app.container.walletManager.state.value.balance)
        assertEquals(2, app.container.walletManager.state.value.transactions.size)
    }

    @Test fun historyFilterAndSearchComposeAndCanBeCleared() {
        launch()
        robot.awaitTag(UiTestTags.WalletScreen).tapText("History").tapDescription("Filter transactions")
            .tapText("Pending").assertTagDoesNotExist(UiTestTags.transactionRow("fixture-incoming"))
            .tapDescription("Filter transactions").tapText("Completed")
            .awaitTag(UiTestTags.transactionRow("fixture-incoming"))
            .tapDescription("Search history").typeIntoTag(UiTestTags.HistorySearch, "deposit")
            .awaitTag(UiTestTags.transactionRow("fixture-incoming"))
            .assertTagDoesNotExist(UiTestTags.transactionRow("fixture-outgoing"))
            .tapDescription("Clear search").awaitTag(UiTestTags.transactionRow("fixture-outgoing"))
    }

    @Test fun manualSentTokenCheckDistinguishesPendingAndClaimed() {
        val app = launch()
        robot.awaitTag(UiTestTags.WalletScreen).tapDescription("Settings")
            .scrollToText(UiTestTags.SettingsList, "Privacy").tapText("Privacy")
        compose.onNode(hasText("Check sent ecash") and isToggleable()).performClick()
        robot.tapDescription("Back").tapDescription("Back").tapTag(UiTestTags.WalletSend)
            .tapDescription("Ecash. Create ecash").tapDescription("2").tapDescription("5")
            .tapTag(UiTestTags.SendEcashSubmit).awaitText("Pending Ecash")
            .tapText("Check Status")
        compose.waitUntil(20_000) {
            compose.onAllNodesWithText("This token has not been claimed yet.").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("This token has not been claimed yet.").performScrollTo().assertIsDisplayed()
        assertEquals(474L, app.container.walletManager.state.value.balance)
        compose.runOnIdle { app.fakeGateway!!.pendingSendClaimed = true }
        robot.tapText("Check Status")
        // The animated receipt title exposes its full text in the merged tree.
        compose.waitUntil(20_000) {
            compose.onAllNodesWithText("Claimed", substring = true).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("Claimed", substring = true).assertIsDisplayed()
        assertEquals(474L, app.container.walletManager.state.value.balance)
    }

    @Test fun backgroundDuringReceiveCreditsOnlyOnce() {
        val app = launch(FixtureMode.SeededWithMint)
        robot.awaitTag(UiTestTags.WalletScreen).tapTag(UiTestTags.WalletReceive)
            .tapDescription("Bitcoin. Receive over Lightning or on-chain")
            .tapDescription("2").tapText("Create invoice").awaitText("Lightning Invoice")
        val fake = app.fakeGateway!!
        compose.waitUntil { fake.latestMintQuoteId != null }
        app.scenario.moveToState(Lifecycle.State.CREATED)
        fake.markMintQuotePaid(checkNotNull(fake.latestMintQuoteId))
        app.scenario.moveToState(Lifecycle.State.RESUMED)
        robot.awaitText("Payment Received!", timeoutMillis = 20_000).tapText("Done")
            .awaitTag(UiTestTags.WalletScreen)
        assertEquals(2L, app.container.walletManager.state.value.balance)
        app.scenario.recreate()
        robot.awaitTag(UiTestTags.WalletScreen).tapText("History").awaitText("Lightning received")
        assertEquals(2L, app.container.walletManager.state.value.balance)
        assertEquals(1, app.container.walletManager.state.value.transactions.count { it.type == TransactionType.Incoming })
    }

    @Test fun onchainReceiveShowsAddressThenSettlesToHistory() {
        fixture = AppTestFixture.launch(FixtureMode.SeededWithMint,
            supportedMintMethods = listOf(PaymentMethodKind.Bolt11, PaymentMethodKind.Onchain))
        val app = fixture!!
        robot.awaitTag(UiTestTags.WalletScreen).tapTag(UiTestTags.WalletReceive)
            .tapDescription("Bitcoin. Receive over Lightning or on-chain")
            .tapDescription("Receive method: Lightning invoice, One-time, instant")
            .tapText("On-chain address").awaitText("Bitcoin Address")
        val fake = app.fakeGateway!!
        compose.waitUntil { fake.latestMintQuoteId != null }
        val quoteId = checkNotNull(fake.latestMintQuoteId)
        assertEquals(PaymentMethodKind.Onchain, runBlocking { fake.checkMintQuote(quoteId) }.paymentMethod)
        compose.runOnIdle { fake.markMintQuotePaid(quoteId, 21) }
        robot.awaitText("Payment Received!", timeoutMillis = 20_000).tapText("Done")
        assertEquals(21L, runBlocking { fake.totalBalance(FakeWalletGateway.TestMintUrl) })
    }
}
