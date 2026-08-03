package com.cashu.me.ui.components

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.cashu.me.ui.theme.CashuTheme

/**
 * Quiet explanatory prose under a settings section (iOS `SettingsSectionFooter`).
 * The single home for this treatment — settings screens previously carried three
 * near-identical copies with drifting vertical padding.
 */
@Composable
fun SettingsFooterText(
    text: String,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(
        start = CashuTheme.spacing.comfortable,
        end = CashuTheme.spacing.comfortable,
        top = CashuTheme.spacing.snug,
        bottom = CashuTheme.spacing.default,
    ),
) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier
            .fillMaxWidth()
            .padding(contentPadding),
    )
}
