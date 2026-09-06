package com.cashu.me.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.cashu.me.ui.theme.CashuTheme

internal val LocalCompactPaymentDetails = compositionLocalOf { false }

/** Fits the QR around the actual receipt text, with scrolling for oversized content. */
@Composable
fun PaymentDetailContent(
    modifier: Modifier = Modifier,
    hero: @Composable (Dp) -> Unit,
    details: @Composable ColumnScope.() -> Unit,
) {
    var detailsHeight by remember { mutableIntStateOf(0) }
    val density = LocalDensity.current
    BoxWithConstraints(modifier = modifier.fillMaxWidth()) {
        val compact = maxHeight < 600.dp
        val qrSize = minOf(280.dp, maxWidth - 64.dp,
            maxHeight - with(density) { detailsHeight.toDp() } - 64.dp).coerceAtLeast(120.dp)
        Column(
            modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState())
                .padding(horizontal = CashuTheme.spacing.comfortable, vertical = CashuTheme.spacing.snug),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
        ) {
            hero(qrSize)
            CompositionLocalProvider(LocalCompactPaymentDetails provides compact) {
                Column(
                    modifier = Modifier.fillMaxWidth().onSizeChanged { detailsHeight = it.height },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
                    content = details,
                )
            }
        }
    }
}
