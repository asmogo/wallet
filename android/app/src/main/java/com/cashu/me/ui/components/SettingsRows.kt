package com.cashu.me.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import com.cashu.me.ui.theme.CashuTheme

/**
 * Settings rows on M3 [ListItem] — native geometry, states, and typography.
 * Pass `tint = colorScheme.error` for destructive rows.
 */
@Composable
fun NavRow(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    leadingIcon: ImageVector? = null,
    subtitle: String? = null,
    enabled: Boolean = true,
    tint: Color? = null,
    showChevron: Boolean = true,
    trailingValue: String? = null,
    trailingIcon: ImageVector? = null,
) {
    val titleColor = tint ?: MaterialTheme.colorScheme.onSurface
    val iconColor = tint ?: MaterialTheme.colorScheme.onSurfaceVariant
    val chevronColor = tint ?: MaterialTheme.colorScheme.onSurfaceVariant
    ListItem(
        modifier = modifier.clickable(enabled = enabled, onClick = onClick),
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        headlineContent = {
            Text(text = title, color = titleColor)
        },
        supportingContent = subtitle?.let {
            { Text(text = it) }
        },
        leadingContent = leadingIcon?.let {
            {
                Icon(
                    imageVector = it,
                    contentDescription = null,
                    tint = iconColor,
                    modifier = Modifier.size(CashuTheme.spacing.section),
                )
            }
        },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (trailingValue != null) {
                    Text(
                        text = trailingValue,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.width(CashuTheme.spacing.tight))
                }
                when {
                    trailingIcon != null -> Icon(
                        imageVector = trailingIcon,
                        contentDescription = null,
                        tint = chevronColor,
                        modifier = Modifier.size(CashuTheme.spacing.loose),
                    )
                    showChevron -> Icon(
                        imageVector = Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                        contentDescription = null,
                        tint = chevronColor,
                        modifier = Modifier.size(CashuTheme.spacing.loose),
                    )
                }
            }
        },
    )
}

/** Settings list row with a trailing Switch, on M3 [ListItem]. */
@Composable
fun ToggleRow(
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    enabled: Boolean = true,
    leadingIcon: ImageVector? = null,
) {
    val contentAlpha = if (enabled) 1f else 0.38f
    ListItem(
        modifier = modifier.clickable(enabled = enabled) { onCheckedChange(!checked) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        headlineContent = {
            Text(
                text = title,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = contentAlpha),
            )
        },
        supportingContent = subtitle?.let {
            {
                Text(
                    text = it,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = contentAlpha),
                )
            }
        },
        leadingContent = leadingIcon?.let {
            {
                Icon(
                    imageVector = it,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = contentAlpha),
                    modifier = Modifier.size(CashuTheme.spacing.section),
                )
            }
        },
        trailingContent = {
            Switch(
                checked = checked,
                onCheckedChange = onCheckedChange,
                enabled = enabled,
            )
        },
    )
}
