package com.cashu.me.ui.theme

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

class SemanticColorContrastTest {
    @Test
    fun lightSemanticForegroundsMeetNormalTextContrastOnCanvas() {
        val canvas = Color.White

        assertContrastAtLeast(LightCashuColors.onReceivedContainer, canvas, 4.5)
        assertContrastAtLeast(LightCashuColors.onPendingContainer, canvas, 4.5)
    }

    @Test
    fun greenSwipeActionUsesAnAccessibleOnFillColor() {
        assertContrastAtLeast(Color.Black, ReceivedGreen, 4.5)
    }

    private fun assertContrastAtLeast(foreground: Color, background: Color, minimum: Double) {
        val lighter = max(luminance(foreground), luminance(background))
        val darker = min(luminance(foreground), luminance(background))
        val ratio = (lighter + 0.05) / (darker + 0.05)
        assertTrue("Expected contrast >= $minimum, was $ratio", ratio >= minimum)
    }

    private fun luminance(color: Color): Double {
        fun channel(value: Float): Double {
            val component = value.toDouble()
            return if (component <= 0.04045) {
                component / 12.92
            } else {
                ((component + 0.055) / 1.055).pow(2.4)
            }
        }
        return 0.2126 * channel(color.red) +
            0.7152 * channel(color.green) +
            0.0722 * channel(color.blue)
    }
}
