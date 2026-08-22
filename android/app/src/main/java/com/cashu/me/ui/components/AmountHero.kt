package com.cashu.me.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.sp
import com.cashu.me.Core.AmountParts
import com.cashu.me.ui.theme.AmountScale
import com.cashu.me.ui.theme.BitcoinSymbol
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.asSubordinateUnit

/**
 * The gap between the numerals and a unit word, as a fraction of the value's
 * size.
 *
 * Carried by `letterSpacing` on a near-zero-size carrier rather than by a space
 * character, so the gap is an exact measurement instead of whatever advance the
 * face happens to give a space — which differs between families and would
 * silently retune itself on a font swap.
 */
private const val UnitGapEm = 0.15f

/**
 * A currency *symbol* is not a unit *word* and does not want the same handling.
 * `sat` is a label and recedes; the `$` in `$18.42` is part of reading the
 * number, and a greyed, half-size `$` reads as a rendering defect. So a symbol
 * keeps full ink and weight, drops only slightly in size, and tucks tight.
 */
private const val SymbolScale = 0.85f

/**
 * The one hero numeral.
 *
 * Owns the value/unit lockup, tabular figures, the line box and the autoscale
 * floor, so that no caller can get any of them individually wrong — which is
 * how the same amount ended up rendering at six different sizes in two
 * different typefaces before this existed.
 *
 * **One `Text`, two styled runs, deliberately.** An outer `Row` of two `Text`s
 * would let [TextAutoSize] shrink the value and the unit independently, so the
 * size relationship between them would drift exactly when it matters most — on
 * the long amounts that trigger scaling. Runs inside one string scale together.
 *
 * The reserved height is derived from the resolved line box rather than being a
 * constant: stable within a text size, so a unit swap or a fiat show/hide can
 * never reflow the home canvas, but growing with the text size, so large-text
 * users are not cropped. That pair of properties is the whole reason the old
 * fixed `62.dp` had to go.
 */
@Composable
fun AmountHero(
    parts: AmountParts,
    scale: AmountScale,
    modifier: Modifier = Modifier,
    color: Color = LocalContentColor.current,
    animated: Boolean = true,
    accessibilityPrefix: String? = null,
) {
    val style = CashuTheme.type.amount(scale)
    Box(
        modifier = modifier.fillMaxWidth().height(amountHeroHeight(scale)),
        contentAlignment = Alignment.Center,
    ) {
        AmountText(
            text = parts.value,
            annotated = lockup(parts, style),
            style = style,
            color = color,
            animated = animated,
            maxLines = 1,
            autoSize = TextAutoSize.StepBased(
                minFontSize = style.fontSize * AmountHeroMinScale,
                maxFontSize = style.fontSize,
            ),
            semanticsLabel = accessibilityPrefix?.let { "$it: ${parts.spoken}" } ?: parts.spoken,
        )
    }
}

/** One autoscale floor for every hero, rather than the 0.4/0.5/0.7 spread. */
const val AmountHeroMinScale = 0.5f

/** The height an [AmountHero] occupies, for parents that must pre-reserve it. */
@Composable
fun amountHeroHeight(scale: AmountScale): Dp =
    with(LocalDensity.current) { CashuTheme.type.amount(scale).lineHeight.toDp() }

/**
 * Composes the value and its unit into a single styled string.
 *
 * A unit word is demoted on three independent axes — size, weight and ink — so
 * the digits are unmistakably the subject. At parity the unit occupies roughly a
 * third of the lockup while carrying none of the information.
 */
@Composable
private fun lockup(parts: AmountParts, style: TextStyle): AnnotatedString {
    val unitStyle = style.asSubordinateUnit()
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant

    // Baseline-aligned, not cap-aligned.
    //
    // Cap-aligning was tried and looks wrong: a unit word is lowercase, so its
    // visual mass sits at x-height, far below the cap line the alignment
    // targets. Raising it to the digits' cap line leaves it floating like a
    // superscript rather than reading as part of the same amount — and the
    // raised run also overflows the reserved line box, shearing the digits.
    //
    // Sitting the unit on the digits' baseline is what makes the two read as
    // one object. Subordination is carried by size, weight and ink instead,
    // which is enough. A currency *symbol* would be a different case — but a
    // symbol takes the prefix path below and is not demoted at all.
    val wordSpan = SpanStyle(
        fontSize = unitStyle.fontSize,
        fontWeight = unitStyle.fontWeight,
        color = secondary,
    )
    val gapSpan = SpanStyle(
        fontSize = 1.sp,
        letterSpacing = (style.fontSize.value * UnitGapEm).sp,
    )
    val symbolSpan = SpanStyle(fontSize = style.fontSize * SymbolScale)
    val bitcoinSymbolSpan = SpanStyle(
        fontSize = style.fontSize * SymbolScale,
        fontFamily = BitcoinSymbol,
        fontWeight = FontWeight.Bold,
    )

    return buildAnnotatedString {
        when (val affix = parts.affix) {
            is AmountParts.Affix.None -> append(parts.value)
            is AmountParts.Affix.Prefix -> {
                withStyle(if (affix.symbol == "₿") bitcoinSymbolSpan else symbolSpan) {
                    append(affix.symbol)
                }
                append(parts.value)
            }
            is AmountParts.Affix.Suffix -> {
                append(parts.value)
                withStyle(gapSpan) { append(" ") }
                withStyle(wordSpan) { append(affix.word) }
            }
        }
    }
}
