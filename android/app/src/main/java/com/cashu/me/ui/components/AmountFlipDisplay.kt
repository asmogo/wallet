package com.cashu.me.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.displayText
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withMonoDigits

private val FlipPillIconSize = 14.dp

/**
 * Hero amount with a tappable unit-flip pill beneath it — the Compose port of
 * iOS `CurrencyAmountDisplay`: the primary amount renders large, the secondary
 * (fiat or sats) sits in a small capsule with a ↕ glyph; tapping the pill
 * swaps which unit leads. The swap cross-fades, same as subsequent value
 * changes via [AmountText].
 *
 * When no fiat price is available the pill is omitted and the amount renders
 * plain in sats.
 */
@Composable
fun AmountFlipDisplay(
    amountSats: Long,
    primary: AmountDisplayPrimary,
    onFlip: (AmountDisplayPrimary) -> Unit,
    btcPrice: Double?,
    currencyCode: String,
    useBitcoinSymbol: Boolean,
    modifier: Modifier = Modifier,
    primaryTextStyle: TextStyle? = null,
    primaryAccessibilityPrefix: String? = null,
) {
    val haptics = LocalHapticFeedback.current
    val formatter = remember { AmountFormatter() }
    val display = formatter.displayText(
        amountSats = amountSats,
        preferredPrimary = primary.rawValue,
        showFiat = btcPrice != null && btcPrice > 0,
        btcPrice = btcPrice,
        currencyCode = currencyCode,
        useBitcoinSymbol = useBitcoinSymbol,
    )
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
    ) {
        // The flip itself cross-fades the whole hero; inside a given unit,
        // amount changes roll via the keyed digit ticker.
        AnimatedContent(
            targetState = display.effectivePrimary,
            transitionSpec = {
                fadeIn(spring(stiffness = Spring.StiffnessMedium))
                    .togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
            },
            label = "amount-flip-hero",
        ) { primaryState ->
            // Re-derive the text for the state being rendered so the outgoing
            // copy keeps its own unit during the cross-fade.
            val stateDisplay = formatter.displayText(
                amountSats = amountSats,
                preferredPrimary = primaryState.rawValue,
                showFiat = btcPrice != null && btcPrice > 0,
                btcPrice = btcPrice,
                currencyCode = currencyCode,
                useBitcoinSymbol = useBitcoinSymbol,
            )
            AmountText(
                text = stateDisplay.primary,
                modifier = if (primaryAccessibilityPrefix != null) {
                    Modifier.semantics {
                        contentDescription = "$primaryAccessibilityPrefix: ${stateDisplay.primary}"
                    }
                } else {
                    Modifier
                },
                style = (primaryTextStyle ?: MaterialTheme.typography.displayMedium).withMonoDigits(),
            )
        }
        val secondary = display.secondary
        if (secondary != null) {
            Row(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.surfaceVariant)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        role = Role.Button,
                        onClickLabel = "Make $secondary primary",
                    ) {
                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        onFlip(
                            if (display.effectivePrimary == AmountDisplayPrimary.Fiat) {
                                AmountDisplayPrimary.Sats
                            } else {
                                AmountDisplayPrimary.Fiat
                            },
                        )
                    }
                    .semantics(mergeDescendants = true) {
                        role = Role.Button
                        contentDescription = "Alternate amount: $secondary. Tap to make it primary."
                    }
                    .padding(
                        horizontal = CashuTheme.spacing.default,
                        vertical = CashuTheme.spacing.micro,
                    ),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.micro),
            ) {
                AnimatedContent(
                    targetState = secondary,
                    transitionSpec = {
                        fadeIn(spring(stiffness = Spring.StiffnessMedium))
                            .togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
                    },
                    label = "amount-flip-pill",
                ) { text ->
                    Text(
                        text = text,
                        style = MaterialTheme.typography.labelLarge.withMonoDigits(),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Icon(
                    imageVector = Icons.Outlined.SwapVert,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(FlipPillIconSize),
                )
            }
        }
    }
}
