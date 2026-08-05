package com.cashu.me.ui.onboarding

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.Core.WalletStartupFailure
import com.cashu.me.ui.setCashuContent
import com.cashu.me.ui.testing.UiTestTags
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WalletStartupFailureComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun welcomeShowsStartupFailureAndInvokesRetry() {
        var retries = 0
        val failure = WalletStartupFailure(
            message = "The wallet couldn't start. Try again in a moment.",
        )

        compose.setCashuContent {
            // The production frame: welcome chassis + stage, exactly as
            // OnboardingScreen composes them.
            OnboardingScaffold(
                chassis = welcomeChassis(
                    creating = false,
                    retryingStartup = false,
                    onCreate = {},
                    onRestore = {},
                ),
            ) {
                WelcomeStageContent(
                    startupFailure = failure,
                    retryingStartup = false,
                    errorText = null,
                    onRetryStartup = { retries += 1 },
                    onInfo = {},
                )
            }
        }

        compose.onNodeWithText(failure.message).assertIsDisplayed()
        compose.onNodeWithTag(UiTestTags.RetryWalletStartup)
            .assertIsDisplayed()
            .performClick()
        compose.runOnIdle { assertEquals(1, retries) }
    }
}
