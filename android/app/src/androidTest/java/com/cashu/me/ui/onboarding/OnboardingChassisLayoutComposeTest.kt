package com.cashu.me.ui.onboarding

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Brief §3: the primary CTA's position is identical on every onboarding step —
 * the measurable success criterion of the chassis redesign. Two scaffolds in
 * identical frames, one with all three slots filled and one with only a
 * primary, must place the primary at exactly the same offset: the hidden slot
 * templates below the primary reserve its position.
 */
@RunWith(AndroidJUnit4::class)
class OnboardingChassisLayoutComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun primaryCtaPositionIdenticalAcrossSlotConfigurations() {
        compose.setCashuContent {
            Column {
                Box(
                    Modifier
                        .testTag("frame-full")
                        .fillMaxWidth()
                        .height(500.dp),
                ) {
                    OnboardingScaffold(
                        chassis = OnboardingChassisModel(
                            headline = "Full slots",
                            subhead = "Subhead",
                            primary = ChassisAction("Primary", onClick = {}, testTag = "primary-full"),
                            secondary = ChassisAction(
                                "Secondary",
                                onClick = {},
                                style = ChassisButtonStyle.Secondary,
                            ),
                            tertiary = ChassisAction(
                                "Back",
                                onClick = {},
                                style = ChassisButtonStyle.Ghost,
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
                            headline = "Primary only",
                            subhead = "Subhead",
                            primary = ChassisAction("Primary", onClick = {}, testTag = "primary-only"),
                        ),
                    ) {}
                }
            }
        }

        val fullFrame = compose.onNodeWithTag("frame-full").fetchSemanticsNode()
        val fullPrimary = compose.onNodeWithTag("primary-full").fetchSemanticsNode()
        val onlyFrame = compose.onNodeWithTag("frame-primary-only").fetchSemanticsNode()
        val onlyPrimary = compose.onNodeWithTag("primary-only").fetchSemanticsNode()

        val fullOffsetY = fullPrimary.positionInRoot.y - fullFrame.positionInRoot.y
        val onlyOffsetY = onlyPrimary.positionInRoot.y - onlyFrame.positionInRoot.y

        assertEquals(
            "Primary CTA drifted vertically between slot configurations",
            fullOffsetY,
            onlyOffsetY,
            1.5f,
        )
        assertEquals(
            "Primary CTA height changed between slot configurations",
            fullPrimary.size.height.toFloat(),
            onlyPrimary.size.height.toFloat(),
            1.5f,
        )
        assertEquals(
            "Primary CTA left edge drifted between slot configurations",
            fullPrimary.positionInRoot.x,
            onlyPrimary.positionInRoot.x,
            1.5f,
        )
    }
}
