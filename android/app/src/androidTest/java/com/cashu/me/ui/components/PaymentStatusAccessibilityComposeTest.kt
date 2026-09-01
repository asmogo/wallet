package com.cashu.me.ui.components

import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.cashu.me.ui.setCashuContent
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PaymentStatusAccessibilityComposeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun changingStatusTitleIsAPoliteLiveRegion() {
        compose.setCashuContent {
            PaymentStatusScreen(
                phase = PaymentStatusPhase.Success,
                title = "Payment sent",
                onDone = {},
            )
        }

        val semantics = compose.onNodeWithText("Payment sent")
            .fetchSemanticsNode()
            .config

        assertEquals(LiveRegionMode.Polite, semantics[SemanticsProperties.LiveRegion])
    }
}
