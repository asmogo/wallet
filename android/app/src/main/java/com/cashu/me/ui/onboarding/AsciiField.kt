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
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.ui.Alignment
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.dp
import com.cashu.me.ui.testing.UiTestTags
import com.cashu.me.ui.theme.rememberReducedMotion
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
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
}

/** Band geometry as pure math, so the layout-invariant test can assert it
 * without composing views. Mirrors iOS `AsciiFieldLayout`.
 *
 * The field pins to the window bottom and runs under the chassis. It
 * terminates through its own mask, not through occlusion: the bottom fade
 * begins above the chassis edge and reaches zero a little past it, so the
 * terrain dissolves toward the buttons — a faint sliver continuing behind
 * them — instead of ending on a hard cut at the chassis top. The on-screen
 * glyph positions are a function of window size and the (constant across the
 * welcome/restore pair) chassis height — never of header height, stage
 * content, or current step — which is what lets the terrain hold perfectly
 * still across the Welcome ↔ Restore Wallet swap. */
internal object AsciiFieldLayout {
    /** Web is `clamp(180px, 26vh, 320px)`; scaled slightly for phone-sized
     * viewports. All values dp. */
    const val MIN_BAND = 160f
    const val MAX_BAND = 300f
    const val BAND_FRACTION = 0.26f

    /** Below this the band would be a squashed few-row smear behind
     * accessibility-size copy (or a landscape phone) — draw nothing instead. */
    const val SUPPRESSION_THRESHOLD = 120f

    /** The mask ramps transparent → opaque over this fraction of the visible
     * band (the web masks the top 30% of its fully-visible band; ours also
     * extends under the chassis, so the fraction applies to the visible part). */
    const val MASK_FADE = 0.30f

    /** The bottom fade starts this far (dp) above the chassis edge… */
    const val BOTTOM_FADE_REACH = 48f

    /** …and reaches zero this far past it — just enough that a faint sliver
     * of terrain sits behind the top of the primary button, no deeper. */
    const val BOTTOM_FADE_UNDERLAP = 40f

    data class Resolution(
        /** Height of the band above the chassis — the part the user sees. */
        val visibleBand: Float,
        /** Full layer height: visible band + chassis underlap. */
        val layerHeight: Float,
        /** Where the mask becomes fully opaque, as a fraction of layerHeight. */
        val maskOpaqueFraction: Float,
        /** Where the bottom fade begins (fraction of layerHeight) — above the
         * chassis edge, so the dissolve is already underway when the terrain
         * meets the buttons. */
        val bottomFadeStart: Float,
        /** Where the bottom fade completes (fraction of layerHeight) —
         * slightly past the chassis edge, behind the buttons. */
        val bottomFadeEnd: Float,
    )

    /** [headerClearance] is the vertical room the pair's tallest header
     * (welcome's two-line title + subhead, scaled by the live fontScale)
     * needs. Using the same clearance for both steps of the pair keeps the
     * resolved frame identical across them — the layout-invariant contract. */
    fun resolve(
        windowHeight: Float,
        headerClearance: Float,
        chassisHeight: Float,
    ): Resolution? {
        val band = (BAND_FRACTION * windowHeight).coerceIn(MIN_BAND, MAX_BAND)
        // The empty region between the header block and the chassis. When the
        // heavy display title wraps at large font scales (or the window is a
        // landscape phone), this collapses and the band is suppressed rather
        // than squashed — the band never shrinks to fit.
        val available = windowHeight - headerClearance - chassisHeight
        if (min(band, available) < SUPPRESSION_THRESHOLD) return null
        return resolution(band, chassisHeight)
    }

    /** The suppressed case still needs a stable frame (the backdrop hides
     * rather than unmounts, to keep its wall clock), so it lays out the
     * floor band. */
    fun fallback(chassisHeight: Float): Resolution = resolution(MIN_BAND, chassisHeight)

    private fun resolution(band: Float, chassisHeight: Float): Resolution {
        val layerHeight = band + chassisHeight
        return Resolution(
            visibleBand = band,
            layerHeight = layerHeight,
            maskOpaqueFraction = (band * MASK_FADE) / layerHeight,
            bottomFadeStart = (band - BOTTOM_FADE_REACH) / layerHeight,
            bottomFadeEnd = (band + min(BOTTOM_FADE_UNDERLAP, chassisHeight)) / layerHeight,
        )
    }

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
 * The terrain layer as the onboarding root mounts it: pinned to the bottom of
 * the (inset-padded) window, running under the chassis, masked at the top.
 *
 * Mounted once at the root rather than inside the stages. Welcome and Restore
 * Wallet are *adjacent* steps; mounted per-stage the field would unmount and
 * materialize-blur on that swap, and the two screens would read as two
 * separate wallpapers that happen to match. Hoisted, the terrain keeps
 * drifting and only the text above it changes — one continuous space.
 * Visibility is opacity only: leaving the pair fades on the same motion-scheme
 * specs the stage swap itself uses (the clock pauses); returning fades back in
 * and resumes from wall-clock.
 *
 * Suppression (tight vertical space) hides rather than removes the field: its
 * identity — and with it the wall clock — must survive, or a pass through a
 * suppressed layout would replay from t=0.
 *
 * @param chassisHeightPx Measured height of the chassis this layer runs
 *   under. Constant across the welcome/restore pair (two capsules, no
 *   accessory), so the terrain cannot shift on that swap.
 */
@Composable
internal fun OnboardingAsciiBackdrop(
    visible: Boolean,
    conceptSheetOpen: Boolean,
    chassisHeightPx: Int,
    modifier: Modifier = Modifier,
    staticTime: Float? = null,
    forceSynthesizedPeak: Boolean = false,
) {
    val density = LocalDensity.current
    val reducedMotion = rememberReducedMotion()

    BoxWithConstraints(modifier) {
        val windowHeightDp = with(density) { constraints.maxHeight.toDp().value }
        val chassisDp = with(density) { chassisHeightPx.toDp().value }
        val resolved = AsciiFieldLayout.resolve(
            windowHeight = windowHeightDp,
            headerClearance = AsciiFieldLayout.headerClearanceDp(density.fontScale),
            chassisHeight = chassisDp,
        )
        val layout = resolved ?: AsciiFieldLayout.fallback(chassisHeight = chassisDp)
        val shouldShow = visible && resolved != null

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
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(layout.layerHeight.dp)
                .graphicsLayer {
                    alpha = opacity.value
                    // The top mask needs the glyphs flattened into one layer
                    // first, or DstIn would knock through to the ground.
                    compositingStrategy = CompositingStrategy.Offscreen
                }
                // Transparent → opaque over the visible band's top ~30%, like
                // the web band's mask-image; then opaque → transparent across
                // the chassis edge, so the terrain dissolves toward the
                // buttons — a faint sliver continuing behind them — rather
                // than ending on a hard cut at the chassis top. Continuous
                // gradients, never stepped, so neither fade bands.
                .drawWithContent {
                    drawContent()
                    drawRect(
                        brush = Brush.verticalGradient(
                            0f to Color.Transparent,
                            layout.maskOpaqueFraction to Color.Black,
                            layout.bottomFadeStart to Color.Black,
                            layout.bottomFadeEnd to Color.Transparent,
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
 */
@Composable
internal fun AsciiField(
    modifier: Modifier = Modifier,
    staticTime: Float? = null,
    active: Boolean = true,
    forceSynthesizedPeak: Boolean = false,
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
    val clockRuns = staticTime == null && !reducedMotion && !powerSave && active

    // Wall-clock zero. Time is always derived from the monotonic clock —
    // never a frame counter — so a pause/resume never rewinds or replays;
    // the terrain simply is where the clock says it is.
    val startNanos = remember { System.nanoTime() }
    val timeState = remember { mutableFloatStateOf(0f) }
    LaunchedEffect(clockRuns) {
        if (clockRuns) {
            // 30fps cap by elapsed time rather than the web's every-2nd-frame
            // skip: alternate frames on a 120 Hz panel would still be 60fps.
            var lastDrawNanos = 0L
            while (true) {
                withFrameNanos { nanos ->
                    if (nanos - lastDrawNanos >= 33_000_000L) {
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
    Canvas(modifier.clearAndSetSemantics { testTag = UiTestTags.OnboardingAsciiField }) {
        val t = (staticTime ?: timeState.floatValue).toDouble()
        drawIntoCanvas { canvas ->
            renderer.draw(canvas.nativeCanvas, size.width, size.height, t)
        }
    }
}

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

    fun draw(canvas: android.graphics.Canvas, widthPx: Float, heightPx: Float, t: Double) {
        val cellWPx = (AsciiFieldTerrain.CELL_W * density).toFloat()
        val cellHPx = (AsciiFieldTerrain.CELL_H * density).toFloat()
        val cols = ceil(widthPx / cellWPx).toInt() + 1
        val rows = ceil(heightPx / cellHPx).toInt() + 1

        for (bucket in buckets) bucket.clear()
        for (row in 0 until rows) {
            val sy = (row + 0.5) * AsciiFieldTerrain.TERRAIN_SCALE
            val py = row * cellHPx + cellHPx / 2f
            for (col in 0 until cols) {
                val level = AsciiFieldTerrain.pickLevel(
                    AsciiFieldTerrain.brightness((col + 0.5) * AsciiFieldTerrain.TERRAIN_SCALE, sy, t),
                )
                if (level < 0) continue
                buckets[level].add(col * cellWPx + cellWPx / 2f, py)
            }
        }

        for (level in 0 until AsciiFieldTerrain.LEVELS) {
            val bucket = buckets[level]
            if (bucket.size == 0) continue
            val paint = paints[level]
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
