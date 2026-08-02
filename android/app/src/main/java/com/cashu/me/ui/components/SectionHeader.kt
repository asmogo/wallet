package com.cashu.me.ui.components

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.asOverline

/** Uppercase, letter-spaced overline used for section group headers.
 *  16dp top + 8dp bottom matches iOS visual rhythm; DESIGN.md §3.1's 28dp top is
 *  carved out (Android value documented as 16dp).
 *
 *  [contentPadding] exists for hosts that already own their horizontal gutter and
 *  vertical rhythm (the connect-a-mint sheet); leave it defaulted everywhere else. */
@Composable
fun SectionHeader(
    text: String,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(
        start = CashuTheme.spacing.comfortable,
        end = CashuTheme.spacing.comfortable,
        top = CashuTheme.spacing.comfortable,
        bottom = CashuTheme.spacing.snug,
    ),
) {
    Text(
        text = text.uppercase(),
        style = MaterialTheme.typography.labelMedium.asOverline(),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier.padding(contentPadding),
    )
}
