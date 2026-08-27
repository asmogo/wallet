package com.cashu.me.ui.theme

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import com.cashu.me.R

/**
 * Geist, as shipped in the vercel/geist-font GitHub release.
 *
 * One variable file per face rather than static instances per weight. The size
 * win is secondary; the decisive argument is that the OpenType-table sourcing
 * mistake can then only be made once. The Google Fonts build of Geist strips
 * the full table, and if that build were ever substituted `withMonoDigits()`
 * would silently stop working and every amount column would start jittering
 * with no error anywhere — so `GeistFeatureTest` asserts `tnum` is live.
 *
 * Variable axis is `wght` 100–900 only; there is no `opsz`, which is why the
 * per-role tracking table in [CashuTracking] is authored by hand.
 */
private fun geistSans(weight: Int) = Font(
    R.font.geist,
    FontWeight(weight),
    variationSettings = FontVariation.Settings(FontVariation.weight(weight)),
)

private fun geistMono(weight: Int) = Font(
    R.font.geist_mono,
    FontWeight(weight),
    variationSettings = FontVariation.Settings(FontVariation.weight(weight)),
)

private fun bitcoinSymbol(weight: Int) = Font(
    R.font.manrope,
    FontWeight(weight),
    variationSettings = FontVariation.Settings(FontVariation.weight(weight)),
)

val GeistSans = FontFamily(
    geistSans(400), geistSans(500), geistSans(600), geistSans(700), geistSans(800),
)

val GeistMono = FontFamily(
    geistMono(400), geistMono(500), geistMono(600), geistMono(700),
)

/**
 * Bitcoin-only fallback for amount lockups. Geist deliberately does not ship
 * U+20BF, so leaving it unspecified would select a different system font per
 * device. Manrope has a compatible geometric construction and a variable
 * weight axis, letting the Bitcoin sign track Geist's numeral weight.
 */
val BitcoinSymbol = FontFamily(
    bitcoinSymbol(400), bitcoinSymbol(500), bitcoinSymbol(600), bitcoinSymbol(700), bitcoinSymbol(800),
)

/**
 * The single point of indirection for the app's typefaces.
 *
 * A family token owns more than a name. It also owns the metrics the
 * typographic lockups depend on ([capHeightRatio], [ascentRatio]) and the
 * per-role tracking table ([tracking]) — because optical fit is a property of
 * the face, not of the role. Keeping all three together is what makes swapping
 * a family a one-file change instead of a re-tuning expedition.
 *
 * Currently resolves to the platform default (Roboto / Droid Sans Mono).
 * Geist Sans + Geist Mono land in their own stage; see DESIGN-ANDROID.md.
 */
@Immutable
data class CashuFonts(
    val sans: FontFamily,
    val mono: FontFamily,
    /**
     * Cap height as a fraction of the em, measured from the shipped face.
     * Drives the cap-aligned unit in the amount lockup: a unit word sits on
     * the value's cap line, not its baseline, so the two read as one object.
     */
    val capHeightRatio: Float,
    /**
     * Ascent as a fraction of the em, measured from the shipped face.
     *
     * Compose's `BaselineShift` is expressed as a multiple of the *ascent*,
     * not as an absolute offset, so converting a cap-height delta into a shift
     * requires this number. It differs between faces, which is exactly why it
     * belongs to the family token — carrying Roboto's value into another face
     * mis-aligns the lockup silently.
     */
    val ascentRatio: Float,
    val tracking: CashuTracking,
) {
    companion object {
        /**
         * The platform faces. [sans] is `SansSerif` rather than `Default`
         * because that is what Material 3's own `TypefaceTokens.Brand` resolves
         * to. Retained as the comparison point for the Geist swap and for
         * screenshot A/B; not what the app provides.
         */
        val System = CashuFonts(
            sans = FontFamily.SansSerif,
            mono = FontFamily.Monospace,
            capHeightRatio = 0.711f,
            ascentRatio = 0.927f,
            tracking = CashuTracking.Roboto,
        )

        /**
         * What the app renders. Ratios are measured from the shipped TTFs
         * (unitsPerEm 1000, OS/2 v4: sCapHeight 710, hhea ascender 1005) and
         * pinned by `GeistFeatureTest`, because the cap-aligned amount lockup
         * mis-aligns silently if they drift.
         *
         * Worth knowing: Geist's cap height (0.710) and x-height (0.530) are
         * within a thousandth of Roboto's. The two faces are metrically near
         * interchangeable, so the Material scale's own tracking carries over
         * unchanged — see [CashuTracking.Geist].
         */
        val Geist = CashuFonts(
            sans = GeistSans,
            mono = GeistMono,
            capHeightRatio = 0.710f,
            ascentRatio = 1.005f,
            tracking = CashuTracking.Geist,
        )
    }
}

/**
 * Per-role tracking, in **em**.
 *
 * Em rather than `sp` is deliberate. The five copy-pasted `.tracking(1.2)`
 * overlines on iOS are 0.1em frozen at 12pt: correct at one size and wrong at
 * every other, because a point value cannot scale. Expressing tracking as a
 * fraction of the em and resolving it against the live size fixes that by
 * construction.
 *
 * Values are authored per family. A face with an optical-size axis applies
 * much of this automatically; a face without one does not, which makes this
 * table load-bearing rather than decorative.
 */
@Immutable
data class CashuTracking(
    val amountHero: Float,
    val amountConfirm: Float,
    val amountCompact: Float,
    val amountRow: Float,
    /** Display headings tighten; -0.0139em is the -0.5sp this replaced. */
    val title: Float,
    /** The documented overline value: 0.06em = 0.72sp at 12sp. */
    val overline: Float,
    val buttonLabel: Float,
    val sheetTitle: Float,
    /** Monospaced faces are already fitted; extra tracking only hurts. */
    val mono: Float,
) {
    companion object {
        /**
         * Roboto. The Material 3 scale already carries Roboto's own reading
         * compensation on the text roles, so only the app-specific roles are
         * tracked here. Display-size numerals want tightening that M3's
         * `displayMedium`/`displaySmall` (both 0.0) do not provide — M3's own
         * `displayLarge` ships -0.2sp at 57sp for the same reason.
         */
        val Roboto = CashuTracking(
            amountHero = -0.015f,
            amountConfirm = -0.010f,
            amountCompact = -0.005f,
            amountRow = 0f,
            title = -0.0139f,
            overline = 0.060f,
            buttonLabel = 0f,
            sheetTitle = 0f,
            mono = 0f,
        )

        /**
         * Geist. Identical to [Roboto], and deliberately so.
         *
         * The expectation going in was that Geist would need its own table
         * because Material's text-role tracking is Roboto legibility
         * compensation. Measuring the shipped TTF killed that argument: Geist's
         * cap height and x-height match Roboto's to three decimal places, so
         * the compensation transfers. The loose amount column that prompted the
         * question is fixed by `amountRow` carrying zero tracking — a property
         * of the role, not of the face.
         *
         * Kept as a separate constant so a real divergence has somewhere
         * obvious to go, and so the two faces can be A/B'd without editing one
         * shared table.
         */
        val Geist = Roboto
    }
}

val LocalCashuFonts = staticCompositionLocalOf { CashuFonts.Geist }
