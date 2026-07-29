package com.cashu.me.ui.navigation

import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.compose.material3.Text
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BackNavigationComposeTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun customBackHandlersDispatchPolicyOutcomes() {
        val activeOutcome = mutableStateOf("unset")
        var observedOutcome = "unset"

        compose.setCashuContent {
            BackHandler(enabled = true) {
                observedOutcome = activeOutcome.value
            }
            Text("Back policy harness")
        }

        val cases = listOf(
            "shell:receive-detail" to shellBackAction(
                receiveDetailVisible = true,
                scannerVisible = true,
            )!!.name,
            "shell:scanner" to shellBackAction(
                receiveDetailVisible = false,
                scannerVisible = true,
            )!!.name,
            "onboarding:restore-progress-working" to onboardingBackAction(
                OnboardingBackState.RestoreProgress,
                canExitOnboarding = false,
                restoreInProgress = true,
            ).name,
            "unified-send:confirm-from-amount" to unifiedSendBackAction(
                sending = false,
                statusVisible = false,
                onConfirmStep = true,
                cameFromAmount = true,
                onInputStep = false,
            ).name,
            "send-ecash:generated" to sendEcashBackAction(sending = false, generated = true).name,
            "receive-ecash:review" to receiveEcashBackAction(claiming = false, reviewing = true).name,
            "receive-lightning:display" to receiveLightningBackAction(displayingQuote = true).name,
            "history:search" to historyBackAction(searching = true)!!.name,
            "direct:close" to directSurfaceBackAction().name,
        )

        cases.forEach { (name, expected) ->
            observedOutcome = "unset"
            compose.runOnIdle { activeOutcome.value = expected }
            compose.waitForIdle()
            compose.activityRule.scenario.onActivity {
                it.onBackPressedDispatcher.onBackPressed()
            }
            compose.runOnIdle {
                assertEquals(name, expected, observedOutcome)
            }
        }
    }
}
