package com.cashu.me.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp

// ---------------------------------------------------------------------------
// Leading
// ---------------------------------------------------------------------------

/** Prose and UI text. Roomy enough to read a paragraph in. */
const val LeadingText = 1.4f

/** Display numerals. Big type needs proportionally less air, not more. */
const val LeadingHero = 1.1f

/** Single-line labels: buttons, sheet titles, overlines. */
const val LeadingLabel = 1.3f

// ---------------------------------------------------------------------------
// The size primitive
// ---------------------------------------------------------------------------

/**
 * The **only** sanctioned way to change a [TextStyle]'s size.
 *
 * Every bare `copy(fontSize = …)` written in this app orphaned its line
 * height, because `copy` carries the old one forward. The worst case was
 * `displayMedium.copy(fontSize = 64.sp)`, which kept `displayMedium`'s 52sp
 * line box — a 0.81x ratio that vertically crops the glyph. The balance hero
 * managed the same trick at 53sp in the same 52sp box, so the font was
 * literally larger than the line it sat on.
 *
 * Here the line box is a *function* of the size, so the ratio cannot drift.
 * Tracking is em-relative for the same reason: a hardcoded `sp` value is
 * correct at exactly one size and wrong at every other.
 *
 * `TypographyGuardTest` fails the build on any bare `fontSize` override
 * outside this file, so the bug cannot come back.
 *
 * @param leading multiple of [size]; becomes the resulting line box.
 * @param trackingEm tracking as a fraction of the em.
 */
fun TextStyle.atSize(
    size: TextUnit,
    leading: Float = LeadingText,
    trackingEm: Float = 0f,
): TextStyle = copy(
    fontSize = size,
    lineHeight = size * leading,
    letterSpacing = (size.value * trackingEm).sp,
    lineHeightStyle = LineHeightStyle(
        alignment = LineHeightStyle.Alignment.Center,
        trim = LineHeightStyle.Trim.None,
    ),
)

/** Retrack without resizing. Em-relative, so it survives a size change. */
fun TextStyle.tracked(em: Float): TextStyle =
    copy(letterSpacing = (fontSize.value * em).sp)

// ---------------------------------------------------------------------------
// OpenType features
// ---------------------------------------------------------------------------

/**
 * Tabular figures. Every balance, amount and fee chains this, so digits keep a
 * fixed advance and a changing number rolls instead of reflowing — numeric
 * jitter on money reads as broken. See DESIGN.md, The Tabular Figure Rule.
 */
fun TextStyle.withMonoDigits(): TextStyle =
    copy(fontFeatureSettings = listOfNotNull(this.fontFeatureSettings, "tnum").joinToString(", "))

/**
 * Slashed zero, for the monospaced roles — a `0` beside an `O` in a mnemonic
 * word, token id, npub or Lightning address is a transcription error waiting to
 * happen.
 *
 * Reached through **`ss09`, not the standard `zero` feature**: Geist ships no
 * `zero` feature in either face, but does carry a `zero.ss09` alternate that
 * `ss09` substitutes in. (On Geist Sans the same set also disambiguates `1`,
 * which is why this is applied to the mono roles only rather than app-wide.)
 *
 * A face without the feature ignores it rather than failing, and a slashed zero
 * has the same advance as a plain one — so no measurement can detect it. The
 * guard for this is necessarily a rendered pixel test.
 */
fun TextStyle.withSlashedZero(): TextStyle =
    copy(fontFeatureSettings = listOfNotNull(this.fontFeatureSettings, "ss09").joinToString(", "))

// ---------------------------------------------------------------------------
// The Material scale
// ---------------------------------------------------------------------------

private val M3 = Typography()

private fun TextStyle.on(family: FontFamily): TextStyle = copy(fontFamily = family)

/**
 * The Material 3 type scale, written out in full.
 *
 * Every role is listed even where it matches stock. That is deliberate: the
 * scale becomes greppable and diffable, each line is the obvious place for a
 * per-family delta to land, and `TypographyGuardTest` can assert that this
 * differs from stock only in the family and in deltas we declare — so a
 * Material upgrade that moves a token underneath us fails loudly instead of
 * quietly reshaping the app.
 *
 * Sizes, line heights and tracking are Material's own. Geist's cap height and
 * x-height are within a thousandth of Roboto's, so Material's Roboto-tuned
 * reading tracking transfers rather than needing to be re-authored; see
 * [CashuTracking.Geist].
 */
fun cashuTypography(fonts: CashuFonts): Typography {
    val sans = fonts.sans
    return Typography(
        displayLarge = M3.displayLarge.on(sans),
        displayMedium = M3.displayMedium.on(sans),
        displaySmall = M3.displaySmall.on(sans),
        headlineLarge = M3.headlineLarge.on(sans),
        headlineMedium = M3.headlineMedium.on(sans),
        headlineSmall = M3.headlineSmall.on(sans),
        titleLarge = M3.titleLarge.on(sans),
        titleMedium = M3.titleMedium.on(sans),
        titleSmall = M3.titleSmall.on(sans),
        bodyLarge = M3.bodyLarge.on(sans),
        bodyMedium = M3.bodyMedium.on(sans),
        bodySmall = M3.bodySmall.on(sans),
        labelLarge = M3.labelLarge.on(sans),
        labelMedium = M3.labelMedium.on(sans),
        labelSmall = M3.labelSmall.on(sans),
    )
}

// ---------------------------------------------------------------------------
// The amount ladder
// ---------------------------------------------------------------------------

/**
 * The four sizes an amount is ever set at. Amounts are typed by *role*, never
 * by point size — six different sizes serving this one role is how the same
 * number ended up rendering in two different typefaces on adjacent screens.
 */
enum class AmountScale { Hero, Confirm, Compact, Row }

/**
 * The unit's size as a fraction of the value's.
 *
 * 0.5 is two rungs of the ladder, and combines with a weight step and a drop to
 * secondary ink for three independent axes of subordination. The unit is a
 * label, not a quantity; at parity it occupies roughly a third of the lockup
 * while carrying none of the information.
 */
const val AmountUnitScale = 0.5f

/** One step down the weight ramp, for the subordinated unit. */
private fun FontWeight.oneStepDown(): FontWeight = when (this) {
    FontWeight.Bold -> FontWeight.SemiBold
    FontWeight.SemiBold -> FontWeight.Medium
    FontWeight.Medium -> FontWeight.Normal
    else -> FontWeight.Normal
}

/**
 * Derives the unit run's style from the value's, so the relationship holds at
 * every rung of the ladder and through a family swap.
 *
 * Vertical placement is not set here — the unit sits on the value's *cap* line
 * rather than its baseline, which needs font metrics and therefore belongs to
 * the lockup component.
 */
fun TextStyle.asSubordinateUnit(): TextStyle =
    atSize(size = fontSize * AmountUnitScale, leading = LeadingHero)
        .copy(fontWeight = (fontWeight ?: FontWeight.Normal).oneStepDown())

// ---------------------------------------------------------------------------
// App roles
// ---------------------------------------------------------------------------

/**
 * The app-specific roles, layered on the Material scale.
 *
 * Follows the [CashuSpacing] / [CashuIconSizes] pattern: an immutable value
 * provided through a composition local and read as `CashuTheme.type`.
 */
@Immutable
data class CashuTypeRoles(
    // Money.
    val amountHero: TextStyle,
    val amountConfirm: TextStyle,
    val amountCompact: TextStyle,
    val amountRow: TextStyle,
    // Structure.
    val title: TextStyle,
    val overline: TextStyle,
    val buttonLabel: TextStyle,
    val sheetTitle: TextStyle,
    val numberPadKey: TextStyle,
    val metadata: TextStyle,
    // Technical strings.
    val monoDisplay: TextStyle,
    val monoBody: TextStyle,
    val monoCaption: TextStyle,
) {
    fun amount(scale: AmountScale): TextStyle = when (scale) {
        AmountScale.Hero -> amountHero
        AmountScale.Confirm -> amountConfirm
        AmountScale.Compact -> amountCompact
        AmountScale.Row -> amountRow
    }
}

fun cashuTypeRoles(fonts: CashuFonts = CashuFonts.Geist): CashuTypeRoles {
    val t = fonts.tracking
    val m3 = cashuTypography(fonts)
    return CashuTypeRoles(
        // Match iOS's 64pt hero base so the Home balance and live amount-entry
        // screens carry the same visual weight on both platforms. Long values
        // still share AmountHero's 0.5 autosize floor, so parity does not cost
        // narrow-screen resilience.
        amountHero = m3.displayMedium
            .atSize(64.sp, leading = LeadingHero, trackingEm = t.amountHero)
            .copy(fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
            .withMonoDigits(),

        amountConfirm = m3.displaySmall
            .atSize(40.sp, leading = LeadingHero, trackingEm = t.amountConfirm)
            .copy(fontWeight = FontWeight.SemiBold)
            .withMonoDigits(),

        amountCompact = m3.headlineMedium
            .atSize(28.sp, leading = 1.15f, trackingEm = t.amountCompact)
            .copy(fontWeight = FontWeight.SemiBold)
            .withMonoDigits(),

        // Money in list rows. Tracking is explicitly zero: Material's bodyLarge
        // carries +0.5sp of Roboto reading compensation, which on an amount
        // column reads as slack rather than legibility.
        amountRow = m3.bodyLarge
            .atSize(16.sp, leading = 1.5f, trackingEm = t.amountRow)
            .copy(fontWeight = FontWeight.Medium)
            .withMonoDigits(),

        // The onboarding / restore hero heading. Display leading is deliberately
        // tighter than Material's 44sp default: a heading this size needs less
        // air between lines, not more.
        title = m3.displaySmall
            .atSize(36.sp, leading = 1.11f, trackingEm = t.title)
            .copy(fontWeight = FontWeight.ExtraBold),

        // Section headers. Casing belongs to the component, not the style.
        overline = m3.labelMedium
            .atSize(12.sp, leading = LeadingLabel, trackingEm = t.overline)
            .copy(fontWeight = FontWeight.SemiBold),

        buttonLabel = m3.titleMedium
            .atSize(18.sp, leading = LeadingLabel, trackingEm = t.buttonLabel)
            .copy(fontWeight = FontWeight.SemiBold),

        sheetTitle = m3.titleMedium
            .atSize(19.sp, leading = 1.26f, trackingEm = t.sheetTitle)
            .copy(fontWeight = FontWeight.SemiBold),

        // Tabular, so key widths don't shimmer as the pressed digit changes.
        numberPadKey = m3.headlineSmall.withMonoDigits(),

        // Timestamps and secondary row text. One step up from the 12sp floor:
        // metadata is already demoted by secondary ink, and 12sp on top of that
        // is a double demotion that pushes it under the legibility line.
        metadata = m3.bodyMedium,

        // The value a QR/receipt sheet displays under its code — the technical
        // string as the sheet's second focal point, not a caption-sized
        // footnote (iOS `monoDisplay` parity).
        monoDisplay = m3.bodyLarge
            .copy(fontFamily = fonts.mono)
            .tracked(t.mono)
            .withSlashedZero(),

        monoBody = m3.bodyMedium
            .copy(fontFamily = fonts.mono)
            .tracked(t.mono)
            .withSlashedZero(),

        monoCaption = m3.bodySmall
            .copy(fontFamily = fonts.mono)
            .tracked(t.mono)
            .withSlashedZero(),
    )
}

val LocalCashuTypeRoles = staticCompositionLocalOf { cashuTypeRoles() }
