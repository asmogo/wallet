package org.cashu.wallet.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/**
 * In-screen face swap used by Send/Receive flows. Default is a 250ms fade-through
 * to match the iOS sheet cross-fade pattern from UX_SPEC §17.3.
 */
@Composable
fun <T> TwoFaceScreen(
    targetState: T,
    modifier: Modifier = Modifier,
    transitionSpec: () -> ContentTransform = {
        (fadeIn(tween(250)) togetherWith fadeOut(tween(250)))
    },
    label: String = "two-face",
    content: @Composable (T) -> Unit,
) {
    AnimatedContent(
        targetState = targetState,
        modifier = modifier,
        transitionSpec = { transitionSpec() },
        label = label,
        content = { content(it) },
    )
}
