package com.cashu.me.ui.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.ButtonColors
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.SecondaryButton
import com.cashu.me.ui.theme.CashuTheme

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

/** Per-step content for the fixed bottom chassis. */
@Immutable
class OnboardingChassisModel(
    val headline: String,
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

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = HeaderPadding),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
        ) {
            Text(
                text = model.headline,
                style = onboardingTitleStyle(),
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = if (model.headline.contains('\n')) Int.MAX_VALUE else 1,
                autoSize = if (model.headline.contains('\n')) null else HeadlineAutoSize,
            )
            if (model.subhead != null) {
                Text(
                    text = model.subhead,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
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
                .padding(top = CashuTheme.spacing.section)
                .padding(bottom = BottomPadding),
            verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            ChassisSlot(model.primary, templateStyle = ChassisButtonStyle.Primary)
            ChassisSlot(model.secondary, templateStyle = ChassisButtonStyle.Secondary)
            ChassisSlot(model.tertiary, templateStyle = ChassisButtonStyle.Ghost)
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

@Composable
private fun ChassisSlot(action: ChassisAction?, templateStyle: ChassisButtonStyle) {
    if (action != null) {
        val tagModifier = action.testTag?.let { Modifier.testTag(it) } ?: Modifier
        when (action.style) {
            ChassisButtonStyle.Primary -> PrimaryButton(
                text = action.label,
                onClick = action.onClick,
                modifier = tagModifier,
                enabled = action.enabled,
                loading = action.loading,
                colors = action.colors,
            )
            ChassisButtonStyle.Secondary -> SecondaryButton(
                text = action.label,
                onClick = action.onClick,
                modifier = tagModifier,
                enabled = action.enabled,
            )
            ChassisButtonStyle.Ghost -> GhostButton(
                text = action.label,
                onClick = action.onClick,
                modifier = tagModifier,
                enabled = action.enabled,
            )
        }
    } else {
        // Reserved slot: a hidden template keeps the slot's height (and
        // therefore the primary CTA's Y) constant across steps, tracking
        // font scale instead of hardcoding a height. Cleared semantics keep
        // it out of TalkBack and the test tree.
        val hiddenModifier = Modifier
            .alpha(0f)
            .clearAndSetSemantics { }
        when (templateStyle) {
            ChassisButtonStyle.Primary, ChassisButtonStyle.Secondary -> PrimaryButton(
                text = "Template",
                onClick = {},
                modifier = hiddenModifier,
                enabled = false,
            )
            ChassisButtonStyle.Ghost -> GhostButton(
                text = "Template",
                onClick = {},
                modifier = hiddenModifier,
                enabled = false,
            )
        }
    }
}
