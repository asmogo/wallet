package com.cashu.me.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.cashu.me.ui.theme.CashuTheme

/** Shared native presentation; bodies retain their QR sizing and pinned actions. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivityDetailSheet(
    title: String,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    onShare: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val state = rememberBottomSheetState(
        initialValue = SheetValue.Hidden,
        enabledValues = setOf(SheetValue.Hidden, SheetValue.Expanded),
    )
    ModalBottomSheet(
        onDismissRequest = onDismissRequest,
        sheetState = state,
        containerColor = CashuTheme.colors.compactSheetContainer,
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
