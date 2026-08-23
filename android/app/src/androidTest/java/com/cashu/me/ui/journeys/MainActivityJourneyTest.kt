package com.cashu.me.ui.journeys

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.accessibility.enableAccessibilityChecks
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.test.Compatibility
import com.cashu.me.test.UiFailureArtifactsRule
import com.cashu.me.test.WalletJourneyRobot
import com.cashu.me.test.fixtures.AppTestFixture
import com.cashu.me.test.fixtures.FakeWalletGateway
import com.cashu.me.test.fixtures.FixtureMode
import com.cashu.me.test.fixtures.LaunchedFixture
import com.cashu.me.ui.testing.UiTestTags
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * App-level behavior tests. Every assertion is made against MainActivity's
 * production navigation and Compose tree.
 */
@RunWith(AndroidJUnit4::class)
class MainActivityJourneyTest {
    @get:Rule(order = 0)
    val compose = createEmptyComposeRule()

    @get:Rule(order = 1)
    val failureArtifacts = UiFailureArtifactsRule(compose) { launched?.close() }

    private val robot by lazy { WalletJourneyRobot(compose) }
    private var launched: LaunchedFixture? = null

    @Test
    fun createWalletRevealAndAcknowledgeSeedSkipMintReachWallet() {
        launch(FixtureMode.EmptyWallet)

        robot.completeCreateWalletToFirstMint()
            .tapTag(UiTestTags.SkipMint)
            .awaitTag(UiTestTags.WalletScreen)
            .awaitText("Add a mint to get started")
    }

    @Test
    fun createWalletAddCustomMintAndVerifyMintsTab() {
        launch(FixtureMode.EmptyWallet)

        robot.completeCreateWalletToFirstMint()
            .tapTag(UiTestTags.AddCustomMint)
            .typeIntoTag(UiTestTags.CustomMintUrl, FakeWalletGateway.TestMintUrl)
            .tapDescription("Add mint")
            .awaitText("Nutshell UI Test Mint")
            .tapTag(UiTestTags.ContinueWithMint)
            .awaitTag(UiTestTags.WalletScreen)
            .tapText("Mints")
            .awaitTag(UiTestTags.MintsScreen)
            .awaitText("Nutshell UI Test Mint")
    }

    @Test
    @Compatibility
    fun navigateWalletHistoryMintsWalletAndVerifyFreshEmptyStates() {
        launch(FixtureMode.SeededWithoutMint)

        robot.awaitTag(UiTestTags.WalletScreen)
            .awaitText("Add a mint to get started")
            .tapText("History")
            .awaitTag(UiTestTags.HistoryScreen)
            .awaitText("No Activity Yet")
            .tapText("Mints")
            .awaitTag(UiTestTags.MintsScreen)
            .awaitText("Add mint")
            .tapText("Wallet")
            .awaitTag(UiTestTags.WalletScreen)
    }

    @Test
    fun sendWithoutMintOffersConnectMintAndUnwindsStepsWithBack() {
        launch(FixtureMode.SeededWithoutMint)

        robot.awaitTag(UiTestTags.WalletScreen)
            // Send is tappable without a mint: the sheet answers with the
            // connect-a-mint surface instead of the button sitting dead.
            .tapTag(UiTestTags.WalletSend)
            .awaitTag(UiTestTags.ConnectMintSheet)
            .awaitText("Add a mint first")
            // "Add by URL" pushes a step inside the same sheet…
            .tapTag(UiTestTags.ConnectMintAddCustom)
            .awaitTag(UiTestTags.AddMintUrl)
            .assertTextDoesNotExist("Add a mint first")
            // …so back unwinds to the picker before the sheet sees it.
            .pressSystemBack()
            .awaitText("Add a mint first")
            .pressSystemBack()
            .assertTagDoesNotExist(UiTestTags.ConnectMintSheet)
            .awaitTag(UiTestTags.WalletScreen)
    }

    @Test
    fun walletEmptyStateAddMintOpensTheSameSurfaceWithoutTheHeadline() {
        launch(FixtureMode.SeededWithoutMint)

        robot.awaitTag(UiTestTags.WalletScreen)
            // No mint means no mint chip — iOS shows nothing here either.
            .assertTextDoesNotExist("No mint")
            .awaitText("Add a mint to get started")
            .tapText("Add mint")
            .awaitTag(UiTestTags.ConnectMintSheet)
            .awaitText("Mints issue the ecash you send and receive. Add one to get started.")
            // The CTA and the sheet title already say "Add mint"; a third
            // restatement is exactly the header stacking this redesign removed.
            .assertTextDoesNotExist("Add a mint first")
    }

    @Test
    fun openAndDismissReceiveWithSystemBack() {
        launch(FixtureMode.SeededWithMint)

        robot.awaitTag(UiTestTags.WalletScreen)
            .tapText("Receive")
            .awaitTag(UiTestTags.ReceiveSheet)
            .awaitText("Paste a Cashu token")
            .pressSystemBack()
            .assertTagDoesNotExist(UiTestTags.ReceiveSheet)
            .awaitTag(UiTestTags.WalletScreen)
    }

    @Test
    fun receiveWithoutMintCreatesAnyMintRequestAndExplainsBitcoinRequirement() {
        launch(FixtureMode.SeededWithoutMint)

        robot.awaitTag(UiTestTags.WalletScreen)
            .tapText("Receive")
            .awaitTag(UiTestTags.ReceiveSheet)
            .awaitText("Mint needed")
        compose.onNodeWithContentDescription("Receive over Lightning or on-chain").assertIsNotEnabled()
        robot.tapDescription("Create a Cashu request")
            .awaitText("Any mint")
    }

    @Test
    fun newEcashRequestDoesNotPinTheActiveMint() {
        launch(FixtureMode.SeededWithMint)

        robot.awaitTag(UiTestTags.WalletScreen)
            .tapText("Receive")
            .awaitTag(UiTestTags.ReceiveSheet)
            .tapDescription("Create a Cashu request")
            .awaitText("Any mint")
    }

    @Test
    fun receiveBitcoinOpensLightningAmountFlow() {
        launch(FixtureMode.SeededWithMint)

        robot.awaitTag(UiTestTags.WalletScreen)
            .tapText("Receive")
            .awaitTag(UiTestTags.ReceiveSheet)
            .tapDescription("Receive over Lightning or on-chain")
            .awaitTag(UiTestTags.ReceiveLightningScreen)
            .awaitDescription("Close")
            .awaitText("Create invoice")
    }

    @Test
    fun settingsSubscreenRoundTripReturnsToSelectedWalletTab() {
        launch(FixtureMode.SeededWithoutMint)

        robot.awaitTag(UiTestTags.WalletScreen)
            .tapDescription("Settings")
            .awaitTag(UiTestTags.SettingsScreen)
            .tapText("Backup & Restore")
            .awaitText("Backup & Restore")
            .tapDescription("Back")
            .awaitTag(UiTestTags.SettingsScreen)
            .tapDescription("Back")
            .awaitTag(UiTestTags.WalletScreen)
        compose.onNodeWithText("Wallet").assertIsDisplayed()
    }

    @Test
    fun settingsPersistAcrossActivityRecreationAndDeleteCanCancel() {
        val fixture = launch(FixtureMode.SeededWithoutMint)
        val initialUseBitcoinSymbol =
            fixture.container.settingsManager.state.value.useBitcoinSymbol

        robot.awaitTag(UiTestTags.WalletScreen)
            .tapDescription("Settings")
            .awaitTag(UiTestTags.SettingsScreen)
            .tapTag(UiTestTags.BitcoinSymbolToggle)
        compose.waitUntil(WalletJourneyRobot.DefaultTimeout) {
            fixture.container.settingsManager.state.value.useBitcoinSymbol != initialUseBitcoinSymbol
        }
        fixture.scenario.recreate()
        robot.awaitTag(UiTestTags.SettingsScreen)
            .scrollToText(UiTestTags.SettingsList, "Delete Wallet")
            .tapText("Delete Wallet")
            .awaitText("Are you sure", substring = true)
            .tapText("Cancel")
            .awaitTag(UiTestTags.SettingsScreen)
        assertEquals(
            !initialUseBitcoinSymbol,
            fixture.container.settingsManager.state.value.useBitcoinSymbol,
        )
    }

    @Test
    fun cashuDeepLinkRoutesToReceiveAndBackReturnsToWallet() {
        launch(
            mode = FixtureMode.SeededWithMint,
            deepLink = "cashu:${FakeWalletGateway.DeterministicToken}",
        )

        robot.awaitText("Receive Ecash")
            .pressSystemBack()
            .awaitTag(UiTestTags.WalletScreen)
    }

    @Test
    fun scannerCanCloseAfterCameraPermissionDenyAndAllow() {
        launch(FixtureMode.SeededWithoutMint)

        robot.awaitTag(UiTestTags.WalletScreen)
            .tapTag(UiTestTags.WalletScan)
            .awaitTag(UiTestTags.ScannerRoot)
            .awaitText("Scan QR Code")
            .awaitText("Camera Access Needed")
            .awaitDescription("Close")
            .tapDescription("Close")
            .awaitTag(UiTestTags.WalletScreen)
            .tapTag(UiTestTags.WalletScan)
            .awaitTag(UiTestTags.ScannerRoot)
            .awaitText("Scan QR Code")
            .awaitText("Camera Access Needed")
            .tapText("Allow Camera")
            .awaitText("Camera Ready")
            .awaitDescription("Close")
            .tapDescription("Close")
            .awaitTag(UiTestTags.WalletScreen)
    }

    @Test
    @Compatibility
    fun criticalWalletTabsPassAutomatedAccessibilityChecks() {
        compose.enableAccessibilityChecks()
        launch(FixtureMode.SeededWithoutMint)

        robot.awaitTag(UiTestTags.WalletScreen)
            .tapText("History")
            .awaitTag(UiTestTags.HistoryScreen)
            .tapText("Mints")
            .awaitTag(UiTestTags.MintsScreen)
        // Trigger one final framework action on the last critical screen.
        compose.onNodeWithText("Add mint").performClick()
        robot.awaitTag(UiTestTags.AddMintSheet)
    }

    private fun launch(
        mode: FixtureMode,
        deepLink: String? = null,
    ): LaunchedFixture = AppTestFixture.launch(mode, deepLink).also { launched = it }
}
