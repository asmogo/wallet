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
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
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
 * The behaviors no screenshot can catch: the field's full-window layer is
 * identical on Welcome and Restore Wallet — the layer never moves; only the
 * material morph differs per step — and each step drives the morph to its
 * resting end state (0 terrain on Welcome, 1 vault on Restore Wallet, held
 * outside the pair). The backdrop is composed exactly as the root wires it
 * (visible and vault derived from the step, everything else constant), the
 * step flips across the pair and out of it, and the field's bounds must
 * never move.
 *
 * Steps are modeled as the booleans the backdrop actually receives; the
 * production `OnboardingStep` is private to OnboardingScreen and the mapping
 * (Welcome/RestoreMethod → visible/vault) is one expression covered by
 * review.
 */
@RunWith(AndroidJUnit4::class)
class OnboardingAsciiFieldLayoutComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun ambientFieldAllowsTheUiToBecomeIdle() {
        compose.setCashuContent {
            // No static-time override: when system motion is enabled, the
            // production loop must honor the test clock's auto-advance policy.
            AsciiField(modifier = Modifier.fillMaxSize())
        }
        compose.waitForIdle()
        compose.onNodeWithTag(UiTestTags.OnboardingAsciiField, useUnmergedTree = true)
            .assertIsDisplayed()
    }

    private enum class Step { Welcome, RestoreMethod, RestoreInput }

    private fun fieldBounds(): Rect =
        compose.onNodeWithTag(UiTestTags.OnboardingAsciiField, useUnmergedTree = true)
            .fetchSemanticsNode()
            .boundsInRoot

    private fun assertVaultTarget(expected: Float) {
        compose.onNodeWithTag(UiTestTags.OnboardingAsciiField, useUnmergedTree = true)
            .assert(SemanticsMatcher.expectValue(AsciiFieldVaultTargetKey, expected))
    }

    @Test
    fun fieldFrameIsIdenticalAcrossTheWelcomeRestorePairAndTheVaultTracksTheStep() {
        var step by mutableStateOf(Step.Welcome)
        // Mirrors the root's hold-last-value wiring: only the pair writes it.
        var vault by mutableStateOf(false)
        compose.setCashuContent {
            Box(Modifier.width(390.dp).height(844.dp)) {
                OnboardingAsciiBackdrop(
                    visible = step == Step.Welcome || step == Step.RestoreMethod,
                    vault = vault,
                    conceptSheetOpen = false,
                    chassisHeightPx = 460,
                    staticTime = 0f,
                    modifier = Modifier.matchParentSize(),
                )
            }
        }
        compose.waitForIdle()
        val welcomeBounds = fieldBounds()
        assertVaultTarget(0f)

        step = Step.RestoreMethod
        vault = true
        compose.waitForIdle()
        assertEquals(welcomeBounds, fieldBounds())
        assertVaultTarget(1f)

        // Leaving the pair only fades — the frame (and the view's identity,
        // which carries the wall clock) must survive untouched, and the
        // morph holds so the material never shifts mid-fade.
        step = Step.RestoreInput
        compose.waitForIdle()
        assertEquals(welcomeBounds, fieldBounds())
        assertVaultTarget(1f)

        step = Step.Welcome
        vault = false
        compose.waitForIdle()
        assertEquals(welcomeBounds, fieldBounds())
        assertVaultTarget(0f)
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
                    vault = false,
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
