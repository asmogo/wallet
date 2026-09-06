package com.cashu.me.ui.journeys

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performClick
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.core.graphics.writeToTestStorage
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
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ActivityDetailJourneyTest {
    @get:Rule(order = 0) val compose = createEmptyComposeRule()
    @get:Rule(order = 1) val artifacts = UiFailureArtifactsRule(compose) { launched?.close() }
    private var launched: LaunchedFixture? = null
    private val robot by lazy { WalletJourneyRobot(compose) }

    @Test fun receiptShowsCodeImmediatelyAndRetiresItWhenPaymentSettles() {
        launched = AppTestFixture.launch(FixtureMode.SeededWithMint)
        val fixture = launched!!
        robot.awaitTag(UiTestTags.WalletScreen)
        val tx = WalletTransaction(id = "activity-invoice", amount = 2100,
            type = TransactionType.Incoming, kind = TransactionKind.Lightning,
            dateEpochMillis = System.currentTimeMillis(), status = TransactionStatus.Pending,
            invoice = "lnbc1fixture", mintUrl = FakeWalletGateway.TestMintUrl, isUnpaidInvoice = true)
        fixture.fakeGateway!!.addTransaction(tx)
        runBlocking { fixture.container.walletManager.loadTransactions() }
        robot.tapText("History").tapText("Lightning invoice").awaitTag(UiTestTags.TransactionReceiptSheet)
        compose.onNodeWithText("Status").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Date").performScrollTo().assertIsDisplayed()
        compose.onNodeWithContentDescription("Close").assertDoesNotExist()
        compose.onNodeWithContentDescription("Share").assertIsDisplayed()
        screenshot("activity-pending")
        compose.onNodeWithContentDescription("QR code. Long press for copy and share options.")
            .performScrollTo().assertIsDisplayed()
        fixture.fakeGateway!!.addTransaction(tx.copy(status = TransactionStatus.Completed, isUnpaidInvoice = false))
        runBlocking { fixture.container.walletManager.loadTransactions() }
        robot.awaitText("Paid")
        compose.onNodeWithContentDescription("Completed").assertIsDisplayed()
        compose.onNodeWithContentDescription("Share").assertDoesNotExist()
        compose.onNodeWithText("Show QR code").assertDoesNotExist()
        compose.onNodeWithText("Hide QR code").assertDoesNotExist()
        compose.onNodeWithContentDescription("QR code. Long press for copy and share options.").assertDoesNotExist()
        robot.pressSystemBack().awaitTag(UiTestTags.HistoryScreen)
    }

    @Test fun reusableInvoiceUsesSameSheetAndKeepsCodeAfterPayment() {
        launched = AppTestFixture.launch(FixtureMode.SeededWithMint)
        val fixture = launched!!
        robot.awaitTag(UiTestTags.WalletScreen)
        fixture.container.cashuRequestStore.upsertQuoteIntent(
            quoteId = "activity-offer", quoteKind = "bolt12", amount = null,
            mints = listOf(FakeWalletGateway.TestMintUrl), memo = "Coffee tips", encoded = "lno1fixture")
        fixture.fakeGateway!!.addTransaction(WalletTransaction(id = "activity-payment", amount = 2100,
            type = TransactionType.Incoming, kind = TransactionKind.Lightning,
            dateEpochMillis = System.currentTimeMillis(), status = TransactionStatus.Completed,
            mintUrl = FakeWalletGateway.TestMintUrl, quoteId = "activity-offer"))
        runBlocking { fixture.container.walletManager.loadTransactions() }
        robot.tapText("History").tapText("Reusable Invoice").awaitText("1 payment received")
        compose.onNodeWithText("Created").performScrollTo().assertIsDisplayed()
        compose.onNodeWithContentDescription("Share").assertIsDisplayed()
        compose.onNodeWithText("New Request").assertDoesNotExist()
        compose.onNodeWithText("Total received").assertIsDisplayed()
        compose.onNodeWithContentDescription("Close").assertDoesNotExist()
        screenshot("activity-reusable")
        compose.onNodeWithContentDescription("QR code. Long press for copy and share options.")
            .performScrollTo().assertIsDisplayed()
        robot.pressSystemBack().awaitTag(UiTestTags.HistoryScreen)
    }

    @Test fun cashuRequestKeepsInlineEditingAndNewRequest() {
        launched = AppTestFixture.launch(FixtureMode.SeededWithMint)
        val fixture = launched!!
        robot.awaitTag(UiTestTags.WalletScreen)
        val original = fixture.container.cashuRequestStore.createNew(
            id = "activity-request", mints = listOf(FakeWalletGateway.TestMintUrl),
            memo = "Coffee tips", encoded = "creqAfixture")
        robot.tapText("History").tapText("Cashu Request").awaitText("New Request")
        compose.onNodeWithContentDescription("Close").assertDoesNotExist()
        compose.onNodeWithContentDescription("Share").assertIsDisplayed()
        compose.onNodeWithText("Copy").assertIsDisplayed()
        compose.onNodeWithText("New Request").assertIsDisplayed().performClick()
        compose.waitUntil(5_000) {
            fixture.container.cashuRequestStore.request(original.id)?.encoded != original.encoded
        }
        val updated = checkNotNull(fixture.container.cashuRequestStore.request(original.id))
        assertTrue(updated.encoded.startsWith("creqA"))
        assertEquals(original.memo, updated.memo)
        assertEquals(original.mints, updated.mints)
        assertEquals(1, fixture.container.cashuRequestStore.state.value.requests.size)
        compose.onNodeWithText("Amount").performScrollTo().performClick()
        robot.awaitText("Done").pressSystemBack().awaitText("New Request")
        robot.pressSystemBack().awaitTag(UiTestTags.HistoryScreen)
    }

    @Test fun failedPaymentKeepsRedFailureGlyph() {
        launched = AppTestFixture.launch(FixtureMode.SeededWithMint)
        val fixture = launched!!
        robot.awaitTag(UiTestTags.WalletScreen)
        fixture.fakeGateway!!.addTransaction(WalletTransaction(
            id = "activity-failed", amount = 2100, type = TransactionType.Outgoing,
            kind = TransactionKind.Lightning, dateEpochMillis = System.currentTimeMillis(),
            status = TransactionStatus.Failed, mintUrl = FakeWalletGateway.TestMintUrl))
        runBlocking { fixture.container.walletManager.loadTransactions() }
        robot.tapText("History").tapText("Lightning paid").awaitTag(UiTestTags.TransactionReceiptSheet)
        compose.onNodeWithContentDescription("Failed").assertIsDisplayed()
        compose.onNodeWithText("Failed").assertIsDisplayed()
    }

    private fun screenshot(name: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        checkNotNull(instrumentation.uiAutomation.takeScreenshot()).writeToTestStorage(name)
    }
}
