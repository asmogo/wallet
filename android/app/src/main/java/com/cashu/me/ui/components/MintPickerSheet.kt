package com.cashu.me.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.AllInclusive
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cashu.me.Core.AmountFormatter
import com.cashu.me.Models.MintInfo
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withMonoDigits

// Matches iOS CashuRequestMintPickerSheet / MintSelectorSheet: 40pt avatar.
private val AvatarSize = 40.dp
// Keep the picker stable as mints are added: this fits its title and roughly
// four selection rows. The list below owns any overflow scrolling.
private val MintPickerSheetHeight = 360.dp

/**
 * Mint chooser bottom sheet — mirrors iOS `MintSelectorSheet` /
 * `CashuRequestMintPickerSheet`: avatar + name + balance per row, optional
 * "Any mint" entry, checkmark on the active selection.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MintPickerSheet(
    mints: List<MintInfo>,
    activeMintUrl: String?,
    onSelect: (MintInfo?) -> Unit,
    onDismiss: () -> Unit,
    title: String = "Choose mint",
    allowAnyMint: Boolean = false,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val formatter = remember { AmountFormatter() }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .height(MintPickerSheetHeight)
                .padding(horizontal = CashuTheme.spacing.comfortable)
                .navigationBarsPadding(),
        ) {
            FlowSheetTitle(title = title)
            // Keep mint identities crisp at rest. The header already supplies
            // the breathing room above this list; an always-on fade only made
            // the selected row look washed out.
            LazyColumn(modifier = Modifier.weight(1f)) {
                if (allowAnyMint) {
                    item(key = "any-mint") {
                        MintPickerAnyRow(
                            selected = activeMintUrl == null,
                            onClick = { onSelect(null) },
                        )
                    }
                }
                items(mints, key = { it.url }) { mint ->
                    MintPickerMintRow(
                        mint = mint,
                        balanceText = formatter.formatSats(mint.balance),
                        selected = mint.url == activeMintUrl,
                        onClick = { onSelect(mint) },
                    )
                }
            }
            Spacer(Modifier.height(CashuTheme.spacing.default))
        }
    }
}

@Composable
private fun MintPickerAnyRow(
    selected: Boolean,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(
                horizontal = CashuTheme.spacing.snug,
                vertical = CashuTheme.spacing.default,
            ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        // iOS: quaternary circle + infinity glyph.
        Box(
            modifier = Modifier
                .size(AvatarSize)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.surfaceContainerHighest),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Outlined.AllInclusive,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(CashuTheme.spacing.loose),
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "Any mint",
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
            )
            Text(
                text = "Sender chooses the mint",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (selected) {
            SelectedCheck()
        }
    }
}

@Composable
private fun MintPickerMintRow(
    mint: MintInfo,
    balanceText: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(
                horizontal = CashuTheme.spacing.snug,
                vertical = CashuTheme.spacing.default,
            ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        MintAvatar(mint = mint, size = AvatarSize)
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = mint.name,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = balanceText,
                style = MaterialTheme.typography.bodySmall.withMonoDigits(),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
            )
        }
        if (selected) {
            SelectedCheck()
        }
    }
}

@Composable
private fun SelectedCheck() {
    Icon(
        imageVector = Icons.Filled.Check,
        contentDescription = "Selected",
        tint = MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.size(CashuTheme.spacing.loose),
    )
}
