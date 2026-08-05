package com.cashu.me.ui.onboarding

import java.io.File
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Golden-vector parity for the ASCII field terrain.
 *
 * docs/product/ascii-field-vectors.json is generated from the cashu.space
 * website's TypeScript (ascii-field.tsx), never from either native port — it
 * is the only thing that proves two independently hand-written ports compute
 * identical terrain. A transposed coefficient produces terrain that looks
 * plausible and is silently wrong; these assertions are how it gets caught.
 * If a record here fails, fix the port — never the fixture.
 */
class AsciiFieldTerrainTest {
    @Serializable
    private data class TerrainRecord(
        val x: Double,
        val y: Double,
        val t: Double,
        val f: Double,
        val b: Int,
        val level: Int,
    )

    @Serializable
    private data class CurrencyRecord(val px: Double, val py: Double, val glyph: String)

    @Serializable
    private data class Fixture(
        val terrain: List<TerrainRecord>,
        val currency: List<CurrencyRecord>,
    )

    private fun loadFixture(): Fixture {
        // Walk up from the module working directory (android/app under
        // Gradle) to the repo root that holds docs/.
        var dir: File? = File(System.getProperty("user.dir")!!)
        while (dir != null) {
            val candidate = File(dir, "docs/product/ascii-field-vectors.json")
            if (candidate.exists()) {
                return Json.decodeFromString(candidate.readText())
            }
            dir = dir.parentFile
        }
        error("ascii-field-vectors.json not found above ${System.getProperty("user.dir")}")
    }

    @Test
    fun terrainMatchesWebVectors() {
        val fixture = loadFixture()
        assertTrue("fixture unexpectedly thin", fixture.terrain.size >= 40)
        for (record in fixture.terrain) {
            assertEquals(
                "fractal(${record.x}, ${record.y}, ${record.t})",
                record.f,
                AsciiFieldTerrain.fractal(record.x, record.y, record.t),
                1e-4,
            )
            val brightness = AsciiFieldTerrain.brightness(record.x, record.y, record.t)
            assertEquals(
                "brightness(${record.x}, ${record.y}, ${record.t})",
                record.b.toDouble(),
                brightness.toDouble(),
                1e-4,
            )
            assertEquals(
                "level(${record.x}, ${record.y}, ${record.t})",
                record.level,
                AsciiFieldTerrain.pickLevel(brightness),
            )
        }
    }

    /**
     * The currency hash relies on JS Math.imul (32-bit signed wraparound) and
     * `>>>` (unsigned shift) semantics. The fixture includes coordinates
     * large enough that a widened multiply silently diverges.
     */
    @Test
    fun currencyGlyphsMatchWebVectors() {
        val fixture = loadFixture()
        assertTrue("fixture unexpectedly thin", fixture.currency.size >= 10)
        for (record in fixture.currency) {
            val index = AsciiFieldTerrain.currencyGlyphIndex(record.px, record.py)
            assertEquals(
                "currency(${record.px}, ${record.py})",
                record.glyph,
                AsciiFieldTerrain.CURRENCY_GLYPHS[index],
            )
        }
    }

    /** The level thresholds and glyph tables must stay in lockstep with the
     * web constants the fixture was generated from. */
    @Test
    fun levelTableShape() {
        assertTrue(AsciiFieldTerrain.LEVEL_MIN.contentEquals(intArrayOf(40, 90, 140, 200, 216)))
        assertEquals(listOf("·", "/", ","), AsciiFieldTerrain.LEVEL_GLYPH)
        assertEquals(listOf("$", "¥", "€"), AsciiFieldTerrain.CURRENCY_GLYPHS)
        assertEquals(-1, AsciiFieldTerrain.pickLevel(39))
        assertEquals(0, AsciiFieldTerrain.pickLevel(40))
        assertEquals(4, AsciiFieldTerrain.pickLevel(255))
    }
}
