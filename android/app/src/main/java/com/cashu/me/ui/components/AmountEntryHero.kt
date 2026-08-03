package com.cashu.me.ui.components

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.ui.theme.AmountScale

/**
 * The shared hero number for every live amount-entry screen (Send Ecash,
 * Receive Lightning, Unified Send).
 *
 * Decides only *what* to format. Size, weight, tabular figures, the
 * value/unit lockup and the autoscale floor all belong to [AmountHero], so the
 * number being typed here and the balance on the home screen are the same
 * typographic object rather than two that happen to look similar.
 * See DESIGN-ANDROID.md.
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
    AmountHero(
        parts = if (fiatCurrencyCode != null) {
            formatter.entryFiatParts(raw, fiatCurrencyCode)
        } else {
            formatter.entryParts(raw, isSat, unit, useBitcoinSymbol)
        },
        scale = AmountScale.Hero,
        color = color,
    )
}
