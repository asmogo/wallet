package com.cashu.me.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cashu.me.Core.WalletHaptic
import com.cashu.me.Core.rememberWalletHaptics
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.rememberReducedMotion

private val MethodRowMinHeight = 64.dp
private val MethodRowPressCorner = 16.dp
private val MethodIconSize = 24.dp
private const val MethodPressedHighlightAlpha = 0.08f
private const val DisabledContentAlpha = 0.38f

/**
 * A full-width destination row used by the Send and Receive entry sheets.
 *
 * The resting state stays deliberately background-free, so the icon and
 * two-line label carry the hierarchy. Unavailable destinations remain in place
 * and replace the chevron with a concise status label.
 */
@Composable
fun MethodActionRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    accessibilityLabel: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    status: String? = null,
) {
    val haptics = rememberWalletHaptics()
    val reduceMotion = rememberReducedMotion()
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    val pressedHighlight by animateColorAsState(
        targetValue = if (enabled && pressed) {
            MaterialTheme.colorScheme.onSurface.copy(alpha = MethodPressedHighlightAlpha)
        } else {
            Color.Transparent
        },
        animationSpec = if (reduceMotion) {
            tween(durationMillis = 0)
        } else {
            tween(
                durationMillis = if (pressed) 90 else 180,
                easing = FastOutSlowInEasing,
            )
        },
        label = "method-row-press-highlight",
    )

    Surface(
        onClick = {
            haptics.perform(WalletHaptic.Selection)
            onClick()
        },
        modifier = modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                contentDescription = accessibilityLabel
                if (status != null) stateDescription = status
            },
        enabled = enabled,
        shape = RoundedCornerShape(MethodRowPressCorner),
        color = pressedHighlight,
        contentColor = MaterialTheme.colorScheme.onSurface,
        interactionSource = interactionSource,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = MethodRowMinHeight)
                .padding(horizontal = CashuTheme.spacing.default, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(MethodIconSize),
                tint = MaterialTheme.colorScheme.onSurface.copy(
                    alpha = if (enabled) 1f else DisabledContentAlpha,
                ),
            )

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface.copy(
                        alpha = if (enabled) 1f else DisabledContentAlpha,
                    ),
                )
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(
                        alpha = if (enabled) 1f else DisabledContentAlpha,
                    ),
                )
            }

            if (status != null) {
                Text(
                    text = status,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(
                        alpha = if (enabled) 1f else DisabledContentAlpha,
                    ),
                    maxLines = 1,
                    overflow = TextOverflow.Clip,
                )
            } else {
                Icon(
                    imageVector = Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(
                        alpha = if (enabled) 1f else DisabledContentAlpha,
                    ),
                    modifier = Modifier.size(MethodIconSize),
                )
            }
        }
    }
}
