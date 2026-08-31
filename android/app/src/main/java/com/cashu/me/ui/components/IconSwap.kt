package com.cashu.me.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

private const val SwapInitialScale = 0.92f
private val DefaultIconSize = 24.dp

/**
 * Animated glyph replacement — the Compose equivalent of iOS
 * `.contentTransition(.symbolEffect(.replace))`. The outgoing icon fades while
 * the incoming one grows in from 0.92 on the motion scheme. Used for copy-confirm
 * checks, selection circles, method badges, and restore result glyphs.
 *
 * Identity is the [icon] itself: pass a stable [ImageVector] per state so the
 * swap only animates on a real state change (never mid-display).
 *
 * Pass [iconSize] = [com.cashu.me.ui.theme.CashuTheme.iconSizes.toolbar] for
 * top-bar chrome (filter, etc.) so it matches [ToolbarIcon].
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun IconSwap(
    icon: ImageVector,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    tint: Color = Color.Unspecified,
    iconSize: Dp = DefaultIconSize,
) {
    val enterEffects = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
    val enterSpatial = MaterialTheme.motionScheme.defaultSpatialSpec<Float>()
    val exitEffects = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
    AnimatedContent(
        targetState = icon,
        transitionSpec = {
            (
                fadeIn(enterEffects) +
                    scaleIn(
                        animationSpec = enterSpatial,
                        initialScale = SwapInitialScale,
                    )
                ).togetherWith(fadeOut(exitEffects))
        },
        label = "icon-swap",
        modifier = modifier,
    ) { current ->
        Icon(
            imageVector = current,
            contentDescription = contentDescription,
            modifier = Modifier.size(iconSize),
            tint = if (tint == Color.Unspecified) LocalContentColor.current else tint,
        )
    }
}
