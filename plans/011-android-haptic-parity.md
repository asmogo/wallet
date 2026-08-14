# 011 — Android haptic parity for onboarding

- **Status**: TODO
- **Commit**: f54a829c
- **Severity**: LOW (missed opportunity — feel parity, near-zero motion risk)
- **Category**: Feedback / platform parity
- **Estimated scope**: 2 files (`OnboardingScreen.kt`, `RestoreWalletFlow.kt`), ~8 new call sites

## Problem

iOS onboarding fires ~20 haptics: `HapticFeedback.selection()` on every chassis CTA press, back/info buttons, seed acknowledge, copy, reveal, custom-mint reveal/commit, mint selection, restore retries (`OnboardingView.swift:354, 367, 395, 404, 501, 534, 601, 856, 1012, 1021, 1098, 1138, 1228, 1273, 1370, 1375, 1738, 1777`), and `HapticFeedback.notification(.success)` at the two completion moments (`:844` iCloud restore success, `:1267` first mint connected).

Android has 8 sites, all `HapticFeedbackType.TextHandleMove`: seed acknowledge (`OnboardingScreen.kt:475`), seed reveal (`:968`), mint select (`:1286`), and restore-input paste/clear/chips (`RestoreWalletFlow.kt:178, 412, 416, 453, 457`). Missing entirely: CTA presses, copy, custom-mint commit, retry, and any success feedback.

## Target

Add haptics at the Android counterparts, following the repo's convention of `LocalHapticFeedback.current.performHapticFeedback(...)` inside the click handler:

| Moment | Android site (f54a829c) | Type |
| --- | --- | --- |
| Chassis primary/secondary/tertiary action press | the step-advance/action lambdas built in `OnboardingScreen.kt` (`:319, :336, :390, :410` and siblings — every `OnboardingChassisAction` onClick) | `TextHandleMove` |
| Back / info bar buttons | `OnboardingBackButton` / info button onClick (`OnboardingChassis.kt`) | `TextHandleMove` |
| Copy seed | the `GhostButton` onClick at `OnboardingScreen.kt:1019-1026` | `TextHandleMove` |
| Custom mint URL commit | `state::commitCustomUrl` call site (`OnboardingScreen.kt:1335`) | `TextHandleMove` |
| Restore per-mint Retry | `GhostButton(text = "Retry", onClick = onRetry)` (`RestoreWalletFlow.kt:1132`) | `TextHandleMove` |
| Restore complete (all mints settled) | where the flow flips to its settled state in `RestoreWalletFlow.kt` state holder / the composable observing it | `Confirm` |
| First mint connected (success before leaving the step) | the success path of the add-mint action in `OnboardingScreen.kt` | `Confirm` |

`HapticFeedbackType.Confirm` exists in Compose UI 1.8+ (BOM here is 2026.05.00 — fine). If it somehow doesn't resolve, fall back to `LocalView.current.performHapticFeedback(HapticFeedbackConstants.CONFIRM)` (API 30+) — but prefer the Compose type.

One rule: haptic on user **action** or flow **completion**, never per-frame or per-row-settle (a 10-mint restore must not buzz 10 times — only the final settle Confirms).

## Repo conventions to follow

- Exemplar: `OnboardingScreen.kt:967-970` — `val haptics = LocalHapticFeedback.current` hoisted, `haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)` first line of the handler.
- `TextHandleMove` is the repo's chosen selection tick — do not introduce `LongPress`/`ContextClick` variants for these.
- Success moments get exactly one `Confirm`, mirroring iOS `.notification(.success)`.

## Steps

1. `OnboardingScreen.kt` — hoist `val haptics = LocalHapticFeedback.current` where missing (it already exists at `:204, :956, :1261`); add the `TextHandleMove` calls per the table (CTA lambdas, copy, custom-mint commit) and one `Confirm` on the first-mint success path.
2. `OnboardingChassis.kt` — back/info button handlers: add `TextHandleMove`.
3. `RestoreWalletFlow.kt` — Retry handler `TextHandleMove`; one `Confirm` where `allSettled` (or equivalent) becomes true — trigger from the state change observer (e.g. `LaunchedEffect(allSettled)`), not per row.
4. Verify no double-fire: chassis actions that also navigate must not buzz twice (one haptic per tap).

## Boundaries

- Do NOT add haptics to scrolling, cascades, or any animation callback — user actions and the two completion moments only.
- Do NOT change iOS.
- Do NOT add a settings toggle — the OS-level haptic settings govern, as everywhere else in the app.
- If a listed site has drifted, STOP on it and report; finish the others.

## Verification

- **Mechanical**: `cd android && ./gradlew :app:compileDebugKotlin`.
- **Feel check** (physical device — emulators don't render haptics): walk create + restore branches with a thumb on the glass. Every CTA tap ticks once; copy ticks; restore completion gives the distinct Confirm; a multi-mint restore buzzes exactly once at the end. Compare against iOS side-by-side for moment-parity, not waveform-parity.
- **Done when**: the table's rows all fire, nothing fires twice, and a full restore produces exactly one Confirm.
