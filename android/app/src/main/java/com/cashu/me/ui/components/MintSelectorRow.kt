package com.cashu.me.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cashu.me.Models.MintInfo
import com.cashu.me.ui.theme.CashuTheme

/** The selected mint's role in the value flow. */
enum class MintSelectorDirection(val label: String) {
    Source("From"),
    Destination("To"),
}

private val ChevronSize = 18.dp
private val RowMinHeight = 56.dp
private val MinimumTouchTarget = 48.dp
private val RowVerticalPadding = 6.dp
private val ActionPadding = PaddingValues(horizontal = 8.dp)

/**
 * The shared value-flow mint selector: an unboxed directional label and mint
 * identity, with an optional plain-text Send Max action and picker chevron.
 * The resting state deliberately has no fill, border, or divider.
 *
 * [direction] is required so receiving flows cannot accidentally describe the
 * destination mint as a source. [showBalance] is reserved for amount entry.
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
        if (isAccessibilityLayout) {
            Text(
                text = direction.label,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.clearAndSetSemantics { },
            )
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth(),
        ) {
            MintIdentity(
                direction = direction,
                mint = mint,
                balanceText = balanceText,
                showBalance = showBalance,
                showDirection = !isAccessibilityLayout,
                stacksBalance = isAccessibilityLayout,
                description = description,
                onPickMint = onPickMint,
                modifier = Modifier.weight(1f),
            )

            if (onUseMax != null) {
                TextButton(
                    onClick = onUseMax,
                    modifier = Modifier
                        .heightIn(min = MinimumTouchTarget)
                        .semantics { contentDescription = "Send maximum" },
                    contentPadding = ActionPadding,
                ) {
                    Text(
                        text = "Send Max",
                        style = MaterialTheme.typography.bodyMedium,
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
    direction: MintSelectorDirection,
    mint: MintInfo,
    balanceText: String?,
    showBalance: Boolean,
    showDirection: Boolean,
    stacksBalance: Boolean,
    description: String,
    onPickMint: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val identityModifier = modifier
        .heightIn(min = RowMinHeight)
        .then(
            if (onPickMint != null) {
                Modifier
                    .clickable(role = Role.Button, onClick = onPickMint)
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

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = identityModifier,
    ) {
        if (showDirection) {
            Text(
                text = direction.label,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
            )
            Spacer(Modifier.width(CashuTheme.spacing.snug))
        }

        if (showBalance && balanceText != null && stacksBalance) {
            Column(modifier = Modifier.weight(1f)) {
                MintName(mint.name)
                MintBalance(balanceText)
            }
        } else {
            Text(
                text = mint.name,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .weight(1f, fill = false),
            )
            if (showBalance && balanceText != null) {
                Spacer(Modifier.width(CashuTheme.spacing.snug))
                MintBalance(balanceText)
            }
        }
    }
}

@Composable
private fun MintName(name: String) {
    Text(
        text = name,
        style = MaterialTheme.typography.bodyLarge,
        fontWeight = FontWeight.Medium,
        color = MaterialTheme.colorScheme.onSurface,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
}

@Composable
private fun MintBalance(balanceText: String) {
    Text(
        text = balanceText,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
}
