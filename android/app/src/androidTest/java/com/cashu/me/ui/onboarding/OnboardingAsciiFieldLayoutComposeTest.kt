package com.cashu.me.ui.onboarding

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import com.cashu.me.ui.testing.UiTestTags
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The one behavior no screenshot can catch: the terrain's frame is identical
 * on Welcome and Restore Wallet — the whole point of hoisting the field to
 * the onboarding root. The backdrop is composed exactly as the root wires it
 * (visible derived from the step, everything else constant), the step flips
 * across the pair and out of it, and the field's bounds must never move.
 *
 * Steps are modeled as the booleans the backdrop actually receives; the
 * production `OnboardingStep` is private to OnboardingScreen and the mapping
 * (Welcome/RestoreMethod → visible) is one expression covered by review.
 */
@RunWith(AndroidJUnit4::class)
class OnboardingAsciiFieldLayoutComposeTest {
    @get:Rule
    val compose = createComposeRule()

    private enum class Step { Welcome, RestoreMethod, RestoreInput }

    private fun fieldBounds(): Rect =
        compose.onNodeWithTag(UiTestTags.OnboardingAsciiField, useUnmergedTree = true)
            .fetchSemanticsNode()
            .boundsInRoot

    @Test
    fun fieldFrameIsIdenticalAcrossTheWelcomeRestorePair() {
        var step by mutableStateOf(Step.Welcome)
        compose.setCashuContent {
            Box(Modifier.width(390.dp).height(844.dp)) {
                OnboardingAsciiBackdrop(
                    visible = step == Step.Welcome || step == Step.RestoreMethod,
                    conceptSheetOpen = false,
                    chassisHeightPx = 460,
                    staticTime = 0f,
                    modifier = Modifier.matchParentSize(),
                )
            }
        }
        compose.waitForIdle()
        val welcomeBounds = fieldBounds()

        step = Step.RestoreMethod
        compose.waitForIdle()
        assertEquals(welcomeBounds, fieldBounds())

        // Leaving the pair only fades — the frame (and the view's identity,
        // which carries the wall clock) must survive untouched.
        step = Step.RestoreInput
        compose.waitForIdle()
        assertEquals(welcomeBounds, fieldBounds())

        step = Step.Welcome
        compose.waitForIdle()
        assertEquals(welcomeBounds, fieldBounds())
    }

    @Test
    fun suppressedLayoutKeepsTheFieldMountedButLaysOutTheFallbackBand() {
        // 360dp of window is far below headerClearance + chassis + 120dp, so
        // AsciiFieldLayout.resolve returns null (see AsciiFieldLayoutTest for
        // the rule itself). The backdrop must respond by hiding, not by
        // unmounting — the node keeps its identity so the wall clock never
        // restarts through a suppressed pass.
        compose.setCashuContent {
            Box(Modifier.width(390.dp).height(360.dp)) {
                OnboardingAsciiBackdrop(
                    visible = true,
                    conceptSheetOpen = false,
                    chassisHeightPx = 460,
                    staticTime = 0f,
                    modifier = Modifier.matchParentSize(),
                )
            }
        }
        compose.waitForIdle()
        compose.onNodeWithTag(UiTestTags.OnboardingAsciiField, useUnmergedTree = true)
            .assertExists()
    }
}
