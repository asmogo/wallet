package com.cashu.me.ui.onboarding

import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Parity vectors for the vault field (mirrors iOS `AsciiFieldVaultTests`).
 *
 * Like the warp, the vault has no web original: the vectors are generated
 * from the design mock's Python (the same script that renders the approved
 * door) and pasted identically into both platforms' tests. If a port
 * disagrees, fix the port — never the vector. The two half-cell boundary
 * records exist because stencil indexing must round half toward +∞
 * (`floor(v + 0.5)`) on both platforms; Swift's half-away `.rounded()` and a
 * careless Kotlin port both diverge exactly there.
 */
class AsciiFieldVaultTest {
    private data class Record(
        val px: Double,
        val py: Double,
        val t: Double,
        val brightness: Double,
        val level: Int,
    )

    // The living ink means every record carries the terrain's contribution
    // at that cell and moment — levels here are one frozen frame, not
    // resting identities (the bolt record sits between its ₿ moments).
    private val vectors = listOf(
        Record(195.0, 154.0, 2.5, 178.07999999999998, 2), // outer ring top
        Record(195.0, 300.0, 2.5, 227.44, 4), // hub: stencil peak
        Record(195.0, 258.0, 2.5, 35.48, -1), // face fill, blinked out here
        Record(243.0, 300.0, 2.5, 182.99999999999977, 2), // horizontal spoke
        Record(195.0, 208.0, 2.5, 173.88, 2), // inner ring top
        Record(287.0, 300.0, 2.5, 182.99999999999955, 2), // inner ring on the spoke axis
        Record(261.0, 300.0, 2.5, 181.87999999999968, 2), // mid-spoke
        Record(247.0, 248.0, 2.5, 37.44, -1), // off-spoke face, blinked out
        Record(316.0, 300.0, 2.5, 194.64, 2), // bolt center, between ₿ moments
        Record(309.0, 235.0, 2.5, 58.72, 0), // between bolts
        Record(195.0, 450.0, 2.5, 126.40727272727273, 1), // face edge below the wheel
        Record(30.0, 60.0, 2.5, -9.24, -1), // far outside: living ink alone
        Record(201.0, 307.0, 0.0, 38.56, -1), // +half-cell stencil boundary
        Record(189.0, 293.0, 0.0, 207.84, 3), // −half-cell stencil boundary
        Record(219.0, 244.0, 2.5, 205.32, 3), // stencil top bar, right reach
        Record(159.0, 300.0, 2.5, 202.52, 3), // stencil left bar
    )

    @Test
    fun vaultBrightnessMatchesParityVectors() {
        for (r in vectors) {
            val b = AsciiFieldVault.brightness(r.px, r.py, 195.0, 300.0, r.t)
            assertEquals("vault(${r.px}, ${r.py}, t=${r.t})", r.brightness, b, 1e-6)
            assertEquals("level(${r.px}, ${r.py}, t=${r.t})", r.level, AsciiFieldTerrain.displayLevel(b))
        }
    }

    /** One record through the renderer's actual morph expression: terrain
     * (already pinned by the web vectors) lerped against the vault at
     * mix 0.5. Pins the lerp's shape — `terrain + (vault − terrain) · mix` —
     * not just its ingredients. */
    @Test
    fun morphLerpMatchesParityVector() {
        val terrain = AsciiFieldTerrain.brightness(2.3725, 3.045714285714286, 2.5).toDouble()
        assertEquals(151.0, terrain, 1e-9)
        val vault = AsciiFieldVault.brightness(219.0, 328.0, 195.0, 300.0, 2.5)
        assertEquals(58.44, vault, 1e-6)
        val mixed = terrain + (vault - terrain) * 0.5
        assertEquals(104.72, mixed, 1e-6)
        assertEquals(1, AsciiFieldTerrain.displayLevel(mixed))
    }

    /** The continuous-brightness level overloads must agree with the [Int]
     * originals at every threshold edge — they are the same ramp. */
    @Test
    fun continuousLevelsMatchIntegerThresholds() {
        for (threshold in AsciiFieldTerrain.LEVEL_MIN) {
            assertEquals(
                AsciiFieldTerrain.pickLevel(threshold),
                AsciiFieldTerrain.pickLevel(threshold.toDouble()),
            )
            assertEquals(
                AsciiFieldTerrain.pickLevel(threshold - 1),
                AsciiFieldTerrain.pickLevel(threshold - 0.0001),
            )
        }
        assertEquals(3, AsciiFieldTerrain.displayLevel(207.9999))
        assertEquals(4, AsciiFieldTerrain.displayLevel(208.0))
        assertEquals(-1, AsciiFieldTerrain.displayLevel(39.9999))
    }

    /** The constants both ports share; retuning is a keep-in-lockstep edit of
     * both platform files, the mock, and these vectors. */
    @Test
    fun vaultConstantsShape() {
        assertEquals(146.0, AsciiFieldVault.OUTER_RADIUS, 0.0)
        assertEquals(11.0, AsciiFieldVault.OUTER_WIDTH, 0.0)
        assertEquals(196.0, AsciiFieldVault.OUTER_BRIGHTNESS, 0.0)
        assertEquals(92.0, AsciiFieldVault.INNER_RADIUS, 0.0)
        assertEquals(9.0, AsciiFieldVault.INNER_WIDTH, 0.0)
        assertEquals(168.0, AsciiFieldVault.INNER_BRIGHTNESS, 0.0)
        assertEquals(152.0, AsciiFieldVault.FACE_RADIUS, 0.0)
        assertEquals(52.0, AsciiFieldVault.FACE_BRIGHTNESS, 0.0)
        assertEquals(24.0, AsciiFieldVault.SPOKE_MIN_DISTANCE, 0.0)
        assertEquals(96.0, AsciiFieldVault.SPOKE_MAX_DISTANCE, 0.0)
        assertEquals(176.0, AsciiFieldVault.SPOKE_BRIGHTNESS, 0.0)
        assertEquals(8.0, AsciiFieldVault.SPOKE_ARC_WIDTH, 0.0)
        assertEquals(121.0, AsciiFieldVault.BOLT_RADIUS, 0.0)
        assertEquals(8.0, AsciiFieldVault.BOLT_HALF_WIDTH, 0.0)
        assertEquals(212.0, AsciiFieldVault.BOLT_BRIGHTNESS, 0.0)
        assertEquals(221.0, AsciiFieldVault.STENCIL_PEAK_BRIGHTNESS, 0.0)
        assertEquals(202.0, AsciiFieldVault.STENCIL_CURRENCY_BRIGHTNESS, 0.0)
        assertEquals(0.28, AsciiFieldVault.LIVE_GAIN, 0.0)
        assertEquals(128.0, AsciiFieldVault.LIVE_PIVOT, 0.0)
        assertEquals(157.0, AsciiFieldVault.EXTENT_RADIUS, 0.0)
        assertEquals(9, AsciiFieldVault.STENCIL_COLS)
        assertEquals(11, AsciiFieldVault.STENCIL_ROWS)
    }

    /** Beyond the vault's reach the field is the living ink alone
     * (`LIVE_GAIN · (terrain − LIVE_PIVOT)`, bounded by ±35.6), which must
     * stay under the first draw threshold — the renderer's settled-vault
     * fast path skips those cells entirely and relies on this bound. */
    @Test
    fun outsideInkNeverDraws() {
        for (step in 0 until 200) {
            val px = step * 7.3
            val py = step * 11.1 + 1400 // far outside any vault center
            val b = AsciiFieldVault.brightness(px, py, 0.0, 0.0, step * 0.17)
            assertTrue("outside ink exceeded the draw threshold at step $step", abs(b) < 40)
        }
    }
}
