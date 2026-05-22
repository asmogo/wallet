package org.cashu.wallet.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
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
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.outlined.CurrencyBitcoin
import androidx.compose.material.icons.outlined.Money
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import org.cashu.wallet.Models.TransactionKind
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.TransactionType
import org.cashu.wallet.Models.WalletTransaction
import org.cashu.wallet.ui.theme.CashuTheme
import org.cashu.wallet.ui.theme.withMonoDigits

data class TransactionRowModel(
    val transaction: WalletTransaction,
    val title: String,
    val timestamp: String,
    val primaryAmount: String,
    val secondaryAmount: String?,
)

@Composable
fun TransactionRow(
    model: TransactionRowModel,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onRefresh: (() -> Unit)? = null,
    isChecking: Boolean = false,
) {
    val tx = model.transaction
    val incoming = tx.type == TransactionType.Incoming
    val amountColor = when (tx.status) {
        TransactionStatus.Pending -> MaterialTheme.colorScheme.onSurfaceVariant
        TransactionStatus.Completed -> CashuTheme.colors.received
        TransactionStatus.Failed -> MaterialTheme.colorScheme.onSurface
    }
    val signPrefix = if (incoming) "+" else "−"
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        MethodIconWithStatusBadge(
            kind = tx.kind,
            status = tx.status,
            incoming = incoming,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = model.title,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = model.timestamp,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        // Pending-refresh affordance per iOS TransactionAmountColumn.
        if (tx.status == TransactionStatus.Pending && onRefresh != null) {
            if (isChecking) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    strokeWidth = 1.5.dp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                IconButton(
                    onClick = onRefresh,
                    modifier = Modifier.size(24.dp),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Sync,
                        contentDescription = "Refresh status",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(16.dp),
                    )
                }
            }
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(
                text = "$signPrefix${model.primaryAmount}",
                style = MaterialTheme.typography.bodyLarge.withMonoDigits(),
                color = amountColor,
            )
            if (model.secondaryAmount != null) {
                Text(
                    text = model.secondaryAmount,
                    style = MaterialTheme.typography.bodySmall.withMonoDigits(),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun MethodIconWithStatusBadge(
    kind: TransactionKind,
    status: TransactionStatus,
    incoming: Boolean,
) {
    Box(modifier = Modifier.size(40.dp)) {
        val methodIcon: ImageVector = when (kind) {
            TransactionKind.Ecash -> Icons.Outlined.Money
            TransactionKind.Lightning -> Icons.Filled.Bolt
            TransactionKind.Onchain -> Icons.Outlined.CurrencyBitcoin
        }
        Box(
            modifier = Modifier
                .size(40.dp)
                .background(
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    shape = CircleShape,
                ),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = methodIcon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.size(20.dp),
            )
        }
        StatusBadge(
            status = status,
            incoming = incoming,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .size(16.dp),
        )
    }
}

@Composable
private fun StatusBadge(
    status: TransactionStatus,
    incoming: Boolean,
    modifier: Modifier = Modifier,
) {
    val targetState = when {
        status == TransactionStatus.Pending -> BadgeState.Pending
        status == TransactionStatus.Failed -> BadgeState.Failed
        incoming -> BadgeState.Incoming
        else -> BadgeState.Outgoing
    }
    val pulseAlpha = if (targetState == BadgeState.Pending) {
        val transition = rememberInfiniteTransition(label = "pending-pulse")
        transition.animateFloat(
            initialValue = 1f,
            targetValue = 0.4f,
            animationSpec = infiniteRepeatable(
                animation = tween(durationMillis = 1100),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "pending-pulse-alpha",
        ).value
    } else 1f
    Box(
        modifier = modifier
            .background(
                color = MaterialTheme.colorScheme.surface,
                shape = CircleShape,
            )
            .alpha(pulseAlpha),
        contentAlignment = Alignment.Center,
    ) {
        AnimatedContent(
            targetState = targetState,
            transitionSpec = { fadeIn(tween(280)) togetherWith fadeOut(tween(280)) },
            label = "status-badge",
        ) { state ->
            val (icon, tint) = when (state) {
                BadgeState.Pending -> Icons.Outlined.Schedule to CashuTheme.colors.pending
                BadgeState.Incoming -> Icons.Filled.ArrowDownward to CashuTheme.colors.received
                BadgeState.Outgoing -> Icons.Filled.ArrowUpward to MaterialTheme.colorScheme.onSurface
                BadgeState.Failed -> Icons.Outlined.Schedule to MaterialTheme.colorScheme.error
            }
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = tint,
                modifier = Modifier.size(14.dp),
            )
        }
    }
}

private enum class BadgeState { Pending, Incoming, Outgoing, Failed }
