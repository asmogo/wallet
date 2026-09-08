package com.cashu.me.ui.journeys

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.test.UiFailureArtifactsRule
import com.cashu.me.test.WalletJourneyRobot
import com.cashu.me.test.fixtures.*
import com.cashu.me.ui.testing.UiTestTags
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Real app security screens with only the OS authentication response replaced. */
@RunWith(AndroidJUnit4::class)
class SecurityJourneyTest {
    @get:Rule(order = 0) val compose = createEmptyComposeRule()
    @get:Rule(order = 1) val artifacts = UiFailureArtifactsRule(compose) { fixture?.close() }
    private val robot by lazy { WalletJourneyRobot(compose) }
    private var fixture: LaunchedFixture? = null
    private var allowAuthentication = false
    private val challenges = mutableListOf<String>()

    private fun settings(): LaunchedFixture = AppTestFixture.launch(
        FixtureMode.SeededWithoutMint,
        authenticate = { reason -> challenges += reason; allowAuthentication },
    ).also {
        fixture = it
        robot.awaitTag(UiTestTags.WalletScreen).tapDescription("Settings").awaitTag(UiTestTags.SettingsScreen)
    }

    @Test fun rejectedAppLockEnablementStaysOffThenSuccessfulRetryPersists() {
        val app = settings()
        robot.tapText("App Lock")
        val toggle = compose.onNode(isToggleable())
        toggle.performClick()
        robot.awaitText("Authentication failed. App Lock was not enabled. Try turning it on again.")
        toggle.assertIsOff()
        assertFalse(app.container.settingsManager.state.value.appLockEnabled)
        compose.runOnIdle { allowAuthentication = true }
        toggle.performClick()
        compose.waitUntil { app.container.settingsManager.state.value.appLockEnabled }
        toggle.assertIsOn()
        app.scenario.recreate()
        compose.onNode(isToggleable()).assertIsOn()
        assertTrue(challenges.contains("Confirm to enable App Lock"))
    }

    @Test fun seedRevealRequiresAuthenticationEvenWithAppLockOff() {
        val app = settings()
        assertFalse(app.container.settingsManager.state.value.appLockEnabled)
        robot.tapText("Backup & Restore").tapText("Backup seed phrase").awaitText("Reveal Recovery Phrase")
            .tapText("Reveal Recovery Phrase")
        compose.waitUntil { challenges.isNotEmpty() }
        robot.assertTextDoesNotExist("Copy Recovery Phrase")
        compose.runOnIdle { allowAuthentication = true }
        robot.tapText("Reveal Recovery Phrase").awaitText("Copy Recovery Phrase")
        assertTrue(challenges.contains("Reveal your seed phrase"))
        robot.pressSystemBack().tapText("Backup seed phrase").awaitText("Reveal Recovery Phrase")
        robot.assertTextDoesNotExist("Copy Recovery Phrase")
    }

    @Test fun cancellingRestorePreservesExistingWalletAndReturnsToSettings() {
        val app = settings()
        val original = app.container.walletManager.state.value
        robot.tapText("Backup & Restore").tapText("Restore").awaitText("Restore Wallet")
        robot.pressSystemBack().awaitText("Backup seed phrase")
        assertEquals(original.balance, app.container.walletManager.state.value.balance)
        assertEquals(original.mints, app.container.walletManager.state.value.mints)
        robot.tapDescription("Back").awaitTag(UiTestTags.SettingsScreen)
    }

    @Test fun restoreFromSeedRecoversFundedMintAndCompletes() {
        fixture = AppTestFixture.launch(FixtureMode.FundedWithHistory)
        val app = fixture!!
        robot.awaitTag(UiTestTags.WalletScreen).tapDescription("Settings")
            .tapText("Backup & Restore").tapText("Restore").awaitText("Restore Wallet")
        val words = FakeWalletGateway.FixedMnemonic.split(" ")
        for (word in words) {
            robot.typeIntoTag(UiTestTags.SeedWordField, word)
            compose.onNodeWithTag(UiTestTags.SeedWordField).performImeAction()
        }
        robot.tapText("Next").awaitText("Add your mints")
        compose.onNode(hasSetTextAction()).performTextInput(FakeWalletGateway.TestMintUrl)
        compose.onNode(hasSetTextAction()).performImeAction()
        robot.pressSystemBack().tapText("Restore from 1 mint").awaitText("Restore complete", timeoutMillis = 30_000)
            .tapText("Continue").awaitText("Backup seed phrase")
        assertEquals(500L, app.container.walletManager.state.value.balance)
        assertEquals(FakeWalletGateway.TestMintUrl, app.container.walletManager.state.value.activeMint?.url)
    }

    @Test fun encryptedMintBackupCompletesThroughSettings() {
        fixture = AppTestFixture.launch(FixtureMode.SeededWithMint)
        val app = fixture!!
        robot.awaitTag(UiTestTags.WalletScreen).tapDescription("Settings")
            .tapText("Backup & Restore").tapText("Back up now")
        compose.waitUntil { app.container.nostrMintBackupService.state.value.lastBackupDateEpochMillis != null }
        robot.awaitText("Last backup", substring = true)
    }

    @Test fun quickLockSelectionAndCancellationPreserveEnteredAmount() {
        fixture = AppTestFixture.launch(FixtureMode.FundedWithHistory)
        val app = fixture!!
        robot.awaitTag(UiTestTags.WalletScreen).tapDescription("Settings")
            .scrollToText(UiTestTags.SettingsList, "Locked Ecash").tapText("Locked Ecash")
        val quickLock = compose.onNode(hasText("Quick lock to my key") and isToggleable())
        quickLock.performScrollTo().performClick()
        quickLock.assertIsOn()
        app.scenario.recreate()
        compose.onNode(hasText("Quick lock to my key") and isToggleable()).assertIsOn()
        robot.tapDescription("Back").tapDescription("Back").tapTag(UiTestTags.WalletSend)
            .tapDescription("Ecash. Create ecash").tapDescription("2").tapDescription("5")
            .tapDescription("Lock ecash").tapText("Allow Camera").awaitText("Lock to my key")
            .pressSystemBack().awaitTag(UiTestTags.SendEcashSubmit)
        compose.onNodeWithTag(UiTestTags.SendEcashSubmit).assertIsEnabled()
        robot.tapDescription("Lock ecash").tapText("Allow Camera").tapText("Lock to my key")
            .awaitTag(UiTestTags.SendEcashSubmit)
        compose.onNodeWithTag(UiTestTags.SendEcashSubmit).assertIsEnabled()
        robot.pressSystemBack().awaitTag(UiTestTags.WalletScreen)
        assertEquals(500L, app.container.walletManager.state.value.balance)
        assertNull(app.fakeGateway!!.lastSentAmount)
    }
}
