package com.cashu.me.ui.restore

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import com.cashu.me.ui.theme.rememberReducedMotion

/** Shared by onboarding and Settings restore, with no delayed or queued values. */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
internal fun <T> RestoreProgressTransition(
    value: T,
    direction: (T, T) -> Int = { _, _ -> 0 },
    reducedMotion: Boolean = rememberReducedMotion(),
    content: @Composable (T) -> Unit,
) {
    if (reducedMotion || LocalInspectionMode.current) {
        content(value)
        return
    }
    val enter = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
    val exit = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
    val spatial = MaterialTheme.motionScheme.defaultSpatialSpec<Float>()
    val slide = MaterialTheme.motionScheme.defaultSpatialSpec<IntOffset>()
    val size = MaterialTheme.motionScheme.defaultSpatialSpec<IntSize>()
    AnimatedContent(
        targetState = value,
        contentAlignment = Alignment.CenterEnd,
        transitionSpec = {
            val roll = direction(initialState, targetState)
            val transition = if (roll != 0) {
                (fadeIn(enter) + slideInVertically(slide) { roll * it / 3 })
                    .togetherWith(fadeOut(exit) + slideOutVertically(slide) { -roll * it / 3 })
            } else {
                (fadeIn(enter) + scaleIn(spatial, initialScale = 0.92f))
                    .togetherWith(fadeOut(exit))
            }
            transition.using(SizeTransform(clip = false) { _, _ -> size })
        },
        label = "restore-progress",
    ) { current -> content(current) }
}
