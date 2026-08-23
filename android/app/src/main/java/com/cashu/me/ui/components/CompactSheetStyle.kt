package com.cashu.me.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf

/**
 * Scopes the opaque compact-sheet control vocabulary without changing global
 * fields or full-screen surfaces. The native Material sheet remains responsible
 * for shape, elevation, dimming, and gesture behavior.
 */
internal val LocalCompactSheetStyle = compositionLocalOf { false }

@Composable
fun CompactSheetContent(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalCompactSheetStyle provides true, content = content)
}
