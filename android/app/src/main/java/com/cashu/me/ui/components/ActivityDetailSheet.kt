package com.cashu.me.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.cashu.me.ui.theme.CashuTheme

/** Shared native history inspector: title, optional QR, amount, facts, actions. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivityDetailSheet(
    title: String,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
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
                SheetHeader(title = title)
                Column(
                    modifier = Modifier.fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = CashuTheme.spacing.comfortable)
                        .padding(bottom = CashuTheme.spacing.comfortable),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.section),
                    content = content,
                )
            }
        }
    }
}

/** Visible payment code above the amount and facts, with native Copy/Share actions. */
@Composable
fun ActivityPaymentCode(
    content: String,
    title: String,
    staticOnly: Boolean = true,
    confirmationMessage: String = "Copied payment request",
) {
    BoxWithConstraints(
        modifier = Modifier.fillMaxWidth(),
        contentAlignment = Alignment.Center,
    ) {
        QrCard(
            content = content,
            size = minOf(240.dp, maxWidth - 32.dp),
            staticOnly = staticOnly,
            shareSubject = title,
            confirmationMessage = confirmationMessage,
        )
    }
}
