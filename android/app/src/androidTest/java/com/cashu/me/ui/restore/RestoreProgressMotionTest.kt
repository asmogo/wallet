package com.cashu.me.ui.restore

import androidx.compose.material3.Text
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RestoreProgressMotionTest {
    private val duration = object : MotionDurationScale { override val scaleFactor = 1f }
    @get:Rule val compose = createComposeRule(effectContext = duration)

    @Test fun interruptedPhaseTransitionSettlesOnLatestValue() {
        val phase = mutableStateOf("Restoring")
        compose.setCashuContent {
            RestoreProgressTransition(phase.value, reducedMotion = false) { Text(it) }
        }
        compose.mainClock.autoAdvance = false
        compose.runOnIdle { phase.value = "Retry" }
        compose.mainClock.advanceTimeBy(32)
        compose.runOnIdle { phase.value = "21 sats" }
        compose.mainClock.advanceTimeBy(2000)
        compose.onNodeWithText("21 sats").assertIsDisplayed()
        compose.onNodeWithText("Retry").assertDoesNotExist()
        compose.onNodeWithText("Restoring").assertDoesNotExist()
    }

    @Test fun reducedMotionReplacesValueWithoutOutgoingContent() {
        val total = mutableStateOf(21L)
        compose.setCashuContent {
            RestoreProgressTransition(total.value, direction = { _, _ -> 1 }, reducedMotion = true) {
                Text("Recovered: $it sats")
            }
        }
        compose.mainClock.autoAdvance = false
        compose.runOnIdle { total.value = 55L }
        compose.mainClock.advanceTimeByFrame()
        compose.onNodeWithText("Recovered: 55 sats").assertIsDisplayed()
        compose.onNodeWithText("Recovered: 21 sats").assertDoesNotExist()
    }
}
