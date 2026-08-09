package com.cashu.me.ui.onboarding

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The field geometry contract (mirrors iOS `AsciiFieldLayoutTests`): the
 * resolved geometry is a pure function of window geometry — it takes no step,
 * no header measurement, no stage content, which is what guarantees the
 * terrain's full-window layer is identical on Welcome and Restore Wallet; the
 * mask extent is the *only* per-step input — plus the suppression rule below
 * the 120dp threshold.
 */
class AsciiFieldLayoutTest {
    private val clearance = AsciiFieldLayout.headerClearanceDp(fontScale = 1f)
    private val topInset = 38f
    private val chassis = 176f

    private fun phoneLayout(): AsciiFieldLayout.Resolution =
        AsciiFieldLayout.resolve(844f, topInset, clearance, chassis)!!

    @Test
    fun bandClampsAgainstWindowHeightAndLayerSpansTheWindow() {
        // Portrait phone: 26% of the window, inside the clamp; the drawn
        // layer is the whole window — the glyph grid must not depend on the
        // band so the mask extent can settle without the texture re-hashing.
        val phone = phoneLayout()
        assertEquals(0.26f * 844f, phone.visibleBand, 0.01f)
        assertEquals(844f, phone.layerHeight, 0.01f)

        // Small window: the 160dp floor holds.
        val small = AsciiFieldLayout.resolve(560f, 0f, clearance, 120f)
        assertNotNull(small)
        assertEquals(160f, small!!.visibleBand, 0.01f)
        assertEquals(560f, small.layerHeight, 0.01f)

        // Tall window: the 300dp ceiling holds.
        val tall = AsciiFieldLayout.resolve(1400f, topInset, clearance, chassis)
        assertNotNull(tall)
        assertEquals(300f, tall!!.visibleBand, 0.01f)
    }

    @Test
    fun identicalInputsResolveIdentically() {
        // The welcome/restore pair share window and chassis geometry; the
        // resolver has no other inputs, so their layers cannot differ. The
        // steps diverge only in the extent their masks are driven to.
        val a = AsciiFieldLayout.resolve(844f, topInset, clearance, chassis)
        val b = AsciiFieldLayout.resolve(844f, topInset, clearance, chassis)
        assertEquals(a, b)
    }

    @Test
    fun suppressesLandscapePhone() {
        // ~390dp tall landscape window: the empty region collapses.
        assertNull(AsciiFieldLayout.resolve(390f, 0f, clearance, 150f))
    }

    @Test
    fun suppressesCollapsedEmptyRegionAtLargeFontScale() {
        val bigTypeClearance = AsciiFieldLayout.headerClearanceDp(fontScale = 2f)
        assertTrue(bigTypeClearance > clearance)
        // A short window plus doubled type (clearance 280dp) and a 200dp
        // chassis leaves 110dp of empty region — under the 120dp threshold.
        assertNull(AsciiFieldLayout.resolve(590f, 0f, bigTypeClearance, 200f))
        // The same window at default type keeps well over the threshold.
        assertNotNull(AsciiFieldLayout.resolve(590f, 0f, clearance, 200f))
    }

    @Test
    fun suppressionThresholdIsExact() {
        // available = window − top − clearance − chassis; the band draws at
        // exactly 120dp of room and not below.
        val atThreshold = 120f + topInset + clearance + chassis
        assertNotNull(AsciiFieldLayout.resolve(atThreshold, topInset, clearance, chassis))
        assertNull(AsciiFieldLayout.resolve(atThreshold - 1f, topInset, clearance, chassis))
    }

    @Test
    fun bandModeIsTheLegacyBandGeometryInWindowCoordinates() {
        // Extent 0 must reproduce the shipped band exactly: clear down to the
        // band top, the web's 30%-of-band ramp, and the same bottom fade —
        // the Restore screen is unchanged by the full-mode work.
        val layout = phoneLayout()
        val bandTop = 844f - chassis - layout.visibleBand
        assertEquals(bandTop / 844f, layout.bandClearEnd, 1e-4f)
        assertEquals((bandTop + 0.30f * layout.visibleBand) / 844f, layout.bandOpaqueEnd, 1e-4f)
        assertEquals((844f - chassis - 48f) / 844f, layout.bottomFadeStart, 1e-4f)
        assertEquals((844f - chassis + 40f) / 844f, layout.bottomFadeEnd, 1e-4f)
    }

    @Test
    fun fullModeClearsTheHeaderBlock() {
        // Extent 1: fully transparent through the header clearance line, then
        // the long 0.30-window ramp. Uncramped geometry — no clamps engage.
        val layout = phoneLayout()
        assertEquals((topInset + clearance) / 844f, layout.fullClearEnd, 1e-4f)
        assertEquals(layout.fullClearEnd + 0.30f, layout.fullOpaqueEnd, 1e-4f)
        // The settle has real travel on a phone — the whole point.
        assertTrue(layout.fullClearEnd < layout.bandClearEnd - 0.2f)
    }

    @Test
    fun fullModeDegradesToBandModeWhenTheHeaderReachesTheBand() {
        // 120 ≤ available < band: not suppressed, but the header block ends
        // below the band top. Full mode must clamp to band mode so the settle
        // becomes a no-op instead of inverting direction.
        val layout = AsciiFieldLayout.resolve(700f, 20f, 280f, 250f)!!
        assertEquals(layout.bandClearEnd, layout.fullClearEnd, 1e-6f)
        assertEquals(layout.bandOpaqueEnd, layout.fullOpaqueEnd, 1e-6f)
        val full = layout.maskStops(1f)
        val band = layout.maskStops(0f)
        assertEquals(band.clearEnd, full.clearEnd, 1e-6f)
        assertEquals(band.opaqueEnd, full.opaqueEnd, 1e-6f)
    }

    @Test
    fun maskStopsLerpEndpointsClampAndStayOrdered() {
        val layout = phoneLayout()
        val atBand = layout.maskStops(0f)
        assertEquals(layout.bandClearEnd, atBand.clearEnd, 1e-6f)
        assertEquals(layout.bandOpaqueEnd, atBand.opaqueEnd, 1e-6f)
        val atFull = layout.maskStops(1f)
        assertEquals(layout.fullClearEnd, atFull.clearEnd, 1e-6f)
        assertEquals(layout.fullOpaqueEnd, atFull.opaqueEnd, 1e-6f)
        // A bouncy spatial spring overshoots the 0…1 target transiently; the
        // stops must clamp, not extrapolate.
        assertEquals(atBand.clearEnd, layout.maskStops(-0.2f).clearEnd, 1e-6f)
        assertEquals(atFull.clearEnd, layout.maskStops(1.3f).clearEnd, 1e-6f)
        // The gradient's stop order must survive every point of the settle.
        for (e in listOf(0f, 0.25f, 0.5f, 0.75f, 1f)) {
            val stops = layout.maskStops(e)
            assertTrue("extent $e", stops.clearEnd < stops.opaqueEnd)
            assertTrue("extent $e", stops.opaqueEnd <= layout.bottomFadeStart)
            assertTrue("extent $e", layout.bottomFadeStart < layout.bottomFadeEnd)
            assertTrue("extent $e", layout.bottomFadeEnd <= 1f)
        }
    }

    @Test
    fun cullStartRowSkipsOnlyFullyMaskedRows() {
        // No cull at zero.
        assertEquals(0, AsciiFieldLayout.cullStartRow(0f))
        // Less than a cell of transparency: the slack row keeps it at zero.
        assertEquals(0, AsciiFieldLayout.cullStartRow(10f))
        val layout = phoneLayout()
        // Band mode on the phone fixture: the layer is 62 rows
        // (ceil(844/14)+1); the cull leaves ~31 — the shipped band's cost,
        // plus one slack row for ink overhang.
        assertEquals(31, AsciiFieldLayout.cullStartRow(layout.transparentStartDp(0f)))
        // Full mode still culls the header block's rows.
        assertEquals(14, AsciiFieldLayout.cullStartRow(layout.transparentStartDp(1f)))
    }

    @Test
    fun fallbackKeepsTheFullWindowFrame() {
        // Suppression hides rather than unmounts, so the fallback frame must
        // match the resolved frame — a pass through a suppressed layout (a
        // rotation, a font-scale change) must not move the layer.
        val fallback = AsciiFieldLayout.fallback(844f, topInset, clearance, chassis)
        assertEquals(phoneLayout().layerHeight, fallback.layerHeight, 1e-4f)
        // A chassis shallower than the underlap clamps the fade inside it.
        val shallow = AsciiFieldLayout.fallback(400f, 0f, clearance, 24f)
        assertEquals(1f, shallow.bottomFadeEnd, 1e-4f)
        // The zero-size transient layout pass must stay finite.
        val degenerate = AsciiFieldLayout.fallback(0f, 0f, clearance, 24f)
        assertTrue(degenerate.layerHeight > 0f)
        assertTrue(degenerate.bandClearEnd >= 0f)
        assertTrue(degenerate.bottomFadeEnd <= 1f)
    }
}
