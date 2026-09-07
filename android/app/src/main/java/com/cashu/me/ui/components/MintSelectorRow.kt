package com.cashu.me.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.cashu.me.Models.MintInfo
import com.cashu.me.ui.theme.CashuTheme

/** The selected mint's role in the value flow. */
enum class MintSelectorDirection(val label: String) {
    Source("From"),
    Destination("To"),
}

private val ChevronSize = 18.dp
private val RowMinHeight = 48.dp
private val MinimumTouchTarget = 48.dp
private val RowVerticalPadding = 6.dp

/**
 * Half the slack a 48dp touch target leaves around an 18dp glyph. Trimming it
 * from the chevron's *layout* box (never its hit area) stops the dead space
 * from pushing the glyph a third of the way in from the trailing margin, and
 * from inflating its gap to Send Max to several times the gap inside the
 * identity. Mirrors iOS's FlowRowMetrics.chevronBox + hitSlop.
 */
private val ChevronBoxTrim = 14.dp

/**
 * Report a narrower box than was measured, placing the content centred so it
 * overhangs on both sides. The touch target keeps its full size; only the space
 * it claims in the row shrinks. Compose has no negative padding, so this is the
 * layout-modifier equivalent.
 */
private fun Modifier.trimHorizontal(trim: Dp) = this.layout { measurable, constraints ->
    val placeable = measurable.measure(constraints)
    val trimPx = trim.roundToPx()
    val width = (placeable.width - trimPx * 2).coerceAtLeast(0)
    layout(width, placeable.height) { placeable.place(-trimPx, 0) }
}
private val ActionPadding = PaddingValues(start = 8.dp, end = 0.dp)

/**
 * The shared value-flow mint selector: an unboxed mint identity with an optional
 * plain-text Send Max action and picker chevron. The resting state deliberately
 * has no fill, border, or divider.
 *
 * The direction label is not drawn — the mint name, its balance and the chevron
 * say what the row is, and every screen using it already names the flow. It
 * survives in the accessibility description, so [direction] is still required
 * and receiving flows still cannot describe the destination mint as a source.
 * [showBalance] is reserved for amount entry.
 */
@Composable
fun MintSelectorRow(
    direction: MintSelectorDirection,
    mint: MintInfo,
    balanceText: String?,
    modifier: Modifier = Modifier,
    showBalance: Boolean = false,
    onPickMint: (() -> Unit)? = null,
    onUseMax: (() -> Unit)? = null,
) {
    val isAccessibilityLayout = LocalDensity.current.fontScale >= 1.3f
    val description = buildString {
        append(direction.label)
        append(' ')
        append(mint.name)
        if (showBalance && balanceText != null) {
            append(", balance ")
            append(balanceText)
        }
    }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(if (isAccessibilityLayout) 2.dp else 0.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth(),
        ) {
            MintIdentity(
                mint = mint,
                balanceText = balanceText,
                showBalance = showBalance,
                stacksBalance = isAccessibilityLayout,
                description = description,
                onPickMint = onPickMint,
                modifier = Modifier.weight(1f),
            )

            if (onUseMax != null) {
                TextButton(
                    onClick = onUseMax,
                    modifier = Modifier
                        .defaultMinSize(minWidth = 0.dp, minHeight = MinimumTouchTarget)
                        .heightIn(min = MinimumTouchTarget)
                        .semantics { contentDescription = "Send maximum" },
                    contentPadding = ActionPadding,
                ) {
                    Text(
                        text = "Send Max",
                        style = CashuTheme.type.mintSelector,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                    )
                }
            }

            if (onPickMint != null) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .trimHorizontal(ChevronBoxTrim)
                        .size(MinimumTouchTarget)
                        .clickable(role = Role.Button, onClick = onPickMint)
                        // The identity already exposes the picker as one control.
                        .clearAndSetSemantics { },
                ) {
                    Icon(
                        imageVector = Icons.Outlined.KeyboardArrowDown,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(ChevronSize),
                    )
                }
            }
        }
    }
}

@Composable
private fun MintIdentity(
    mint: MintInfo,
    balanceText: String?,
    showBalance: Boolean,
    stacksBalance: Boolean,
    description: String,
    onPickMint: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val identityInteractionSource = remember { MutableInteractionSource() }
    val identityModifier = modifier
        .heightIn(min = RowMinHeight)
        .then(
            if (onPickMint != null) {
                Modifier
                    // Opening the picker is the feedback. Suppress the default
                    // rectangular ripple so this deliberately unboxed selector
                    // does not flash a filled card around only the mint name.
                    .clickable(
                        interactionSource = identityInteractionSource,
                        indication = null,
                        role = Role.Button,
                        onClick = onPickMint,
                    )
                    .clearAndSetSemantics {
                        contentDescription = description
                        role = Role.Button
                        onClick(label = "Choose a different mint") {
                            onPickMint()
                            true
                        }
                    }
            } else {
                Modifier.clearAndSetSemantics { contentDescription = description }
            },
        )
        .padding(vertical = RowVerticalPadding)

    Box(modifier = identityModifier, contentAlignment = Alignment.CenterStart) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (showBalance && balanceText != null && stacksBalance) {
                Column(modifier = Modifier.weight(1f)) {
                    MintName(mint.name)
                    MintBalance(balanceText)
                }
            } else {
                Text(
                    text = mint.name,
                    style = CashuTheme.type.mintSelector,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .weight(1f, fill = false)
                        .alignByBaseline(),
                )
                if (showBalance && balanceText != null) {
                    Spacer(Modifier.width(CashuTheme.spacing.snug))
                    MintBalance(balanceText, Modifier.alignByBaseline())
                }
            }
        }
    }
}

@Composable
private fun MintName(name: String) {
    Text(
        text = name,
        style = CashuTheme.type.mintSelector,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurface,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
}

/**
 * The row speaks in one voice: mint name, balance and Send Max all share
 * `mintSelector` + SemiBold + `onSurface`, so the whole row is a single treatment
 * rather than three competing ones. It previously ran three sizes across two
 * inks and two weights, with the balance at the 12sp floor *under* secondary
 * ink — a double demotion.
 */
@Composable
private fun MintBalance(balanceText: String, modifier: Modifier = Modifier) {
    Text(
        text = bitcoinAmountText(balanceText),
        modifier = modifier,
        style = CashuTheme.type.mintSelector,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurface,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
}
