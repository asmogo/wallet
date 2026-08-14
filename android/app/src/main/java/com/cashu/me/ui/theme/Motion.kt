package com.cashu.me.ui.theme

import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.unit.dp

/**
 * Choreography constants shared across the app's motion system. Curve *feel*
 * comes from M3 Expressive springs (per DESIGN-ANDROID.md); these values are
 * literal copies of the iOS choreography — stagger cadence and loop periods —
 * which are timing decisions, not curve decisions.
 */
object CashuMotion {
    /** Per-index delay for staggered entrances (chooser cascade, onboarding rise). */
    const val StaggerStepMs = 70

    /** Period of the looping "waiting" alpha pulse (clock/pending glyphs). */
    const val PulsePeriodMs = 1100

    /** Resting alpha for the waiting pulse's low point. */
    const val PulseMinAlpha = 0.4f

    /** One full rotation of the processing spinner ring (iOS SpinnerRing). */
    const val SpinnerPeriodMs = 900

    /**
     * Soft fade-through between sibling tabs (Wallet / History / Mints).
     * Outgoing empties in [TabFadeOutMs]; incoming settles over [TabFadeInMs]
     * after that delay, scaling from [TabFadeInitialScale].
     */
    const val TabFadeOutMs = 40
    const val TabFadeInMs = 250
    const val TabFadeInitialScale = 0.992f

    /**
     * Material Shared Axis X — push/pop between related destinations.
     * Outgoing fades in [SharedAxisOutMs]; incoming fades over
     * [SharedAxisInMs] after that delay. Total travel ≈ [SharedAxisDurationMs].
     */
    const val SharedAxisOutMs = 90
    const val SharedAxisInMs = 210
    const val SharedAxisDurationMs = 300
}

/**
 * True when the user has disabled system animations (animator duration scale 0)
 * — the Android convention for reduce-motion. Decorative loops (waiting pulses,
 * cascades) should render their resting state instead.
 *
 * Reactive: observes [Settings.Global.ANIMATOR_DURATION_SCALE] so toggling the
 * developer/accessibility setting mid-session is respected without recreating
 * the composition.
 */
/**
 * iOS onboarding entrance-stagger twin (`OnboardingView.stagger`): content
 * blocks rise 12dp into place while sharpening from a 3dp blur, 400ms,
 * [CashuMotion.StaggerStepMs] per index. No opacity — the step crossfade owns
 * the fade, and doubling it flickers (binding onboarding decision). The blur
 * needs API 31; below that the rise carries the effect alone — the same
 * degradation `materializeBlur` accepts. Reduce-motion renders the resting
 * state, and inspection mode (Studio previews, screenshot baselines) freezes
 * at the resting state so goldens stay deterministic — the same freeze the
 * hidden-seed grid applies to its blur.
 *
 * Promoted from OnboardingScreen.kt so every onboarding stage (including the
 * restore branch) can share one cascade primitive.
 */
@Composable
fun Modifier.riseIn(appeared: Boolean, index: Int): Modifier {
    if (rememberReducedMotion() || LocalInspectionMode.current) return this
    val progress by animateFloatAsState(
        targetValue = if (appeared) 1f else 0f,
        animationSpec = tween(
            durationMillis = 400,
            delayMillis = index * CashuMotion.StaggerStepMs,
            easing = FastOutSlowInEasing,
        ),
        label = "rise-in-$index",
    )
    val density = LocalDensity.current
    val risePx = with(density) { 12.dp.toPx() }
    val blurPx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        with(density) { 3.dp.toPx() }
    } else {
        0f
    }
    return this.graphicsLayer {
        val remaining = 1f - progress
        translationY = risePx * remaining
        val radius = blurPx * remaining
        renderEffect = if (radius > 0.05f) BlurEffect(radius, radius, TileMode.Decal) else null
    }
}

/** One-shot entrance trigger for [riseIn] call sites. */
@Composable
fun rememberAppeared(): Boolean {
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { appeared = true }
    return appeared
}

@Composable
fun rememberReducedMotion(): Boolean {
    val context = LocalContext.current
    val resolver = context.contentResolver

    fun read(): Boolean = Settings.Global.getFloat(
        resolver,
        Settings.Global.ANIMATOR_DURATION_SCALE,
        1f,
    ) == 0f

    var reduced by remember { mutableStateOf(read()) }
    DisposableEffect(resolver) {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                reduced = read()
            }
        }
        resolver.registerContentObserver(
            Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE),
            false,
            observer,
        )
        onDispose { resolver.unregisterContentObserver(observer) }
    }
    return reduced
}
