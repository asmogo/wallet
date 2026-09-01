package com.cashu.me.ui.components

import android.graphics.Color as AndroidColor
import android.graphics.drawable.ColorDrawable
import android.view.WindowManager
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
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

private const val ToastExitSettleMs = 220L

/**
 * Quiet top-center feedback for completed actions. It intentionally has no icon
 * or bounce: the message is the only confirmation and copy affordances stay put.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun ConfirmationToastHost(
    controller: ConfirmationToastController,
) {
    val message = controller.message
    var displayedMessage by remember { mutableStateOf<ConfirmationToastMessage?>(null) }
    var visible by remember { mutableStateOf(false) }

    LaunchedEffect(message?.id) {
        val current = message
        if (current == null) {
            visible = false
            delay(ToastExitSettleMs)
            displayedMessage = null
            return@LaunchedEffect
        }

        val wasVisible = displayedMessage != null
        displayedMessage = current
        if (!wasVisible) {
            visible = false
            withFrameNanos { }
        }
        visible = true
        delay(2_200)
        visible = false
        delay(ToastExitSettleMs)
        controller.dismiss(current.id)
        displayedMessage = null
    }

    displayedMessage?.let { current ->
        val enterEffects = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
        val enterSpatial = MaterialTheme.motionScheme.defaultSpatialSpec<IntOffset>()
        val exitEffects = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
        Dialog(
            onDismissRequest = {},
            properties = DialogProperties(
                dismissOnBackPress = false,
                dismissOnClickOutside = false,
                usePlatformDefaultWidth = false,
                decorFitsSystemWindows = false,
            ),
        ) {
            val window = (LocalView.current.parent as DialogWindowProvider).window
            DisposableEffect(window) {
                window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                )
                window.setBackgroundDrawable(ColorDrawable(AndroidColor.TRANSPARENT))
                onDispose { }
            }

            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .padding(horizontal = 24.dp, vertical = 8.dp),
                contentAlignment = Alignment.TopCenter,
            ) {
                AnimatedVisibility(
                    visible = visible,
                    enter = fadeIn(enterEffects) +
                        slideInVertically(
                            animationSpec = enterSpatial,
                            initialOffsetY = { -it },
                        ),
                    exit = fadeOut(exitEffects),
                ) {
                    Surface(
                        shape = CircleShape,
                        color = MaterialTheme.colorScheme.surfaceContainerHigh,
                        contentColor = MaterialTheme.colorScheme.onSurface,
                        tonalElevation = 6.dp,
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
}
