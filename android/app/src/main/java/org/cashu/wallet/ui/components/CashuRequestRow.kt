package org.cashu.wallet.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.material.icons.outlined.Money
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.unit.dp
import org.cashu.wallet.Models.CashuRequest
import org.cashu.wallet.ui.theme.CashuTheme
import org.cashu.wallet.ui.theme.withMonoDigits

/**
 * Cashu Request timeline row, paired with [TransactionRow] in History and Home Recent.
 * Mirrors iOS CashuRequestAmountColumn variants — fixed-amount vs any-amount,
 * waiting vs received.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun CashuRequestRow(
    request: CashuRequest,
    timestamp: String,
    primaryAmountText: String?,
    secondaryAmountText: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onLongClick: (() -> Unit)? = null,
) {
    val received = request.receivedPayments.isNotEmpty()
    Row(
        modifier = modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = onClick,
                onLongClick = onLongClick,
            )
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        RequestIconWithStatusBadge(received = received)
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "Cashu Request",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = timestamp,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Column(horizontalAlignment = Alignment.End) {
            if (primaryAmountText != null) {
                Text(
                    text = "+$primaryAmountText",
                    style = MaterialTheme.typography.bodyLarge.withMonoDigits(),
                    color = if (received) CashuTheme.colors.received
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (secondaryAmountText != null) {
                Text(
                    text = secondaryAmountText,
                    style = MaterialTheme.typography.bodySmall.withMonoDigits(),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun RequestIconWithStatusBadge(received: Boolean) {
    Box(modifier = Modifier.size(40.dp)) {
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
                imageVector = Icons.Outlined.Money,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.size(20.dp),
            )
        }
        val pulseAlpha = if (!received) {
            val transition = rememberInfiniteTransition(label = "request-pulse")
            transition.animateFloat(
                initialValue = 1f,
                targetValue = 0.4f,
                animationSpec = infiniteRepeatable(
                    animation = tween(durationMillis = 1100),
                    repeatMode = RepeatMode.Reverse,
                ),
                label = "request-pulse-alpha",
            ).value
        } else 1f
        Box(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .size(16.dp)
                .background(
                    color = MaterialTheme.colorScheme.surface,
                    shape = CircleShape,
                )
                .alpha(pulseAlpha),
            contentAlignment = Alignment.Center,
        ) {
            AnimatedContent(
                targetState = received,
                transitionSpec = { fadeIn(tween(280)) togetherWith fadeOut(tween(280)) },
                label = "request-badge",
            ) { isReceived ->
                if (isReceived) {
                    Icon(
                        imageVector = Icons.Filled.ArrowDownward,
                        contentDescription = null,
                        tint = CashuTheme.colors.received,
                        modifier = Modifier.size(14.dp),
                    )
                } else {
                    Icon(
                        imageVector = Icons.Outlined.Schedule,
                        contentDescription = null,
                        tint = CashuTheme.colors.pending,
                        modifier = Modifier.size(14.dp),
                    )
                }
            }
        }
    }
}
