package com.cashu.me.ui.journeys

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import com.cashu.me.test.UiFailureArtifactsRule
import com.cashu.me.test.WalletJourneyRobot
import com.cashu.me.test.fixtures.AppTestFixture
import com.cashu.me.test.fixtures.FakeWalletGateway
import com.cashu.me.test.fixtures.FixtureMode
import com.cashu.me.test.fixtures.LaunchedFixture
import com.cashu.me.ui.testing.UiTestTags
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Exercise the real history screens with deterministic settlement, without spending funds. */
@RunWith(AndroidJUnit4::class)
class HistoryDescriptionJourneyTest {
    @get:Rule(order = 0) val compose = createEmptyComposeRule()
    @get:Rule(order = 1) val artifacts = UiFailureArtifactsRule(compose) { launched?.close() }
    private var launched: LaunchedFixture? = null
    private val robot by lazy { WalletJourneyRobot(compose) }

    @Test fun paidRequestAndOutgoingInvoiceKeepDescriptionsInHistoryAndDetails() {
        launched = AppTestFixture.launch(FixtureMode.SeededWithMint)
        val fixture = launched!!
        robot.awaitTag(UiTestTags.WalletScreen)
        val description = "Coffee tips 🌱 " + "Thank you for supporting the cafe. ".repeat(12) + "End of description."
        val request = fixture.container.cashuRequestStore.upsertQuoteIntent(
            quoteId = "history-quote", quoteKind = "bolt12", amount = null,
            mints = listOf(FakeWalletGateway.TestMintUrl), memo = description, encoded = "lno1fixture",
        )
        val payment = WalletTransaction(id = "history-payment", amount = 21, type = TransactionType.Incoming,
            kind = TransactionKind.Lightning, dateEpochMillis = System.currentTimeMillis(),
            status = TransactionStatus.Completed, mintUrl = FakeWalletGateway.TestMintUrl, quoteId = "history-quote")
        fixture.fakeGateway!!.addTransaction(payment)
        fixture.fakeGateway!!.addTransaction(payment.copy(id = "history-outgoing", type = TransactionType.Outgoing,
            quoteId = "melt-quote", memo = "Outgoing coffee receipt"))
        runBlocking { fixture.container.walletManager.loadTransactions() }
        assertEquals(description, fixture.container.walletManager.state.value.transactions.first { it.id == payment.id }.memo)
        assertEquals(21L, fixture.container.cashuRequestStore.request(request.id)?.totalReceived)
        fixture.scenario.recreate()
        robot.awaitTag(UiTestTags.WalletScreen)
        compose.onNodeWithText(description, useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithText("Outgoing coffee receipt", useUnmergedTree = true).assertDoesNotExist()
        robot.tapText("History").awaitText("Reusable Invoice")
        compose.onNodeWithText(description, useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithText("Outgoing coffee receipt", useUnmergedTree = true).assertDoesNotExist()
        robot.tapDescription("Search history").typeIntoTag(UiTestTags.HistorySearch, "Coffee")
            .tapText("Reusable Invoice")
        val preview = compose.onNodeWithTag("payment-description-preview", useUnmergedTree = true)
        preview.assertIsDisplayed()
        robot.awaitText("Read more")
        val layouts = mutableListOf<TextLayoutResult>()
        preview.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertTrue("The visible preview must fit without scrolling",
            preview.fetchSemanticsNode().boundsInRoot.height >= layouts.single().size.height - 1)
        val initialBounds = preview.fetchSemanticsNode().boundsInRoot
        compose.onNodeWithText("Created", useUnmergedTree = true).performScrollTo().assertIsDisplayed()
        assertEquals("The description stays at the bottom while details scroll",
            initialBounds, preview.fetchSemanticsNode().boundsInRoot)
        robot.tapText("Read more")
        compose.onAllNodesWithText(description, useUnmergedTree = true).onLast().assertIsDisplayed()
        robot.tapText("Done")
        robot.awaitText("Description").pressSystemBack()
            .tapText("Lightning paid")
        compose.onNodeWithText("Outgoing coffee receipt", useUnmergedTree = true).assertIsDisplayed()
        robot.awaitText("Description")
    }
}
