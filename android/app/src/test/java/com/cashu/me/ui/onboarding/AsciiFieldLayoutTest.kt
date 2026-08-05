package com.cashu.me.ui.onboarding

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The band geometry contract (mirrors iOS `AsciiFieldLayoutTests`): the
 * resolved frame is a pure function of window size and chassis height — it
 * takes no step, no header measurement, no stage content, which is what
 * guarantees the terrain's frame is identical on Welcome and Restore Wallet —
 * plus the §8 suppression rule below the 120dp threshold.
 */
class AsciiFieldLayoutTest {
    private val clearance = AsciiFieldLayout.headerClearanceDp(fontScale = 1f)

    @Test
    fun bandClampsAgainstWindowHeight() {
        // Portrait phone: 26% of the window, inside the clamp.
        val phone = AsciiFieldLayout.resolve(844f, clearance, 176f)
        assertNotNull(phone)
        assertEquals(0.26f * 844f, phone!!.visibleBand, 0.01f)
        assertEquals(phone.visibleBand + 176f, phone.layerHeight, 0.01f)

        // Small window: the 160dp floor holds.
        val small = AsciiFieldLayout.resolve(560f, clearance, 120f)
        assertNotNull(small)
        assertEquals(160f, small!!.visibleBand, 0.01f)

        // Tall window: the 300dp ceiling holds.
        val tall = AsciiFieldLayout.resolve(1400f, clearance, 176f)
        assertNotNull(tall)
        assertEquals(300f, tall!!.visibleBand, 0.01f)
    }

    @Test
    fun identicalInputsResolveIdentically() {
        // The welcome/restore pair share window and chassis geometry; the
        // resolver has no other inputs, so their frames cannot differ.
        val a = AsciiFieldLayout.resolve(844f, clearance, 176f)
        val b = AsciiFieldLayout.resolve(844f, clearance, 176f)
        assertEquals(a, b)
    }

    @Test
    fun suppressesLandscapePhone() {
        // ~390dp tall landscape window: the empty region collapses.
        assertNull(AsciiFieldLayout.resolve(390f, clearance, 150f))
    }

    @Test
    fun suppressesCollapsedEmptyRegionAtLargeFontScale() {
        val bigTypeClearance = AsciiFieldLayout.headerClearanceDp(fontScale = 2f)
        assertTrue(bigTypeClearance > clearance)
        // A short window plus doubled type (clearance 280dp) and a 200dp
        // chassis leaves 110dp of empty region — under the 120dp threshold.
        assertNull(AsciiFieldLayout.resolve(590f, bigTypeClearance, 200f))
        // The same window at default type keeps well over the threshold.
        assertNotNull(AsciiFieldLayout.resolve(590f, clearance, 200f))
    }

    @Test
    fun suppressionThresholdIsExact() {
        // available = window − clearance − chassis; the band draws at exactly
        // 120dp of room and not below.
        val chassis = 176f
        val atThreshold = 120f + clearance + chassis
        assertNotNull(AsciiFieldLayout.resolve(atThreshold, clearance, chassis))
        assertNull(AsciiFieldLayout.resolve(atThreshold - 1f, clearance, chassis))
    }

    @Test
    fun maskFadeCoversTopOfVisibleBandOnly() {
        val layout = AsciiFieldLayout.resolve(844f, clearance, 176f)!!
        // The opaque point sits at 30% of the visible band, expressed as a
        // fraction of the full (band + underlap) layer.
        assertEquals(
            layout.visibleBand * 0.30f / layout.layerHeight,
            layout.maskOpaqueFraction,
            1e-4f,
        )
        assertTrue(layout.maskOpaqueFraction < 0.30f)
    }
}
