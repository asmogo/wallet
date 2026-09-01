package com.cashu.me.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.IntOffset
import com.cashu.me.ui.theme.CashuTheme

private val NoticeIconSize = 18.dp
private val NoticePadding = 12.dp
private val NoticeCorner = RoundedCornerShape(12.dp)

/**
 * Severity tiers, sharing their vocabulary with iOS `ErrorSeverity`.
 *
 * - [Error]   the action failed or is blocked. Something broke.
 * - [Caution] non-blocking: proceed carefully, or this won't work here.
 * - [Info]    a neutral precondition, not a failure.
 * - [Success] confirmation.
 *
 * Deliberately has **no default**. It used to default to [Error], so a call site
 * that simply didn't think about severity rendered the loudest tier in the
 * system — and 24 of them did. Severity is a claim about what the message
 * costs the user, not about how the code found out, so it has to be made.
 *
 * `Caution` rather than "warning": orange also means *pending* in this app, and
 * "warning" invites the warning-triangle glyph Material reserves for something
 * else. The names match iOS so one vocabulary describes both apps — the glyphs
 * deliberately do not, because each platform follows its own convention.
 */
enum class NoticeSeverity { Error, Caution, Info, Success }

/**
 * The **in-context** error channel: the message that blocks the primary action
 * and has to be resolved before the user can continue.
 *
 * One of four channels, chosen by the rule in
 * docs/product/inline-error-fixes.md §1b. Deliberately *not* the channel for the
 * other three:
 *
 * - fixable in a field right here → `CashuTextField(isError, supportingText)`
 * - already happened, nothing to fix → `SnackbarHost`
 * - blocks the whole screen → this, plus a retry action
 *
 * Rendered as a Material tonal container. Every fill is paired with its matching
 * content role, so contrast comes from the colour system instead of restating
 * the fill colour as the text colour.
 *
 * @param detail optional second line for amounts and supporting specifics
 * @param showsContainer drop the tonal fill and padding, leaving glyph + text.
 *   For notices that float on a bare surface rather than sitting inside a list
 *   or card — the Send amount faces, where the only other things on screen are
 *   the amount and the keypad, and a filled box reads as a foreign object.
 *   Matches iOS `InlineNotice`, which never fills.
 * @param centered centre the glyph + text as a group, for a notice that floats
 *   under a centred amount rather than sitting in a left-aligned form.
 */
@Composable
fun InlineNotice(
    text: String,
    modifier: Modifier = Modifier,
    severity: NoticeSeverity,
    detail: String? = null,
    showsContainer: Boolean = true,
    centered: Boolean = false,
) {
    val (icon, content, container) = noticeColors(severity)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .then(
                if (showsContainer) {
                    Modifier.background(container, NoticeCorner).padding(NoticePadding)
                } else {
                    Modifier
                },
            )
            // Announced on appearance without stealing focus. The component owns
            // this so a call site cannot forget it.
            .semantics { liveRegion = LiveRegionMode.Polite },
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(
                8.dp,
                if (centered) Alignment.CenterHorizontally else Alignment.Start,
            ),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = content,
                modifier = Modifier.size(NoticeIconSize),
            )
            Column(
                // `fill = false` when centred: a filling child leaves no free
                // space for the row to centre the group into.
                modifier = Modifier.weight(1f, fill = !centered),
                verticalArrangement = Arrangement.spacedBy(2.dp),
                horizontalAlignment = if (centered) {
                    Alignment.CenterHorizontally
                } else {
                    Alignment.Start
                },
            ) {
                val align = if (centered) TextAlign.Center else TextAlign.Start
                Text(
                    text = text,
                    style = MaterialTheme.typography.bodyMedium,
                    color = content,
                    textAlign = align,
                )
                if (detail != null) {
                    Text(
                        text = detail,
                        style = MaterialTheme.typography.bodySmall,
                        color = content.copy(alpha = 0.78f),
                        textAlign = align,
                    )
                }
            }
        }
    }
}

/**
 * Show/hide wrapper with the canonical entrance (slide up + fade) and quiet exit
 * (fade only — exits are subtler than entrances).
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun InlineNoticeHost(
    text: String?,
    modifier: Modifier = Modifier,
    contentModifier: Modifier = Modifier,
    severity: NoticeSeverity,
    detail: String? = null,
) {
    val enterSpatial = MaterialTheme.motionScheme.defaultSpatialSpec<IntOffset>()
    val enterEffects = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
    val exitEffects = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
    // Keep the last non-null text so the exit fade shows content, not a blank.
    var lastText by remember { mutableStateOf(text) }
    LaunchedEffect(text) {
        if (text != null) lastText = text
    }
    AnimatedVisibility(
        visible = text != null,
        modifier = modifier,
        enter = slideInVertically(enterSpatial) { it / 2 } + fadeIn(enterEffects),
        exit = fadeOut(exitEffects),
    ) {
        InlineNotice(
            text = (text ?: lastText).orEmpty(),
            modifier = contentModifier,
            severity = severity,
            detail = detail,
        )
    }
}

/** Icon, content colour, container fill — always a Material role pair. */
@Composable
private fun noticeColors(severity: NoticeSeverity): Triple<ImageVector, Color, Color> = when (severity) {
    NoticeSeverity.Error -> Triple(
        Icons.Filled.Error,
        MaterialTheme.colorScheme.onErrorContainer,
        MaterialTheme.colorScheme.errorContainer,
    )
    NoticeSeverity.Caution -> Triple(
        Icons.Filled.Warning,
        CashuTheme.colors.onPendingContainer,
        CashuTheme.colors.pendingContainer,
    )
    NoticeSeverity.Info -> Triple(
        Icons.Filled.Info,
        MaterialTheme.colorScheme.onSurfaceVariant,
        MaterialTheme.colorScheme.surfaceContainerHigh,
    )
    NoticeSeverity.Success -> Triple(
        Icons.Filled.CheckCircle,
        CashuTheme.colors.onReceivedContainer,
        CashuTheme.colors.receivedContainer,
    )
}
