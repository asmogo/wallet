package com.cashu.me.ui.components

import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Distance over which content dissolves. iOS holds the same value in
 * `ScrollFadeMetrics.band` — the two fades are meant to be indistinguishable, so
 * this number only ever moves in both places at once.
 */
val ScrollFadeBand: Dp = 24.dp

/**
 * Dissolves scroll content into the chrome at one or both edges, so rows fade
 * out as they approach a pinned header or CTA instead of cutting against it.
 *
 * [top] / [bottom] are the distances from each edge at which the content is
 * still fully clear — pass the measured height of whatever chrome sits there.
 * The [band] above/below that inset is the gradient itself. `null` leaves that
 * edge alone, which is why `0.dp` has to stay meaningful: it means "fade right
 * at the container's own edge", the case where the chrome is a sibling rather
 * than an overlay.
 *
 * One mask with one stop list, never two stacked passes — overlapping masks
 * multiply their alpha and the shared band comes out twice as dark as either
 * edge alone. iOS mirrors this in `View.scrollEdgeFade(top:bottom:band:)`.
 *
 * Apply this *before* the scroll modifier so the layer wraps the scroll clip.
 */
fun Modifier.scrollEdgeFade(
    top: Dp? = null,
    bottom: Dp? = null,
    band: Dp = ScrollFadeBand,
): Modifier = this
    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
    .drawWithCache {
        val brush = Brush.verticalGradient(
            *scrollEdgeFadeStops(
                total = size.height,
                topPx = top?.toPx(),
                bottomPx = bottom?.toPx(),
                bandPx = band.toPx(),
            ),
        )
        onDrawWithContent {
            drawContent()
            drawRect(brush = brush, blendMode = BlendMode.DstIn)
        }
    }

/**
 * Mask stops for [scrollEdgeFade].
 *
 * Locations are forced non-decreasing on the way out. On a short container the
 * two bands can otherwise cross, and [Brush.verticalGradient] requires ascending
 * stops — handed a descending pair it throws rather than clamping.
 */
private fun scrollEdgeFadeStops(
    total: Float,
    topPx: Float?,
    bottomPx: Float?,
    bandPx: Float,
): Array<Pair<Float, Color>> {
    val height = total.coerceAtLeast(1f)
    val stops = mutableListOf<Pair<Float, Color>>()

    if (topPx != null) {
        stops += 0f to Color.Transparent
        stops += (topPx / height) to Color.Transparent
        stops += ((topPx + bandPx) / height) to Color.Black
    } else {
        stops += 0f to Color.Black
    }

    if (bottomPx != null) {
        stops += (1f - (bottomPx + bandPx) / height) to Color.Black
        stops += (1f - bottomPx / height) to Color.Transparent
        stops += 1f to Color.Transparent
    } else {
        stops += 1f to Color.Black
    }

    var highWater = 0f
    return stops.map { (location, color) ->
        highWater = maxOf(highWater, location.coerceIn(0f, 1f))
        highWater to color
    }.toTypedArray()
}
