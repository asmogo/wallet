package com.cashu.me.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.windowInsetsBottomHeight
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Backspace
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Core.UnitAmountEntry
import com.cashu.me.ui.theme.CashuTheme

// Minimal keypad: no background boxes, just numbers with subtle press feedback.
// Matches iOS NumberPadAmountInput (10pt gaps, up to 64pt keys).
private val KeyGap = 10.dp
// Grow toward iOS on roomy screens while preserving the 48dp touch target.
private val PreferredKeyHeight = 64.dp
private val MinimumKeyHeight = 48.dp

/**
 * Minimal numeric keypad for amount entry — no background boxes, just numbers
 * with opacity-based press feedback (iOS-style). Digits type left-to-right, so
 * "21" is twenty-one whole units; see [UnitAmountEntry]. With [decimals] > 0 the
 * bottom-left slot carries a decimal key that arms the fraction ("21." →
 * "21.50"); with decimals == 0 there is no fraction to enter, so the slot stays
 * the blank spacer it has always been. Long-press delete clears all.
 */
@Composable
fun NumberPad(
    amount: String,
    onAmountChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    decimals: Int = 0,
) {
    // Labelled with the locale's separator; the raw string stays canonical.
    val separatorKey = remember(decimals) {
        if (decimals > 0) AmountFormatter.decimalSeparator() else ""
    }
    val rows = listOf(
        listOf("1", "2", "3"),
        listOf("4", "5", "6"),
        listOf("7", "8", "9"),
        listOf(separatorKey, "0", "delete"),
    )
    BoxWithConstraints(modifier = modifier.fillMaxWidth()) {
        val keyHeight = ((maxHeight - KeyGap * 3) / 4)
            .coerceIn(MinimumKeyHeight, PreferredKeyHeight)
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(KeyGap),
        ) {
            rows.forEach { row ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(KeyGap),
                ) {
                    row.forEach { key ->
                        when (key) {
                            "" -> Box(modifier = Modifier.weight(1f).height(keyHeight))
                            separatorKey -> NumberPadKey(
                                modifier = Modifier.weight(1f).height(keyHeight),
                                contentDescription = "Decimal point",
                                onClick = {
                                    onAmountChange(UnitAmountEntry.appendSeparator(amount, decimals))
                                },
                            ) {
                                Text(
                                    text = key,
                                    style = CashuTheme.type.numberPadKey,
                                )
                            }
                            "delete" -> NumberPadKey(
                                modifier = Modifier.weight(1f).height(keyHeight),
                                contentDescription = "Delete. Long press to clear.",
                                onClick = {
                                    if (amount.isNotEmpty()) {
                                        onAmountChange(UnitAmountEntry.backspace(amount))
                                    }
                                },
                                onLongClick = {
                                    if (amount.isNotEmpty()) onAmountChange("")
                                },
                            ) {
                                Icon(
                                    imageVector = Icons.AutoMirrored.Outlined.Backspace,
                                    contentDescription = null,
                                )
                            }
                            else -> NumberPadKey(
                                modifier = Modifier.weight(1f).height(keyHeight),
                                contentDescription = key,
                                onClick = {
                                    onAmountChange(UnitAmountEntry.append(key, amount, decimals))
                                },
                            ) {
                                Text(
                                    text = key,
                                    style = CashuTheme.type.numberPadKey,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Shared tail for every amount-entry screen: [NumberPad] followed by a primary
 * action button, spaced with the 16dp keypad-to-button gap
 * and a bottom spacer sized to the real navigation-bar/gesture-bar inset.
 * Centralizing this stops each screen from hand-deriving its own spacing.
 */
@Composable
fun NumberPadFooter(
    amount: String,
    onAmountChange: (String) -> Unit,
    buttonText: String,
    onButtonClick: () -> Unit,
    modifier: Modifier = Modifier,
    decimals: Int = 0,
    buttonEnabled: Boolean = true,
    buttonLoading: Boolean = false,
    buttonModifier: Modifier = Modifier,
) {
    Column(modifier = modifier) {
        NumberPad(
            amount = amount,
            onAmountChange = onAmountChange,
            decimals = decimals,
            modifier = Modifier
                .weight(1f, fill = false)
                .padding(horizontal = CashuTheme.spacing.snug),
        )
        Spacer(Modifier.height(CashuTheme.spacing.comfortable))
        PrimaryButton(
            text = buttonText,
            onClick = onButtonClick,
            modifier = buttonModifier,
            enabled = buttonEnabled,
            loading = buttonLoading,
        )
        // Breathing room above the gesture area — the app-wide bottom-CTA
        // margin (see AddMintSheet/PaymentStatusScreen), matching iOS's
        // .padding(.bottom, 16). The raw inset alone left the button flush
        // against the screen edge.
        Spacer(Modifier.height(CashuTheme.spacing.comfortable))
        Spacer(Modifier.windowInsetsBottomHeight(WindowInsets.navigationBars))
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun NumberPadKey(
    contentDescription: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val haptics = LocalHapticFeedback.current
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    // Opacity-based press feedback: subtle dim on press (iOS-style, no background).
    val alpha by animateFloatAsState(
        targetValue = if (pressed) 0.4f else 1f,
        animationSpec = tween(durationMillis = 100),
        label = "key-press-alpha",
    )
    Box(
        modifier = modifier
            .graphicsLayer { this.alpha = alpha }
            .semantics {
                this.contentDescription = contentDescription
            }
            .combinedClickable(
                interactionSource = interactionSource,
                indication = null, // No ripple — opacity handles feedback
                onClickLabel = contentDescription,
                onLongClickLabel = onLongClick?.let { "Clear" },
                onLongClick = onLongClick?.let {
                    {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        it()
                    }
                },
                onClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    onClick()
                },
            ),
        contentAlignment = Alignment.Center,
        content = { content() },
    )
}
