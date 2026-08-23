package com.cashu.me.ui.components

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.ui.graphics.graphicsLayer
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

private val MethodRowMinHeight = 80.dp
private val MethodRowCorner = 24.dp
private val MethodIconTileSize = 48.dp
private val MethodIconSize = 24.dp
private const val MethodPressedScale = 0.98f
private const val DisabledContentAlpha = 0.38f

/**
 * A full-width destination row used by the Send and Receive entry sheets.
 *
 * The solid neutral surface, inset icon tile, two-line label, and trailing
 * affordance mirror iOS `MethodActionRow`. Unavailable destinations remain in
 * place and replace the chevron with a concise status pill.
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
    val scale by animateFloatAsState(
        targetValue = if (enabled && pressed && !reduceMotion) MethodPressedScale else 1f,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioNoBouncy,
            stiffness = if (pressed) Spring.StiffnessHigh else Spring.StiffnessMedium,
        ),
        label = "method-row-press",
    )

    Surface(
        onClick = {
            haptics.perform(WalletHaptic.Selection)
            onClick()
        },
        modifier = modifier
            .fillMaxWidth()
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            }
            .semantics(mergeDescendants = true) {
                contentDescription = accessibilityLabel
                if (status != null) stateDescription = status
            },
        enabled = enabled,
        shape = RoundedCornerShape(MethodRowCorner),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        contentColor = MaterialTheme.colorScheme.onSurface,
        interactionSource = interactionSource,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = MethodRowMinHeight)
                .padding(CashuTheme.spacing.default),
            horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.comfortable),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(MethodIconTileSize),
                contentAlignment = Alignment.Center,
            ) {
                Surface(
                    modifier = Modifier.matchParentSize(),
                    shape = MaterialTheme.shapes.large,
                    color = MaterialTheme.colorScheme.surfaceContainerLowest,
                    contentColor = MaterialTheme.colorScheme.onSurface,
                ) {}
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    modifier = Modifier.size(MethodIconSize),
                    tint = MaterialTheme.colorScheme.onSurface.copy(
                        alpha = if (enabled) 1f else DisabledContentAlpha,
                    ),
                )
            }

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
                Surface(
                    shape = RoundedCornerShape(percent = 50),
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    border = BorderStroke(
                        1.dp,
                        MaterialTheme.colorScheme.outlineVariant.copy(
                            alpha = if (enabled) 1f else DisabledContentAlpha,
                        ),
                    ),
                ) {
                    Text(
                        text = status,
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(
                            alpha = if (enabled) 1f else DisabledContentAlpha,
                        ),
                        maxLines = 1,
                        overflow = TextOverflow.Clip,
                    )
                }
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
