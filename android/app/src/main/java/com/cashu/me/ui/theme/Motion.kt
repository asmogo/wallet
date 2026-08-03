package com.cashu.me.ui.theme

import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext

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
