package com.cashu.me.ui.onboarding

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Design review 2026-08-05: chassis actions hug the bottom edge — no reserved
 * slots. Whatever the slot configuration, the bottom-most action's bottom edge
 * sits exactly the chassis bottom padding (24dp) above the scaffold's bottom.
 */
@RunWith(AndroidJUnit4::class)
class OnboardingChassisLayoutComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun ctasAnchorToBottomAcrossSlotConfigurations() {
        compose.setCashuContent {
            // Scrollable so both frames keep their full 500dp height — in a
            // plain Column the second frame would be coerced to the screen
            // remainder and the comparison would measure different frames.
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Box(
                    Modifier
                        .testTag("frame-full")
                        .fillMaxWidth()
                        .height(500.dp),
                ) {
                    OnboardingScaffold(
                        chassis = OnboardingChassisModel(
                            primary = ChassisAction("Primary", onClick = {}, testTag = "primary-full"),
                            secondary = ChassisAction(
                                "Secondary",
                                onClick = {},
                                style = ChassisButtonStyle.Secondary,
                            ),
                            tertiary = ChassisAction(
                                "Skip",
                                onClick = {},
                                style = ChassisButtonStyle.Ghost,
                                testTag = "tertiary-full",
                            ),
                        ),
                    ) {}
                }
                Box(
                    Modifier
                        .testTag("frame-primary-only")
                        .fillMaxWidth()
                        .height(500.dp),
                ) {
                    OnboardingScaffold(
                        chassis = OnboardingChassisModel(
                            primary = ChassisAction("Primary", onClick = {}, testTag = "primary-only"),
                        ),
                    ) {}
                }
            }
        }

        val bottomPaddingPx = with(compose.density) { 24.dp.toPx() }
        // A TextButton's 40dp layout box centers inside the 48dp minimum touch
        // target, leaving up to 4dp of invisible target below the visual button.
        val touchTargetSlackPx = with(compose.density) { 4.dp.toPx() }

        fun bottomGap(frameTag: String, ctaTag: String): Float {
            val frame = compose.onNodeWithTag(frameTag).fetchSemanticsNode()
            val cta = compose.onNodeWithTag(ctaTag).fetchSemanticsNode()
            val frameBottom = frame.positionInRoot.y + frame.size.height
            val ctaBottom = cta.positionInRoot.y + cta.size.height
            return frameBottom - ctaBottom
        }

        assertEquals(
            "Tertiary should hug the bottom when all slots are filled",
            bottomPaddingPx,
            bottomGap("frame-full", "tertiary-full"),
            touchTargetSlackPx + 2f,
        )
        assertEquals(
            "A lone primary should hug the bottom itself — no reserved slots below it",
            bottomPaddingPx,
            bottomGap("frame-primary-only", "primary-only"),
            2f,
        )
    }

    /**
     * Every step titles itself at the top on the same line — welcome included,
     * since its title moved out of the chassis (2026-08-05, user-directed).
     */
    @Test
    fun welcomeTitleSitsOnTheSameLineAsEveryOtherStep() {
        compose.setCashuContent {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Box(
                    Modifier
                        .testTag("frame-welcome")
                        .fillMaxWidth()
                        .height(500.dp),
                ) {
                    OnboardingScaffold(chassis = OnboardingChassisModel()) {
                        WelcomeStageContent(
                            startupFailure = null,
                            retryingStartup = false,
                            errorText = null,
                            onRetryStartup = {},
                        )
                    }
                }
                Box(
                    Modifier
                        .testTag("frame-step")
                        .fillMaxWidth()
                        .height(500.dp),
                ) {
                    OnboardingScaffold(chassis = OnboardingChassisModel()) {
                        Column(Modifier.fillMaxWidth()) {
                            OnboardingBackButton(
                                onBack = {},
                                modifier = Modifier.padding(
                                    start = OnboardingMetrics.BarStartInset,
                                    top = OnboardingMetrics.BarTopInset,
                                ),
                            )
                            OnboardingStepHeader(
                                title = "Restore Wallet",
                                modifier = Modifier.padding(top = OnboardingMetrics.TitleGap),
                            )
                        }
                    }
                }
            }
        }

        fun titleTopInFrame(frameTag: String, title: String): Float {
            val frame = compose.onNodeWithTag(frameTag).fetchSemanticsNode()
            val node = compose.onNodeWithText(title, substring = true).fetchSemanticsNode()
            return node.positionInRoot.y - frame.positionInRoot.y
        }

        assertEquals(
            "Welcome's title should start on the same line as a step that draws a back button",
            titleTopInFrame("frame-step", "Restore Wallet"),
            titleTopInFrame("frame-welcome", "Private cash."),
            2f,
        )
    }
}
