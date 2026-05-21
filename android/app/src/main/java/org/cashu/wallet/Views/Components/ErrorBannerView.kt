package org.cashu.wallet.Views.Components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import org.cashu.wallet.Resources.CashuOrange

enum class BannerType {
    Error,
    Warning,
    Info,
}

@Composable
fun ErrorBannerView(
    message: String,
    modifier: Modifier = Modifier,
    type: BannerType = BannerType.Error,
    onDismiss: (() -> Unit)? = null,
) {
    val color = when (type) {
        BannerType.Error -> MaterialTheme.colorScheme.error
        BannerType.Warning -> CashuOrange
        BannerType.Info -> MaterialTheme.colorScheme.secondary
    }
    val icon = when (type) {
        BannerType.Info -> Icons.Filled.Info
        else -> Icons.Filled.Warning
    }
    Row(
        modifier = modifier
            .fillMaxWidth()
            .semantics { contentDescription = message }
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(imageVector = icon, contentDescription = null, tint = color)
        Text(
            text = message,
            color = color,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f),
        )
        if (onDismiss != null) {
            IconButton(onClick = onDismiss) {
                Icon(
                    imageVector = Icons.Filled.Close,
                    contentDescription = "Dismiss",
                    tint = MaterialTheme.colorScheme.secondary,
                )
            }
        } else {
            Spacer(Modifier)
        }
    }
}
