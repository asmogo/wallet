package com.cashu.me.ui.onboarding

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Parity for the handoff's erosion curve.
 *
 * Hand-authored vectors — there is no web counterpart to generate from, so
 * these values are mirrored verbatim in AsciiFieldErosionTests.swift. If a
 * port disagrees, fix the port. What the assertions defend is the *shape* the
 * exit depends on: the field must thin from its faintest matter upward, must
 * never brighten, and the ₿ peaks must still be standing when the dotted
 * plain has gone.
 */
class AsciiFieldErosionTest {
    private val eps = 1e-9

    @Test
    fun `intact field is untouched`() {
        for (level in 0 until AsciiFieldTerrain.LEVELS) {
            assertEquals(1.0, AsciiFieldTerrain.erosionAlpha(level, 0.0), eps)
        }
    }

    @Test
    fun `every level is gone at full progress`() {
        for (level in 0 until AsciiFieldTerrain.LEVELS) {
            assertEquals(0.0, AsciiFieldTerrain.erosionAlpha(level, 1.0), eps)
        }
    }

    /** The last level's window must close exactly at 1.0, or the curtain would
     * still be holding glyphs when the overlay unmounts and they would pop. */
    @Test
    fun `peak window closes exactly at the end`() {
        val last = AsciiFieldTerrain.LEVELS - 1
        val start = last * AsciiFieldTerrain.EROSION_STAGGER
        assertEquals(1.0, start + AsciiFieldTerrain.EROSION_WINDOW, eps)
        assertTrue(AsciiFieldTerrain.erosionAlpha(last, 0.999) > 0.0)
    }

    /** The ordering the whole effect rests on: at any progress mid-dissolve, a
     * stronger level is at least as present as a fainter one. */
    @Test
    fun `stronger levels always outlast fainter ones`() {
        var p = 0.0
        while (p <= 1.0) {
            for (level in 1 until AsciiFieldTerrain.LEVELS) {
                val faint = AsciiFieldTerrain.erosionAlpha(level - 1, p)
                val strong = AsciiFieldTerrain.erosionAlpha(level, p)
                assertTrue(
                    "level $level must outlast ${level - 1} at p=$p ($strong vs $faint)",
                    strong >= faint - eps,
                )
            }
            p += 0.01
        }
    }

    /** Half-way through the exit the plain is gone and the peaks are barely
     * touched — that gap is what makes the ₿ the last thing over the balance. */
    @Test
    fun `mid-dissolve leaves peaks standing over a cleared plain`() {
        assertEquals(0.0, AsciiFieldTerrain.erosionAlpha(0, 0.5), eps)
        assertTrue(AsciiFieldTerrain.erosionAlpha(4, 0.5) > 0.99)
    }

    @Test
    fun `alpha never rises as the dissolve advances`() {
        for (level in 0 until AsciiFieldTerrain.LEVELS) {
            var previous = 1.0
            var p = 0.0
            while (p <= 1.0) {
                val alpha = AsciiFieldTerrain.erosionAlpha(level, p)
                assertTrue("level $level rose at p=$p", alpha <= previous + eps)
                assertTrue("level $level out of range at p=$p", alpha in 0.0..1.0)
                previous = alpha
                p += 0.005
            }
        }
    }

    /** Pinned midpoints, so a retuned stagger or window is a deliberate edit
     * to both ports rather than a silent drift in one. */
    @Test
    fun `pinned vectors`() {
        assertEquals(0.5, AsciiFieldTerrain.erosionAlpha(0, 0.24), eps)
        assertEquals(0.5, AsciiFieldTerrain.erosionAlpha(2, 0.50), eps)
        assertEquals(0.5, AsciiFieldTerrain.erosionAlpha(4, 0.76), eps)
    }
}
