package com.cashu.me.ui.journeys

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
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
        val copyBounds = compose.onNodeWithText("Copy").getUnclippedBoundsInRoot()
        val newBounds = compose.onNodeWithText("New Request").getUnclippedBoundsInRoot()
        val fontScale = InstrumentationRegistry.getInstrumentation().targetContext.resources.configuration.fontScale
        if (fontScale > 1.3f) {
            assertTrue("Large text actions must stack", newBounds.top >= copyBounds.bottom)
        } else {
            assertEquals(copyBounds.top.value, newBounds.top.value, 1f)
            assertEquals((copyBounds.bottom - copyBounds.top).value, (newBounds.bottom - newBounds.top).value, 1f)
            assertEquals((copyBounds.right - copyBounds.left).value, (newBounds.right - newBounds.left).value, 1f)
        }
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText("New Request", useUnmergedTree = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertEquals(1, layouts.single().lineCount)
        val labelLayout = layouts.single()
        assertTrue(!labelLayout.isLineEllipsized(0))
        assertEquals("New Request".length, labelLayout.getLineEnd(0))
        // Text layout rounds its measured size to pixels; allow that rounding,
        // while still detecting a truncated label or a clipped line box.
        val lineWidth = labelLayout.getLineRight(0) - labelLayout.getLineLeft(0)
        assertTrue("Label width $lineWidth exceeds ${labelLayout.size.width}",
            lineWidth <= labelLayout.size.width + 1f)
        assertTrue("Label height ${labelLayout.getLineBottom(0)} exceeds ${labelLayout.size.height}",
            labelLayout.getLineBottom(0) <= labelLayout.size.height + 1f)
        screenshot("activity-cashu")
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

    @Test fun requestTotalsAndEditableAmountRespectTheirCurrency() {
        launched = AppTestFixture.launch(FixtureMode.SeededWithMint)
        val fixture = launched!!
        val store = fixture.container.cashuRequestStore
        robot.awaitTag(UiTestTags.WalletScreen).tapText("History").awaitTag(UiTestTags.HistoryScreen)
        for (unit in listOf("sat", "usd")) {
            val request = store.createNew(id = "parity-$unit", unit = unit,
                mints = listOf("https://mint.example"), memo = "Coffee tips", encoded = "creqAfixture")
            store.attachPayment(request.id, "payment-$unit-1", 1200)
            store.attachPayment(request.id, "payment-$unit-2", 34)
            robot.tapText("Cashu Request").awaitText("2 payments received")
            compose.onNodeWithText("Total received").performScrollTo().assertIsDisplayed()
            compose.onNodeWithText(if (unit == "sat") "₿1,234" else "$12.34").assertIsDisplayed()
            compose.onNodeWithText("mint.example").assertIsDisplayed()
            screenshot("activity-cashu-$unit-received")
            robot.pressSystemBack().awaitTag(UiTestTags.HistoryScreen)
            compose.runOnIdle { store.delete(request.id) }
        }
        store.createNew(id = "parity-fixed", amount = 2100,
            mints = listOf(FakeWalletGateway.TestMintUrl), encoded = "creqAfixture")
        robot.tapText("Cashu Request").awaitText("New Request")
        compose.onNode(hasText("Amount").and(hasText("₿2,100"))).assertExists()
        compose.runOnIdle { fixture.container.settingsManager.setUseBitcoinSymbol(false) }
        compose.onNode(hasText("Amount").and(hasText("2,100 sat"))).assertExists()
        compose.onNodeWithText("Total received").assertDoesNotExist()
    }

    @Test fun changingMintCurrencyShowsNewRequestAndPreservesOldTotal() {
        launched = AppTestFixture.launch(FixtureMode.SeededWithMint)
        val fixture = launched!!
        val store = fixture.container.cashuRequestStore
        robot.awaitTag(UiTestTags.WalletScreen)
        val original = store.createNew(id = "usd-request", amount = 500, unit = "usd",
            mints = listOf("https://usd.example"), memo = "Coffee", encoded = "creqAoriginal")
        store.attachPayment(original.id, "first", 1200)
        store.attachPayment(original.id, "second", 34)
        robot.tapText("History").tapText("Cashu Request").awaitText("2 payments received")
        compose.onNodeWithText("Mint").performScrollTo().performClick()
        robot.tapText("Nutshell UI Test Mint").awaitText("Waiting for payment…")
        compose.onNodeWithText("Total received").assertDoesNotExist()
        compose.onNodeWithText("SAT").assertIsDisplayed()
        compose.onNode(hasText("Amount").and(hasText("Any"))).assertExists()
        val next = checkNotNull(store.state.value.currentRequest)
        assertTrue(next.id != original.id)
        assertEquals("sat", next.unit)
        assertEquals(0L, next.totalReceived)
        assertEquals("usd", store.request(original.id)?.unit)
        assertEquals(1234L, store.request(original.id)?.totalReceived)
        screenshot("request-after-currency-change")
        // A payment to the previous code must not trigger success on this sheet.
        compose.runOnIdle { store.attachPayment(original.id, "late", 10) }
        robot.awaitText("Waiting for payment…")
        compose.runOnIdle { store.attachPayment(next.id, "new", 21) }
        robot.awaitText("Payment Received!")
    }

    @Test fun pasteRemainsAvailableWithEmptyClipboard() {
        launched = AppTestFixture.launch(FixtureMode.SeededWithMint)
        robot.awaitTag(UiTestTags.WalletScreen)
        compose.runOnIdle {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            context.getSystemService(android.content.ClipboardManager::class.java).clearPrimaryClip()
        }
        robot.tapTag(UiTestTags.WalletReceive).awaitTag(UiTestTags.ReceiveSheet)
        compose.onNodeWithText("Paste").assertIsDisplayed().performClick()
        compose.onNodeWithText("Paste").assertIsDisplayed()
        compose.onNodeWithContentDescription("Clear").assertDoesNotExist()
        screenshot("receive-empty-clipboard")
    }

    @Test fun captureMainScreensAndReceiptStates() {
        launched = AppTestFixture.launch(FixtureMode.SeededWithMint)
        val fixture = launched!!
        robot.awaitTag(UiTestTags.WalletScreen)
        screenshot("wallet")
        robot.tapTag(UiTestTags.WalletSend).awaitTag(UiTestTags.SendSheet)
        screenshot("send-options")
        robot.pressSystemBack().tapTag(UiTestTags.WalletReceive).awaitTag(UiTestTags.ReceiveSheet)
        screenshot("receive-options")
        robot.pressSystemBack().tapDescription("Settings").awaitTag(UiTestTags.SettingsScreen)
        screenshot("settings")
        robot.pressSystemBack().tapText("Mints").awaitTag(UiTestTags.MintsScreen)
        screenshot("mints")
        robot.tapText("History").awaitTag(UiTestTags.HistoryScreen)
        screenshot("history-empty")
        for ((id, kind, type) in listOf(
            Triple("paid-lightning", TransactionKind.Lightning, TransactionType.Incoming),
            Triple("sent-lightning", TransactionKind.Lightning, TransactionType.Outgoing),
            Triple("received-ecash", TransactionKind.Ecash, TransactionType.Incoming),
            Triple("received-bitcoin", TransactionKind.Onchain, TransactionType.Incoming),
        )) {
            val tx = WalletTransaction(id = id, amount = 2100, kind = kind, type = type,
                dateEpochMillis = 1_788_768_000_000, status = TransactionStatus.Completed,
                mintUrl = "https://mint.example",
                memo = if (id == "paid-lightning") "Coffee payment" else null,
                invoice = when (id) {
                    "paid-lightning" -> "lnbc1test"
                    "received-bitcoin" -> "bc1qfixture"
                    else -> null
                },
                preimage = if (id == "sent-lightning" || id == "received-bitcoin")
                    "0123456789abcdef0123456789abcdef" else null,
                token = if (id == "received-ecash") "cashu-token" else null,
                fee = if (id == "sent-lightning") 2L else 0L,
            )
            fixture.fakeGateway!!.addTransaction(tx)
            runBlocking { fixture.container.walletManager.loadTransactions() }
            val title = when (id) {
                "paid-lightning" -> "Lightning received"
                "sent-lightning" -> "Lightning paid"
                "received-ecash" -> "Ecash received"
                else -> "Bitcoin received"
            }
            robot.tapText(title).awaitTag(UiTestTags.TransactionReceiptSheet)
            screenshot(id)
            robot.pressSystemBack().awaitTag(UiTestTags.HistoryScreen)
        }
    }

    private fun screenshot(name: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        checkNotNull(instrumentation.uiAutomation.takeScreenshot()).writeToTestStorage(name)
    }
}
