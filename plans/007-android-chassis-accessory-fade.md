# 007 — Fade the Android chassis accessory in and out

- **Status**: TODO
- **Commit**: f54a829c
- **Severity**: LOW
- **Category**: Physicality / platform parity (hard mount + instant height shift)
- **Estimated scope**: 1 file (`OnboardingChassis.kt`), 1 site

## Problem

The chassis accessory (the seed step's warning + acknowledge block) mounts and unmounts with no transition, popping into view and instantly shifting the chassis height while the CTA slots around it cross-fade smoothly. iOS fades the same accessory (`OnboardingChassis.swift:57` — `.transition(.opacity)`, height reflow riding the 0.28 s step transaction).

```kotlin
// android/.../ui/onboarding/OnboardingChassis.kt:176-185 — current
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
```

## Target

The accessory fades in with its height expanding on a spring, and fades out quietly:

```kotlin
val reducedMotion = rememberReducedMotion()
val accessoryEnterSpec = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
val accessoryExitSpec = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
val accessorySizeSpec = MaterialTheme.motionScheme.defaultSpatialSpec<IntSize>()

AnimatedVisibility(
    visible = accessory != null,
    enter = if (reducedMotion) fadeIn(tween(250))
            else fadeIn(accessoryEnterSpec) +
                 expandVertically(animationSpec = accessorySizeSpec, clip = false),
    exit = if (reducedMotion) fadeOut(tween(180))
           else fadeOut(accessoryExitSpec),   // exits subtler: fade only, no shrink race with the step swap
) {
    Box(/* same modifiers as current */) { lastAccessory?.invoke() }
}
```

Because `accessory` is a nullable composable lambda, keep the last non-null value in a local (`var lastAccessory = accessory` before the block, updated inside when non-null — the `InlineNoticeHost` remember-last pattern at `InlineNotice.kt:117-118`) so the exit fade renders content, not a blank.

Note: exit deliberately has no `shrinkVertically` — the accessory leaves only during a step swap, when the incoming stage is already materializing; a height collapse there reads as the chassis lurching. If the feel check shows a hard height snap on exit instead, add `shrinkVertically(accessorySizeSpec, clip = false)` and re-check.

## Repo conventions to follow

- Spec capture before non-composable lambdas: `OnboardingChassis.kt:244-253` (the slot swap right below this site — same three specs).
- `clip = false` on size animations (`Buttons.kt:347`, `OnboardingChassis.kt:263`).
- The chassis **container** never animates (`OnboardingChassis.kt:47-65` header comment, binding) — this plan animates content *inside* the chassis, same as the slots already do. Do not contradict that comment; extend it with one line noting the accessory fades.

## Steps

1. `OnboardingChassis.kt:176-185` — replace the `if` with the `AnimatedVisibility` above; add the remember-last local; hoist the three specs + `rememberReducedMotion()` next to the existing slot specs.
2. Extend the header comment (`:47-65`) with the accessory rule.

## Boundaries

- Do NOT animate the CTA slot column or touch `ChassisSlot`.
- Do NOT add lateral motion or scale — fade + height only (`:47-65`: nothing in the chassis moves laterally).
- If the accessory block has moved (drift since f54a829c), STOP and report.

## Verification

- **Mechanical**: `cd android && ./gradlew :app:compileDebugKotlin`; `:app:validateDebugScreenshotTest` (chassis layout goldens exist — `OnboardingChassisLayoutComposeTest`); the settled height must be pixel-identical.
- **Feel check**: navigate Welcome → seed step: the warning + acknowledge block fades in while the chassis grows on a spring, in step with the slot cross-fades. Navigate back: it fades out without the CTAs jumping. `animator_duration_scale 0`: fade only. Slow-motion (`scale 5`): accessory and slots read as one chassis re-composition, not two mechanisms.
- **Done when**: no hard pop on the accessory in either direction, settled layout unchanged.
