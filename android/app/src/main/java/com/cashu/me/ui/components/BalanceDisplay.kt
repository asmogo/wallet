package com.cashu.me.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cashu.me.Core.AmountDisplayText
import com.cashu.me.Core.AmountParts
import com.cashu.me.ui.theme.AmountScale
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.rememberReducedMotion
import com.cashu.me.ui.theme.withMonoDigits

/** Status-line height (titleMedium / delta / empty reserve). */
val BalanceHeroStatusHeight: Dp = 24.dp

/**
 * The hero column's reserved height: primary line box + micro gap + status.
 *
 * Derived from the resolved type metrics rather than being a constant. It stays
 * fixed for a given text size, so a unit swap or a fiat show/hide still cannot
 * reflow the home canvas — that guarantee is why the reservation exists. But it
 * now grows with the text size, so a large-text user is no longer cropped by a
 * box that was sized for the default.
 */
@Composable
fun balanceHeroHeight(): Dp = amountHeroHeight(AmountScale.Hero) + 4.dp + BalanceHeroStatusHeight

/** What occupies the status line under the hero number. */
private sealed interface BalanceStatusLine {
    /** Transient "+2,500" received beat (takes over the fiat slot). */
    data class Delta(val text: String) : BalanceStatusLine

    /** A wallet lifecycle message that takes precedence over the regular sub-amount. */
    data class Status(val text: String) : BalanceStatusLine

    /** The regular fiat/secondary sub-amount. */
    data class Secondary(val text: String) : BalanceStatusLine

    data object None : BalanceStatusLine
}

/**
 * Large hero balance with optional secondary line.
 * Numbers cross-fade on change via [AmountText].
 *
 * Primary and status lines use fixed heights so unit swaps / fiat show-hide never
 * reflow the home canvas (iOS MainWalletView parity).
 *
 * @param receivedDelta transient received-delta beat ("+2,500"): while non-null
 *   it takes over the secondary slot with the sanctioned celebration spring
 *   (scale 0.9 + fade in, fade out), then the fiat line fades back. Same slot,
 *   so the swap never reflows the balance.
 * @param statusMessage wallet lifecycle copy, such as runtime preparation,
 *   shown ahead of the regular secondary amount.
 */
@Composable
fun BalanceDisplay(
    amount: AmountDisplayText,
    modifier: Modifier = Modifier,
    padding: PaddingValues = PaddingValues(),
    receivedDelta: String? = null,
    statusMessage: String? = null,
) {
    val reduceMotion = rememberReducedMotion()
    Column(
        modifier = modifier
            .padding(padding),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.micro),
    ) {
        AmountHero(
            parts = amount.primaryParts,
            scale = AmountScale.Hero,
            accessibilityPrefix = "Balance",
        )
        val statusLine: BalanceStatusLine = when {
            receivedDelta != null -> BalanceStatusLine.Delta(receivedDelta)
            statusMessage != null -> BalanceStatusLine.Status(statusMessage)
            amount.secondary != null -> BalanceStatusLine.Secondary(amount.secondary)
            else -> BalanceStatusLine.None
        }
        Box(
            modifier = Modifier.height(BalanceHeroStatusHeight),
            contentAlignment = Alignment.Center,
        ) {
            AnimatedContent(
                targetState = statusLine,
                transitionSpec = {
                    // Celebration spring only when the delta beat lands; everything
                    // else (fiat return, plain show/hide) is a quiet cross-fade.
                    // Reduce-motion collapses the beat to the same cross-fade.
                    val enter = if (targetState is BalanceStatusLine.Delta && !reduceMotion) {
                        fadeIn(spring(stiffness = Spring.StiffnessMedium)) + scaleIn(
                            animationSpec = spring(
                                dampingRatio = 0.7f,
                                stiffness = Spring.StiffnessMediumLow,
                            ),
                            initialScale = 0.9f,
                        )
                    } else {
                        fadeIn(spring(stiffness = Spring.StiffnessMedium))
                    }
                    enter.togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
                },
                label = "balance-status-line",
            ) { line ->
                when (line) {
                    is BalanceStatusLine.Delta ->
                        // Quiet monochrome beat — no green, no checkmark, no bounce:
                        // the rolling balance above is the primary signal.
                        Text(
                            text = line.text,
                            style = MaterialTheme.typography.titleMedium
                                .withMonoDigits()
                                .copy(fontWeight = FontWeight.SemiBold),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    is BalanceStatusLine.Status ->
                        Text(
                            text = line.text,
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    is BalanceStatusLine.Secondary ->
                        AmountText(
                            text = line.text,
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            animated = false,
                        )
                    BalanceStatusLine.None ->
                        // Keep the slot — invisible stand-in so height never collapses.
                        Text(
                            text = "\u00A0",
                            style = MaterialTheme.typography.titleMedium,
                            color = Color.Transparent,
                        )
                }
            }
        }
    }
}
