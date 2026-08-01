package com.cashu.me.ui.settings

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LightningAddressSetupFeedbackComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun activeSetupHasDedicatedProgressFeedback() {
        compose.setCashuContent {
            LightningAddressSetupFeedback(
                status = LightningAddressSetupStatus.SettingUp,
                retrying = false,
                recoveryError = null,
                onRetry = {},
            )
        }

        compose.onNodeWithText("Setting up Lightning address…").assertIsDisplayed()
    }

    @Test
    fun incompleteSetupExplainsProblemAndOffersRetry() {
        var retries = 0
        compose.setCashuContent {
            LightningAddressSetupFeedback(
                status = LightningAddressSetupStatus.NeedsRecovery,
                retrying = false,
                recoveryError = null,
                onRetry = { retries += 1 },
            )
        }

        compose.onNodeWithText(
            "Wallet not fully initialized. Try setup again to finish your Lightning address.",
        ).assertIsDisplayed()
        compose.onNodeWithText("Try setup again").performClick()
        compose.runOnIdle { assertEquals(1, retries) }
    }
}
