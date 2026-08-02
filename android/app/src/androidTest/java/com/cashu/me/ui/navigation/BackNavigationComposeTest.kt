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

    /**
     * Flow screens keep a single swallow handler, enabled only while money is
     * moving: back must not reach the sheet's dismiss handling mid-payment,
     * and must fall through to it (back = swipe = abandon to the wallet) at
     * every other step.
     */
    @Test
    fun executingSwallowBlocksDismissalAndIdleFallsThrough() {
        val executing = mutableStateOf(true)
        var sheetDismissals = 0

        compose.setCashuContent {
            // Registered first → lower priority: stands in for the M3 sheet's
            // own back-to-dismiss handling.
            BackHandler(enabled = true) { sheetDismissals++ }
            // The flow screens' pattern: BackHandler(enabled = executing) {}.
            BackHandler(enabled = executing.value) {}
            Text("Back contract harness")
        }

        compose.activityRule.scenario.onActivity {
            it.onBackPressedDispatcher.onBackPressed()
        }
        compose.runOnIdle { assertEquals(0, sheetDismissals) }

        compose.runOnIdle { executing.value = false }
        compose.waitForIdle()
        compose.activityRule.scenario.onActivity {
            it.onBackPressedDispatcher.onBackPressed()
        }
        compose.runOnIdle { assertEquals(1, sheetDismissals) }
    }

    /** Shell back closes the topmost activity-window overlay first. */
    @Test
    fun shellBackDispatchesTopmostOverlay() {
        val receiveDetailVisible = mutableStateOf(true)
        var observed: ShellBackAction? = null

        compose.setCashuContent {
            BackHandler(enabled = true) {
                observed = shellBackAction(
                    receiveDetailVisible = receiveDetailVisible.value,
                    scannerVisible = true,
                )
            }
            Text("Shell back harness")
        }

        compose.activityRule.scenario.onActivity {
            it.onBackPressedDispatcher.onBackPressed()
        }
        compose.runOnIdle { assertEquals(ShellBackAction.CloseReceiveDetail, observed) }

        compose.runOnIdle { receiveDetailVisible.value = false }
        compose.waitForIdle()
        compose.activityRule.scenario.onActivity {
            it.onBackPressedDispatcher.onBackPressed()
        }
        compose.runOnIdle { assertEquals(ShellBackAction.CloseScanner, observed) }
    }
}
