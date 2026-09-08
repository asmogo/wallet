package com.cashu.me.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.CornerSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SheetValue
import androidx.compose.material3.IconButton
import androidx.compose.material3.SheetState
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.cashu.me.ui.theme.CashuTheme

/** Shared native presentation; bodies retain their QR sizing and pinned actions. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivityDetailSheet(
    title: String,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    onShare: (() -> Unit)? = null,
    sheetState: SheetState = rememberBottomSheetState(
        initialValue = SheetValue.Hidden,
        enabledValues = setOf(SheetValue.Hidden, SheetValue.Expanded),
    ),
    onBackdropVisibilityChanged: (Boolean) -> Unit = {},
    sheetGesturesEnabled: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    val compactWidth = LocalConfiguration.current.screenWidthDp < 600
    CashuModalBottomSheet(
        onDismissRequest = onDismissRequest,
        sheetState = sheetState,
        containerColor = CashuTheme.colors.compactSheetContainer,
        onBackdropVisibilityChanged = onBackdropVisibilityChanged,
        sheetGesturesEnabled = sheetGesturesEnabled,
        // Phone receipts attach to both sides and the bottom. Wider windows
        // retain Material's width-limited presentation.
        sheetMaxWidth = if (compactWidth) Dp.Unspecified else BottomSheetDefaults.SheetMaxWidth,
        shape = if (compactWidth) MaterialTheme.shapes.extraLarge.copy(
            bottomStart = CornerSize(0.dp),
            bottomEnd = CornerSize(0.dp),
        ) else BottomSheetDefaults.ExpandedShape,
    ) {
        CompactSheetContent {
            Column(modifier = modifier.fillMaxWidth()) {
                SheetHeader(title = title, actions = {
                    if (onShare != null) {
                        IconButton(onClick = onShare) {
                            ToolbarIcon(imageVector = Icons.Outlined.IosShare, contentDescription = "Share")
                        }
                    }
                })
                content()
            }
        }
    }
}
