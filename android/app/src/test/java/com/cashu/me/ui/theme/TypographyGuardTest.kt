package com.cashu.me.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.sp
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The ratchet.
 *
 * This layer exists because the type system was written in prose and never in
 * code, so every refinement landed at a call site and the whole thing drifted.
 * Rebuilding it fixes the present; these tests are what stop it happening
 * again. They are deliberately mechanical — the point is that they fail in CI
 * rather than relying on a reviewer noticing.
 */
class TypographyGuardTest {

    private val uiRoot: File =
        sequenceOf(File("src/main/java/com/cashu/me/ui"), File("app/src/main/java/com/cashu/me/ui"))
            .firstOrNull { it.isDirectory }
            ?: error("cannot locate the ui source root")

    private fun sources(): List<Pair<String, String>> =
        uiRoot.walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            // The type layer itself. AmountHero composes the value/unit runs,
            // so setting an explicit span size and tracking is precisely its job.
            .filterNot { it.name in setOf("Type.kt", "CashuFonts.kt", "AmountHero.kt") }
            .map { it.relativeTo(uiRoot).path to it.readText() }
            .toList()

    /**
     * A size change is a line-box change.
     *
     * `copy(fontSize = …)` carries the old line height forward, which is how
     * `displayMedium.copy(fontSize = 64.sp)` ended up rendering 64sp type in a
     * 52sp box — a 0.81x ratio that vertically crops the glyph. `atSize()`
     * makes the line box a function of the size so the ratio cannot drift.
     *
     * The allowlist is empty and must stay that way. Adding an entry means
     * consciously accepting a cropped line box.
     */
    @Test
    fun `no bare fontSize override outside the type layer`() {
        val allowed = emptySet<String>()
        val offenders = sources()
            .filter { (_, text) -> FONT_SIZE_OVERRIDE.containsMatchIn(text) }
            .map { (path, _) -> path }
            .filterNot { it in allowed }

        assertTrue(
            "Use TextStyle.atSize(size, leading) instead. A bare fontSize override orphans " +
                "the line height — see the 0.81x displayMedium crop this replaced. Offenders: $offenders",
            offenders.isEmpty(),
        )
    }

    /**
     * Tracking is expressed in em and resolved against the live size.
     *
     * A hardcoded `sp` value is correct at exactly one size and wrong at every
     * other, which is what made the six copy-pasted overlines diverge.
     */
    @Test
    fun `no hardcoded letterSpacing outside the type layer`() {
        val offenders = sources()
            .filter { (_, text) -> LETTER_SPACING.containsMatchIn(text) }
            .map { (path, _) -> path }

        assertTrue(
            "Use CashuTheme.type.* or TextStyle.tracked(em). A literal sp tracking value " +
                "does not scale with the text. Offenders: $offenders",
            offenders.isEmpty(),
        )
    }

    /** Every role must give its glyphs at least as much line as they occupy. */
    @Test
    fun `every role has a line box no smaller than its type`() {
        allRoles().forEach { (name, style) ->
            val size = style.fontSize.value
            val line = style.lineHeight.value
            assertTrue(
                "$name sets ${size}sp type in a ${line}sp line box",
                line >= size * 1.05f,
            )
        }
    }

    /** Keep the shared Home and entry hero aligned with iOS's 64pt base. */
    @Test
    fun `amount hero matches the cross-platform scale`() {
        assertEquals(64.sp, cashuTypeRoles(CashuFonts.Geist).amountHero.fontSize)
    }

    /**
     * Fires when a Material upgrade moves a token underneath the explicit
     * scale. The scale is written out in full precisely so this can be checked:
     * anything that differs from stock beyond the declared family swap is drift
     * we did not choose.
     */
    @Test
    fun `the Material scale differs from stock only in font family`() {
        val stock = Typography()
        val ours = cashuTypography(CashuFonts.Geist)
        materialRoles(stock).forEach { (name, stockStyle) ->
            val ourStyle = materialRoles(ours).getValue(name)
            assertEquals("$name size drifted", stockStyle.fontSize, ourStyle.fontSize)
            assertEquals("$name line height drifted", stockStyle.lineHeight, ourStyle.lineHeight)
            assertEquals("$name tracking drifted", stockStyle.letterSpacing, ourStyle.letterSpacing)
            assertEquals("$name weight drifted", stockStyle.fontWeight, ourStyle.fontWeight)
            assertEquals("$name should carry Geist", CashuFonts.Geist.sans, ourStyle.fontFamily)
        }
    }

    /**
     * The role budget. An unbounded vocabulary is the old drift wearing a nicer
     * API, so growing it should be a deliberate, reviewed act.
     */
    @Test
    fun `role inventory is frozen`() {
        assertEquals(
            "Adding or removing a role is a design decision — update this count deliberately",
            13,
            allRoles().size,
        )
    }

    /** Every money role carries tabular figures. */
    @Test
    fun `money roles are tabular`() {
        val roles = cashuTypeRoles(CashuFonts.Geist)
        AmountScale.entries.forEach { scale ->
            val features = roles.amount(scale).fontFeatureSettings.orEmpty()
            assertTrue("$scale is not tabular", "tnum" in features)
        }
    }

    /** The mono roles carry the slashed zero. */
    @Test
    fun `mono roles disambiguate zero`() {
        val roles = cashuTypeRoles(CashuFonts.Geist)
        listOf(
            "monoDisplay" to roles.monoDisplay,
            "monoBody" to roles.monoBody,
            "monoCaption" to roles.monoCaption,
        )
            .forEach { (name, style) ->
                assertTrue("$name lacks ss09", "ss09" in style.fontFeatureSettings.orEmpty())
                assertEquals("$name is not Geist Mono", CashuFonts.Geist.mono, style.fontFamily)
            }
    }

    private fun allRoles(): Map<String, TextStyle> = cashuTypeRoles(CashuFonts.Geist).let { r ->
        mapOf(
            "amountHero" to r.amountHero,
            "amountConfirm" to r.amountConfirm,
            "amountCompact" to r.amountCompact,
            "amountRow" to r.amountRow,
            "title" to r.title,
            "overline" to r.overline,
            "buttonLabel" to r.buttonLabel,
            "sheetTitle" to r.sheetTitle,
            "numberPadKey" to r.numberPadKey,
            "metadata" to r.metadata,
            "monoDisplay" to r.monoDisplay,
            "monoBody" to r.monoBody,
            "monoCaption" to r.monoCaption,
        )
    }

    private fun materialRoles(t: Typography): Map<String, TextStyle> = mapOf(
        "displayLarge" to t.displayLarge, "displayMedium" to t.displayMedium,
        "displaySmall" to t.displaySmall, "headlineLarge" to t.headlineLarge,
        "headlineMedium" to t.headlineMedium, "headlineSmall" to t.headlineSmall,
        "titleLarge" to t.titleLarge, "titleMedium" to t.titleMedium,
        "titleSmall" to t.titleSmall, "bodyLarge" to t.bodyLarge,
        "bodyMedium" to t.bodyMedium, "bodySmall" to t.bodySmall,
        "labelLarge" to t.labelLarge, "labelMedium" to t.labelMedium,
        "labelSmall" to t.labelSmall,
    )

    private companion object {
        /** `.copy(fontSize = …)` and `base.fontSize * 1.2f`-style rescaling. */
        val FONT_SIZE_OVERRIDE = Regex("""fontSize\s*=(?![^\n]*\batSize\b)|\.fontSize\s*\*""")
        val LETTER_SPACING = Regex("""letterSpacing\s*=""")
    }
}
