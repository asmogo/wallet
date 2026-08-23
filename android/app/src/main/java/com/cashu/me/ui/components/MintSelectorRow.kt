package com.cashu.me.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cashu.me.Models.MintInfo
import com.cashu.me.ui.theme.CashuTheme

// A quiet row, not a card: 28dp avatar and a compact mint identity. Its
// optional balance line is reserved for Send Ecash, where it explains the
// amount Send Max will use.
//
// The identity needs some air above and below it. A 56dp row keeps the mint
// selector comfortably tappable and prevents the avatar from feeling pressed
// against the rounded container on amount-entry screens.
private val AvatarSize = 28.dp
private val ChevronSize = 18.dp
private val RowMinHeight = 56.dp
private val RowPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)
private val UseMaxPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp)

/**
 * The one mint selector for every value flow, on both platforms: mint identity
 * on the left, an optional "Send Max" chip and the picker chevron on the right.
 * Tapping anywhere except the chip opens the picker.
 *
 * [onPickMint] is null when the wallet holds a single mint — there is nothing to
 * choose between, so the row drops its chevron and stops being a control.
 * [showBalance] opts into the second balance line on amount entry screens,
 * where it makes the selected mint's available amount explicit.
 */
@Composable
fun MintSelectorRow(
    mint: MintInfo,
    balanceText: String?,
    modifier: Modifier = Modifier,
    showBalance: Boolean = false,
    onPickMint: (() -> Unit)? = null,
    onUseMax: (() -> Unit)? = null,
) {
    val isCompactSheet = LocalCompactSheetStyle.current
    val rowColor = if (isCompactSheet) {
        MaterialTheme.colorScheme.surfaceContainerHigh
    } else {
        MaterialTheme.colorScheme.surfaceContainer
    }
    val useMaxColor = if (isCompactSheet) {
        MaterialTheme.colorScheme.surfaceContainerLowest
    } else {
        MaterialTheme.colorScheme.surfaceContainerHighest
    }
    val description = if (balanceText != null) {
        "Mint: ${mint.name}, balance $balanceText"
    } else {
        "Mint: ${mint.name}"
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = RowMinHeight)
            .clip(MaterialTheme.shapes.medium)
            .background(rowColor)
            .then(
                if (onPickMint != null) {
                    Modifier.clickable(role = Role.Button, onClick = onPickMint)
                } else {
                    Modifier
                },
            )
            .semantics(mergeDescendants = true) { contentDescription = description }
            .padding(RowPadding),
    ) {
        MintAvatar(mint = mint, size = AvatarSize)
        Spacer(Modifier.width(CashuTheme.spacing.snug))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = mint.name,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (showBalance && balanceText != null) {
                Text(
                    text = balanceText,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (onUseMax != null) {
            Spacer(Modifier.width(CashuTheme.spacing.snug))
            Text(
                text = "Send Max",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(useMaxColor)
                    .clickable(role = Role.Button, onClick = onUseMax)
                    .semantics { contentDescription = "Send maximum" }
                    .padding(UseMaxPadding),
            )
        }
        if (onPickMint != null) {
            Spacer(Modifier.width(CashuTheme.spacing.snug))
            Icon(
                imageVector = Icons.Outlined.KeyboardArrowDown,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(ChevronSize),
            )
        }
    }
}
