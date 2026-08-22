package com.cashu.me.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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

// A quiet row, not a card: 20dp avatar, one line, 48dp tall. The 64dp block it
// replaces (40dp avatar over a balance line) outweighed both the toolbar above
// it and the amount hero it exists to qualify.
//
// Vertical padding is deliberately absent from the container: the "Send Max"
// chip pads itself out to a real touch target, and container padding would stack
// on top of that and make the row with a chip taller than the rows without one.
private val AvatarSize = 20.dp
private val ChevronSize = 18.dp
private val RowMinHeight = 48.dp
private val RowPadding = PaddingValues(horizontal = 16.dp)
private val UseMaxPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp)

/**
 * The one mint selector for every value flow, on both platforms: mint identity
 * on the left, an optional "Send Max" chip and the picker chevron on the right.
 * Tapping anywhere except the chip opens the picker.
 *
 * [onPickMint] is null when the wallet holds a single mint — there is nothing to
 * choose between, so the row drops its chevron and stops being a control.
 * [balanceText] is deliberately not rendered; it lives in the accessibility
 * label and reappears on screen only in the insufficient-balance notice.
 */
@Composable
fun MintSelectorRow(
    mint: MintInfo,
    balanceText: String?,
    modifier: Modifier = Modifier,
    onPickMint: (() -> Unit)? = null,
    onUseMax: (() -> Unit)? = null,
) {
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
            .background(MaterialTheme.colorScheme.surfaceContainer)
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
        Text(
            text = mint.name,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
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
                    .background(MaterialTheme.colorScheme.surfaceContainerHighest)
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
