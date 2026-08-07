# 004 — Animate Android restore progress: row phases + rolling total

- **Status**: TODO
- **Commit**: f54a829c
- **Severity**: MEDIUM
- **Category**: Purpose/state indication + platform parity; includes the restore-completion delight moment
- **Estimated scope**: 1 file (`RestoreWalletFlow.kt`), 2 composables

## Problem

The restore-progress screen is the emotional payoff of the restore branch — the user watches their money come back — and on Android every state change hard-cuts. iOS animates all of it: per-row phase flips ride `withAnimation(.snappy)` (`OnboardingView.swift:1867-1886`), the result glyph morphs via `.contentTransition(.symbolEffect(.replace))` (`:1655`), and the recovered total rolls with `.contentTransition(.numericText(value:))` (`:1585`).

```kotlin
// android/app/src/main/java/com/cashu/me/ui/restore/RestoreWalletFlow.kt:1084-1092 — current (trailing slot)
when (phase) {
    RestoreMintPhase.Pending, RestoreMintPhase.Restoring -> {
        // Expressive loader per DESIGN-ANDROID.md §1 — the classic
        // circular spinner is reserved for nothing.
        LoadingIndicator(
            modifier = Modifier.size(ProgressSpinnerSize),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
    is RestoreMintPhase.Recovered -> { /* Icon + "N sats" Row */ }
    is RestoreMintPhase.Failed -> { GhostButton(text = "Retry", onClick = onRetry) }
}
```

```kotlin
// RestoreWalletFlow.kt:894-900 — current (total): a plain Text that jumps
Text(
    text = "Recovered: $totalRecovered sats",
    style = MaterialTheme.typography.bodyMedium
        .copy(fontWeight = FontWeight.SemiBold)
        .withMonoDigits(),
    color = CashuTheme.colors.received,
)
```

Note: `RestoreWalletFlow.kt` is shared between onboarding and the in-app Settings restore. That is fine here — this plan uses only the app's standard motion vocabulary (`IconSwap`-style swaps, motion-scheme springs), not onboarding-exempt motion, so both contexts improving together is correct and matches iOS.

## Target

1. **Row trailing slot**: wrap the `when (phase)` content in `AnimatedContent` keyed on the phase, spec matching the app's slot-morph convention:
   - enter: `fadeIn(motionScheme.defaultEffectsSpec()) + scaleIn(motionScheme.defaultSpatialSpec(), initialScale = 0.8f)` (the `IconSwap` entrance scale)
   - exit: `fadeOut(motionScheme.fastEffectsSpec())` (exits subtler than entrances, DESIGN.md §6)
   - `.using(SizeTransform(clip = false) { _, _ -> motionScheme.defaultSpatialSpec<IntSize>() })` so spinner → "1 234 sats" → "Retry" width changes spring instead of jumping
   - `contentAlignment = Alignment.CenterEnd` so content stays pinned to the row's trailing edge.
2. **Rolling total**: animate `totalRecovered` with a numericText-like vertical roll:

```kotlin
AnimatedContent(
    targetState = totalRecovered,
    transitionSpec = {
        if (targetState > initialState) {
            (slideInVertically(enterSpec) { it / 3 } + fadeIn(enterSpec))
                .togetherWith(slideOutVertically(exitSpec) { -it / 3 } + fadeOut(exitSpec))
        } else {
            (slideInVertically(enterSpec) { -it / 3 } + fadeIn(enterSpec))
                .togetherWith(slideOutVertically(exitSpec) { it / 3 } + fadeOut(exitSpec))
        }.using(SizeTransform(clip = false) { _, _ -> sizeSpec })
    },
    label = "recovered-total",
) { total -> Text(text = "Recovered: $total sats", /* styles exactly as current */) }
```

   with `enterSpec = motionScheme.defaultEffectsSpec<Float>()`, `exitSpec = motionScheme.fastEffectsSpec<Float>()`, `sizeSpec = motionScheme.defaultSpatialSpec<IntSize>()`, all captured outside the `transitionSpec` lambda. Digits roll upward as the number grows — the closest Compose expression of iOS `.numericText`.

Reduce-motion: Compose scales these to instant via the system animator scale; additionally the specs must not slide under reduce motion — branch on `rememberReducedMotion()` to plain `fadeIn(tween(250)).togetherWith(fadeOut(tween(180)))` for both AnimatedContents (matching the stage-swap RM branch at `OnboardingScreen.kt:530-531`).

## Repo conventions to follow

- Capture motion-scheme specs into locals before `transitionSpec` (pattern at `OnboardingChassis.kt:244-253`, `Buttons.kt:308-311` — the comment "Captured outside the non-composable transitionSpec lambda").
- `SizeTransform(clip = false)` everywhere a morph changes width (`Buttons.kt:347`, `OnboardingChassis.kt:263`).
- Reduce-motion source: `rememberReducedMotion()` from `com.cashu.me.ui.theme.Motion` (`Motion.kt:102-128`).
- Exit-subtler-than-entrance: fast spec out, default spec in — every morph in the app does this.

## Steps

1. `RestoreWalletFlow.kt` — in `RestoreProgressRow` (the composable containing the `when (phase)` at `:1084`), capture the four specs + `rememberReducedMotion()` as locals, and wrap the `when` in the `AnimatedContent` described above. Key on the phase value itself (`RestoreMintPhase` is the natural key; `Recovered` carries its result so re-keying on data change is correct).
2. In `RestoreRecoveredTotal` (`:875-905`), wrap the `Text` in the rolling `AnimatedContent`; keep the check icon static (it's constant). Keep all current text styles/colors verbatim.
3. Reduce-motion branches per the Target section.

## Boundaries

- Do NOT introduce onboarding-only motion (no `riseIn`, no stage-swap specs) into this shared file.
- Do NOT change phase semantics, retry wiring, row layout, or the `LoadingIndicator` (DESIGN-ANDROID §1 reserves the classic spinner "for nothing" — keep the expressive loader).
- Do NOT add a celebration flourish beyond the rolling total — the success haptic is plan 011's job.
- If the `when (phase)` or total composable has moved (drift since f54a829c), STOP and report.

## Verification

- **Mechanical**: `cd android && ./gradlew :app:compileDebugKotlin`.
- **Feel check** (restore a wallet with 2+ mints; a Testnut mint per the repo's README screenshot workflow works):
  - Each row's spinner dissolves as the check + sats grow in from 0.8; the trailing edge stays pinned; width springs, never jumps.
  - The running total rolls upward digit-block by digit-block as mints settle — watch in slow motion (`adb shell settings put global animator_duration_scale 5`, restore with `1`).
  - Fail a mint (airplane-mode one mid-restore): spinner → Retry morphs the same way; tapping Retry morphs back to the spinner.
  - `animator_duration_scale 0`: all swaps instant, no sliding.
  - Also open Settings → restore (the in-app context) and confirm the same motion — this file is shared and both contexts should improve.
- **Done when**: no hard cut remains on the progress screen, the total rolls, and iOS/Android read as the same moment side-by-side.
