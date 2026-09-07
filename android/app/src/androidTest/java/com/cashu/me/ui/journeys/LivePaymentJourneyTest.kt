package com.cashu.me.ui.journeys

import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import com.cashu.me.liveintegration.PaymentFixtureTest
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.test.UiFailureArtifactsRule
import com.cashu.me.test.WalletJourneyRobot
import com.cashu.me.test.fixtures.AppTestFixture
import com.cashu.me.test.fixtures.FixtureMode
import com.cashu.me.test.fixtures.LaunchedFixture
import com.cashu.me.ui.testing.UiTestTags
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class LivePaymentJourneyTest : PaymentFixtureTest() {
    @get:Rule(order = 0) val compose = createEmptyComposeRule()
    @get:Rule(order = 1) val artifacts = UiFailureArtifactsRule(compose) { launched?.close() }
    private val robot by lazy { WalletJourneyRobot(compose) }
    private var launched: LaunchedFixture? = null

    @Test fun cdkReceivePayAndReopenHistory() = receivePayAndReopen("cdk")
    @Test fun nutshellReceivePayAndReopenHistory() = receivePayAndReopen("nutshell")

    private fun receivePayAndReopen(mint: String) {
        val fixture = AppTestFixture.launch(FixtureMode.LivePayments, paymentMintUrl = mintUrl(mint))
        launched = fixture
        robot.awaitTag(UiTestTags.WalletScreen)
            .tapTag(UiTestTags.WalletReceive)
            .tapDescription("Bitcoin. Receive over Lightning or on-chain")
            .awaitTag(UiTestTags.ReceiveLightningScreen)
            .tapDescription("1").tapDescription("0").tapDescription("0")
            .tapTextWithinTag(UiTestTags.ReceiveLightningScreen, "Create invoice")
            .awaitText("Payment Received!", timeoutMillis = 30_000)
            .tapText("Done")
            .awaitTag(UiTestTags.WalletScreen)
        val manager = fixture.container.walletManager
        assertEquals(100L, manager.state.value.balance)
        robot.tapTag(UiTestTags.WalletSend)
            .awaitTag(UiTestTags.SendSheet)
            .typeIntoTag(UiTestTags.SendDestination, invoice())
            .awaitTag(UiTestTags.SendPaymentSubmit)
            .tapTag(UiTestTags.SendPaymentSubmit)
            .awaitText("Payment sent", timeoutMillis = 30_000)
        val payment = manager.state.value.transactions.single {
            it.type == TransactionType.Outgoing && it.kind == TransactionKind.Lightning
        }
        assertEquals(TransactionStatus.Completed, payment.status)
        assertEquals(21L, payment.amount)
        assertEquals(100L - 21 - payment.fee, manager.state.value.balance)
        robot.tapText("Done").awaitTag(UiTestTags.WalletScreen).tapText("History")
            .awaitTag(UiTestTags.transactionRow(payment.id))
        fixture.scenario.recreate()
        robot.awaitTag(UiTestTags.HistoryScreen).awaitTag(UiTestTags.transactionRow(payment.id))
    }
}
