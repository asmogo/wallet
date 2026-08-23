package com.cashu.me.ui.journeys

import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionType
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
class FunctionalWalletJourneyTest {
    @get:Rule(order = 0)
    val compose = createEmptyComposeRule()

    @get:Rule(order = 1)
    val failureArtifacts = UiFailureArtifactsRule(compose) { launched?.close() }

    private val robot by lazy { WalletJourneyRobot(compose) }
    private var launched: LaunchedFixture? = null

    @Test
    fun mintLifecycleOpenDuplicateRejectActivateAndRemove() {
        val fixture = launch(FixtureMode.SeededWithMint)

        robot.awaitTag(UiTestTags.WalletScreen)
            .tapText("Mints")
            .awaitTag(UiTestTags.MintsScreen)
            .tapTag(UiTestTags.mintRow(FakeWalletGateway.TestMintUrl))
            .awaitText("Default mint")
            .tapDescription("Back")
            .awaitTag(UiTestTags.MintsScreen)
            .tapDescription("Add mint")
            .awaitTag(UiTestTags.AddMintSheet)
            .typeIntoTag(UiTestTags.AddMintUrl, FakeWalletGateway.TestMintUrl)
            .tapTag(UiTestTags.AddMintSubmit)
            .awaitText("Mint already exists.")
            .pressSystemBack()
            .awaitTag(UiTestTags.MintsScreen)
            .tapDescription("Add mint")
            .replaceTextInTag(UiTestTags.AddMintUrl, SecondMintUrl)
            .tapTag(UiTestTags.AddMintSubmit)
            .awaitTag(UiTestTags.mintRow(SecondMintUrl))
            .tapTag(UiTestTags.mintRow(SecondMintUrl))
            .awaitTag(UiTestTags.MintDetailScreen)
            .scrollToText(UiTestTags.MintDetailContent, "Set as Default")
            .tapText("Set as Default")
        compose.waitUntil(WalletJourneyRobot.DefaultTimeout) {
            fixture.container.walletManager.state.value.activeMint?.url == SecondMintUrl
        }
        robot.scrollToText(UiTestTags.MintDetailContent, "Default mint")
            .awaitText("Default mint")
            .scrollToText(UiTestTags.MintDetailContent, "Remove mint")
            .tapText("Remove mint")
            .awaitText("Remove Test Mint?")
            .tapText("Remove")
            .awaitTag(UiTestTags.MintsScreen)
            .assertTagDoesNotExist(UiTestTags.mintRow(SecondMintUrl))
            .awaitTag(UiTestTags.mintRow(FakeWalletGateway.TestMintUrl))
    }

    @Test
    fun sendEcashReducesBalanceAndCreatesHistoryEntry() {
        val fixture = launch(FixtureMode.FundedWithHistory)
        val fake = checkNotNull(fixture.fakeGateway)

        robot.awaitTag(UiTestTags.WalletScreen)
            .tapTag(UiTestTags.WalletSend)
            .awaitTag(UiTestTags.SendSheet)
            .tapDescription("Create ecash")
            .awaitTag(UiTestTags.SendEcashScreen)
            .tapDescription("2")
            .tapDescription("5")
            .tapTextWithinTag(UiTestTags.SendEcashScreen, "Send")
            .awaitText("Pending Ecash")

        assertEquals(474L, runBlocking { fake.totalBalance(FakeWalletGateway.TestMintUrl) })
        val sentTransaction = checkNotNull(
            fixture.container.walletManager.state.value.transactions.firstOrNull {
                it.type == TransactionType.Outgoing && it.kind == TransactionKind.Ecash
            },
        )

        robot.pressSystemBack()
            .awaitTag(UiTestTags.WalletScreen)
            .tapText("History")
            .awaitTag(UiTestTags.HistoryScreen)
            .awaitTag(UiTestTags.transactionRow(sentTransaction.id))
    }

    @Test
    fun receiveEcashDeepLinkCompletesAndUpdatesBalanceAndHistory() {
        val fixture = launch(
            FixtureMode.SeededWithMint,
            deepLink = "cashu:${FakeWalletGateway.DeterministicToken}",
        )
        val fake = checkNotNull(fixture.fakeGateway)

        robot.awaitTag(UiTestTags.ReceiveEcashDetail)
            .awaitText("Receive Ecash")
            .tapTextWithinTag(UiTestTags.ReceiveEcashDetail, "Receive")
            .awaitText("Payment Received!")
            .tapText("Done")
            .awaitTag(UiTestTags.WalletScreen)
            .tapText("History")
            .awaitText("Ecash received")

        assertEquals(25L, runBlocking { fake.totalBalance(FakeWalletGateway.TestMintUrl) })
    }

    @Test
    fun receiveLaterMemoAppearsInHistoryAndLaterClaimReview() {
        val fixture = launch(
            FixtureMode.SeededWithMint,
            deepLink = "cashu:${FakeWalletGateway.MemoDeterministicToken}",
        )

        robot.awaitTag(UiTestTags.ReceiveEcashDetail)
            .awaitTextWithinTag(UiTestTags.ReceiveEcashDetail, "Memo")
            .awaitTextWithinTag(UiTestTags.ReceiveEcashDetail, "Coffee from Alice")
            .tapTextWithinTag(UiTestTags.ReceiveEcashDetail, "Receive later")
            .awaitTag(UiTestTags.WalletScreen)

        val pending = fixture.container.walletManager.state.value.pendingReceiveTokens.single()
        assertEquals("Coffee from Alice", pending.memo)

        robot.tapText("History")
            .awaitTag(UiTestTags.HistoryScreen)
            .tapTag(UiTestTags.transactionRow(pending.tokenId))
            .awaitText("Memo")
            .awaitText("Coffee from Alice")
            .tapText("Receive")
            .awaitTag(UiTestTags.ReceiveEcashDetail)
            .awaitTextWithinTag(UiTestTags.ReceiveEcashDetail, "Memo")
            .awaitTextWithinTag(UiTestTags.ReceiveEcashDetail, "Coffee from Alice")
    }

    @Test
    fun unknownMintReceiveShowsWarningAndClaimsOnReceive() {
        val fixture = launch(
            FixtureMode.SeededWithMint,
            deepLink = "cashu:${FakeWalletGateway.UnknownMintDeterministicToken}",
        )
        val fake = checkNotNull(fixture.fakeGateway)

        robot.awaitTag(UiTestTags.ReceiveEcashDetail)
            .awaitText("New mint: mint.minibits.cash")
            .tapTextWithinTag(UiTestTags.ReceiveEcashDetail, "Receive")
            .awaitText("Payment Received!")
            .tapText("Done")
            .awaitTag(UiTestTags.WalletScreen)

        assertEquals(25L, runBlocking { fake.totalBalance(FakeWalletGateway.TestMintUrl) })
    }

    @Test
    fun lightningReceiveTransitionsToPaidSuccessAndHistory() {
        val fixture = launch(FixtureMode.SeededWithMint)
        val fake = checkNotNull(fixture.fakeGateway)

        robot.awaitTag(UiTestTags.WalletScreen)
            .tapTag(UiTestTags.WalletReceive)
            .tapDescription("Receive over Lightning or on-chain")
            .awaitTag(UiTestTags.ReceiveLightningScreen)
            .tapDescription("2")
            .tapTextWithinTag(UiTestTags.ReceiveLightningScreen, "Create invoice")
            .awaitText("Lightning Invoice")

        compose.waitUntil(WalletJourneyRobot.DefaultTimeout) {
            fake.latestMintQuoteId != null
        }
        compose.runOnIdle {
            fake.markMintQuotePaid(checkNotNull(fake.latestMintQuoteId))
        }

        robot.awaitText("Payment Received!", timeoutMillis = 20_000)
            .tapText("Done")
            .awaitTag(UiTestTags.WalletScreen)
            .tapText("History")
            .awaitText("Lightning received")
        assertEquals(2L, runBlocking { fake.totalBalance(FakeWalletGateway.TestMintUrl) })
    }

    @Test
    fun lightningInvoiceQuoteConfirmPayUpdatesBalanceFeesAndHistory() {
        val fixture = launch(FixtureMode.FundedWithHistory)
        val fake = checkNotNull(fixture.fakeGateway)

        robot.awaitTag(UiTestTags.WalletScreen)
            .tapTag(UiTestTags.WalletSend)
            .awaitTag(UiTestTags.SendSheet)
            .typeIntoTag(UiTestTags.SendDestination, FixedBolt11Invoice)
            .awaitTag(UiTestTags.SendPaymentSubmit)
            .awaitText("Network fee")
            .awaitText("2 sat")
            .tapTag(UiTestTags.SendPaymentSubmit)
            .awaitText("Payment sent")
            .awaitText("Network fee")
            .awaitText("₿2")

        assertEquals(477L, runBlocking { fake.totalBalance(FakeWalletGateway.TestMintUrl) })
        val paidTransaction = checkNotNull(
            fixture.container.walletManager.state.value.transactions.firstOrNull {
                it.type == TransactionType.Outgoing && it.kind == TransactionKind.Lightning
            },
        )
        assertEquals(2L, paidTransaction.fee)

        robot.tapText("Done")
            .awaitTag(UiTestTags.WalletScreen)
            .tapText("History")
            .awaitTag(UiTestTags.HistoryScreen)
            .awaitTag(UiTestTags.transactionRow(paidTransaction.id))
    }

    @Test
    fun historySearchNoResultsDetailAndBackAreStable() {
        launch(FixtureMode.FundedWithHistory)

        robot.awaitTag(UiTestTags.WalletScreen)
            .tapText("History")
            .awaitTag(UiTestTags.HistoryScreen)
            .tapDescription("Search history")
            .typeIntoTag(UiTestTags.HistorySearch, "deposit")
            .awaitTag(UiTestTags.transactionRow("fixture-incoming"))
            .tapDescription("Clear search")
            .typeIntoTag(UiTestTags.HistorySearch, "not-present")
            .awaitText("No matches")
            .tapDescription("Clear search")
            .tapTag(UiTestTags.transactionRow("fixture-incoming"))
            .awaitText("Lightning received")
            .tapDescription("Close")
            .awaitTag(UiTestTags.HistoryScreen)
    }

    @Test
    fun insufficientBalanceAndBackendFailureExposeRecoveryPath() {
        val fixture = launch(FixtureMode.FundedWithHistory)
        val fake = checkNotNull(fixture.fakeGateway)

        robot.awaitTag(UiTestTags.WalletScreen)
            .tapTag(UiTestTags.WalletSend)
            .tapDescription("Create ecash")
            .awaitTag(UiTestTags.SendEcashScreen)
            .tapDescription("9")
            .tapDescription("9")
            .tapDescription("9")
            .awaitText("Insufficient balance")
            .assertTagIsNotEnabled(UiTestTags.SendEcashSubmit)
            .tapDescription("Delete. Long press to clear.")
            .tapDescription("Delete. Long press to clear.")
            .tapDescription("Delete. Long press to clear.")

        compose.runOnIdle {
            fake.nextFailure = IllegalStateException("Temporary backend failure. Try again.")
        }
        robot.tapDescription("1")
            .tapTextWithinTag(UiTestTags.SendEcashScreen, "Send")
            .awaitText("Couldn't Create Ecash")
            .awaitText("Temporary backend failure. Try again.")
            .tapTextWithinTag(UiTestTags.SendEcashScreen, "Try Again")
            .tapTextWithinTag(UiTestTags.SendEcashScreen, "Send")
            .awaitText("Pending Ecash")
    }

    @Test
    fun deleteWalletConfirmationReturnsToOnboarding() {
        launch(FixtureMode.SeededWithoutMint)

        robot.awaitTag(UiTestTags.WalletScreen)
            .tapDescription("Settings")
            .awaitTag(UiTestTags.SettingsScreen)
            .scrollToText(UiTestTags.SettingsList, "Delete Wallet")
            .tapText("Delete Wallet")
            .awaitText("Are you sure", substring = true)
            .tapText("Delete")
            .awaitTag(UiTestTags.OnboardingRoot)
            .awaitText("Create Wallet")
    }

    private fun launch(
        mode: FixtureMode,
        deepLink: String? = null,
    ): LaunchedFixture = AppTestFixture.launch(mode, deepLink).also { launched = it }

    companion object {
        private const val SecondMintUrl = "https://second.test"
        private const val FixedBolt11Invoice =
            "lnbc30n1p4yuxg4pp5zarhytpl8gq9j6rm5lezx3zcduwxdfq9n7h4zgqajgjwpsze7e5qdp2g9hxgun0d9jzqmnpw35hvefqd4shgunf0qsx6etvwssp5qfx3ut73g4uj4jyf6vp4dfr6duqerykycqsq0rgz6k0dx0uxf3fs9qypqsqxqxfvcqcq3n0nce8ju867gmhvd8kejujxyrsz4fh8af2yghef9853az3ekxz4l3mev8p6rldfceh75kxal4ejva6cur7dep6dzw5wz4gq29zt6lcpkwmv3l"
    }
}
