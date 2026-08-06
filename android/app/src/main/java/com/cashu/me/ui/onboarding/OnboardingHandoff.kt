package com.cashu.me.ui.onboarding

import android.content.Context
import android.os.PowerManager
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.cashu.me.ui.theme.rememberReducedMotion
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// MARK: Onboarding handoff
//
// The closing beat of onboarding: a full-screen ASCII terrain curtain that
// sweeps down over the last onboarding screen, holds for one center bloom
// while the app gate flips beneath it, then slides down and dissolves onto
// the wallet already in place. Defined under the onboarding motion exemption
// and owned by onboarding — CashuApp only mounts the host; nothing here is
// referenced by wallet-proper code. The gate's own transition spec is
// untouched; it simply plays unseen under the cover.
//
// Choreography (T = a completion call site firing `begin`):
//   T+0        curtain reveals top → bottom (450ms, soft 30%-height edge)
//   T+450ms    gate flip under full cover — the root swap is invisible
//   T+480ms    lens bloom fires at screen center (existing warp envelopes)
//   T+750ms    overlay slides down 20dp and fades out (500ms)
//   T+1250ms   session ends, overlay unmounts
//
// Under Reduce Motion the overlay never shows and completion runs
// immediately — the app gate's plain crossfade is the entire transition
// (opacity-or-nothing).

/** One completion handoff. Owns the programmatic lens touch and the closure
 * that flips the app gate; dies with the overlay. */
internal class OnboardingHandoffSession(
    private val complete: suspend () -> Unit,
) {
    /** Drives the center bloom on the overlay's terrain — the same warp a
     * finger drives on the welcome band, fired once by the app itself. */
    val touch = AsciiFieldWarpTouch()
    private var didComplete = false

    /** The gate flip, run under full cover. Idempotent, and non-cancellable
     * once started, so a torn-down host can never abandon a half-finished
     * completion. */
    suspend fun runComplete() {
        if (didComplete) return
        didComplete = true
        withContext(NonCancellable) { complete() }
    }
}

/** Hoisted in CashuAppContent — above the gate's AnimatedContent, so the
 * choreography's lifetime survives the onboarding teardown it conceals —
 * and handed to OnboardingScreen as a parameter. `begin` is the single
 * entry point for every completion path. */
internal class OnboardingHandoffController {
    var session by mutableStateOf<OnboardingHandoffSession?>(null)
        private set

    /** No-ops while a handoff is already running (double-tap guard). */
    fun begin(complete: suspend () -> Unit) {
        if (session != null) return
        session = OnboardingHandoffSession(complete)
    }

    fun end() {
        session = null
    }
}

/** Soft leading edge of the sweep, as a fraction of screen height — mirrors
 * the band's `AsciiFieldLayout.MASK_FADE`. */
private const val SweepEdge = 0.30f
private const val SweepInMs = 450
private const val BloomDelayMs = 30
private const val HoldMs = 270
private const val ReleaseDelayMs = 10
private const val DissolveMs = 500
private val DissolveSlide = 20.dp

/** The curtain itself: an opaque scrim plus full-bleed drifting terrain,
 * revealed by a sweeping mask. Blocks all input while it runs — the
 * half-born wallet beneath must not be tappable. */
@Composable
internal fun OnboardingHandoffHost(controller: OnboardingHandoffController) {
    val session = controller.session ?: return
    val reducedMotion = rememberReducedMotion()
    // Latched at session start: a mid-run system toggle must not restructure
    // the choreography under itself.
    val skipOverlay = remember(session) { reducedMotion }

    if (skipOverlay) {
        // Reduce Motion: no curtain — completion runs immediately (in this
        // hoisted scope, which outlives OnboardingScreen's) and the app
        // gate's plain crossfade is the whole transition.
        LaunchedEffect(session) {
            session.runComplete()
            controller.end()
        }
        return
    }

    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val lifecycleOwner = LocalLifecycleOwner.current

    val sweep = remember(session) { Animatable(0f) }
    val fade = remember(session) { Animatable(1f) }
    val slide = remember(session) { Animatable(0f) }

    // Backgrounding escape hatch: run the flip if it hasn't happened and drop
    // the overlay with no animation, so a mid-sweep exit can never strand the
    // user in a half-finished handoff. Nobody sees the cut.
    DisposableEffect(session, lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) {
                // NonCancellable job: ending the session below unmounts this
                // host and disposes `scope`, and the flip must survive that.
                scope.launch(NonCancellable) { session.runComplete() }
                controller.end()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .graphicsLayer {
                translationY = slide.value
                alpha = fade.value
                // The sweep mask needs scrim + glyphs flattened into one
                // layer first, or DstIn would knock through to the wallet
                // beneath.
                compositingStrategy = CompositingStrategy.Offscreen
            }
            .drawWithContent {
                drawContent()
                // The sweep: an opaque column one screen tall with a soft
                // 30%-height trailing edge, slid from fully above the window
                // (nothing visible) to covering it exactly (fully opaque).
                val columnHeight = size.height * (1f + SweepEdge)
                val top = (sweep.value - 1f) * columnHeight
                drawRect(
                    brush = Brush.verticalGradient(
                        0f to Color.Black,
                        1f / (1f + SweepEdge) to Color.Black,
                        1f to Color.Transparent,
                        startY = top,
                        endY = top + columnHeight,
                    ),
                    blendMode = BlendMode.DstIn,
                )
            }
            // Full-screen input block while the wallet is half-born.
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        awaitPointerEvent().changes.forEach { it.consume() }
                    }
                }
            },
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background),
        )
        // Full-bleed, no band geometry — the sweep above is the only mask.
        // Same renderer, speed, glyphs, and opacity ramp as the welcome band.
        AsciiField(
            modifier = Modifier.fillMaxSize(),
            touchOverride = session.touch,
        )

        val centerXDp = maxWidth.value / 2.0
        val centerYDp = maxHeight.value / 2.0
        val slidePx = with(LocalDensity.current) { DissolveSlide.toPx() }

        LaunchedEffect(session) {
            launch { sweep.animateTo(1f, tween(SweepInMs, easing = EaseOut)) }
            delay(SweepInMs.toLong())
            // The gate flip, under full cover — the root swap is invisible.
            session.runComplete()

            delay(BloomDelayMs.toLong())
            // Bloom only when the field's frame clock can render it — under
            // battery saver the press would sit invisible and release stale.
            val powerSave = (context.getSystemService(Context.POWER_SERVICE) as? PowerManager)
                ?.isPowerSaveMode == true
            if (!powerSave) session.touch.press(centerXDp, centerYDp, nowSeconds())

            delay(HoldMs.toLong())
            launch { fade.animateTo(0f, tween(DissolveMs, easing = EaseOut)) }
            launch { slide.animateTo(slidePx, tween(DissolveMs, easing = EaseOut)) }

            delay(ReleaseDelayMs.toLong())
            if (!powerSave) session.touch.release(nowSeconds())

            delay((DissolveMs - ReleaseDelayMs).toLong())
            controller.end()
        }
    }
}

/** Wall-clock seconds for the warp envelope — monotonic, arbitrary epoch;
 * only differences are ever used. */
private fun nowSeconds(): Double = System.nanoTime() / 1e9
