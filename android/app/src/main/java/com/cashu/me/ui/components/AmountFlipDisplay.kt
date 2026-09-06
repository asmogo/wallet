package com.cashu.me.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.AmountDisplayText
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.displayText
import com.cashu.me.ui.theme.AmountScale
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withMonoDigits

/**
 * Hero amount whose whole primary/secondary pair toggles units, matching Home.
 * The swap cross-fades through [AmountText], and the pair stays visually plain
 * rather than assigning the affordance to a separate icon or support-line button.
 *
 * When [entryRaw] is set, the primary line follows the typed keypad string
 * (partial decimals included) while the secondary line keeps the mint-unit
 * alternate — matching iOS live entry on Receive / Send.
 *
 * When no fiat price is available the control is omitted and the amount renders
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
    entryRaw: String? = null,
    primaryTextStyle: TextStyle? = null,
    primaryAccessibilityPrefix: String? = null,
    color: Color = MaterialTheme.colorScheme.onSurface,
) {
    val haptics = LocalHapticFeedback.current
    val formatter = remember { AmountFormatter() }
    val priceAvailable = btcPrice != null && btcPrice > 0
    val display = if (entryRaw != null) {
        formatter.entryDisplayText(
            entryRaw = entryRaw,
            amountSats = amountSats,
            preferredPrimary = primary,
            btcPrice = btcPrice,
            currencyCode = currencyCode,
            useBitcoinSymbol = useBitcoinSymbol,
        )
    } else {
        formatter.displayText(
            amountSats = amountSats,
            preferredPrimary = primary.rawValue,
            showFiat = priceAvailable,
            btcPrice = btcPrice,
            currencyCode = currencyCode,
            useBitcoinSymbol = useBitcoinSymbol,
        )
    }
    val secondary = display.secondary
    val flip = {
        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        onFlip(
            if (display.effectivePrimary == AmountDisplayPrimary.Fiat) {
                AmountDisplayPrimary.Sats
            } else {
                AmountDisplayPrimary.Fiat
            },
        )
    }
    val toggleModifier = if (secondary != null) {
        Modifier
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                role = Role.Button,
                onClickLabel = "Make $secondary primary",
                onClick = flip,
            )
            .clearAndSetSemantics {
                role = Role.Button
                contentDescription =
                    "Amount: ${display.primary}. Tap to make $secondary primary."
                onClick(label = "Make $secondary primary") {
                    flip()
                    true
                }
            }
            .sizeIn(minHeight = 48.dp)
    } else {
        Modifier
    }
    Column(
        modifier = modifier.then(toggleModifier),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.micro),
    ) {
        val primaryStyle =
            (primaryTextStyle ?: MaterialTheme.typography.displayMedium).withMonoDigits()
        if (entryRaw != null) {
            // Entry mode: the parent re-expresses [entryRaw] on flip, so animate
            // the resulting string directly. Re-deriving the same raw under the
            // opposite unit would briefly mint-unit-misread fiat digits as sats.
            AmountHero(
                parts = display.primaryParts,
                scale = AmountScale.Hero,
                color = color,
                accessibilityPrefix = primaryAccessibilityPrefix,
            )
        } else {
            // Display mode: amountSats is unit-agnostic, so cross-fade units
            // while each side keeps its own formatting.
            AnimatedContent(
                targetState = display.effectivePrimary,
                transitionSpec = {
                    fadeIn(spring(stiffness = Spring.StiffnessMedium))
                        .togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
                },
                label = "amount-flip-hero",
            ) { primaryState ->
                val stateDisplay = formatter.displayText(
                    amountSats = amountSats,
                    preferredPrimary = primaryState.rawValue,
                    showFiat = priceAvailable,
                    btcPrice = btcPrice,
                    currencyCode = currencyCode,
                    useBitcoinSymbol = useBitcoinSymbol,
                )
                AmountText(
                    text = stateDisplay.primary,
                    modifier = if (primaryAccessibilityPrefix != null) {
                        Modifier.semantics {
                            contentDescription =
                                "$primaryAccessibilityPrefix: ${stateDisplay.primary}"
                        }
                    } else {
                        Modifier
                    },
                    style = primaryStyle,
                    color = color,
                )
            }
        }
        if (secondary != null) {
            AnimatedContent(
                targetState = secondary,
                transitionSpec = {
                    fadeIn(spring(stiffness = Spring.StiffnessMedium))
                        .togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
                },
                label = "amount-flip-control",
            ) { text ->
                Text(
                    text = bitcoinAmountText(text),
                    style = CashuTheme.type.amountSecondary,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/**
 * Live keypad presentation for sat-denominated entry. Primary follows the typed
 * raw string; secondary always keeps the mint-unit alternate when a BTC price
 * is loaded (including "$0.00"), matching iOS `CurrencyAmountDisplay` entry mode.
 */
internal fun AmountFormatter.entryDisplayText(
    entryRaw: String,
    amountSats: Long,
    preferredPrimary: AmountDisplayPrimary,
    btcPrice: Double?,
    currencyCode: String,
    useBitcoinSymbol: Boolean,
): AmountDisplayText {
    val priceAvailable = btcPrice != null && btcPrice > 0
    val effective = if (preferredPrimary == AmountDisplayPrimary.Fiat && priceAvailable) {
        AmountDisplayPrimary.Fiat
    } else {
        AmountDisplayPrimary.Sats
    }
    val satsText = formatWalletSats(amountSats, useBitcoinSymbol = useBitcoinSymbol)
    val fiatSecondary = if (priceAvailable) {
        formatFiat(amountSats, btcPrice, currencyCode)
            ?: formatFiatZero(currencyCode)
    } else {
        null
    }
    // Whole-number-first entry: an untouched pad is "0" in both units. The
    // secondary line below is a settled amount, so it keeps its full fraction.
    val primaryRaw = entryRaw.ifEmpty { "0" }
    return when (effective) {
        AmountDisplayPrimary.Fiat -> AmountDisplayText(
            primary = entryFiatDisplay(primaryRaw, currencyCode),
            secondary = satsText,
            effectivePrimary = effective,
        )
        AmountDisplayPrimary.Sats -> AmountDisplayText(
            primary = entryDisplay(
                raw = primaryRaw,
                isSat = true,
                unit = "sat",
                useBitcoinSymbol = useBitcoinSymbol,
            ),
            secondary = fiatSecondary,
            effectivePrimary = effective,
        )
    }
}

private fun AmountFormatter.formatFiatZero(currencyCode: String): String =
    entryFiatDisplay("0.00", currencyCode)
