package com.cashu.me.ui.journeys

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.Models.PaymentMethodKind
import com.cashu.me.test.UiFailureArtifactsRule
import com.cashu.me.test.WalletJourneyRobot
import com.cashu.me.test.fixtures.AppTestFixture
import com.cashu.me.test.fixtures.FakeWalletGateway
import com.cashu.me.test.fixtures.FixtureMode
import com.cashu.me.test.fixtures.LaunchedFixture
import com.cashu.me.ui.testing.UiTestTags
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReusableReceiveJourneyTest {
    @get:Rule(order = 0) val compose = createEmptyComposeRule()
    @get:Rule(order = 1) val artifacts = UiFailureArtifactsRule(compose) { launched?.close() }
    private var launched: LaunchedFixture? = null
    private val robot by lazy { WalletJourneyRobot(compose) }

    @Test fun cashuRequestReturnsToSameQRAfterEachPayment() = verifySavedRequest(quoteKind = null)

    @Test fun savedBolt12ReturnsToSameQRAfterEachPayment() = verifySavedRequest(quoteKind = "bolt12")

    private fun verifySavedRequest(quoteKind: String?) {
        launched = AppTestFixture.launch(FixtureMode.SeededWithMint)
        val store = launched!!.container.cashuRequestStore
        robot.awaitTag(UiTestTags.WalletScreen)
        val request = if (quoteKind == null) {
            store.createNew(encoded = "creqAreusable", mints = listOf(FakeWalletGateway.TestMintUrl))
        } else {
            store.upsertQuoteIntent(
                quoteId = "saved-offer", quoteKind = quoteKind, amount = null,
                encoded = "lno1reusable", mints = listOf(FakeWalletGateway.TestMintUrl),
            )
        }
        robot.tapText("History").tapText(request.displayTitle).awaitText("Copy")
        for (index in 1..2) {
            compose.runOnIdle { store.attachPayment(request.id, "payment-$index", 21) }
            robot.awaitText("Payment Received!").tapText("Done").awaitText("Copy")
            compose.onNodeWithText("Payment Received!").assertDoesNotExist()
            compose.onNodeWithContentDescription("QR code. Long press for copy and share options.")
                .performScrollTo().assertIsDisplayed()
            assertEquals(request.encoded, store.request(request.id)?.encoded)
            assertEquals(index, store.request(request.id)?.receivedPayments?.size)
        }
    }

    @Test fun newBolt12ShowsEachPaymentAmountAndKeepsItsOffer() {
        launched = AppTestFixture.launch(
            FixtureMode.SeededWithMint,
            supportedMintMethods = listOf(PaymentMethodKind.Bolt11, PaymentMethodKind.Bolt12),
        )
        val fixture = launched!!
        val fake = fixture.fakeGateway!!
        robot.awaitTag(UiTestTags.WalletScreen).tapTag(UiTestTags.WalletReceive)
            .tapDescription("Bitcoin. Receive over Lightning or on-chain")
            .tapDescription("Receive method: Lightning invoice, One-time, instant")
            .tapText("Reusable invoice").awaitText("Copy invoice")
        val quoteId = checkNotNull(fake.latestMintQuoteId)
        val original = runBlocking { fake.checkMintQuote(quoteId) }.request
        for (total in listOf(21L, 42L)) {
            compose.runOnIdle { fake.markMintQuotePaid(quoteId, amountPaid = total) }
            robot.awaitText("Payment Received!", timeoutMillis = 20_000)
            compose.onNodeWithText("₿21").assertIsDisplayed()
            robot.tapText("Done").awaitText("Copy invoice")
            compose.onNodeWithText("Payment Received!").assertDoesNotExist()
            assertEquals(quoteId, fake.latestMintQuoteId)
            assertEquals(original, runBlocking { fake.checkMintQuote(quoteId) }.request)
            assertEquals(total, runBlocking { fake.totalBalance(FakeWalletGateway.TestMintUrl) })
        }
    }
}
