package com.cashu.me.ui.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
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
import androidx.compose.material.icons.outlined.HelpOutline
import androidx.compose.material3.ButtonColors
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cashu.me.ui.components.GhostButton
import com.cashu.me.ui.components.PrimaryButton
import com.cashu.me.ui.components.SecondaryButton
import com.cashu.me.ui.components.morphBlur
import com.cashu.me.ui.testing.UiTestTags
import com.cashu.me.ui.theme.CashuTheme
import com.cashu.me.ui.theme.rememberReducedMotion

// ---------------------------------------------------------------------------
// The fixed bottom action chassis shared by every onboarding step
// (docs/product/onboarding-restyle-brief.md §3).
//
// The chassis pins primary → secondary → tertiary at the bottom of every step
// (titles live at the top of the stage); the stage owns all vertical slack.
// Absent actions
// contribute zero height, so the stack always hugs the bottom edge rather than
// reserving empty slots (design review 2026-08-05, replacing the earlier hidden
// slot templates). Everything therefore grows UPWARD into the stage on a step
// change; the bottom edge is the fixed point.
//
// Motion rule: only the stack's HEIGHT animates, and only on a spring. Nothing
// ever moves laterally and nothing is ever clipped — every AnimatedContent here
// must opt out of Compose's default SizeTransform(clip = true) and out of its
// default Alignment.TopStart, or content pins to the top-left of a box whose
// size is springing while the parent re-centers it, which reads as a button
// sliding in from the left with its sides sheared off.
// ---------------------------------------------------------------------------

// Shared onboarding metrics (iOS parity: headers 28pt, CTA stacks 24pt).
internal val HeaderPadding = 28.dp
internal val CtaPadding = 24.dp
internal val BottomPadding = 24.dp

// Cross-fade mask for a whole-capsule slot swap — wider than the label mask in
// Buttons.kt because there is more of the outgoing object to bridge.
private val SlotMorphBlur = 3.dp

/**
 * Step-layout metrics. Onboarding draws no `TopAppBar`, so these state the
 * top-chrome geometry once instead of letting each step hand-roll it: a bar
 * band holding the back button, with the title on the line below. Every step
 * resolves to the same [TitleTopInset], so the title stays put across the
 * stage swap rather than jumping per screen.
 *
 * Same rule as iOS `OnboardingMetrics`, each platform in its own native
 * measure — the band is M3's 48 dp minimum touch target (what `IconButton`
 * occupies) where iOS uses its 44 pt navigation bar.
 */
internal object OnboardingMetrics {
    /** Margin above the bar band (`spacing.snug`). */
    val BarTopInset = 8.dp

    /**
     * Bar band height: M3's minimum interactive size, which is what an
     * [IconButton] lays out as (40 dp state layer inside a 48 dp target).
     */
    val BarHeight = 48.dp

    /** Band-to-title gap (`spacing.snug`). */
    val TitleGap = 8.dp

    /**
     * Start padding for the back button. The 24 dp icon centers in the 48 dp
     * target, so its glyph lands on the [HeaderPadding] gutter (16 + 12 = 28).
     */
    val BarStartInset = 16.dp

    /**
     * Where the title starts on a step that draws no back button, so it lands
     * on the same line as the steps that do.
     */
    val TitleTopInset = BarTopInset + BarHeight + TitleGap
}

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
 * Actions only: every step — welcome included — titles itself at the top of its
 * stage with [OnboardingStepHeader], so the chassis holds nothing but the
 * buttons and they hug the bottom edge. */
@Immutable
class OnboardingChassisModel(
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
    // Deliberately no background: the ASCII terrain band's bottom fade
    // continues a little way behind the buttons (AsciiField.kt), and an
    // opaque ground here would cut it off at the chassis edge. The scaffold
    // stacks the chassis below the stage, so nothing ever scrolls under it —
    // unlike iOS, whose safe-area-inset chassis needs a conditional ground.
    Column(modifier = modifier.fillMaxWidth()) {
        // Indicator slot — resolved as "no indicator" (brief §3): the flow
        // branches into paths of different lengths, so page dots would imply
        // a linear path that doesn't exist. The stage carries the sense of
        // place; the slot stays here for the record.

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
                .padding(top = CashuTheme.spacing.comfortable)
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
    /** Extra chassis modifiers — the onboarding root measures the chassis
     * height here so the ASCII backdrop knows how far to underlap it. */
    chassisModifier: Modifier = Modifier,
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
        OnboardingChassis(model = chassis, modifier = chassisModifier, accessory = accessory)
    }
}

@Composable
private fun ChassisSlot(action: ChassisAction?, topPadding: Dp) {
    // Occupancy and style changes cross-fade the whole slot in place; label
    // changes within the same style flow through the button's own label
    // cross-fade.
    //
    // An empty slot measures 0×0, so an occupancy change is a real size
    // animation — see the file header. clip = false keeps the button whole while
    // its slot springs open, and BottomCenter anchors it to the stack's fixed
    // bottom edge so it rides up with the stack instead of unwrapping downward
    // from a moving top edge. Reduce Motion drops the size animation entirely
    // (`using(null)`): the stack snaps and only opacity moves.
    val reducedMotion = rememberReducedMotion()
    // transitionSpec is not composable — capture the motion-scheme specs here.
    // The size spring is stated rather than left to Compose's built-in default:
    // this was the one place the chassis ignored MotionScheme.expressive() and
    // drifted off the app's curve identity. Spatial (not effects) because a
    // slot's height is a spatial property — the slight overshoot spatial specs
    // carry is M3 Expressive's signature and is chartered in
    // docs/android/DESIGN-ANDROID.md, which is explicitly off the iOS
    // "no bounce" constraint.
    val slotEnterSpec = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
    val slotExitSpec = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
    val slotSizeSpec = MaterialTheme.motionScheme.defaultSpatialSpec<IntSize>()
    AnimatedContent(
        targetState = action?.style,
        transitionSpec = {
            fadeIn(slotEnterSpec)
                // Exits subtler than entrances (DESIGN.md §6).
                .togetherWith(fadeOut(slotExitSpec))
                .using(
                    if (reducedMotion) null else SizeTransform(clip = false) { _, _ -> slotSizeSpec },
                )
        },
        contentAlignment = Alignment.BottomCenter,
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
            // Blur mask across the whole capsule: a Primary→Secondary restyle
            // otherwise shows two stacked buttons mid-fade. A full button needs
            // more bridging than a label, hence the wider radius.
            Box(Modifier.padding(top = topPadding).then(morphBlur(SlotMorphBlur))) {
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

/** Top-of-step title + supporting copy — every step, welcome included, so the
 * title sits in the same place from the first screen onward. */
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

/**
 * Bar-band icon colors.
 *
 * These MUST be set explicitly. The onboarding root paints its canvas with
 * `Modifier.background(colorScheme.background)` rather than wrapping in a
 * `Surface`, and only a `Surface` provides `LocalContentColor` — so the
 * ambient value stays at Compose's default of **black**, which is invisible on
 * the dark canvas. Never let a bar-band icon inherit `LocalContentColor` here.
 */
@Composable
private fun barButtonColors() = IconButtonDefaults.iconButtonColors(
    contentColor = MaterialTheme.colorScheme.onSurface,
)

/** M3 back affordance for onboarding — a plain icon button, no top app bar. */
@Composable
fun OnboardingBackButton(
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    IconButton(onClick = onBack, modifier = modifier, colors = barButtonColors()) {
        Icon(
            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
            contentDescription = "Back",
        )
    }
}

/**
 * Help affordance, in the bar band's *trailing* slot — opposite the back
 * button's leading one, where a help glyph conventionally lives. Keeping it in
 * the bar band rather than the chassis is what stops Welcome being the only
 * three-slot step, so the button stack no longer changes height when you leave
 * it. Welcome is the only user today.
 */
@Composable
fun OnboardingInfoButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    IconButton(
        onClick = onClick,
        modifier = modifier.testTag(UiTestTags.OnboardingInfo),
        colors = barButtonColors(),
    ) {
        Icon(
            imageVector = Icons.Outlined.HelpOutline,
            contentDescription = "What is ecash?",
        )
    }
}
