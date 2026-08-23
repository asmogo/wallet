package com.cashu.me.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import java.util.UUID

data class ConfirmationToastMessage(
    val id: String = UUID.randomUUID().toString(),
    val text: String,
)

/** One-at-a-time confirmation channel. A new action replaces the current toast. */
@Stable
class ConfirmationToastController {
    var message by mutableStateOf<ConfirmationToastMessage?>(null)
        private set

    fun show(text: String) {
        message = ConfirmationToastMessage(text = text)
    }

    fun dismiss(id: String) {
        if (message?.id == id) message = null
    }
}

val LocalConfirmationToastController = staticCompositionLocalOf<ConfirmationToastController?> {
    null
}

/**
 * Quiet top-center feedback for completed actions. It intentionally has no icon
 * or bounce: the message is the only confirmation and copy affordances stay put.
 */
@Composable
fun ConfirmationToastHost(
    controller: ConfirmationToastController,
    modifier: Modifier = Modifier,
    respectStatusBar: Boolean = true,
) {
    val message = controller.message

    LaunchedEffect(message?.id) {
        val current = message ?: return@LaunchedEffect
        delay(2_200)
        controller.dismiss(current.id)
    }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .then(if (respectStatusBar) Modifier.statusBarsPadding() else Modifier)
            .padding(horizontal = 24.dp, vertical = 8.dp),
        contentAlignment = Alignment.TopCenter,
    ) {
        AnimatedVisibility(
            visible = message != null,
            enter = fadeIn(tween(durationMillis = 150)) +
                slideInVertically(
                    animationSpec = tween(durationMillis = 240, easing = FastOutSlowInEasing),
                    initialOffsetY = { -it },
                ),
            exit = fadeOut(tween(durationMillis = 130)),
        ) {
            message?.let { current ->
                Surface(
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    contentColor = MaterialTheme.colorScheme.onSurface,
                    tonalElevation = 6.dp,
                    shadowElevation = 8.dp,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                    modifier = Modifier.semantics {
                        liveRegion = LiveRegionMode.Polite
                    },
                ) {
                    Text(
                        text = current.text,
                        style = MaterialTheme.typography.bodyMedium.copy(
                            fontWeight = FontWeight.SemiBold,
                        ),
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
                    )
                }
            }
        }
    }
}
