package com.cashu.me.ui.components

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.cashu.me.ui.theme.CashuTheme

// Hairline (0.5dp) matches iOS Color(.separator) at @2x — finer than M3's 1dp default.
private val HairlineThickness = 0.5.dp

/**
 * Single hairline used to separate rows on canvas screens (History, Settings root, Mints).
 * 28dp leading inset (spacing.page) aligns with the icon column by default;
 * trailing inset matches row content padding so the line doesn't kiss the screen edge.
 */
@Composable
fun CanvasDivider(
    modifier: Modifier = Modifier,
    leadingInset: Dp = 28.dp,
    trailingInset: Dp = CashuTheme.spacing.comfortable,
) {
    HorizontalDivider(
        thickness = HairlineThickness,
        color = CashuTheme.colors.canvasDivider,
        modifier = modifier.padding(start = leadingInset, end = trailingInset),
    )
}
