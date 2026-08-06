package com.cashu.me.ui.theme

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards the shipped Geist binaries.
 *
 * The failure this exists to prevent is silent. Geist is published in two
 * builds: the GitHub release carries the full OpenType table, and the Google
 * Fonts build strips it. Swap one for the other and nothing errors — but
 * `withMonoDigits()` stops resolving, digits lose their fixed advance, and
 * every amount column in the wallet starts jittering as values change. There is
 * no crash, no log, and no test failure anywhere else to catch it.
 *
 * So rather than measuring rendered text — which needs a device, and which a
 * face whose default figures happen to be tabular would pass trivially — this
 * reads the font tables directly and asserts the features are actually present.
 *
 * It also pins the metrics the amount lockup aligns against. The unit sits on
 * the value's cap line; if `capHeightRatio` drifts from the shipped face the
 * lockup mis-aligns with nothing to indicate why.
 */
class GeistFontTest {

    private fun fontFile(name: String): File =
        sequenceOf(File("src/main/res/font/$name"), File("app/src/main/res/font/$name"))
            .firstOrNull { it.exists() }
            ?: error("Geist font $name is missing from res/font — the bundle is incomplete")

    // -- Minimal TTF table reader. Enough to read the feature list and metrics,
    //    and no dependency to add for it.

    private class Ttf(val bytes: ByteArray) {
        private fun u16(o: Int) = ((bytes[o].toInt() and 0xFF) shl 8) or (bytes[o + 1].toInt() and 0xFF)
        private fun s16(o: Int) = u16(o).toShort().toInt()
        private fun u32(o: Int) = (u16(o).toLong() shl 16) or u16(o + 2).toLong()

        private val tables: Map<String, Int> = buildMap {
            repeat(u16(4)) { i ->
                val rec = 12 + i * 16
                val tag = String(bytes, rec, 4, Charsets.ISO_8859_1)
                put(tag, u32(rec + 8).toInt())
            }
        }

        val unitsPerEm: Int get() = u16(tables.getValue("head") + 18)
        val capHeightRatio: Float get() = s16(tables.getValue("OS/2") + 88) / unitsPerEm.toFloat()
        val xHeightRatio: Float get() = s16(tables.getValue("OS/2") + 86) / unitsPerEm.toFloat()
        val ascentRatio: Float get() = s16(tables.getValue("hhea") + 4) / unitsPerEm.toFloat()

        /** Every feature tag registered in a layout table. */
        fun features(table: String): Set<String> {
            val base = tables[table] ?: return emptySet()
            val list = base + u16(base + 6)
            return (0 until u16(list)).mapTo(mutableSetOf()) { i ->
                String(bytes, list + 2 + i * 6, 4, Charsets.ISO_8859_1)
            }
        }

        /** Variable-font axis tags. */
        fun axes(): Set<String> {
            val base = tables["fvar"] ?: return emptySet()
            val arrayOffset = u16(base + 4)
            val count = u16(base + 8)
            val size = u16(base + 10)
            return (0 until count).mapTo(mutableSetOf()) { i ->
                String(bytes, base + arrayOffset + i * size, 4, Charsets.ISO_8859_1)
            }
        }
    }

    private val sans get() = Ttf(fontFile("geist.ttf").readBytes())
    private val mono get() = Ttf(fontFile("geist_mono.ttf").readBytes())

    @Test
    fun `Geist Sans ships tabular figures`() {
        assertTrue(
            "geist.ttf has no 'tnum' feature. This is the Google Fonts build, which strips " +
                "the OpenType table — withMonoDigits() will silently no-op and every amount " +
                "column will jitter. Ship the GitHub release TTF instead.",
            "tnum" in sans.features("GSUB"),
        )
    }

    /**
     * The slashed zero is reached through `ss09`, not the standard `zero`
     * feature, which Geist does not ship. [TextStyle.withSlashedZero] depends
     * on that being true of the bundled file.
     */
    @Test
    fun `both faces ship the ss09 slashed zero`() {
        assertTrue("geist.ttf has no 'ss09'", "ss09" in sans.features("GSUB"))
        assertTrue("geist_mono.ttf has no 'ss09'", "ss09" in mono.features("GSUB"))
    }

    /**
     * Documents why `withSlashedZero()` uses `ss09`. If a future Geist release
     * adds a real `zero` feature this fails, and the helper should switch to it.
     */
    @Test
    fun `neither face ships a standard zero feature`() {
        assertFalse("geist.ttf now has 'zero' — prefer it over ss09", "zero" in sans.features("GSUB"))
        assertFalse("geist_mono.ttf now has 'zero' — prefer it over ss09", "zero" in mono.features("GSUB"))
    }

    /**
     * Geist varies on weight alone. Without an optical-size axis nothing
     * compensates display sizes automatically, which is what makes the
     * hand-authored [CashuTracking] table load-bearing rather than cosmetic.
     */
    @Test
    fun `Geist varies on weight only`() {
        assertEquals(setOf("wght"), sans.axes())
        assertEquals(setOf("wght"), mono.axes())
    }

    /**
     * Pins the metrics [CashuFonts.Geist] declares. The cap-aligned unit in the
     * amount lockup is computed from these; a drift here mis-aligns it silently.
     */
    @Test
    fun `declared metrics match the shipped faces`() {
        assertEquals(CashuFonts.Geist.capHeightRatio, sans.capHeightRatio, 0.001f)
        assertEquals(CashuFonts.Geist.ascentRatio, sans.ascentRatio, 0.001f)
        assertEquals(CashuFonts.Geist.capHeightRatio, mono.capHeightRatio, 0.001f)
        assertEquals(CashuFonts.Geist.ascentRatio, mono.ascentRatio, 0.001f)
    }

    /**
     * Records the finding that settled the tracking question: Geist and Roboto
     * are metrically near-identical, so Material's Roboto-tuned reading
     * tracking transfers unchanged instead of needing a Geist-specific table.
     * If a future release moves these, revisit [CashuTracking.Geist].
     */
    @Test
    fun `Geist stays metrically interchangeable with Roboto`() {
        assertEquals(CashuFonts.System.capHeightRatio, sans.capHeightRatio, 0.005f)
        assertEquals(0.528f, sans.xHeightRatio, 0.005f)
    }
}
