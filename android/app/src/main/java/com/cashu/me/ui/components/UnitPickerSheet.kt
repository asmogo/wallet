package com.cashu.me.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.cashu.me.Core.Protocols.CurrencyRegistry
import com.cashu.me.ui.theme.CashuTheme

/**
 * Ecash-unit chooser for multi-unit mints (Send / Receive Lightning), the
 * transient attribute-editor sibling of [MintPickerSheet]. Dismisses on
 * selection; the parent's context never leaves the screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UnitPickerSheet(
    units: List<String>,
    selectedUnit: String,
    onSelect: (String) -> Unit,
    onDismiss: () -> Unit,
    title: String = "Choose unit",
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = CashuTheme.colors.compactSheetContainer,
    ) {
        CompactSheetContent {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = CashuTheme.spacing.comfortable)
                    .navigationBarsPadding(),
            ) {
                FlowSheetTitle(title = title)
                units.forEach { unit ->
                    val code = unit.uppercase()
                    val displayName = CurrencyRegistry.currencyForMintUnit(unit).displayName
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onSelect(unit) }
                            .padding(
                                horizontal = CashuTheme.spacing.snug,
                                vertical = CashuTheme.spacing.default,
                            ),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(code, style = MaterialTheme.typography.bodyLarge)
                            if (!displayName.equals(code, ignoreCase = true)) {
                                Text(
                                    displayName,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                )
                            }
                        }
                        if (unit == selectedUnit) {
                            Icon(
                                imageVector = Icons.Filled.Check,
                                contentDescription = "Selected",
                                tint = MaterialTheme.colorScheme.onSurface,
                                modifier = Modifier.size(CashuTheme.spacing.loose),
                            )
                        }
                    }
                }
                Spacer(Modifier.height(CashuTheme.spacing.snug))
            }
        }
    }
}
