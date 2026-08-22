package com.cashu.me.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.withMonoDigits

// Leading muted directional arrow on a soft circle. Glyph slightly larger
// than half the 40dp circle for clearer direction without growing the pad.
private val DirectionIconCircle = 40.dp
private val DirectionIconSize = 24.dp

data class TransactionRowModel(
    val transaction: WalletTransaction,
    val title: String,
    val timestamp: String,
    val primaryAmount: String,
    val secondaryAmount: String?,
)

/**
 * Canonical timeline row. Leading muted directional arrow (direction is the
 * arrow's orientation, never colour); kind is named in the title. The amount is
 * the ledger signal: received is green with a plus, sent is primary with no
 * sign, and pending/expired is muted with no sign.
 */
@Composable
fun TransactionRow(
    model: TransactionRowModel,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tx = model.transaction
    val incoming = tx.type == TransactionType.Incoming
    val unsettled = tx.isUnsettled
    val amountColor = when {
        unsettled -> MaterialTheme.colorScheme.onSurfaceVariant
        incoming -> CashuTheme.colors.received
        else -> MaterialTheme.colorScheme.onSurface
    }
    val amountText = if (!unsettled && incoming) "+${model.primaryAmount}" else model.primaryAmount
    val semanticAmount = amountText
    val semanticParts = listOfNotNull(
        model.title,
        if (incoming) "Incoming" else "Outgoing",
        tx.displayStatusText,
        semanticAmount,
        model.secondaryAmount,
        model.timestamp,
    )
    Row(
        modifier = modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = semanticParts.joinToString(", ")
            }
            .clickable(onClick = onClick)
            // Slightly looser than the original 16pt so home Recent + History
            // breathe between rows without going sparse.
            .padding(horizontal = CashuTheme.spacing.comfortable, vertical = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
    ) {
        DirectionIcon(incoming = incoming)
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = model.title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
            )
            Text(
                text = model.timestamp,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(
                text = amountText,
                style = MaterialTheme.typography.bodyLarge.withMonoDigits(),
                fontWeight = FontWeight.Medium,
                color = amountColor,
            )
            if (model.secondaryAmount != null) {
                Text(
                    text = model.secondaryAmount,
                    style = MaterialTheme.typography.bodyMedium.withMonoDigits(),
                    fontWeight = FontWeight.Normal,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/** Always-muted directional arrow on a soft neutral circle (iOS TransactionIcon). */
@Composable
internal fun DirectionIcon(incoming: Boolean) {
    Box(
        modifier = Modifier
            .size(DirectionIconCircle)
            .background(
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                shape = CircleShape,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = if (incoming) Icons.Filled.ArrowDownward else Icons.Filled.ArrowUpward,
            contentDescription = if (incoming) "Incoming" else "Outgoing",
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(DirectionIconSize),
        )
    }
}
