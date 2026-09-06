package com.cashu.me.ui.components

import android.content.res.Configuration
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withMonoDigits

// Inspector leading icon stays at 18dp (a touch smaller than the 20dp body icon size)
// so the inspector reads as denser metadata, not list-row chrome.
private val InspectorLeadingIconSize = 18.dp
private val InspectorEditHintSize = 16.dp

/**
 * Two-column metadata row used inside Cashu Request / Transaction Detail inspector
 * groups. Optional leading icon, optional pencil affordance for editable rows
 * (which trigger a sub-sheet on tap), optional quiet trailing affordance for
 * other tappable rows (e.g. tap-to-copy: ContentCopy → green Check).
 *
 * @param loading skeleton fill-in (iOS `.redacted(.placeholder)` on confirm fee
 *   rows): while true a quiet placeholder bar holds the value slot, then the
 *   real value crossfades in place when it lands.
 * @param secondaryValue optional caption beneath the value (iOS mint detail's
 *   fiat conversion under the sat balance), always quiet onSurfaceVariant.
 */
@Composable
fun InspectorRow(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    leadingIcon: ImageVector? = null,
    editable: Boolean = false,
    onClick: (() -> Unit)? = null,
    trailingIcon: ImageVector? = null,
    trailingIconTint: Color? = null,
    valueMonospaced: Boolean = false,
    valueColor: Color? = null,
    secondaryValue: String? = null,
    loading: Boolean = false,
) {
    val rowMod = if (onClick != null) {
        modifier.fillMaxWidth().clickable(onClick = onClick)
    } else {
        modifier.fillMaxWidth()
    }
    Row(
        modifier = rowMod.padding(
            horizontal = CashuTheme.spacing.comfortable,
            vertical = CashuTheme.spacing.default,
        ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        if (leadingIcon != null) {
            Icon(
                imageVector = leadingIcon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(InspectorLeadingIconSize),
            )
        }
        Text(
            text = label,
            // bodyLarge, not bodyMedium: every neighboring row vocabulary
            // (settings rows, MintSelectorRow, the flow rows) reads at 16sp,
            // and 14sp here made payment facts look like fine print.
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        // Value fills the remaining width and right-aligns its text so it sits
        // flush against the trailing edge, matching iOS (HStack + Spacer).
        Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
            SkeletonValue(loading = loading) {
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        text = value,
                        style = if (valueMonospaced) {
                            MaterialTheme.typography.bodyLarge.withMonoDigits()
                        } else MaterialTheme.typography.bodyLarge,
                        color = valueColor ?: MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        overflow = TextOverflow.MiddleEllipsis,
                        textAlign = TextAlign.End,
                    )
                    if (secondaryValue != null) {
                        Text(
                            text = secondaryValue,
                            style = if (valueMonospaced) {
                                MaterialTheme.typography.bodyMedium.withMonoDigits()
                            } else MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.MiddleEllipsis,
                            textAlign = TextAlign.End,
                        )
                    }
                }
            }
        }
        if (editable) {
            Icon(
                imageVector = Icons.Outlined.Edit,
                contentDescription = "Edit $label",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(InspectorEditHintSize),
            )
        } else if (trailingIcon != null) {
            Icon(
                imageVector = trailingIcon,
                contentDescription = null,
                tint = trailingIconTint ?: MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(InspectorEditHintSize),
            )
        }
    }
}


/** Prose belongs to the inspector, with a native reader for longer descriptions. */
@Composable
fun DescriptionDetailRow(description: String, label: String = "Description") {
    var overflowing by remember(description) { mutableStateOf(false) }
    var showFullDescription by remember(description) { mutableStateOf(false) }
    val configuration = LocalConfiguration.current
    val previewLines = if (LocalCompactPaymentDetails.current || configuration.orientation == Configuration.ORIENTATION_LANDSCAPE ||
        configuration.fontScale > 1.3f) 1 else 3

    Column(
        modifier = Modifier.fillMaxWidth().padding(
            horizontal = CashuTheme.spacing.comfortable,
            vertical = CashuTheme.spacing.default,
        ),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(label, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (overflowing) {
                TextButton(onClick = { showFullDescription = true }) { Text("Read more") }
            }
        }
        SelectionContainer {
            Text(
                text = description,
                style = MaterialTheme.typography.bodyLarge,
                maxLines = previewLines,
                overflow = TextOverflow.Ellipsis,
                onTextLayout = { overflowing = it.hasVisualOverflow },
                modifier = Modifier.testTag("payment-description-preview"),
            )
        }
    }
    if (showFullDescription) {
        AlertDialog(
            onDismissRequest = { showFullDescription = false },
            title = { Text(label) },
            text = {
                SelectionContainer {
                    Text(description, modifier = Modifier.verticalScroll(rememberScrollState()))
                }
            },
            confirmButton = {
                TextButton(onClick = { showFullDescription = false }) { Text("Done") }
            },
        )
    }
}
