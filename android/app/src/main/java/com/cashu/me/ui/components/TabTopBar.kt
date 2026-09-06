package com.cashu.me.ui.components

import androidx.compose.foundation.layout.RowScope
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.LargeFlexibleTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.TopAppBarScrollBehavior
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight

/**
 * The shared top bar for the top-level tab screens (History and Mints).
 *
 * Both tabs route through this wrapper so their titles are identical by
 * construction — same big collapsing `LargeFlexibleTopAppBar`, same background,
 * same weight. Titles render **Bold** (a deliberate carve-out from stock M3
 * `Typography()` W400) for cross-platform brand parity with the iOS large title;
 * the explicit `fontWeight` overrides the bar's default in both the expanded and
 * collapsed states while preserving each state's size. The native
 * collapse-on-scroll behavior is kept — a scrolled History still shrinks its
 * title, exactly as iOS does. See DESIGN-ANDROID.md §1.
 *
 * [navigationIcon] defaults to empty (History/Mints are bottom-nav tabs with no
 * back affordance). Pushed destinations such as Settings use a compact native
 * top app bar, matching the iOS navigation hierarchy.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun TabTopBar(
    title: String,
    scrollBehavior: TopAppBarScrollBehavior,
    modifier: Modifier = Modifier,
    navigationIcon: @Composable () -> Unit = {},
    actions: @Composable RowScope.() -> Unit = {},
) {
    LargeFlexibleTopAppBar(
        title = { Text(title, fontWeight = FontWeight.Bold) },
        modifier = modifier,
        scrollBehavior = scrollBehavior,
        navigationIcon = navigationIcon,
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = MaterialTheme.colorScheme.background,
            scrolledContainerColor = MaterialTheme.colorScheme.background,
        ),
        actions = actions,
    )
}
