package com.cashu.me.ui.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ButtonColors
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.SecondaryButton
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.rememberReducedMotion

// ---------------------------------------------------------------------------
// The fixed bottom action chassis shared by every onboarding step
// (docs/product/onboarding-restyle-brief.md §3).
//
// The chassis pins headline → subhead → primary → secondary → tertiary at the
// bottom of every step; the stage above owns all vertical slack. The primary
// CTA's Y position is identical on every step: every slot BELOW the primary is
// always reserved — an absent action renders a hidden template button, so slot
// height tracks font scale instead of a hardcoded constant. Content ABOVE the
// primary (headline, subhead, accessory) grows upward into the stage and can
// never move the button. The container itself never animates on step change;
// only its text and labels swap, in place.
// ---------------------------------------------------------------------------

// Shared onboarding metrics (iOS parity: headers 28pt, CTA stacks 24pt).
internal val HeaderPadding = 28.dp
internal val CtaPadding = 24.dp
internal val BottomPadding = 24.dp

/** iOS `.largeTitle.weight(.heavy)` + `.tracking(-0.5)` — the step-title voice. */
@Composable
internal fun onboardingTitleStyle(): TextStyle =
    MaterialTheme.typography.displaySmall.copy(
        fontWeight = FontWeight.ExtraBold,
        letterSpacing = (-0.5).sp,
        lineHeight = 40.sp,
    )

// Single-line headlines render at full display size and step down only when
// the line would overflow (narrow devices / large font scales). Multi-line
// headlines (the welcome step's deliberate break) wrap at full size instead.
private val HeadlineAutoSize = TextAutoSize.StepBased(
    minFontSize = 26.sp,
    maxFontSize = 36.sp,
    stepSize = 1.sp,
)

enum class ChassisButtonStyle { Primary, Secondary, Ghost }

/** One action slot in the chassis. Slot position ≠ style: the restore-method
 * chooser hosts a Secondary-styled button in the primary slot, preserving
 * today's hierarchy. */
@Immutable
class ChassisAction(
    val label: String,
    val onClick: () -> Unit,
    val style: ChassisButtonStyle = ChassisButtonStyle.Primary,
    val enabled: Boolean = true,
    val loading: Boolean = false,
    val testTag: String? = null,
    val colors: ButtonColors? = null,
)

/** Per-step content for the bottom action chassis.
 *
 * [headline]/[subhead] are the *welcome* treatment only (design review
 * 2026-08-05): every other step titles itself at the top of its stage with
 * [OnboardingStepHeader] and leaves these null, so its actions hug the
 * bottom. */
@Immutable
class OnboardingChassisModel(
    val headline: String? = null,
    val subhead: String? = null,
    val primary: ChassisAction? = null,
    val secondary: ChassisAction? = null,
    val tertiary: ChassisAction? = null,
)

@Composable
fun OnboardingChassis(
    model: OnboardingChassisModel,
    modifier: Modifier = Modifier,
    accessory: (@Composable () -> Unit)? = null,
) {
    Column(modifier = modifier.fillMaxWidth()) {
        // Indicator slot — resolved as "no indicator" (brief §3): the flow
        // branches into paths of different lengths, so page dots would imply
        // a linear path that doesn't exist. The stage carries the sense of
        // place; the slot stays here for the record.

        // In-place text swaps: the incoming line rises 10dp on a spring while
        // fading in; the outgoing line just fades — exits subtler than
        // entrances. Reduce Motion is opacity both ways. The container itself
        // never moves.
        val reducedMotion = rememberReducedMotion()
        val riseOffsetPx = with(LocalDensity.current) { 10.dp.roundToPx() }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = HeaderPadding),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
        ) {
            AnimatedContent(
                targetState = model.headline,
                transitionSpec = { chassisTextTransform(reducedMotion, riseOffsetPx) },
                label = "chassis-headline",
            ) { headline ->
                if (headline != null) {
                    Text(
                        text = headline,
                        style = onboardingTitleStyle(),
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = if (headline.contains('\n')) Int.MAX_VALUE else 1,
                        autoSize = if (headline.contains('\n')) null else HeadlineAutoSize,
                    )
                } else {
                    Box(Modifier.fillMaxWidth())
                }
            }
            AnimatedContent(
                targetState = model.subhead,
                transitionSpec = { chassisTextTransform(reducedMotion, riseOffsetPx) },
                label = "chassis-subhead",
            ) { subhead ->
                if (subhead != null) {
                    Text(
                        text = subhead,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else {
                    Box(Modifier.fillMaxWidth())
                }
            }
        }

        if (accessory != null) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = HeaderPadding)
                    .padding(top = CashuTheme.spacing.comfortable),
            ) {
                accessory()
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = CtaPadding)
                .padding(
                    top = if (model.headline != null) {
                        CashuTheme.spacing.section
                    } else {
                        CashuTheme.spacing.comfortable
                    },
                )
                .padding(bottom = BottomPadding),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Per-slot top padding lives inside each slot's visible branch, so
            // absent actions contribute zero height and the stack hugs the
            // bottom (design review 2026-08-05 — no reserved slots).
            ChassisSlot(model.primary, topPadding = 0.dp)
            ChassisSlot(model.secondary, topPadding = CashuTheme.spacing.snug)
            ChassisSlot(model.tertiary, topPadding = CashuTheme.spacing.snug)
        }
    }
}

/**
 * The production onboarding frame: flexible stage over the pinned chassis.
 * Instrumented and screenshot tests compose exactly this, so what they measure
 * is what ships.
 */
@Composable
fun OnboardingScaffold(
    chassis: OnboardingChassisModel,
    modifier: Modifier = Modifier,
    accessory: (@Composable () -> Unit)? = null,
    stage: @Composable () -> Unit,
) {
    Column(modifier = modifier.fillMaxSize()) {
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
        ) {
            stage()
        }
        OnboardingChassis(model = chassis, accessory = accessory)
    }
}

/** Rise-and-fade in, fade out — the chassis' in-place text swap. */
private fun <T> AnimatedContentTransitionScope<T>.chassisTextTransform(
    reducedMotion: Boolean,
    riseOffsetPx: Int,
): ContentTransform =
    if (reducedMotion) {
        fadeIn(tween(200))
            .togetherWith(fadeOut(tween(140)))
            .using(SizeTransform(clip = false))
    } else {
        (
            fadeIn(spring(stiffness = Spring.StiffnessMedium)) +
                slideInVertically(
                    animationSpec = spring(stiffness = Spring.StiffnessMediumLow),
                    initialOffsetY = { riseOffsetPx },
                )
            )
            .togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
            .using(SizeTransform(clip = false))
    }

@Composable
private fun ChassisSlot(action: ChassisAction?, topPadding: Dp) {
    // Occupancy and style changes cross-fade the whole slot in place; label
    // changes within the same style flow through the button's own label
    // cross-fade. Fades only — vestibular-safe without a reduce-motion branch.
    AnimatedContent(
        targetState = action?.style,
        transitionSpec = {
            fadeIn(spring(stiffness = Spring.StiffnessMedium))
                .togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
        },
        label = "chassis-slot",
    ) { style ->
        // Snapshot the action that was live when this content entered, so an
        // emptying or restyled slot fades out showing its own outgoing button
        // rather than snapping empty or to the new label.
        var snapshot by remember { mutableStateOf(action?.takeIf { it.style == style }) }
        if (action != null && action.style == style && action !== snapshot) snapshot = action
        val shown = if (style != null) snapshot else null
        if (style != null && shown != null) {
            // While this content is exiting, `action` no longer matches —
            // neutralize the click (not `enabled`, which would restyle the
            // outgoing button to disabled colors mid-fade) so a tap can't
            // fire a stale step.
            val live = action?.style == style
            val onClick = if (live) shown.onClick else fun() {}
            val tagModifier = shown.testTag?.let { Modifier.testTag(it) } ?: Modifier
            Box(Modifier.padding(top = topPadding)) {
                when (style) {
                    ChassisButtonStyle.Primary -> PrimaryButton(
                        text = shown.label,
                        onClick = onClick,
                        modifier = tagModifier,
                        enabled = shown.enabled,
                        loading = shown.loading,
                        colors = shown.colors,
                    )
                    ChassisButtonStyle.Secondary -> SecondaryButton(
                        text = shown.label,
                        onClick = onClick,
                        modifier = tagModifier,
                        enabled = shown.enabled,
                    )
                    ChassisButtonStyle.Ghost -> GhostButton(
                        text = shown.label,
                        onClick = onClick,
                        modifier = tagModifier,
                        enabled = shown.enabled,
                        animatedLabel = true,
                    )
                }
            }
        }
    }
}

// MARK: step chrome ---------------------------------------------------------

/** Top-of-step title + supporting copy — every step except welcome, which
 * keeps its text in the bottom action block (design review 2026-08-05). */
@Composable
fun OnboardingStepHeader(
    title: String,
    subhead: String? = null,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = HeaderPadding),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
    ) {
        Text(
            text = title,
            style = onboardingTitleStyle(),
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = if (title.contains('\n')) Int.MAX_VALUE else 1,
            autoSize = if (title.contains('\n')) null else HeadlineAutoSize,
        )
        if (subhead != null) {
            Text(
                text = subhead,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** M3 back affordance for onboarding — a plain icon button, no top app bar. */
@Composable
fun OnboardingBackButton(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    IconButton(onClick = onBack, modifier = modifier) {
        Icon(
            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
            contentDescription = "Back",
        )
    }
}
