package com.cashu.me.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cashu.me.ui.theme.CashuTheme

// Compact chrome under the system drag handle — title row sits tight to the top.
private val SheetHeaderMinHeight = 40.dp
private val SheetHeaderEdgePadding = 0.dp
// Keep title clear of leading/trailing icon buttons (48dp targets).
private val SheetHeaderTitleSideInset = 48.dp

/**
 * Header row for flow bottom sheets — replaces `TopAppBar` for content hosted
 * in a `ModalBottomSheet` (iOS `.sheet` parity: centered inline title, optional
 * leading back, trailing actions), sitting under the system drag handle.
 * Dismiss is via the drag handle / scrim — no close X.
 */
@Composable
fun SheetHeader(
    title: String,
    modifier: Modifier = Modifier,
    navigationIcon: ImageVector? = null,
    navigationContentDescription: String? = null,
    onNavigationClick: (() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = SheetHeaderMinHeight)
            .padding(horizontal = SheetHeaderEdgePadding),
    ) {
        // Title is absolutely centered; nav / actions draw on top in the corners
        // so a single leading close still leaves "Send" dead-center (iOS inline).
        AnimatedContent(
            targetState = title,
            transitionSpec = {
                fadeIn(spring(stiffness = Spring.StiffnessMedium))
                    .togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
            },
            label = "sheet-header-title",
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxWidth()
                .padding(horizontal = SheetHeaderTitleSideInset),
        ) { current ->
            Text(
                text = current,
                style = CashuTheme.type.sheetTitle,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if (navigationIcon != null && onNavigationClick != null) {
            IconButton(
                onClick = onNavigationClick,
                modifier = Modifier.align(Alignment.CenterStart),
            ) {
                ToolbarIcon(
                    imageVector = navigationIcon,
                    contentDescription = navigationContentDescription,
                )
            }
        }
        Row(
            modifier = Modifier.align(Alignment.CenterEnd),
            content = actions,
        )
    }
}
