package com.cashu.me.ui.onboarding

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import android.os.PowerManager
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.statusBars
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.semantics.SemanticsPropertyKey
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.testTag
import com.cashu.me.App.UiTestRuntime
import com.cashu.me.ui.testing.UiTestTags
import com.cashu.me.ui.theme.rememberReducedMotion
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt
import kotlinx.coroutines.delay

// ---------------------------------------------------------------------------
// The onboarding terrain band, ported from the cashu.space hero
// (ascii-field.tsx). A grid of monospaced glyphs driven by layered sinusoidal
// noise: three fractal octaves produce a heightfield, and cells near contour
// lines (height mod spacing) intensify, so drifting topographic ridgelines
// emerge from a quiet dotted plain. The ramp runs faint → strong: `·` and `/`
// fill the open field, `,` marks crests, $, ¥, and € mark high contours, and
// ₿ caps the strongest peaks.
//
// The web implementation is the reference — same coefficients, same order of
// operations, same magic numbers. docs/product/ascii-field-vectors.json
// (generated from the web TypeScript, not from either port) pins this port
// and the iOS one to identical terrain via AsciiFieldTerrainTest. The glyph
// *shapes* are each platform's own mono face; only the math is shared.
// ---------------------------------------------------------------------------

/** The pure terrain functions, verbatim from the web source. Kept free of any
 * UI state so the golden-vector parity test can drive them directly. */
internal object AsciiFieldTerrain {
    /** Grid cell size in dp. The terrain is texture, not text — the grid must
     * not scale with the user's font size, or the composition itself would
     * change with accessibility settings. */
    const val CELL_W = 12.0
    const val CELL_H = 14.0
    const val FONT_SIZE_DP = 12f
    const val TERRAIN_SCALE = 0.13
    const val CONTOUR_SPACING = 0.08

    /** Half the web's 0.9. A marketing hero is scrolled past in seconds; this
     * screen is stared at while someone decides whether to trust the app with
     * their money. The field must be ambient texture noticed once, not
     * something that pulls the eye while the headline is being read. */
    const val SPEED = 0.45

    /** Brightness thresholds ascend toward the stronger glyph; cells below
     * the first threshold stay empty. */
    val LEVEL_MIN = intArrayOf(40, 90, 140, 200, 216)
    val LEVEL_GLYPH = listOf("·", "/", ",")
    val CURRENCY_GLYPHS = listOf("$", "¥", "€")
    const val CURRENCY_LEVEL = 3
    const val PEAK_LEVEL = 4
    const val LEVELS = 5

    fun noise(x: Double, y: Double, t: Double): Double =
        sin(0.8 * x + 0.3 * t) * cos(0.6 * y + 0.2 * t) * 0.5 +
            0.25 * sin(1.6 * x + 1.2 * y + 0.15 * t) +
            sin(0.3 * x - 0.4 * t) * cos(0.4 * y + 0.25 * t) * 0.6 +
            0.3 * sin(0.5 * (x + y) + 0.35 * t) +
            sin(2.5 * x + 0.1 * t) * cos(2.8 * y - 0.12 * t) * 0.15

    fun fractal(x: Double, y: Double, t: Double): Double =
        noise(x, y, t) +
            0.4 * noise(2.2 * x, 2.2 * y, 0.7 * t) +
            0.15 * noise(4.5 * x, 4.5 * y, 0.4 * t)

    fun brightness(x: Double, y: Double, t: Double): Int {
        val r = min(1.0, ((fractal(x, y, t) + 1.8) / 3.6).coerceAtLeast(0.0))
        val s = (r % CONTOUR_SPACING) / CONTOUR_SPACING
        val onContour = s < 0.12 || s > 0.88
        // roundToInt is floor(x + 0.5) — JS Math.round semantics exactly.
        var b = if (onContour) (200 * r + 55).roundToInt() else (140 * r).roundToInt()
        if (onContour) {
            // Steeper terrain sharpens its contour line.
            val gx = noise(x + 0.01, y, t) - noise(x - 0.01, y, t)
            val gy = noise(x, y + 0.01, t) - noise(x, y - 0.01, t)
            val d = 12 * hypot(gx, gy)
            if (d > 0.5) b = min(255, b + (40 * d).roundToInt())
        }
        return b
    }

    /** Highest level whose threshold [b] clears; -1 draws nothing. */
    fun pickLevel(b: Int): Int {
        for (i in LEVEL_MIN.indices.reversed()) {
            if (b >= LEVEL_MIN[i]) return i
        }
        return -1
    }

    /** The wallet's one deliberate divergence from the web terrain: more ₿.
     * Cells in the top of the currency band are promoted to the peak glyph
     * (roughly doubling the on-screen ₿, ≈1.6 → ≈3.2 on a phone band)
     * without touching the $¥€ population below the boost line. [pickLevel]
     * itself stays verbatim-web so the golden-vector fixture keeps pinning
     * both ports; the boost is its own mirrored constant + function. */
    const val PEAK_BOOST_MIN = 208

    /** The level the renderer draws: [pickLevel], plus the ₿ boost. */
    fun displayLevel(b: Int): Int = if (b >= PEAK_BOOST_MIN) PEAK_LEVEL else pickLevel(b)

    // Erosion
    //
    // The handoff's exit dissolves the terrain by its own material rather than
    // by geometry: the faint dotted plain thins out first, the contour
    // ridgelines hold, and the ₿ peaks are the last glyphs standing. Nothing
    // translates and no edge travels, so the field never reads as a slide or a
    // wipe — it erodes, and the wallet comes up through it.
    //
    // Mirrored on iOS and pinned by AsciiFieldErosionTest (same constants in
    // both test files — if a port disagrees, fix the port). Only the handoff
    // overlay ever passes a non-zero progress; the welcome band always renders
    // at full strength.
    const val EROSION_STAGGER = 0.13
    const val EROSION_WINDOW = 0.48

    /** Opacity multiplier for [level] at erosion [progress] (0 intact → 1
     * gone). Windows overlap, so the field thins continuously instead of
     * clearing in five visible steps; each window is smoothstepped so no
     * level pops. */
    fun erosionAlpha(level: Int, progress: Double): Double {
        val u = ((progress - level * EROSION_STAGGER) / EROSION_WINDOW).coerceIn(0.0, 1.0)
        return 1 - u * u * (3 - 2 * u)
    }

    /** Stable spatial hash: a cell always keeps the same currency, so motion
     * comes from the terrain crossing thresholds rather than random shimmer.
     * Kotlin's Int `*` already wraps at 32 bits like JS `Math.imul`, and
     * `ushr` is JS `>>>` — get this wrong and the currency distribution
     * silently diverges from iOS; the parity fixture is what catches it. */
    fun currencyGlyphIndex(px: Double, py: Double): Int {
        val col = floor(px / CELL_W).toInt()
        val row = floor(py / CELL_H).toInt()
        val hash = (col * 31) xor (row * 17)
        val mixed = (hash xor (hash ushr 13)) * 1274126177
        return (mixed.toUInt() % 3u).toInt()
    }

    /** Continuous-brightness variants for the vault morph: the terrain→vault
     * lerp produces fractional brightness, and rounding it first would add a
     * second platform-sensitive rounding step for no visual gain. Threshold
     * semantics are identical to the [Int] originals. */
    fun pickLevel(b: Double): Int {
        for (i in LEVEL_MIN.indices.reversed()) {
            if (b >= LEVEL_MIN[i]) return i
        }
        return -1
    }

    fun displayLevel(b: Double): Int = if (b >= PEAK_BOOST_MIN) PEAK_LEVEL else pickLevel(b)
}

// ---------------------------------------------------------------------------
// The Restore Wallet screen's material: a procedural vault door rendered
// through the same glyph ramp and thresholds as the terrain, its ink
// modulated by the live terrain field itself — a brightness field, not an
// image, and never a still one. Rings, spokes, and bolts are
// distance functions; the central ₿ monogram is a tiny hand-authored stencil
// (a shared fixture, like the warp vectors — never an asset). The step morph
// lerps this field against the terrain per cell, so the landscape *deforms*
// into the vault — dots condense first, ₿ bolts last — rather than
// crossfading like a video edit.
//
// This is the restyle brief's one sanctioned representational image (§4
// exception): restoring is opening your vault, and the vault is built from
// the field's own living material on a task screen — not an illustration
// laid on top.
//
// Mirrored on iOS and pinned by AsciiFieldVaultTest (vectors generated from
// the design mock's Python, pasted identically into both test files — if a
// port disagrees, fix the port). All geometry in grid units (dp here, points
// on iOS), authored at fixed size: the vault does not scale with the window,
// it only recenters.
// ---------------------------------------------------------------------------
internal object AsciiFieldVault {
    /** Heavy outer door ring. */
    const val OUTER_RADIUS = 146.0
    const val OUTER_WIDTH = 11.0
    const val OUTER_BRIGHTNESS = 196.0

    /** Inner ring around the wheel. */
    const val INNER_RADIUS = 92.0
    const val INNER_WIDTH = 9.0
    const val INNER_BRIGHTNESS = 168.0

    /** Faint dotted door face, out to just past the outer ring's center line. */
    const val FACE_RADIUS = 152.0
    const val FACE_BRIGHTNESS = 52.0

    /** Six wheel spokes, hub → inner ring, thinning with angular distance. */
    const val SPOKE_MIN_DISTANCE = 24.0
    const val SPOKE_MAX_DISTANCE = 96.0
    const val SPOKE_BRIGHTNESS = 176.0
    const val SPOKE_ARC_WIDTH = 8.0

    /** Twelve rim studs between the rings — bright enough for the ₿ boost. */
    const val BOLT_RADIUS = 121.0
    const val BOLT_HALF_WIDTH = 8.0
    const val BOLT_BRIGHTNESS = 212.0

    /** The monogram stencil's two ink strengths. 221, not a rounder number:
     * at [LIVE_GAIN] 0.28 the monogram shows ₿ ~83% of the time with ~8
     * glyph trades/sec across its cells — one point lower reads $-heavy,
     * one higher goes static (tuned against the terrain's own liveliness). */
    const val STENCIL_PEAK_BRIGHTNESS = 221.0
    const val STENCIL_CURRENCY_BRIGHTNESS = 202.0

    /** The living ink: the vault's brightness is modulated by the *live
     * terrain brightness at the same cell*, so the landing screen's
     * ridgelines keep crawling through the door's structure. The terrain's
     * motion is its contour cliffs (the mod-spacing discontinuity), which no
     * amount of smooth noise shimmer reproduces — borrowing the terrain
     * field wholesale is what makes the vault move exactly like Welcome. */
    const val LIVE_GAIN = 0.28
    const val LIVE_PIVOT = 128.0

    /** Past this distance the field is the living ink alone, whose maximum
     * 0.28·(255−128) = 35.6 sits under the first draw threshold — nothing
     * ever draws, so the renderer may skip the cell outright when the morph
     * is fully settled. */
    const val EXTENT_RADIUS = OUTER_RADIUS + OUTER_WIDTH

    /** The central ₿ monogram, cell-aligned to the vault center: 2 = peak
     * ink, 1 = currency-strength ink. Hand-authored against the real cell
     * metrics (12×14) — edit only alongside the mock render and the parity
     * vectors. */
    const val STENCIL_COLS = 9
    const val STENCIL_ROWS = 11
    private val STENCIL_ART = listOf(
        "....2....",
        ".222222..",
        ".2....22.",
        ".2.....2.",
        ".2....22.",
        ".222222..",
        ".2....22.",
        ".2.....2.",
        ".2....22.",
        ".222222..",
        "....2....",
    )
    private val STENCIL_BOOST: Array<DoubleArray> = Array(STENCIL_ROWS) { row ->
        DoubleArray(STENCIL_COLS) { col ->
            when (STENCIL_ART[row][col]) {
                '2' -> STENCIL_PEAK_BRIGHTNESS
                '1' -> STENCIL_CURRENCY_BRIGHTNESS
                else -> 0.0
            }
        }
    }

    private fun ringProfile(d: Double, radius: Double, width: Double): Double =
        max(0.0, 1.0 - abs(d - radius) / width)

    /** Brightness at grid point (px, py) for a vault centered at
     * (centerX, centerY). Same output domain as the terrain's brightness, so
     * the two lerp per cell and share one glyph ramp. */
    fun brightness(px: Double, py: Double, centerX: Double, centerY: Double, t: Double): Double {
        val dx = px - centerX
        val dy = py - centerY
        val d = sqrt(dx * dx + dy * dy)
        var b = 0.0
        if (d < FACE_RADIUS) b = FACE_BRIGHTNESS
        b = max(b, OUTER_BRIGHTNESS * ringProfile(d, OUTER_RADIUS, OUTER_WIDTH))
        b = max(b, INNER_BRIGHTNESS * ringProfile(d, INNER_RADIUS, INNER_WIDTH))
        // `ang + π` is never negative (atan2 ∈ [−π, π]), so Kotlin's
        // truncating `%` matches Python/Swift here.
        val ang = atan2(dy, dx)
        if (d > SPOKE_MIN_DISTANCE && d < SPOKE_MAX_DISTANCE) {
            val a = (ang + PI) % (PI / 3)
            val arc = min(a, PI / 3 - a) * d
            b = max(b, SPOKE_BRIGHTNESS * max(0.0, 1.0 - arc / SPOKE_ARC_WIDTH))
        }
        val a12 = (ang + PI) % (PI / 6)
        val boltArc = min(a12, PI / 6 - a12) * BOLT_RADIUS
        val boltD = sqrt((d - BOLT_RADIUS) * (d - BOLT_RADIUS) + boltArc * boltArc)
        if (boltD < BOLT_HALF_WIDTH) b = max(b, BOLT_BRIGHTNESS)
        // Stencil index rounds half toward +∞ (floor(v + 0.5)) — the same
        // convention as `roundToInt`, spelled out so it visibly matches the
        // Swift port, which must NOT use its half-away `.rounded()`. The
        // parity vectors include both boundary signs to catch exactly that.
        val col = floor(dx / AsciiFieldTerrain.CELL_W + 0.5).toInt() + STENCIL_COLS / 2
        val row = floor(dy / AsciiFieldTerrain.CELL_H + 0.5).toInt() + STENCIL_ROWS / 2
        if (row in 0 until STENCIL_ROWS && col in 0 until STENCIL_COLS) {
            b = max(b, STENCIL_BOOST[row][col])
        }
        // Same cell→noise mapping the renderer uses for the terrain itself,
        // so a warped vault sample rides the identical warped terrain sample.
        val tb = AsciiFieldTerrain.brightness(
            px / AsciiFieldTerrain.CELL_W * AsciiFieldTerrain.TERRAIN_SCALE,
            py / AsciiFieldTerrain.CELL_H * AsciiFieldTerrain.TERRAIN_SCALE,
            t,
        ).toDouble()
        return b + LIVE_GAIN * (tb - LIVE_PIVOT)
    }
}

/** The lens warp under a pressed finger, as pure functions mirrored on iOS
 * and pinned by [AsciiFieldWarpTest] (hand-authored vectors, same constants
 * in both test files — if a port disagrees, fix the port).
 *
 * All distances are in grid units (dp here, points on iOS): the space where a
 * cell is 12×14, so the lens is circular on screen and both ports feed the
 * functions numerically identical inputs. */
internal object AsciiFieldWarp {
    /** Full-bloom lens radius: 10 columns / ~8.6 rows of the band grid. */
    const val RADIUS = 120.0

    /** The lens materializes at this fraction of its radius and blooms to
     * full as the envelope rises — it grows out of the touch point rather
     * than appearing at final size. */
    const val RADIUS_BLOOM_FLOOR = 0.75

    /** Peak sample displacement: 3 cells ≈ 0.39 noise-x units. */
    const val MAX_DISPLACEMENT = 36.0

    /** Envelope durations in wall-clock seconds — not terrain `t`, which is
     * speed-scaled and freezes with the clock. */
    const val PRESS_DURATION = 0.28
    const val RELEASE_DURATION = 0.6

    /** easeOutBack shape parameter: ~5% overshoot (envelope peaks at
     * 1.0529), so the lens blooms slightly past full and relaxes. Positive
     * overshoot is safe — only a *negative* envelope would flip the lens
     * into attraction — and the no-fold margin holds at the peak
     * (max slope 3.079·A·k/R = 0.973 < 1). */
    const val BACK_OVERSHOOT = 1.2

    /** Swirl at full displacement, radians. The displacement direction is
     * rotated in proportion to local strength, so terrain flows *around*
     * the finger instead of only fleeing it — and un-twists as the release
     * envelope decays. */
    const val SWIRL_MAX = 0.35

    /** Position-glide time constant: the lens eases toward the finger with
     * `1 - exp(-dt/τ)` per frame, so a drag reads as fluid pursuit rather
     * than per-frame teleports. */
    const val FOLLOW_TAU = 0.07

    /** Lens radius at envelope [k] — the bloom. */
    fun bloomedRadius(k: Double): Double =
        RADIUS * (RADIUS_BLOOM_FLOOR + (1 - RADIUS_BLOOM_FLOOR) * min(1.0, k))

    /** Sample displacement at distance [d] from the finger, envelope [k].
     * The bump `16·(s(1-s))²` is zero in value *and* slope at the touch point
     * and at the rim, so contours never kink at the lens boundary, and its
     * max slope stays below 1 even at the overshoot peak, so the warped
     * sampling never folds over itself. */
    fun displacement(d: Double, k: Double): Double {
        if (k <= 0.0 || d <= 0.0) return 0.0
        val r = bloomedRadius(k)
        if (d >= r) return 0.0
        val s = d / r
        val e = s * (1 - s)
        return MAX_DISPLACEMENT * k * 16 * e * e
    }

    /** easeOutBack: fast rise, small overshoot, soft settle. Clamped at
     * zero — the polynomial dips to −2e-16 at u = 0 in floating point, and
     * even that microscopically negative envelope is the attraction flip
     * the design forbids (the parity tests assert k ≥ 0 throughout). */
    private fun backOut(u: Double): Double {
        val c = u.coerceIn(0.0, 1.0)
        val q = c - 1
        return (1 + (BACK_OVERSHOOT + 1) * q * q * q + BACK_OVERSHOOT * q * q).coerceAtLeast(0.0)
    }

    /** Ease-in from [k0] (non-zero when a finger lands mid-decay). */
    fun pressEnvelope(elapsed: Double, k0: Double): Double =
        k0 + (1 - k0) * backOut(elapsed / PRESS_DURATION)

    /** `k0·(1-v)³` — a settle, deliberately not a spring: overshoot *here*
     * would swing `k` negative and flip the lens into attraction. */
    fun releaseEnvelope(elapsed: Double, k0: Double): Double {
        val v = 1 - (elapsed / RELEASE_DURATION).coerceIn(0.0, 1.0)
        return k0 * v * v * v
    }

    /** Rotation of the displacement direction at displacement [f] —
     * proportional to local strength, so the swirl is strongest mid-lens
     * and vanishes at both the touch point and the rim. */
    fun swirlAngle(f: Double): Double = SWIRL_MAX * f / MAX_DISPLACEMENT

    /** Per-frame glide fraction for elapsed [dt] — exponential smoothing,
     * frame-rate independent. */
    fun followFactor(dt: Double): Double = 1 - exp(-dt / FOLLOW_TAU)
}

/** Mutable finger state, read by the frame loop. Deliberately not Compose
 * state: the 30fps [withFrameNanos] tick already repaints, so mutations here
 * surface on the next frame without invalidating the composition per touch
 * event. Mirrors iOS `AsciiFieldWarpTouch`. */
internal class AsciiFieldWarpTouch {
    enum class Phase { Idle, Pressed, Released }

    var phase = Phase.Idle
        private set

    /** Where the lens *is*, in grid units (dp) — glides toward the finger
     * via [advance] (see [AsciiFieldWarp.FOLLOW_TAU]). */
    var x = 0.0
        private set
    var y = 0.0
        private set

    /** Where the finger is — the glide target. */
    private var targetX = 0.0
    private var targetY = 0.0
    private var phaseStart = 0.0
    private var k0 = 0.0
    private var lastAdvance = 0.0

    fun press(px: Double, py: Double, now: Double) {
        targetX = px
        targetY = py
        // A landing finger snaps the lens under it — the bloom starts where
        // the touch is, never gliding in from a stale spot.
        x = px
        y = py
        lastAdvance = now
        // Ramp from the current envelope, so re-pressing mid-decay doesn't
        // snap the lens shut and reopen it from zero.
        k0 = currentK(now)
        phaseStart = now
        phase = Phase.Pressed
    }

    fun move(px: Double, py: Double) {
        targetX = px
        targetY = py
    }

    fun release(now: Double) {
        if (phase != Phase.Pressed) return
        k0 = currentK(now)
        phaseStart = now
        phase = Phase.Released
    }

    fun reset() {
        phase = Phase.Idle
    }

    /** Advances the position glide; call once per frame before sampling.
     * Keeps gliding through the release settle, so a flick's lens drifts
     * to rest at the lift point instead of freezing mid-pursuit. */
    fun advance(now: Double) {
        if (phase == Phase.Idle) return
        // Clamp dt so a hitch or pause can't turn into a teleport.
        val dt = (now - lastAdvance).coerceIn(0.0, 0.1)
        lastAdvance = now
        val a = AsciiFieldWarp.followFactor(dt)
        x += (targetX - x) * a
        y += (targetY - y) * a
    }

    fun currentK(now: Double): Double = when (phase) {
        Phase.Idle -> 0.0
        Phase.Pressed -> AsciiFieldWarp.pressEnvelope(now - phaseStart, k0)
        Phase.Released -> {
            val k = AsciiFieldWarp.releaseEnvelope(now - phaseStart, k0)
            if (k <= 0.0) phase = Phase.Idle
            k
        }
    }
}

/** Field geometry as pure math, so the layout-invariant test can assert it
 * without composing views. Mirrors iOS `AsciiFieldLayout`.
 *
 * The drawn layer always spans the full window, on both steps of the pair:
 * glyph positions (and the currency hash keyed on them) are a function of
 * layer size, so a layer that resized between steps would make the whole
 * texture swim and re-hash mid-transition. What differs per step is the
 * field's *material* — Welcome's tall terrain vs Restore Wallet's vault door
 * (see AsciiFieldVault) — plus the mask's opaque ramp, which shortens from
 * the long welcome fade to end at the vault's top edge; both ride a single
 * 0…1 morph on the stage swap. The clear line behind the header never moves,
 * and the glyph grid never moves and never re-hashes. (Band mode — extent 0 —
 * survives as pure math and its tests; no step rests on it anymore.)
 *
 * The field terminates through its mask, not through occlusion: the bottom
 * fade begins above the chassis edge and settles onto a faint floor a little
 * past it, so the terrain dissolves toward the buttons — a faint sliver
 * continuing behind them — instead of ending on a hard cut. */
internal object AsciiFieldLayout {
    /** Web is `clamp(180px, 26vh, 320px)`; scaled slightly for phone-sized
     * viewports. All values dp. */
    const val MIN_BAND = 160f
    const val MAX_BAND = 300f
    const val BAND_FRACTION = 0.26f

    /** Below this the band would be a squashed few-row smear behind
     * accessibility-size copy (or a landscape phone) — draw nothing instead. */
    const val SUPPRESSION_THRESHOLD = 120f

    /** Band mode ramps transparent → opaque over this fraction of the visible
     * band (the web masks the top 30% of its fully-visible band; ours also
     * extends under the chassis, so the fraction applies to the visible part). */
    const val MASK_FADE = 0.30f

    /** Full mode's ramp length as a fraction of the *window* — the same 0.30
     * family as [MASK_FADE] and the handoff's SweepEdge, stretched over the
     * taller extent so the field materializes gradually below the header
     * instead of arriving on a visible line. */
    const val FULL_FADE = 0.30f

    /** The bottom fade starts this far (dp) above the chassis edge… */
    const val BOTTOM_FADE_REACH = 48f

    /** …and settles onto the floor opacity this far past it, so the dimming
     * is complete by the time the terrain passes behind the buttons. */
    const val BOTTOM_FADE_UNDERLAP = 40f

    /** The fade lands on this opacity — not zero — and holds it to the very
     * bottom of the window: the terrain runs subtly behind the chassis
     * buttons and the navigation bar instead of cutting out above them. */
    const val BOTTOM_FLOOR_ALPHA = 0.25f

    /** The two extent-dependent mask boundaries, as fractions of layerHeight. */
    data class MaskStops(val clearEnd: Float, val opaqueEnd: Float)

    data class Resolution(
        /** Height of the band above the chassis — what Restore Wallet shows. */
        val visibleBand: Float,
        /** Full layer height — always the window height, on both steps. */
        val layerHeight: Float,
        /** Band mode (extent 0), as fractions of layerHeight: fully clear
         * above [bandClearEnd], ramping to fully opaque at [bandOpaqueEnd].
         * Geometrically the shipped band mask in window coordinates. */
        val bandClearEnd: Float,
        val bandOpaqueEnd: Float,
        /** Full mode (extent 1): clear behind the whole header block — the
         * boundary sits at the header-clearance line — then the long ramp. */
        val fullClearEnd: Float,
        val fullOpaqueEnd: Float,
        /** The bottom fade never moves with extent — above the chassis edge,
         * so the dissolve is already underway when the terrain meets the
         * buttons… */
        val bottomFadeStart: Float,
        /** …completing slightly past the chassis edge, behind the buttons. */
        val bottomFadeEnd: Float,
        /** Vault mode (Restore Wallet): the ramp completes by the vault's top
         * edge so nothing of the door is dimmed — a shorter ramp than full
         * mode's, same clear line behind the header. */
        val vaultOpaqueEnd: Float,
        /** The vault's center, dp from the layer top: the middle of the empty
         * region between the header block and the chassis. */
        val vaultCenterY: Float,
    ) {
        /** The extent-dependent stops, lerped. Clamped because a bouncy
         * spatial spring overshoots its 0…1 target transiently. */
        fun maskStops(extent: Float): MaskStops {
            val e = extent.coerceIn(0f, 1f)
            return MaskStops(
                clearEnd = bandClearEnd + (fullClearEnd - bandClearEnd) * e,
                opaqueEnd = bandOpaqueEnd + (fullOpaqueEnd - bandOpaqueEnd) * e,
            )
        }

        /** The stops the live pair actually renders: full mode (Welcome's
         * tall terrain) lerped toward vault mode by the morph. The clear line
         * never moves — both modes are transparent through the header block —
         * so the cull is constant across the whole morph. */
        fun morphedMaskStops(vaultMix: Float): MaskStops {
            val m = vaultMix.coerceIn(0f, 1f)
            val full = maskStops(1f)
            return MaskStops(
                clearEnd = full.clearEnd,
                opaqueEnd = full.opaqueEnd + (vaultOpaqueEnd - full.opaqueEnd) * m,
            )
        }

        /** Dp from the layer top to the current fully-transparent boundary —
         * everything above it is masked to nothing and cullable. */
        fun transparentStartDp(extent: Float): Float = maskStops(extent).clearEnd * layerHeight
    }

    /** [headerClearance] is the vertical room the pair's tallest header
     * (welcome's two-line title + subhead, scaled by the live fontScale)
     * needs. Using the same clearance for both steps of the pair keeps the
     * resolved geometry identical across them — the layout-invariant
     * contract, now carried by the constant full-window layer. */
    fun resolve(
        windowHeight: Float,
        topInset: Float,
        headerClearance: Float,
        chassisHeight: Float,
    ): Resolution? {
        val band = (BAND_FRACTION * windowHeight).coerceIn(MIN_BAND, MAX_BAND)
        // The empty region between the header block and the chassis. When the
        // heavy display title wraps at large font scales (or the window is a
        // landscape phone), this collapses and the field is suppressed rather
        // than squashed — the band never shrinks to fit.
        val available = windowHeight - topInset - headerClearance - chassisHeight
        if (min(band, available) < SUPPRESSION_THRESHOLD) return null
        return resolution(band, windowHeight, topInset, headerClearance, chassisHeight)
    }

    /** The suppressed case still needs a stable frame (the backdrop hides
     * rather than unmounts, to keep its wall clock), so it lays out the
     * floor band against the same full-window layer. */
    fun fallback(
        windowHeight: Float,
        topInset: Float,
        headerClearance: Float,
        chassisHeight: Float,
    ): Resolution = resolution(MIN_BAND, windowHeight, topInset, headerClearance, chassisHeight)

    private fun resolution(
        band: Float,
        windowHeight: Float,
        topInset: Float,
        headerClearance: Float,
        chassisHeight: Float,
    ): Resolution {
        // A transient zero-size layout pass must not divide by zero; the
        // degenerate frame is invisible (suppressed → alpha 0) either way.
        val height = max(windowHeight, band + chassisHeight)
        val bandTop = height - chassisHeight - band
        val bandClearEnd = bandTop / height
        val bandOpaqueEnd = (bandTop + MASK_FADE * band) / height
        // Both full-mode stops clamp against their band counterparts: in a
        // cramped-but-not-suppressed window the header block can reach below
        // the band top, and full mode must degrade to band mode — the settle
        // becomes a no-op rather than inverting direction.
        val fullClearEnd = min((topInset + headerClearance) / height, bandClearEnd)
        val fullOpaqueEnd = min(fullClearEnd + FULL_FADE, bandOpaqueEnd)
        // The vault floats in the middle of the free region. Its mask ramp
        // must be done by the door's top edge; on cramped windows the door
        // reaches the header clearance line and the ramp degrades to a hard
        // edge there rather than dimming the ring.
        val vaultCenterY = (topInset + headerClearance + height - chassisHeight) / 2
        val vaultTop = (vaultCenterY - AsciiFieldVault.EXTENT_RADIUS.toFloat()) / height
        return Resolution(
            visibleBand = band,
            layerHeight = height,
            bandClearEnd = bandClearEnd,
            bandOpaqueEnd = bandOpaqueEnd,
            fullClearEnd = fullClearEnd,
            fullOpaqueEnd = fullOpaqueEnd,
            bottomFadeStart = (height - chassisHeight - BOTTOM_FADE_REACH) / height,
            bottomFadeEnd = (height - chassisHeight + min(BOTTOM_FADE_UNDERLAP, chassisHeight)) / height,
            vaultOpaqueEnd = max(fullClearEnd, min(vaultTop, fullOpaqueEnd)),
            vaultCenterY = vaultCenterY,
        )
    }

    /** First grid row worth evaluating under a mask whose fully-transparent
     * region ends [transparentStartDp] from the layer top. One row of slack
     * for glyph ink overhanging its cell; everything above multiplies to zero
     * through the mask anyway, so culling is purely a cost move — it changes
     * which rows are computed, never where anything draws. */
    fun cullStartRow(transparentStartDp: Float): Int =
        max(0, floor(transparentStartDp / AsciiFieldTerrain.CELL_H).toInt() - 1)

    /** Welcome's header at the live font scale: bar band + two title lines +
     * gap + one subhead line, in dp. Tracks fontScale so the suppression rule
     * reacts to accessibility sizes without measuring live views (which would
     * differ between the two steps). Line heights from OnboardingChassis
     * typography: title 40sp, subhead (bodyLarge) 24sp. */
    fun headerClearanceDp(fontScale: Float): Float {
        val titleTopInset = 8f + 48f + 8f // BarTopInset + BarHeight + TitleGap
        return titleTopInset + (2 * 40f + 24f) * fontScale + 8f
    }
}

/**
 * The terrain layer as the onboarding root mounts it: a full-window field
 * whose gradient mask decides how much of it shows.
 *
 * Mounted once at the root rather than inside the stages. Welcome and Restore
 * Wallet are *adjacent* steps; mounted per-stage the field would unmount and
 * materialize-blur on that swap, and the two screens would read as two
 * separate wallpapers that happen to match. Hoisted, the terrain keeps
 * drifting while its mask settles between the pair's two extents — tall on
 * Welcome, the classic band on Restore Wallet — one continuous space whose
 * visible reach is the cue that the screen changed. Visibility is opacity
 * only: leaving the pair fades on the same motion-scheme specs the stage swap
 * itself uses (the clock pauses); returning fades back in and resumes from
 * wall-clock.
 *
 * Suppression (tight vertical space) hides rather than removes the field: its
 * identity — and with it the wall clock — must survive, or a pass through a
 * suppressed layout would replay from t=0.
 *
 * @param vault True on Restore Wallet (the field's brightness morphs into the
 *   vault door — restoring is opening your vault), false on Welcome (the tall
 *   terrain). The morph rides the spatial spec; Reduce Motion and frozen
 *   goldens snap between the end states. Steps outside the pair hold the
 *   last value — the exit is opacity-only, and the field must not morph
 *   mid-fade.
 * @param chassisHeightPx Measured height of the chassis this layer runs
 *   under. Constant across the welcome/restore pair (two capsules, no
 *   accessory), so the terrain cannot shift on that swap.
 */
@Composable
internal fun OnboardingAsciiBackdrop(
    visible: Boolean,
    vault: Boolean,
    conceptSheetOpen: Boolean,
    chassisHeightPx: Int,
    modifier: Modifier = Modifier,
    staticTime: Float? = null,
    forceSynthesizedPeak: Boolean = false,
) {
    val density = LocalDensity.current
    val reducedMotion = rememberReducedMotion()

    BoxWithConstraints(modifier) {
        // The backdrop spans the *un-inset* window (the onboarding root
        // mounts it outside its own inset padding), so the terrain can run
        // to the physical screen bottom. The nav bar joins the chassis as
        // underlap — exactly how iOS folds the home indicator into
        // `chassisInset` — and the status bar goes to the resolver as the
        // top inset, matching iOS's full-window height + explicit topInset.
        // Tests compose the backdrop with zero insets and are unaffected.
        val statusBarDp = with(density) { WindowInsets.statusBars.getTop(this).toDp().value }
        val navBarDp = with(density) { WindowInsets.navigationBars.getBottom(this).toDp().value }
        val windowHeightDp = with(density) { constraints.maxHeight.toDp().value }
        val chassisDp = with(density) { chassisHeightPx.toDp().value } + navBarDp
        val resolved = AsciiFieldLayout.resolve(
            windowHeight = windowHeightDp,
            topInset = statusBarDp,
            headerClearance = AsciiFieldLayout.headerClearanceDp(density.fontScale),
            chassisHeight = chassisDp,
        )
        val layout = resolved ?: AsciiFieldLayout.fallback(
            windowHeight = windowHeightDp,
            topInset = statusBarDp,
            headerClearance = AsciiFieldLayout.headerClearanceDp(density.fontScale),
            chassisHeight = chassisDp,
        )
        val shouldShow = visible && resolved != null

        // The material morph, 0 (terrain) … 1 (vault). Initialized at the
        // target — a frozen (staticTime) golden must show the step's resting
        // material on its very first frame — and animated on the spatial
        // spec, the same register the stage swap's scale rides, so the morph
        // and the text materialize read as one gesture. Reduce Motion snaps:
        // the end states differ (terrain vs vault), so the step change stays
        // legible without motion.
        val vaultMix = remember { Animatable(if (vault) 1f else 0f) }
        val morphSpec = MaterialTheme.motionScheme.defaultSpatialSpec<Float>()
        LaunchedEffect(vault, reducedMotion) {
            val target = if (vault) 1f else 0f
            if (staticTime != null || reducedMotion) {
                vaultMix.snapTo(target)
            } else {
                vaultMix.animateTo(target, morphSpec)
            }
        }

        // First-launch entrance: title y-rise settles (~400ms), then a 450ms
        // delay and a 900ms easeOut fade — the field comes up like light in a
        // room, a slow plain fade, not a materialize. It's a texture, not an
        // object; a blur on already-soft 12dp glyphs behind a gradient mask
        // reads as nothing while costing an offscreen pass. Later shows/hides
        // ride the stage swap's own effects specs — exits subtler than
        // entrances. Reduce Motion snaps; staticTime (goldens) is always
        // fully visible.
        // The initial value matters for goldens: a frozen (staticTime)
        // composition must be fully visible on its very first frame, before
        // any effect has run.
        val opacity = remember { Animatable(if (staticTime != null && shouldShow) 1f else 0f) }
        var enteredOnce by remember { mutableStateOf(staticTime != null) }
        val showSpec = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
        val hideSpec = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
        LaunchedEffect(shouldShow, reducedMotion) {
            when {
                staticTime != null -> opacity.snapTo(if (shouldShow) 1f else 0f)
                !shouldShow -> if (reducedMotion) opacity.snapTo(0f) else opacity.animateTo(0f, hideSpec)
                reducedMotion -> opacity.snapTo(1f).also { enteredOnce = true }
                !enteredOnce -> {
                    enteredOnce = true
                    delay(450)
                    opacity.animateTo(1f, tween(durationMillis = 900, easing = EaseOut))
                }
                else -> opacity.animateTo(1f, showSpec)
            }
        }

        AsciiField(
            staticTime = staticTime,
            active = visible && !conceptSheetOpen && resolved != null,
            forceSynthesizedPeak = forceSynthesizedPeak,
            vaultTarget = if (vault) 1f else 0f,
            // The morph, read in the draw scope like erosion, so each
            // animated value repaints without recomposing.
            vaultMix = { vaultMix.value.toDouble() },
            vaultCenterYDp = layout.vaultCenterY,
            // Rows above the mask's fully-transparent boundary are skipped
            // rather than computed-then-erased. The clear line sits at the
            // header clearance on both steps of the pair, so the cull is a
            // constant of the layout.
            topCullDp = { layout.transparentStartDp(1f) },
            // The layer spans the whole window on both steps — the glyph
            // grid is a function of window size alone, so the morph never
            // moves or re-hashes the texture.
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer {
                    alpha = opacity.value
                    // The top mask needs the glyphs flattened into one layer
                    // first, or DstIn would knock through to the ground.
                    compositingStrategy = CompositingStrategy.Offscreen
                }
                // Clear behind the header block on both steps, ramping to
                // opaque — the long Welcome ramp shortening to end at the
                // vault's top edge as the morph settles; then opaque → floor
                // across the chassis edge, so the field dims toward the
                // buttons and keeps running — very subtle — behind them all
                // the way to the window bottom. Continuous gradients, never
                // stepped, so neither fade bands. The morph is read *here*,
                // in the draw phase, so each animated value invalidates only
                // the draw — no recomposition per frame.
                .drawWithContent {
                    drawContent()
                    val stops = layout.morphedMaskStops(vaultMix.value)
                    drawRect(
                        brush = Brush.verticalGradient(
                            0f to Color.Transparent,
                            stops.clearEnd to Color.Transparent,
                            stops.opaqueEnd to Color.Black,
                            layout.bottomFadeStart to Color.Black,
                            layout.bottomFadeEnd to
                                Color.Black.copy(alpha = AsciiFieldLayout.BOTTOM_FLOOR_ALPHA),
                            1f to Color.Black.copy(alpha = AsciiFieldLayout.BOTTOM_FLOOR_ALPHA),
                        ),
                        blendMode = BlendMode.DstIn,
                    )
                },
        )
    }
}

/**
 * The Canvas renderer. The parent backdrop drives visibility with opacity
 * only — this composable never unmounts while onboarding is on screen.
 *
 * @param staticTime Freezes the renderer at a chosen moment — deterministic
 *   goldens and the evidence strips. In post-SPEED time units, like the web's
 *   prop.
 * @param active The onboarding-side gate inputs: current step shows the
 *   field, and no concept sheet is presented over it.
 * @param forceSynthesizedPeak Test/preview hook so the synthesized-₿ path can
 *   be exercised on a device whose mono face carries a native ₿.
 * @param touchOverride Externally driven lens (the onboarding handoff's
 *   programmatic center bloom). When set, the field never listens to fingers —
 *   the owner is the only one pressing. Warp math and constants are untouched.
 */
@Composable
internal fun AsciiField(
    modifier: Modifier = Modifier,
    staticTime: Float? = null,
    active: Boolean = true,
    forceSynthesizedPeak: Boolean = false,
    touchOverride: AsciiFieldWarpTouch? = null,
    /** The owning step's resting material (0 Welcome terrain, 1 Restore
     * Wallet vault), published through semantics so the layout compose test
     * can assert the end state each step drives without reading animation
     * internals. Null (the handoff curtain) publishes nothing. */
    vaultTarget: Float? = null,
    /** The Welcome ↔ Restore morph, 0 (terrain) → 1 (vault): each cell's
     * brightness lerps between the two fields, so the landscape deforms into
     * the vault through the shared glyph ramp. A draw-scope lambda like
     * [erosion]; at 0 the draw is byte-identical to the pure terrain — the
     * handoff curtain and the Welcome step never set it. */
    vaultMix: () -> Double = { 0.0 },
    /** The vault's center, dp from the layer top (the layout's vaultCenterY);
     * x is always the layer's midline. */
    vaultCenterYDp: Float = 0f,
    /** Dp from the layer top that are fully transparent under the owner's
     * mask — rows above are skipped rather than computed-then-erased. A
     * draw-scope lambda like [erosion], so the settle repaints without
     * recomposing. The handoff leaves the default and draws every row. */
    topCullDp: () -> Float = { 0f },
    /** The handoff's exit dissolve, 0 (intact) → 1 (gone). A lambda, not a
     * value: the overlay's animation is read inside the draw scope, so a
     * dissolving field repaints without recomposing 30 times a second. At 0
     * the draw is byte-identical to what it always was. */
    erosion: () -> Double = { 0.0 },
) {
    val context = LocalContext.current
    val density = LocalDensity.current.density
    val reducedMotion = rememberReducedMotion()
    // Previews and screenshot goldens render through layoutlib, whose context
    // has no real PowerManager and no broadcast delivery — skip the guard
    // there (staticTime freezes those compositions anyway).
    val inspectionMode = LocalInspectionMode.current

    // Battery saver, observed live — a mid-session toggle freezes the frame
    // in place rather than waiting for the next cold mount.
    var powerSave by remember {
        val pm = if (inspectionMode) null else context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        mutableStateOf(pm?.isPowerSaveMode == true)
    }
    if (!inspectionMode) {
        DisposableEffect(context) {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(c: Context?, i: Intent?) {
                    powerSave = pm?.isPowerSaveMode == true
                }
            }
            context.registerReceiver(receiver, IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED))
            onDispose { context.unregisterReceiver(receiver) }
        }
    }

    // The single decision point for every play/pause input, mirroring the
    // web's sync(): Reduce Motion / battery saver / staticTime paint one
    // still frame; leaving the step pair or opening the concept sheet stops
    // the clockwork. Backgrounding pauses for free — withFrameNanos simply
    // stops being serviced while the choreographer is idle.
    //
    // Instrumented runs freeze the ambient clock too, the same way Reduce
    // Motion and battery saver do: the field is decoration, and a 30fps
    // full-window software render held across a whole journey suite kept
    // killing the CI emulator mid-run. UiTestRuntime flips only under the
    // instrumentation runner's application — never in production. One still
    // frame keeps layout, goldens, and the handoff intact.
    val clockRuns = staticTime == null && !reducedMotion && !powerSave && !UiTestRuntime.active && active

    // Wall-clock zero. Time is always derived from the monotonic clock —
    // never a frame counter — so a pause/resume never rewinds or replays;
    // the terrain simply is where the clock says it is.
    val startNanos = remember { System.nanoTime() }
    val timeState = remember { mutableFloatStateOf(0f) }
    // Remembered independently of the theme-keyed renderer, so a dark-mode
    // flip mid-press keeps the lens where the finger is. An injected lens
    // takes its place wholesale — one identity per field, never both.
    val internalTouch = remember { AsciiFieldWarpTouch() }
    val touch = touchOverride ?: internalTouch
    // 60fps while a finger is down — the lens pursuit reads steppy at the
    // ambient 30. Plain state: the frame loop reads it each frame, and the
    // release settle runs at the ambient rate (nothing tracks the finger
    // anymore).
    val interacting = remember { mutableStateOf(false) }
    LaunchedEffect(clockRuns) {
        // Never carry a stale lens across a pause — a resume must not replay
        // a half-finished decay.
        touch.reset()
        if (clockRuns) {
            // Frame cap by elapsed time rather than the web's every-2nd-frame
            // skip: alternate frames on a 120 Hz panel would still be 60fps.
            var lastDrawNanos = 0L
            while (true) {
                withFrameNanos { nanos ->
                    val capNanos = if (interacting.value) 16_000_000L else 33_000_000L
                    if (nanos - lastDrawNanos >= capNanos) {
                        lastDrawNanos = nanos
                        timeState.floatValue =
                            ((nanos - startNanos) / 1e9 * AsciiFieldTerrain.SPEED).toFloat()
                    }
                }
            }
        } else {
            // Freeze at the current wall-clock moment so repaints (theme
            // change, resize) reuse it instead of silently drifting.
            timeState.floatValue =
                ((System.nanoTime() - startNanos) / 1e9 * AsciiFieldTerrain.SPEED).toFloat()
        }
    }

    val ink = MaterialTheme.colorScheme.onSurface
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f
    val renderer = remember(ink, dark, density, forceSynthesizedPeak) {
        AsciiFieldRenderer(ink, dark, density, forceSynthesizedPeak)
    }

    // Decoration only — never reaches TalkBack, never appears in the
    // accessibility tree the chassis UI tests walk. The test tag is the one
    // property left behind: it carries no assistive content, and it's what
    // the layout-invariant test measures the field's frame through.
    //
    // Touch is the one exception to "decoration only": the finger warps the
    // terrain (lens warp) — but only while the clock runs. The decay needs
    // the frame loop to render, Reduce Motion users shouldn't get a motion
    // effect, and battery saver / static goldens must stay inert. The field
    // is a pure observer: it never consumes a change, and as the lowest
    // sibling it only sees touches nothing above claimed — buttons, banners,
    // and the chassis still win.
    Canvas(
        modifier
            .pointerInput(clockRuns, density, touchOverride) {
                if (!clockRuns || touchOverride != null) return@pointerInput
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    interacting.value = true
                    try {
                        // Grid units are dp — the warp's (and iOS's) space.
                        touch.press(
                            down.position.x / density.toDouble(),
                            down.position.y / density.toDouble(),
                            nowSeconds(),
                        )
                        while (true) {
                            val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                            if (!change.pressed) break
                            touch.move(
                                change.position.x / density.toDouble(),
                                change.position.y / density.toDouble(),
                            )
                        }
                    } finally {
                        // finally, so a cancelled gesture (scrim, system) still
                        // releases the lens and drops back to the ambient rate.
                        interacting.value = false
                        touch.release(nowSeconds())
                    }
                }
            }
            .clearAndSetSemantics {
                testTag = UiTestTags.OnboardingAsciiField
                vaultTarget?.let { this[AsciiFieldVaultTargetKey] = it }
            },
    ) {
        val t = (staticTime ?: timeState.floatValue).toDouble()
        val now = nowSeconds()
        touch.advance(now)
        val warpK = touch.currentK(now)
        drawIntoCanvas { canvas ->
            renderer.draw(
                canvas.nativeCanvas, size.width, size.height, t,
                touch.x, touch.y, warpK, erosion(), topCullDp(),
                vaultMix(), vaultCenterYDp,
            )
        }
    }
}

/** Published by the onboarding backdrop so the layout compose test can assert
 * each step's resting material without reaching into animation internals. */
internal val AsciiFieldVaultTargetKey = SemanticsPropertyKey<Float>("AsciiFieldVaultTarget")

/** Wall-clock seconds for the warp envelope — monotonic, arbitrary epoch;
 * only differences are ever used. */
private fun nowSeconds(): Double = System.nanoTime() / 1e9

/**
 * Paints, glyph metrics, and reusable buckets — everything the frame loop
 * must not allocate. One cached [Paint] per level so the draw sets paint
 * state 5 times per frame, not ~700: the trig is not the bottleneck;
 * unbatched draw-state changes would be.
 */
internal class AsciiFieldRenderer(
    ink: Color,
    dark: Boolean,
    private val density: Float,
    forceSynthesizedPeak: Boolean = false,
) {
    /** The zinc ramp converted to opacities on semantic ink (the design
     * system allows no custom colors). Deliberately asymmetric between
     * schemes: the site mirrors its hex array, which lands on different
     * perceived alphas against black paper vs white paper — using one column
     * for both would flatten dark mode's peaks and overweight its dots. */
    private val alphas: FloatArray =
        if (dark) floatArrayOf(0.25f, 0.32f, 0.44f, 0.63f, 0.83f)
        else floatArrayOf(0.17f, 0.37f, 0.56f, 0.68f, 0.75f)

    private val paints: Array<Paint> = Array(AsciiFieldTerrain.LEVELS) { level ->
        Paint().apply {
            isAntiAlias = true
            // dp-scaled, deliberately NOT fontScale-scaled (§ terrain is
            // texture, not text).
            textSize = AsciiFieldTerrain.FONT_SIZE_DP * density
            typeface = Typeface.MONOSPACE
            textAlign = Paint.Align.CENTER
            color = ink.copy(alpha = alphas[level]).toArgb()
        }
    }

    /** The ramp alphas as the paints were built with them, so an erosion of 0
     * restores the exact byte the goldens were captured against rather than a
     * recomputed one. */
    private val baseAlpha: IntArray = IntArray(AsciiFieldTerrain.LEVELS) { paints[it].alpha }

    /** Probed once: draw ₿ directly when the platform mono face carries
     * U+20BF (`Paint.hasGlyph`, real coverage — not the web's advance-width
     * heuristic); otherwise reproduce the web's synthesis: the font's own B
     * plus the official symbol's two vertical strokes, anchored to the B's
     * measured ink bounds. */
    val peakIsNative: Boolean = !forceSynthesizedPeak && paints[0].hasGlyph("₿")
    private val peakGlyph: String = if (peakIsNative) "₿" else "B"
    private val peakInkBounds = Rect().also {
        if (!peakIsNative) paints[AsciiFieldTerrain.PEAK_LEVEL].getTextBounds("B", 0, 1, it)
    }
    private val strokeW = 1f * density
    private val strokeLen = 2f * density
    private val strokeDX = 1.25f * density

    /** Vertical centering: offset from a cell's center to the text baseline,
     * the Canvas-2D `textBaseline = "middle"` equivalent. */
    private val baselineOffset: Float = paints[0].fontMetrics.let { -(it.ascent + it.descent) / 2f }

    /** Interleaved (px, py) cell centers per level, reused every frame —
     * zero per-frame allocation once warm. */
    private val buckets = Array(AsciiFieldTerrain.LEVELS) { FloatArrayBucket() }

    fun draw(
        canvas: android.graphics.Canvas,
        widthPx: Float,
        heightPx: Float,
        t: Double,
        touchX: Double = 0.0,
        touchY: Double = 0.0,
        warpK: Double = 0.0,
        erosion: Double = 0.0,
        topCullDp: Float = 0f,
        vaultMix: Double = 0.0,
        vaultCenterYDp: Float = 0f,
    ) {
        val cellWPx = (AsciiFieldTerrain.CELL_W * density).toFloat()
        val cellHPx = (AsciiFieldTerrain.CELL_H * density).toFloat()
        val cols = ceil(widthPx / cellWPx).toInt() + 1
        val rows = ceil(heightPx / cellHPx).toInt() + 1
        val startRow = min(rows, AsciiFieldLayout.cullStartRow(topCullDp))
        val vaultCenterX = widthPx / density / 2.0
        val vaultCenterY = vaultCenterYDp.toDouble()
        val vaultReachSquared = AsciiFieldVault.EXTENT_RADIUS * AsciiFieldVault.EXTENT_RADIUS

        for (bucket in buckets) bucket.clear()
        for (row in startRow until rows) {
            val sy = (row + 0.5) * AsciiFieldTerrain.TERRAIN_SCALE
            val py = row * cellHPx + cellHPx / 2f
            // Cell center on the dp grid — the warp's (and iOS's) space, so
            // both ports feed identical numbers into the shared math.
            val cyDp = (row + 0.5) * AsciiFieldTerrain.CELL_H
            for (col in 0 until cols) {
                val cxDp = (col + 0.5) * AsciiFieldTerrain.CELL_W
                var sampleX = (col + 0.5) * AsciiFieldTerrain.TERRAIN_SCALE
                var sampleY = sy
                // The vault samples on the dp grid; the warp displaces its
                // sampling exactly as it displaces the terrain's.
                var warpedXDp = cxDp
                var warpedYDp = cyDp
                if (warpK > 0) {
                    // Samples are displaced *toward* the finger: the inverse
                    // mapping moves the visible terrain away from it — a
                    // clearing with a compressed contour ring at the rim.
                    // Displacing away would read as a magnifier pulling
                    // contours in. The direction is rotated by the swirl, so
                    // the terrain flows around the finger as it flees. Only
                    // sampling warps; glyph positions (and the currency hash
                    // keyed on them) never move.
                    val dx = cxDp - touchX
                    val dy = cyDp - touchY
                    val d = sqrt(dx * dx + dy * dy)
                    val f = AsciiFieldWarp.displacement(d, warpK)
                    if (f > 0) {
                        val theta = AsciiFieldWarp.swirlAngle(f)
                        val cosT = cos(theta)
                        val sinT = sin(theta)
                        val inv = f / d
                        warpedXDp = cxDp - (dx * cosT - dy * sinT) * inv
                        warpedYDp = cyDp - (dx * sinT + dy * cosT) * inv
                        sampleX = warpedXDp /
                            AsciiFieldTerrain.CELL_W * AsciiFieldTerrain.TERRAIN_SCALE
                        sampleY = warpedYDp /
                            AsciiFieldTerrain.CELL_H * AsciiFieldTerrain.TERRAIN_SCALE
                    }
                }
                val level: Int
                if (vaultMix <= 0.0) {
                    level = AsciiFieldTerrain.displayLevel(
                        AsciiFieldTerrain.brightness(sampleX, sampleY, t),
                    )
                } else if (vaultMix >= 1.0) {
                    // Settled vault: outside its reach the field is the
                    // living ink alone — always below the first threshold —
                    // so the cell is skipped before any trig runs. Restore's
                    // steady state costs roughly the door's bounding circle.
                    val dx = warpedXDp - vaultCenterX
                    val dy = warpedYDp - vaultCenterY
                    if (dx * dx + dy * dy > vaultReachSquared) continue
                    level = AsciiFieldTerrain.displayLevel(
                        AsciiFieldVault.brightness(warpedXDp, warpedYDp, vaultCenterX, vaultCenterY, t),
                    )
                } else {
                    // Mid-morph: one brightness field lerping into the other,
                    // per cell — the glyphs never crossfade, the landscape
                    // deforms.
                    val terrain = AsciiFieldTerrain.brightness(sampleX, sampleY, t).toDouble()
                    val vault =
                        AsciiFieldVault.brightness(warpedXDp, warpedYDp, vaultCenterX, vaultCenterY, t)
                    level = AsciiFieldTerrain.displayLevel(terrain + (vault - terrain) * vaultMix)
                }
                if (level < 0) continue
                buckets[level].add(col * cellWPx + cellWPx / 2f, py)
            }
        }

        for (level in 0 until AsciiFieldTerrain.LEVELS) {
            val bucket = buckets[level]
            if (bucket.size == 0) continue
            val paint = paints[level]
            // Per-level opacity is one paint mutation per bucket — the
            // batching that makes the field cheap is exactly what lets it
            // erode by material.
            if (erosion > 0.0) {
                val alpha = AsciiFieldTerrain.erosionAlpha(level, erosion)
                if (alpha <= 0.0) continue
                paint.alpha = (baseAlpha[level] * alpha).roundToInt()
            } else {
                paint.alpha = baseAlpha[level]
            }
            val isPeak = level >= AsciiFieldTerrain.PEAK_LEVEL
            val isCurrency = level == AsciiFieldTerrain.CURRENCY_LEVEL
            var i = 0
            while (i < bucket.size) {
                val px = bucket.values[i]
                val py = bucket.values[i + 1]
                i += 2
                val glyph = when {
                    isPeak -> peakGlyph
                    // The hash runs on the dp grid so its distribution is
                    // density-independent and matches the fixture.
                    isCurrency -> AsciiFieldTerrain.CURRENCY_GLYPHS[
                        AsciiFieldTerrain.currencyGlyphIndex(
                            (px / density).toDouble(),
                            (py / density).toDouble(),
                        ),
                    ]
                    else -> AsciiFieldTerrain.LEVEL_GLYPH[level]
                }
                val baselineY = py + baselineOffset
                canvas.drawText(glyph, px, baselineY, paint)
                if (isPeak && !peakIsNative) {
                    // The synthesized ₿'s four stroke stubs: two verticals
                    // piercing the B, ±DX from center, LEN beyond its ink.
                    val inkTop = baselineY + peakInkBounds.top
                    val inkBottom = baselineY + peakInkBounds.bottom
                    val xl = px - strokeDX - strokeW / 2f
                    val xr = px + strokeDX - strokeW / 2f
                    canvas.drawRect(xl, inkTop - strokeLen, xl + strokeW, inkTop, paint)
                    canvas.drawRect(xr, inkTop - strokeLen, xr + strokeW, inkTop, paint)
                    canvas.drawRect(xl, inkBottom, xl + strokeW, inkBottom + strokeLen, paint)
                    canvas.drawRect(xr, inkBottom, xr + strokeW, inkBottom + strokeLen, paint)
                }
            }
        }
    }

    /** Minimal growable float pair list, so the frame loop never boxes or
     * reallocates once capacity is warm. */
    internal class FloatArrayBucket {
        var values = FloatArray(256)
            private set
        var size = 0
            private set

        fun add(x: Float, y: Float) {
            if (size + 2 > values.size) values = values.copyOf(values.size * 2)
            values[size] = x
            values[size + 1] = y
            size += 2
        }

        fun clear() {
            size = 0
        }
    }
}
