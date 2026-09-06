package com.cashu.me.ui.mints

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.cashu.me.ui.theme.CashuTheme

/** Persistent connection feedback stays with the affected metadata. */
@Composable
internal fun MintConnectionStatus(
    connection: MintConnectionState,
    showsRecovery: Boolean,
    onRetry: () -> Unit,
) {
    val configuration = LocalConfiguration.current
    val stacked = configuration.fontScale > 1.3f || configuration.screenWidthDp < 360
    val checking = connection == MintConnectionState.Checking
    Column(
        modifier = Modifier.fillMaxWidth().padding(
            horizontal = CashuTheme.spacing.comfortable,
            vertical = CashuTheme.spacing.default,
        ),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        val label: @Composable () -> Unit = {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(CashuTheme.spacing.default),
            ) {
                Icon(Icons.Outlined.Public, contentDescription = null,
                    modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("Connection", style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        val status: @Composable () -> Unit = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (checking && !showsRecovery) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(
                    text = if (checking && showsRecovery) "Refreshing" else connection.label,
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (connection == MintConnectionState.Online) MaterialTheme.colorScheme.onSurface
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Column(modifier = Modifier.semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }) {
            if (stacked) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { label(); status() }
            } else {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically) { label(); status() }
            }
        }
        if (showsRecovery) {
            if (stacked) {
                RecoveryText()
                RetryButton(checking, onRetry)
            } else {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    RecoveryText(Modifier.weight(1f))
                    RetryButton(checking, onRetry)
                }
            }
        }
    }
}

@Composable
private fun RecoveryText(modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text("Couldn't refresh mint information.", style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("Showing saved information.", style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun RetryButton(checking: Boolean, onRetry: () -> Unit) {
    TextButton(onClick = onRetry, enabled = !checking,
        colors = ButtonDefaults.textButtonColors(
            contentColor = MaterialTheme.colorScheme.onSurface,
            disabledContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
        )) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (checking) {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(
                text = if (checking) "Checking…" else "Retry",
                color = if (checking) MaterialTheme.colorScheme.onSurfaceVariant
                    else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}
