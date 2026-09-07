package com.cashu.me.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.cashu.me.ui.theme.CashuTheme

/** The shared compact confirmation, also used by Generate new key. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActionConfirmationSheet(
    title: String,
    message: String,
    actionLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    destructive: Boolean = false,
) {
    var submitted by remember { mutableStateOf(false) }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        ActionConfirmationContent(
            title = title,
            message = message,
            actionLabel = actionLabel,
            destructive = destructive,
            enabled = !submitted,
            onConfirm = {
                if (!submitted) {
                    submitted = true
                    onConfirm()
                }
            },
            onDismiss = onDismiss,
        )
    }
}

@Composable
internal fun ActionConfirmationContent(
    title: String,
    message: String,
    actionLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    destructive: Boolean = false,
    enabled: Boolean = true,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .navigationBarsPadding()
            .padding(horizontal = CashuTheme.spacing.comfortable)
            .padding(bottom = CashuTheme.spacing.section),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.section),
    ) {
        Text(
            text = title,
            style = CashuTheme.type.sheetTitle,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().semantics { heading() },
        )
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
        val colors = if (destructive) {
            ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.error,
                contentColor = Color.White,
            )
        } else {
            ButtonDefaults.buttonColors()
        }
        val actionModifier = Modifier.semantics {
            if (destructive) stateDescription = "Destructive action"
        }
        val fontScale = LocalDensity.current.fontScale
        BoxWithConstraints {
            if (maxWidth < 320.dp || fontScale >= 1.3f) {
                Column(verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug)) {
                    PrimaryButton(actionLabel, onConfirm, actionModifier, enabled = enabled, colors = colors)
                    SecondaryButton("Cancel", onDismiss)
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug)) {
                    SecondaryButton("Cancel", onDismiss, Modifier.weight(1f))
                    PrimaryButton(actionLabel, onConfirm, actionModifier.weight(1f), enabled = enabled, colors = colors)
                }
            }
        }
    }
}
