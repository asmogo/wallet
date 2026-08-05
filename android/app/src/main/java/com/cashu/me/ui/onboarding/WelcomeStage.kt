package com.cashu.me.ui.onboarding

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import com.cashu.me.ui.theme.rememberReducedMotion

/**
 * The welcome stage's "note becomes cash" piece (onboarding-restyle-brief §4).
 *
 * A minimal geometric construction in pure ink: a thin-stroke banknote outline
 * slowly closes into an ecash-token circle, and two MintAvatar-sized companion
 * circles resolve beside it — a note becoming digital cash. No gradient, no
 * illustration, no fill, no shadow; theme ink strokes only, so it reads as
 * restrained after the tenth launch.
 *
 * Self-playing on one autoreversing infinite transition (~3.2s each way),
 * with every animated value read inside `drawBehind` — the loop costs zero
 * recompositions, so a cold launch's first frame can't stutter. Reduce Motion
 * (and the [quiet] variant on the restore-method chooser) renders the composed
 * token-cluster end state, static but intentional. Decorative only — cleared
 * from the semantics tree.
 */
@Composable
internal fun WelcomeStagePiece(
    modifier: Modifier = Modifier,
    quiet: Boolean = false,
) {
    val reducedMotion = rememberReducedMotion()
    val animates = !quiet && !reducedMotion

    val morph: State<Float> = if (animates) {
        rememberInfiniteTransition(label = "welcome-note-token").animateFloat(
            initialValue = 0f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(
                animation = tween(durationMillis = 3200, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "morph",
        )
    } else {
        // Non-animating presentations hold the resolved end state.
        remember { mutableFloatStateOf(1f) }
    }

    val strokeColor = MaterialTheme.colorScheme.onSurfaceVariant
    val baseAlpha = if (quiet) 0.5f else 1f

    Spacer(
        modifier = modifier
            .fillMaxSize()
            .clearAndSetSemantics { }
            .drawBehind {
                val fraction = morph.value
                val stroke = Stroke(width = 1.5.dp.toPx())

                // The note is a ~1.6:1 banknote outline; the token keeps its
                // height as diameter.
                val noteWidth = 180.dp.toPx()
                val noteHeight = 112.dp.toPx()
                val tokenDiameter = 112.dp.toPx()
                val cornerStart = 14.dp.toPx()

                val width = noteWidth + (tokenDiameter - noteWidth) * fraction
                val height = noteHeight + (tokenDiameter - noteHeight) * fraction
                val corner = cornerStart + (tokenDiameter / 2 - cornerStart) * fraction

                drawRoundRect(
                    color = strokeColor,
                    topLeft = Offset(center.x - width / 2, center.y - height / 2),
                    size = Size(width, height),
                    cornerRadius = CornerRadius(corner),
                    style = stroke,
                    alpha = baseAlpha,
                )

                // Companions echo MintAvatar's 36dp circle geometry, resolving
                // from 92% scale as the note tokenizes (never from zero).
                val companionRadius = 18.dp.toPx() * (0.92f + 0.08f * fraction)
                drawCircle(
                    color = strokeColor,
                    radius = companionRadius,
                    center = center + Offset(-86.dp.toPx(), 46.dp.toPx()),
                    style = stroke,
                    alpha = baseAlpha * 0.7f * fraction,
                )
                drawCircle(
                    color = strokeColor,
                    radius = companionRadius,
                    center = center + Offset(88.dp.toPx(), -52.dp.toPx()),
                    style = stroke,
                    alpha = baseAlpha * 0.7f * fraction,
                )
            },
    )
}
