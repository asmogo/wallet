# 006 — Android stage swap: exit-side blur and entrance overlap

- **Status**: TODO
- **Commit**: f54a829c
- **Severity**: MEDIUM
- **Category**: Easing & sequencing / platform parity — carries a charter tension; feel-check gates the second half
- **Estimated scope**: 1 file (`OnboardingScreen.kt`), plus `Materialize.kt` read-only reference

## Problem

The brief's binding motion table (`docs/product/onboarding-restyle-brief.md` §5) defines the stage swap as: **out** = "blur 0→6, opacity 1→0, ~180 ms ease-out"; **in** = "scale 0.96→1, blur 6→0, opacity 0→1, ~280 ms; overlap the tail of *out* by ~80 ms". iOS ships exactly that (`OnboardingView.swift:275-286` — removal carries `materializeBlur(radius: 6)`, insertion is delayed 0.10 s). The blur riding *both* halves is the technique: blurred, outgoing and incoming blend into one object transforming; one-sided, the eye resolves two overlapping states (`OnboardingChassis.swift:152-160` documents this for the same pattern).

Android's swap has neither the exit blur nor the overlap — enter and exit both start at t = 0 and the outgoing stage only fades:

```kotlin
// android/.../ui/onboarding/OnboardingScreen.kt:529-552 — current
transitionSpec = {
    if (reducedMotion) {
        fadeIn(tween(250)).togetherWith(fadeOut(tween(180)))
    } else {
        (
            fadeIn(stageEnterSpec) +
                scaleIn(animationSpec = stageScaleSpec, initialScale = 0.96f)
            )
            .togetherWith(fadeOut(stageExitSpec))
    }
},
...
val enteredViaTransition = remember { transition.currentState != transition.targetState }
val stageModifier = if (enteredViaTransition) {
    Modifier
        .fillMaxSize()
        .materializeBlur()   // enter-side only; 4dp -> 0 spring (Materialize.kt:43-63)
} else {
    Modifier.fillMaxSize()
}
```

## Target

**Part A — exit blur (do unconditionally).** The outgoing stage blurs as it fades, using the existing scope-aware primitive `AnimatedVisibilityScope.morphBlur` (`android/.../ui/components/Materialize.kt:89-107`), which animates blur on *both* enter and exit keyed on `EnterExitState.Visible` — it exists for exactly this and is already used by the chassis capsule morph. Inside the stage `AnimatedContent` content lambda, replace the enter-only `materializeBlur()` with `morphBlur(4.dp)` (the scope receiver is available there). Keep 4 dp — it is Android's established materialize radius (`Materialize.kt` default; `SlotMorphBlur = 3.dp` for the chassis); the brief's "6" is iOS's expression, and DESIGN-ANDROID's charter says intent, not literal values, must match. `morphBlur` is already API-31- and reduce-motion-gated internally.

Preserve the cold-launch guard: on first composition `currentState == targetState`, so `morphBlur` starts at rest (blur 0) — but verify the first frame stays sharp in the screenshot tests before deleting `enteredViaTransition`; if in doubt, keep the guard and apply `morphBlur` only on the `enteredViaTransition` branch.

**Part B — entrance overlap (feel-check gated).** iOS delays the insertion 100 ms so the entrance overlaps only the exit's tail. Compose spring specs cannot delay; the only faithful expression is a delayed tween on the enter pair:

```kotlin
fadeIn(tween(durationMillis = 280, delayMillis = 100, easing = FastOutSlowInEasing)) +
    scaleIn(tween(280, delayMillis = 100, easing = FastOutSlowInEasing), initialScale = 0.96f)
```

This trades the expressive-spring charter (`docs/android/DESIGN-ANDROID.md`: "MotionScheme.expressive() springs rather than hand-tuned tweens") for the brief's ordering intent ("the intent (duration feel, **ordering**, stagger stride) is what must match"). The two documents conflict here; the reduce-motion branch already uses tweens, so a tween is not unprecedented. **Implement Part B behind a side-by-side feel check** (see Verification): if the simultaneous-start spring version with Part A's blur added already reads as "old dissolves, new materializes" rather than a double-exposure, keep springs and record that decision in the code comment; otherwise land the delayed tween and note the charter exception in the comment block at `:523-528`.

## Repo conventions to follow

- `morphBlur` exemplar: chassis capsule content (`OnboardingChassis.kt:286` via `Box(...).then(morphBlur(SlotMorphBlur))`).
- The transition comment block at `OnboardingScreen.kt:523-528` documents the swap's rationale — update it to describe whatever ships (it currently says "the outgoing stage just fades").
- Reduce-motion branch stays exactly as-is (`fadeIn(tween(250)) / fadeOut(tween(180))`, no blur, no scale).

## Steps

1. `OnboardingScreen.kt:545-552` — swap `materializeBlur()` for `morphBlur(4.dp)` (import from `com.cashu.me.ui.components`); decide on the `enteredViaTransition` guard per Part A.
2. Run the feel check for Part B; implement the delayed tween only if the check fails, updating the comment block either way.
3. Update the `:523-528` comment to match shipped behavior.

## Boundaries

- Do NOT change the reduce-motion branch, the `AnimatedContent` key, or stage content.
- Do NOT alter `Materialize.kt` — both primitives are correct.
- Do NOT exceed 4 dp blur or 100 ms delay — no "more is better" tuning.
- If `morphBlur`'s signature or the transitionSpec has drifted, STOP and report.

## Verification

- **Mechanical**: `cd android && ./gradlew :app:compileDebugKotlin && ./gradlew :app:validateDebugScreenshotTest` (regenerate baselines if the swap's mid-states are captured; the cold-launch first frame MUST remain pixel-identical — that's the guard's contract).
- **Feel check** (the gate for Part B):
  - `adb shell settings put global animator_duration_scale 5`, then advance Welcome → seed → first mint and back. Watch the crossfade midpoint: with Part A alone, do the two stages blend (both soft) or double-expose (incoming sharp over outgoing text)? Compare against iOS Simulator doing the same transition.
  - With Part B applied: the outgoing stage should be mostly gone before the incoming one is prominent; total swap should not feel slower than today.
  - Reset `animator_duration_scale 1`; set `0` and confirm plain crossfade, no blur, no scale.
- **Done when**: exit blur ships; the overlap decision (spring-as-is vs delayed tween) is made from the side-by-side and recorded in the comment block; screenshots stable.
