package com.cashu.me.ui.onboarding

import android.content.Context
import android.os.PowerManager
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.LinearEasing
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
// while the app gate flips beneath it, then lifts off the top to reveal the
// wallet already in place. Defined under the onboarding motion exemption
// and owned by onboarding — CashuApp only mounts the host; nothing here is
// referenced by wallet-proper code. The gate's own transition spec is
// untouched; it simply plays unseen under the cover.
//
// Choreography (T = a completion call site firing `begin`):
//   T+0        curtain reveals top → bottom (450ms, soft 30%-height edge)
//   T+450ms    gate flip under full cover — the root swap is invisible
//   T+480ms    lens bloom fires at screen center (existing warp envelopes)
//   T+750ms    the curtain erodes (1000ms, linear driver — the easing lives
//              in the material). Nothing translates and no edge travels: a
//              moving plane reads as a slide and a moving edge reads as a
//              wipe, and both are the wrong register for the last beat of
//              onboarding. Three things run off one progress value:
//              the opaque scrim clears early (by 42%), so the wallet arrives
//              *behind* a still-standing terrain rather than by a cut;
//              the glyphs dissolve level by level (`erosionAlpha`) — the
//              faint dotted plain thins first, the ridgelines hold, and the
//              ₿ peaks are the last things over the balance; and a
//              screen-anchored top bias deepens so the field clears from the
//              top down. The terrain keeps drifting and the bloom's release
//              swirl keeps unwinding throughout — the motion is the field's
//              own life, not the plane's.
//   T+1750ms   session ends, overlay unmounts
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

/** The erosion progress by which the opaque scrim is fully gone. Early, so the
 * wallet stands behind a terrain that is still substantially there — the
 * reveal is a change of material, not a change of screen. */
private const val ScrimClear = 0.42f

/** Depth of the screen-anchored top bias, as a fraction of screen height.
 * Fixed geometry: only its strength animates, so nothing ever travels. */
private const val TopBiasDepth = 0.55f

private const val SweepInMs = 450
private const val BloomDelayMs = 30
private const val HoldMs = 270
private const val ReleaseDelayMs = 10
private const val ErosionMs = 1000

/** Smoothstepped so the scrim neither snaps at the start nor lingers. */
private fun scrimOpacity(erosion: Float): Float {
    val u = (erosion / ScrimClear).coerceIn(0f, 1f)
    return 1f - u * u * (3f - 2f * u)
}

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

    /** 0 (intact) → 1 (gone). The single driver of the exit: scrim, glyph
     * erosion, and top bias are all pure functions of it, so the curtain
     * clears as one material rather than as three overlapping animations. */
    val erosion = remember(session) { Animatable(0f) }

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
                // The masks need scrim + glyphs flattened into one layer
                // first, or DstIn would knock through to the wallet beneath.
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
                // The exit's only geometry, and it never moves: a fixed
                // gradient whose strength grows with the erosion, so the field
                // clears from the top down.
                if (erosion.value > 0f) {
                    drawRect(
                        brush = Brush.verticalGradient(
                            0f to Color.Black.copy(alpha = 1f - erosion.value),
                            1f to Color.Black,
                            startY = 0f,
                            endY = size.height * TopBiasDepth,
                        ),
                        blendMode = BlendMode.DstIn,
                    )
                }
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
        // The scrim clears early and on its own curve, so the wallet is
        // already standing behind the terrain when the glyphs begin to go.
        // graphicsLayer, not a recomposing alpha: the read happens in the draw
        // phase.
        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer { alpha = scrimOpacity(erosion.value) }
                .background(MaterialTheme.colorScheme.background),
        )
        // Full-bleed, no band geometry — the sweep is the only mask.
        // Same renderer, speed, glyphs, and opacity ramp as the welcome band.
        AsciiField(
            modifier = Modifier.fillMaxSize(),
            touchOverride = session.touch,
            erosion = { erosion.value.toDouble() },
        )

        val centerXDp = maxWidth.value / 2.0
        val centerYDp = maxHeight.value / 2.0

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
            // Linear driver on purpose: every stage of the exit carries its
            // own smoothstep, so easing the driver too would double-ease the
            // dissolve and stall it in the middle.
            launch { erosion.animateTo(1f, tween(ErosionMs, easing = LinearEasing)) }

            delay(ReleaseDelayMs.toLong())
            if (!powerSave) session.touch.release(nowSeconds())

            delay((ErosionMs - ReleaseDelayMs).toLong())
            controller.end()
        }
    }
}

/** Wall-clock seconds for the warp envelope — monotonic, arbitrary epoch;
 * only differences are ever used. */
private fun nowSeconds(): Double = System.nanoTime() / 1e9
