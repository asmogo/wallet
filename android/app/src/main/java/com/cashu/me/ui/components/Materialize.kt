package com.cashu.me.ui.components

import android.os.Build
import androidx.compose.animation.AnimatedVisibilityScope
import androidx.compose.animation.EnterExitState
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.cashu.me.ui.theme.rememberReducedMotion

// iOS AnyTransition.materializeBlur sharpens from a 4pt radius.
private val MaterializeBlurRadius = 4.dp

// Default mask for a content cross-fade. Deliberately much softer than
// MaterializeBlurRadius: this one is not meant to be seen as an effect, only to
// stop the eye resolving the two halves as separate objects.
private val MorphBlurRadius = 2.dp

/**
 * Blur-to-sharp "materialize" entrance — the Compose equivalent of the iOS
 * `AnyTransition.materializeBlur` carve-out used on the success check. Apply
 * alongside the enter transition; the content settles from a 4dp blur to
 * sharp on a medium spring.
 *
 * `RenderEffect` requires API 31; below that (and under reduce-motion) this is
 * a no-op — the paired fade/scale enter still carries the moment.
 */
@Composable
fun Modifier.materializeBlur(delayMillis: Int = 0): Modifier {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || rememberReducedMotion()) {
        return this
    }
    var materialized by remember { mutableStateOf(false) }
    // The optional delay lets a staged entrance hold the blur until its beat
    // (the celebration mount's glyph waits ~100ms for the container fade).
    LaunchedEffect(Unit) {
        if (delayMillis > 0) kotlinx.coroutines.delay(delayMillis.toLong())
        materialized = true
    }
    val radiusPx by animateFloatAsState(
        targetValue = if (materialized) 0f else with(LocalDensity.current) {
            MaterializeBlurRadius.toPx()
        },
        animationSpec = spring(stiffness = Spring.StiffnessMedium),
        label = "materialize-blur",
    )
    return this.graphicsLayer {
        renderEffect = if (radiusPx > 0.05f) {
            BlurEffect(radiusPx, radiusPx, TileMode.Decal)
        } else {
            null
        }
    }
}

/**
 * Blur mask for a content cross-fade — the companion to [materializeBlur],
 * which is entrance-only (its `LaunchedEffect(Unit)` can never run for a child
 * that is on its way out).
 *
 * This one reads the enter/exit transition directly, so the *outgoing* and
 * *incoming* halves blur toward each other off the same clock. That symmetry is
 * the whole point: without it a cross-fade shows two distinct objects
 * overlapping, and the eye reads a swap. Blurred, it reads as one object
 * transforming. Radii stay small ([MorphBlurRadius] by default) — this is a
 * mask, not a flourish.
 *
 * Call from inside an `AnimatedContent` / `AnimatedVisibility` content lambda:
 * ```
 * AnimatedContent(targetState = label, ...) { current ->
 *     Text(current, modifier = morphBlur())
 * }
 * ```
 *
 * `RenderEffect` requires API 31; below that (and under reduce-motion) this is
 * a no-op and the paired fade/scale carries the morph alone — the same
 * degradation `materializeBlur` and `Modifier.riseIn` already accept.
 *
 * The radius rides a medium spring by default; call sites mirroring a timed
 * iOS transition (the onboarding step swap) pass explicit enter/exit specs so
 * the blur settles on the same clock as the fade it masks.
 */
@Composable
fun AnimatedVisibilityScope.morphBlur(
    radius: Dp = MorphBlurRadius,
    enterSpec: FiniteAnimationSpec<Float> = spring(stiffness = Spring.StiffnessMedium),
    exitSpec: FiniteAnimationSpec<Float> = enterSpec,
): Modifier {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || rememberReducedMotion()) {
        return Modifier
    }
    val density = LocalDensity.current
    val radiusPx by transition.animateFloat(
        transitionSpec = {
            if (targetState == EnterExitState.Visible) enterSpec else exitSpec
        },
        label = "morph-blur",
    ) { state ->
        if (state == EnterExitState.Visible) 0f else with(density) { radius.toPx() }
    }
    return Modifier.graphicsLayer {
        renderEffect = if (radiusPx > 0.05f) {
            BlurEffect(radiusPx, radiusPx, TileMode.Decal)
        } else {
            null
        }
    }
}
