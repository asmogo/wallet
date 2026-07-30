package com.cashu.me.ui.components

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.sp
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.ui.theme.withMonoDigits

/** iOS `CurrencyAmountDisplay` primarySize — large enough to read as the hero. */
private val HeroFontSize = 64.sp
/** Matches iOS `.minimumScaleFactor(0.4)`. */
private val HeroMinFontSize = 26.sp

/**
 * The shared hero number for every live amount-entry screen (Send Ecash,
 * Receive Lightning, Unified Send).
 *
 * Mirrors iOS `CurrencyAmountDisplay` entry mode: one bold number with the unit
 * baked *inline* (`₿1,234` / `1,234 sat`) — no separate unit caption. Centered
 * at 64sp SemiBold (iOS primarySize), autoscaling down so long amounts stay on
 * one line. See DESIGN-ANDROID.md §1.
 *
 * @param entryRaw the raw typed amount ("" before the first keypress)
 * @param isSat    true for a sat wallet; false routes through the unit code
 * @param unit     effective unit code for non-sat mints (e.g. "USD")
 * @param decimals fractional places for the empty-state placeholder
 * @param fiatCurrencyCode applies the saved fiat symbol instead of a mint-unit suffix
 * @param color    dims to `onSurfaceVariant` on insufficient balance (Send Ecash)
 */
@Composable
fun AmountEntryHero(
    entryRaw: String,
    isSat: Boolean,
    unit: String,
    decimals: Int,
    useBitcoinSymbol: Boolean,
    formatter: AmountFormatter,
    fiatCurrencyCode: String? = null,
    color: Color = MaterialTheme.colorScheme.onSurface,
) {
    val raw = when {
        entryRaw.isNotEmpty() -> entryRaw
        decimals > 0 -> "0." + "0".repeat(decimals)
        else -> "0"
    }
    AmountText(
        text = if (fiatCurrencyCode != null) {
            formatter.entryFiatDisplay(raw, fiatCurrencyCode)
        } else {
            formatter.entryDisplay(raw, isSat, unit, useBitcoinSymbol)
        },
        modifier = Modifier.fillMaxWidth(),
        style = MaterialTheme.typography.displayMedium
            .copy(
                fontWeight = FontWeight.SemiBold,
                fontSize = HeroFontSize,
                textAlign = TextAlign.Center,
            )
            .withMonoDigits(),
        color = color,
        maxLines = 1,
        autoSize = TextAutoSize.StepBased(
            minFontSize = HeroMinFontSize,
            maxFontSize = HeroFontSize,
        ),
    )
}
