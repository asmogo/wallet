# 008 — Reduce-motion gate the Android app-gate transition

- **Status**: TODO
- **Commit**: f54a829c
- **Severity**: LOW
- **Category**: Accessibility (ungated scale under reduce-motion)
- **Estimated scope**: 1 file (`CashuApp.kt`), 1 site

## Problem

The root gate that cross-fades Loading → Onboarding → Shell always runs a `scaleIn(0.98)` fade-through, with no reduce-motion branch. `docs/android/DESIGN-ANDROID.md` requires onboarding motion to degrade to opacity-or-nothing, and every other motion site in the flow is gated. The iOS twin is opacity-only (`ContentView.swift:18-32`, `.transition(.opacity)` + `.easeInOut(0.35)`), so the scale is also a small parity divergence.

```kotlin
// android/app/src/main/java/com/cashu/me/ui/shell/CashuApp.kt:235-242 — current
AnimatedContent(
    targetState = gate,
    transitionSpec = {
        (fadeIn(spring(stiffness = Spring.StiffnessMedium)) +
            scaleIn(initialScale = 0.98f, animationSpec = spring(stiffness = Spring.StiffnessMedium)))
            .togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
    },
    label = "app-gate",
)
```

## Target

Keep the default fade-through exactly as-is; under reduce-motion, plain crossfade:

```kotlin
val reducedMotion = rememberReducedMotion()
...
transitionSpec = {
    if (reducedMotion) {
        fadeIn(tween(250)).togetherWith(fadeOut(tween(180)))
    } else {
        (fadeIn(spring(stiffness = Spring.StiffnessMedium)) +
            scaleIn(initialScale = 0.98f, animationSpec = spring(stiffness = Spring.StiffnessMedium)))
            .togetherWith(fadeOut(spring(stiffness = Spring.StiffnessMedium)))
    }
},
```

Fallback tween values 250/180 are the flow's established RM crossfade (`OnboardingScreen.kt:530-531`).

## Repo conventions to follow

- `rememberReducedMotion()` from `com.cashu.me.ui.theme.Motion` (`Motion.kt:102-128`) — call it in the composable scope above `AnimatedContent` (the `transitionSpec` lambda is not composable).
- RM-branch exemplar: the stage swap at `OnboardingScreen.kt:529-538`.

## Steps

1. `CashuApp.kt` — add `val reducedMotion = rememberReducedMotion()` near the `gate` computation (`:229-233`); import `com.cashu.me.ui.theme.rememberReducedMotion`.
2. Branch the `transitionSpec` as shown.

## Boundaries

- Do NOT remove the scale from the default branch (fade-through is a deliberate Material pattern here; only the RM path changes).
- Do NOT touch the nav host or sheet transitions below this in the file.
- If the transitionSpec has drifted, STOP and report.

## Verification

- **Mechanical**: `cd android && ./gradlew :app:compileDebugKotlin`.
- **Feel check**: complete onboarding with `animator_duration_scale 0` (or the Remove-animations accessibility toggle) → the handoff into the wallet is a plain instant/fade swap with no scale; with scale `1`, behavior is unchanged from today. Toggling the setting mid-session takes effect without restart (`rememberReducedMotion` observes the setting).
- **Done when**: RM path is opacity-only; default path byte-identical in feel.
