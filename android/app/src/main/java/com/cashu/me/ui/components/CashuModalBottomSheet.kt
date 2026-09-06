package com.cashu.me.ui.components

import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.SheetState
import androidx.compose.material3.SheetValue
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.graphics.Color

/** Native sheet gestures and layout, with spatial motion for dismissal. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun CashuModalBottomSheet(
    onDismissRequest: () -> Unit,
    sheetState: SheetState = rememberBottomSheetState(
        initialValue = SheetValue.Hidden,
        enabledValues = setOf(SheetValue.Hidden, SheetValue.Expanded),
    ),
    containerColor: Color = BottomSheetDefaults.ContainerColor,
    sheetGesturesEnabled: Boolean = true,
    onBackdropVisibilityChanged: (Boolean) -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    val backdropVisibilityChanged by rememberUpdatedState(onBackdropVisibilityChanged)
    LaunchedEffect(sheetState) {
        var hasBeenVisible = false
        snapshotFlow { sheetState.targetValue }.collect { target ->
            if (target != SheetValue.Hidden) {
                hasBeenVisible = true
                backdropVisibilityChanged(true)
            } else if (hasBeenVisible) {
                // Release depth when dismissal starts, including back and swipes.
                // A cancelled dismissal restores it when the sheet targets visible again.
                backdropVisibilityChanged(false)
            }
        }
    }
    val baseMotion = MaterialTheme.motionScheme
    val sheetMotion = remember(baseMotion) { SheetDismissMotionScheme(baseMotion) }
    WithMotionScheme(sheetMotion) {
        ModalBottomSheet(
            onDismissRequest = onDismissRequest,
            sheetState = sheetState,
            containerColor = containerColor,
            sheetGesturesEnabled = sheetGesturesEnabled,
        ) {
            val columnScope = this
            // Buttons and content transitions retain the normal effects springs.
            WithMotionScheme(baseMotion) { columnScope.content() }
        }
    }
}

/**
 * Keep the sheet mounted until hide completes before selecting or navigating.
 * The first tap wins; cancellation never runs an action on an unfinished dismissal.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun rememberSheetDismissAction(sheetState: SheetState): SheetDismissAction {
    val action = remember(sheetState) { SheetDismissAction() }
    val pending = action.pending
    // Start after composition applies the disabled gesture state. Starting hide
    // inside onClick races the native draggable's cancellation when it is disabled.
    LaunchedEffect(sheetState, pending) {
        if (pending != null) {
            try {
                sheetState.hide()
                if (!sheetState.isVisible) pending()
            } finally {
                action.pending = null
            }
        }
    }
    return action
}

@Stable
class SheetDismissAction internal constructor() {
    internal var pending by mutableStateOf<(() -> Unit)?>(null)
    val isDismissing: Boolean get() = pending != null

    operator fun invoke(afterDismiss: () -> Unit) {
        if (!isDismissing) pending = afterDismiss
    }
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun WithMotionScheme(scheme: MotionScheme, content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = MaterialTheme.colorScheme,
        motionScheme = scheme,
        shapes = MaterialTheme.shapes,
        typography = MaterialTheme.typography,
        content = content,
    )
}

/**
 * Material3 1.5.0-alpha23 uses fastEffectsSpec for hideMotionSpec in BottomSheet.kt.
 * That alpha spring makes a full-height translation appear to snap away. Reuse
 * the spatial dismissal already established by the wallet's payment sheets.
 * Remove this override when Material3 uses a spatial spec for sheet dismissal.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
private class SheetDismissMotionScheme(private val base: MotionScheme) : MotionScheme by base {
    override fun <T> fastEffectsSpec(): FiniteAnimationSpec<T> = base.slowSpatialSpec()
}
