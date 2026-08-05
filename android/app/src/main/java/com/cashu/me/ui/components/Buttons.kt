package com.cashu.me.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
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
import androidx.compose.ui.unit.IntSize
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

// Content arriving into a CTA grows in from just under full size — never from
// zero, which reads as a pop rather than as the label resolving into place.
private const val MorphInitialScale = 0.96f

// Text links get a lighter cross-fade mask than the CTA's 18sp label.
private val GhostLabelMorphBlur = 1.5.dp

/**
 * Press-scale feedback, **asymmetric on purpose**.
 *
 * A spring carries no direction, so the asymmetry lives in *which spec is
 * selected on the press edge* — `animateFloatAsState` re-reads `animationSpec`
 * when it re-targets. Feedback belongs on pointer-down and has to feel instant;
 * the release is the system responding and can settle. iOS states the same
 * ratio literally, as `.snappy(0.09)` down / `.snappy(0.18)` up in
 * `PressableButtonStyle`.
 *
 * **Effects specs, deliberately, even though scale is nominally spatial.**
 * Expressive's spatial springs are under-damped (`fastSpatial` is 0.6/800,
 * `defaultSpatial` 0.8/380), and a press must not overshoot — DESIGN.md §6
 * classes a press as a *state flip*, not a reflow, and bans bounce; apple-design
 * reserves overshoot for gestures that actually carried momentum, which a
 * finger-down does not. The effects pair is the only critically-damped one in
 * the scheme: `fastEffects` 1.0/3800 down, `defaultEffects` 1.0/1600 up — the
 * latter being the `StiffnessMedium` (1500) this replaces, now named rather
 * than coincidental.
 */
@Composable
private fun rememberPressScale(interactionSource: MutableInteractionSource): Float {
    val pressed by interactionSource.collectIsPressedAsState()
    val compress = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
    val release = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
    val scale by animateFloatAsState(
        targetValue = if (pressed) PressedScale else 1f,
        animationSpec = if (pressed) compress else release,
        label = "press-scale",
    )
    return scale
}

/**
 * Pressed-opacity feedback for text-style buttons — the iOS
 * `TextLinkButtonStyle` (opacity 0.6 while pressed), asymmetric for the same
 * reason as [rememberPressScale], and on the same critically-damped pair.
 */
@Composable
private fun rememberPressAlpha(interactionSource: MutableInteractionSource): Float {
    val pressed by interactionSource.collectIsPressedAsState()
    val dim = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
    val restore = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
    val alpha by animateFloatAsState(
        targetValue = if (pressed) TextLinkPressedAlpha else 1f,
        animationSpec = if (pressed) dim else restore,
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
    // Resolve the enabled/disabled pair first, then ease the two resolved colors:
    // a CTA that keeps its slot across a step change (the onboarding chassis keys
    // its slot cross-fade on style, not on colors) would otherwise hard-cut its
    // fill under the cross-fading label. Baking `active` in is why the disabled
    // entries can carry the same animated values.
    val active = enabled && !loading
    val target = colors ?: neutralActionButtonColors()
    val container by animateColorAsState(
        targetValue = if (active) target.containerColor else target.disabledContainerColor,
        animationSpec = spring(stiffness = Spring.StiffnessMedium),
        label = "primary-button-container",
    )
    val content by animateColorAsState(
        targetValue = if (active) target.contentColor else target.disabledContentColor,
        animationSpec = spring(stiffness = Spring.StiffnessMedium),
        label = "primary-button-content",
    )
    // AnimatedContent's transitionSpec lambda is not composable, so the
    // motion-scheme specs are captured here (same device as the onboarding
    // stage swap in OnboardingScreen.kt).
    val morphEnterSpec = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
    val morphScaleSpec = MaterialTheme.motionScheme.defaultSpatialSpec<Float>()
    val morphExitSpec = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
    val morphSizeSpec = MaterialTheme.motionScheme.defaultSpatialSpec<IntSize>()
    Button(
        onClick = onClick,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = ButtonMinHeight)
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            },
        enabled = active,
        interactionSource = interactionSource,
        colors = ButtonColors(container, content, container, content),
        contentPadding = PaddingValues(horizontal = CashuTheme.spacing.section, vertical = ButtonContentVertical),
    ) {
        Box(contentAlignment = Alignment.Center) {
            // The spinner is a morph *target*, not a branch outside the
            // animation — a `if (loading)` wrapper around this AnimatedContent
            // hard-cut the label away, which was the one place the CTA visibly
            // snapped. `null` means loading, so label→spinner and label→label
            // are the same transition.
            AnimatedContent(
                targetState = if (loading) null else text,
                transitionSpec = {
                    (
                        fadeIn(morphEnterSpec) +
                            scaleIn(
                                animationSpec = morphScaleSpec,
                                initialScale = MorphInitialScale,
                            )
                        )
                        // Exits stay subtler than entrances (DESIGN.md §6):
                        // the outgoing half only fades, and on the fast spec.
                        .togetherWith(fadeOut(morphExitSpec))
                        // clip = false: the default clipping size animation
                        // shears a wide outgoing label mid-fade. Center: the
                        // Box above only centers this node, not its children,
                        // so TopStart would slide both labels sideways as the
                        // box springs between the two label widths. The size
                        // spring is stated rather than left to Compose's
                        // built-in default, so the CTA rides the app's own
                        // curve identity.
                        .using(SizeTransform(clip = false) { _, _ -> morphSizeSpec })
                },
                contentAlignment = Alignment.Center,
                label = "primary-button-content",
            ) { current ->
                // Blur mask: both halves soften toward each other so the swap
                // reads as one object transforming rather than two overlapping.
                val morph = morphBlur()
                if (current == null) {
                    LoadingIndicator(
                        modifier = Modifier.size(ButtonProgressSize).then(morph),
                        color = LocalContentColor.current,
                    )
                } else {
                    Text(
                        text = current,
                        modifier = morph,
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
    leadingIcon: ImageVector? = null,
    trailingIcon: ImageVector? = null,
    textStyle: TextStyle = MaterialTheme.typography.labelLarge,
    contentColor: Color = Color.Unspecified,
    animatedLabel: Boolean = false,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val alpha = rememberPressAlpha(interactionSource)
    // Captured outside the non-composable transitionSpec lambda (see PrimaryButton).
    val morphEnterSpec = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
    val morphExitSpec = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
    val morphSizeSpec = MaterialTheme.motionScheme.defaultSpatialSpec<IntSize>()
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
        if (leadingIcon != null) {
            Icon(
                imageVector = leadingIcon,
                contentDescription = null,
                modifier = Modifier.size(GhostButtonIconSize),
            )
            Spacer(Modifier.width(CashuTheme.spacing.tight))
        }
        if (animatedLabel) {
            // Opt-in in-place label cross-fade (the onboarding chassis'
            // tertiary slot swaps "What is ecash?" ↔ "Back" ↔ "Skip for now").
            // clip = false: the default clipping size animation would crop a
            // wide outgoing label mid-fade. Center: the default TopStart would
            // still walk both labels sideways while the box springs between the
            // two widths and the parent re-centers it every frame.
            AnimatedContent(
                targetState = text,
                transitionSpec = {
                    // No scale on the way in — a text link growing into place
                    // reads fussy at this size; the blur mask below does the
                    // work on its own. Exit fades on the fast spec (subtler
                    // than the entrance, DESIGN.md §6).
                    fadeIn(morphEnterSpec)
                        .togetherWith(fadeOut(morphExitSpec))
                        .using(SizeTransform(clip = false) { _, _ -> morphSizeSpec })
                },
                contentAlignment = Alignment.Center,
                label = "ghost-button-text",
            ) { current ->
                // Softer mask than the CTA's — a subheadline needs less
                // bridging than an 18sp label.
                Text(text = current, modifier = morphBlur(GhostLabelMorphBlur), style = textStyle)
            }
        } else {
            Text(text = text, style = textStyle)
        }
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
