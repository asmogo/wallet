package com.cashu.me.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonColors
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cashu.me.ui.theme.CashuTheme

// Generous circular "method" buttons shared by the Send and Receive sheets
// (Scan · Ecash · Tap / Scan · Ecash · Bitcoin). Surface, not
// FilledTonalIconButton — the latter hardcodes 40dp and would ignore these
// sizes. MethodRowSpacing is public so callers space the row identically.
private val MethodButtonSize = 72.dp
private val MethodIconSize = 32.dp
val MethodRowSpacing = 40.dp

// Full-width CTAs (incl. home Receive/Send). +10% over the original 58/16
// iOS-large glass capsule sizing for a taller Android press target.
private val ButtonMinHeight = 64.dp
private val ButtonContentVertical = 18.dp
private val ButtonProgressSize = 24.dp
// Chevron-scale glyph inside GhostButton labels.
private val GhostButtonIconSize = 16.dp
private const val PressedScale = 0.97f
// iOS TextLinkButtonStyle: text links dim to 0.6 while pressed.
private const val TextLinkPressedAlpha = 0.6f
private const val DestructiveActionStateDescription = "Destructive action"

@Composable
private fun rememberPressScale(interactionSource: MutableInteractionSource): Float {
    val pressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed) PressedScale else 1f,
        animationSpec = spring(stiffness = Spring.StiffnessMedium),
        label = "press-scale",
    )
    return scale
}

/**
 * Pressed-opacity feedback for text-style buttons — the iOS
 * `TextLinkButtonStyle` (opacity 0.6 while pressed) on a medium spring.
 */
@Composable
private fun rememberPressAlpha(interactionSource: MutableInteractionSource): Float {
    val pressed by interactionSource.collectIsPressedAsState()
    val alpha by animateFloatAsState(
        targetValue = if (pressed) TextLinkPressedAlpha else 1f,
        animationSpec = spring(stiffness = Spring.StiffnessMedium),
        label = "press-alpha",
    )
    return alpha
}

/**
 * Quiet neutral tonal fill — [PrimaryButton]'s default treatment, the analog
 * of iOS's non-prominent glass capsule (`.glassButton()`). Matches the history
 * row's arrow chips and adapts to light/dark via the theme's surface roles.
 */
@Composable
fun neutralActionButtonColors(): ButtonColors = ButtonDefaults.buttonColors(
    containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
    contentColor = MaterialTheme.colorScheme.onSurface,
    disabledContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
    disabledContentColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f),
)

/**
 * The primary full-width CTA: gray tonal fill by default (iOS parity — every
 * iOS bottom CTA is the non-prominent gray glass capsule), spring press-scale,
 * expressive loading indicator.
 *
 * Pass [colors] to override — the sole inverted-ink case is the Receive Ecash
 * commit button, mirroring iOS's single `.glassButton(prominent: true)`.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun PrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    loading: Boolean = false,
    colors: ButtonColors? = null,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val scale = rememberPressScale(interactionSource)
    Button(
        onClick = onClick,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = ButtonMinHeight)
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            },
        enabled = enabled && !loading,
        interactionSource = interactionSource,
        colors = colors ?: neutralActionButtonColors(),
        contentPadding = PaddingValues(horizontal = CashuTheme.spacing.section, vertical = ButtonContentVertical),
    ) {
        Box(contentAlignment = Alignment.Center) {
            if (loading) {
                LoadingIndicator(
                    modifier = Modifier.size(ButtonProgressSize),
                    color = LocalContentColor.current,
                )
            } else {
                AnimatedContent(
                    targetState = text,
                    transitionSpec = {
                        fadeIn(spring(stiffness = Spring.StiffnessMedium))
                            .togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
                    },
                    label = "primary-button-text",
                ) { current ->
                    Text(
                        text = current,
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 18.sp,
                        ),
                    )
                }
            }
        }
    }
}

/** The secondary full-width CTA: tonal, one step quieter than [PrimaryButton]. */
@Composable
fun SecondaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val scale = rememberPressScale(interactionSource)
    FilledTonalButton(
        onClick = onClick,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = ButtonMinHeight)
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            },
        enabled = enabled,
        interactionSource = interactionSource,
        contentPadding = PaddingValues(horizontal = CashuTheme.spacing.section, vertical = ButtonContentVertical),
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.titleMedium.copy(
                fontWeight = FontWeight.SemiBold,
                fontSize = 18.sp,
            ),
        )
    }
}

/** Inline non-emphasized action (Copy, Paste, Restore from seed, etc.). */
@Composable
fun GhostButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    trailingIcon: ImageVector? = null,
    textStyle: TextStyle = MaterialTheme.typography.labelLarge,
    contentColor: Color = Color.Unspecified,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val alpha = rememberPressAlpha(interactionSource)
    TextButton(
        onClick = onClick,
        modifier = modifier.graphicsLayer { this.alpha = alpha },
        enabled = enabled,
        interactionSource = interactionSource,
        colors = if (contentColor != Color.Unspecified) {
            ButtonDefaults.textButtonColors(contentColor = contentColor)
        } else {
            ButtonDefaults.textButtonColors()
        },
    ) {
        Text(text = text, style = textStyle)
        if (trailingIcon != null) {
            Spacer(Modifier.width(CashuTheme.spacing.micro))
            Icon(
                imageVector = trailingIcon,
                contentDescription = null,
                modifier = Modifier.size(GhostButtonIconSize),
            )
        }
    }
}

/**
 * One round tonal icon button with a one-word caption below — the shared "way to
 * send / receive" button. iOS parity: `CircularGlassIconButton`.
 */
@Composable
fun CircularMethodButton(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    Column(
        modifier = modifier.alpha(if (enabled) 1f else 0.38f),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Surface(
            onClick = onClick,
            enabled = enabled,
            modifier = Modifier.size(MethodButtonSize),
            shape = CircleShape,
            color = MaterialTheme.colorScheme.secondaryContainer,
            contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
        ) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = label,
                    modifier = Modifier.size(MethodIconSize),
                )
            }
        }
        Spacer(Modifier.height(CashuTheme.spacing.snug))
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * Destructive inline action (Delete Wallet, Remove Mint).
 *
 * Material's error color communicates the action visually. The state description
 * gives accessibility services the equivalent destructive announcement while the
 * underlying [TextButton] continues to expose the native button role.
 */
@Composable
fun DestructiveTextButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val alpha = rememberPressAlpha(interactionSource)
    TextButton(
        onClick = onClick,
        modifier = modifier
            .semantics { stateDescription = DestructiveActionStateDescription }
            .graphicsLayer { this.alpha = alpha },
        enabled = enabled,
        interactionSource = interactionSource,
        colors = ButtonDefaults.textButtonColors(
            contentColor = MaterialTheme.colorScheme.error,
        ),
    ) {
        Text(text = text, style = MaterialTheme.typography.labelLarge)
    }
}
