package com.cashu.me.ui.components

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cashu.me.ui.theme.rememberReducedMotion
import com.cashu.me.ui.theme.CashuTheme

// iOS renders the glyph hierarchically at 0.62 opacity; dim the tint the same
// amount so the icon sits behind the text instead of competing with it.
private const val EmptyStateIconAlpha = 0.62f

/**
 * Size variants mirroring iOS NativeEmptyState.Style. Dimensions are the iOS
 * point values, deliberately off the spacing scale. (iOS also has a smaller
 * `.compact`; add it here when an Android call site needs one.)
 */
enum class EmptyStateSize(
    internal val iconSize: Dp,
    internal val iconGap: Dp,
) {
    /** Full-tab empty trays (Home, History): 56dp glyph, title2-scale text. */
    FullScreen(iconSize = 56.dp, iconGap = 12.dp),

    /** Content-fit hosts like the Send sheet: 42dp glyph, headline-scale text. */
    Section(iconSize = 42.dp, iconGap = 10.dp),
}
// iOS NativeEmptyState entrance: opacity 0→1, scale 0.96→1, rise from 8pt.
private const val EntranceInitialScale = 0.96f
private val EntranceRise = 8.dp
private const val EntranceDamping = 0.82f

/**
 * Quiet tray empty state (iOS NativeEmptyState). Full-tab empty states render
 * at rest because their navigation subtree can remount on an ordinary tab
 * visit. Rarer section states settle in once: fade, scale from 0.96, an 8dp
 * rise, and one glyph bounce. Reduce-motion keeps the section fade only. The
 * centering layout lives outside the animated layer, so the entrance can't
 * drag content in from the top-left (see the 2026-07 fly-in bug history).
 *
 * @param fillHeight when true (default), expands to fill the parent and
 *   centers its content — home/history empty trays. Set false for wrap-content
 *   hosts like a content-fit Send bottom sheet.
 * @param size glyph/text scale; [EmptyStateSize.Section] matches the smaller
 *   iOS `.section` style used inside sheets.
 */
@Composable
fun EmptyState(
    icon: ImageVector,
    title: String,
    modifier: Modifier = Modifier,
    supporting: String? = null,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
    fillHeight: Boolean = true,
    size: EmptyStateSize = EmptyStateSize.FullScreen,
) {
    val reduceMotion = rememberReducedMotion()
    val allowsEntranceMotion = size != EmptyStateSize.FullScreen
    var appeared by remember(allowsEntranceMotion) { mutableStateOf(!allowsEntranceMotion) }
    LaunchedEffect(allowsEntranceMotion) { appeared = true }
    val alpha by animateFloatAsState(
        targetValue = if (appeared) 1f else 0f,
        animationSpec = spring(stiffness = Spring.StiffnessMedium),
        label = "empty-entrance-alpha",
    )
    val settle by animateFloatAsState(
        targetValue = if (appeared || reduceMotion) 1f else 0f,
        animationSpec = spring(
            dampingRatio = EntranceDamping,
            stiffness = Spring.StiffnessMediumLow,
        ),
        label = "empty-entrance-settle",
    )
    val risePx = with(LocalDensity.current) { EntranceRise.toPx() }
    val iconBounce = rememberBounceScale(
        trigger = Unit,
        bounceOnEntry = allowsEntranceMotion,
    )
    Column(
        modifier = modifier
            .then(if (fillHeight) Modifier.fillMaxSize() else Modifier.fillMaxWidth())
            .padding(horizontal = CashuTheme.spacing.comfortable)
            .graphicsLayer {
                this.alpha = alpha
                if (allowsEntranceMotion && !reduceMotion) {
                    val scale = EntranceInitialScale + (1f - EntranceInitialScale) * settle
                    scaleX = scale
                    scaleY = scale
                    translationY = risePx * (1f - settle)
                }
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = if (fillHeight) Arrangement.Center else Arrangement.Top,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = EmptyStateIconAlpha),
            modifier = Modifier
                .size(size.iconSize)
                .graphicsLayer {
                    scaleX = if (allowsEntranceMotion) iconBounce else 1f
                    scaleY = if (allowsEntranceMotion) iconBounce else 1f
                },
        )
        Spacer(Modifier.height(size.iconGap))
        Text(
            text = title,
            // iOS title2/headline semibold; the M3 roles ship lighter weights.
            style = when (size) {
                EmptyStateSize.FullScreen ->
                    MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold)
                EmptyStateSize.Section ->
                    MaterialTheme.typography.titleMedium.copy(
                        fontWeight = FontWeight.SemiBold,
                    )
            },
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
        )
        if (supporting != null) {
            Spacer(Modifier.height(CashuTheme.spacing.micro))
            Text(
                text = supporting,
                // iOS body/subheadline with SF's near-zero tracking; the M3
                // roles' default letter spacing reads looser than the iOS twin.
                style = when (size) {
                    EmptyStateSize.FullScreen ->
                        MaterialTheme.typography.bodyLarge
                    EmptyStateSize.Section ->
                        MaterialTheme.typography.bodyMedium
                },
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        if (actionLabel != null && onAction != null) {
            Spacer(Modifier.height(CashuTheme.spacing.section))
            PrimaryButton(
                text = actionLabel,
                onClick = onAction,
                // Full width at 32dp side margins (16dp component padding +
                // 16dp here) — iOS renders every primary CTA as a full-width
                // capsule inset 32pt, including this one.
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = CashuTheme.spacing.comfortable),
            )
        }
    }
}
