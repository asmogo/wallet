package com.cashu.me.ui.journeys

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
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

    @Test fun receiptStartsCollapsedAndRetiresCodeWhenPaymentSettles() {
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
        compose.onNodeWithText("Status").assertIsDisplayed()
        compose.onNodeWithText("Date").assertIsDisplayed()
        compose.onNodeWithContentDescription("Close").assertDoesNotExist()
        compose.onNodeWithContentDescription("QR code. Long press for copy and share options.").assertDoesNotExist()
        screenshot("activity-pending")
        compose.onNodeWithText("Show QR code").performScrollTo().performClick()
        compose.onNodeWithText("Hide QR code").assertIsDisplayed()
        compose.onNodeWithContentDescription("QR code. Long press for copy and share options.")
            .performScrollTo().assertIsDisplayed()
        fixture.fakeGateway!!.addTransaction(tx.copy(status = TransactionStatus.Completed, isUnpaidInvoice = false))
        runBlocking { fixture.container.walletManager.loadTransactions() }
        robot.awaitText("Paid")
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
        robot.tapText("History").tapText("Reusable Invoice").awaitText("Active")
        compose.onNodeWithText("Status").assertIsDisplayed()
        compose.onNodeWithText("Date").assertIsDisplayed()
        compose.onNodeWithText("Total received").assertIsDisplayed()
        compose.onNodeWithContentDescription("Close").assertDoesNotExist()
        screenshot("activity-reusable")
        compose.onNodeWithText("Show QR code").performScrollTo().performClick()
        compose.onNodeWithContentDescription("QR code. Long press for copy and share options.")
            .performScrollTo().assertIsDisplayed()
        robot.pressSystemBack().awaitTag(UiTestTags.HistoryScreen)
    }

    private fun screenshot(name: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        checkNotNull(instrumentation.uiAutomation.takeScreenshot()).writeToTestStorage(name)
    }
}
