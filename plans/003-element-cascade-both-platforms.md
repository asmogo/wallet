# 003 — Implement the spec'd 70 ms element cascade (iOS + Android)

- **Status**: TODO
- **Commit**: f54a829c
- **Depends on**: plan 002 (Android `riseIn` wiring at headers)
- **Severity**: MEDIUM
- **Category**: Cohesion (spec'd stagger unused) + missed opportunity (mint-list cascade)
- **Estimated scope**: 2 files (`OnboardingView.swift`, `OnboardingScreen.kt`), ~10 sites

## Problem

The shared spec (`docs/product/onboarding-restyle-brief.md` §5) commits both platforms to an "element cascade inside a stage — 70 ms stride, reusing the existing stagger helper." Neither platform ships it:

- **iOS**: all 8 `stagger()` calls pass `index: 0` (`OnboardingView.swift:541, 633, 709, 886, 1062, 1297, 1393, 1569` — verified by grep), so only headers rise and everything below enters as one slab.
- **Android**: has no cascade at all (plan 002 adds the header at index 0; this plan adds the following blocks).

The stride tokens already agree across platforms and sit unused: iOS `.delay(Double(index) * 0.07)` (`OnboardingView.swift:331`), Android `CashuMotion.StaggerStepMs = 70` consumed via `riseIn`'s `delayMillis = index * CashuMotion.StaggerStepMs` (`Motion.kt:84-88`).

Current iOS exemplar of the pattern (first mint step — header staggered, list not):

```swift
// ios/CashuWallet/Views/Main/OnboardingView.swift:1062-1071 — current
stagger(appeared: firstMintAppeared, index: 0) {
    OnboardingStepHeader(
        title: "Pick your first mint.",
        subhead: "Mints issue your ecash and redeem it for Bitcoin. Add more anytime in Settings."
    )
}
.padding(.top, OnboardingMetrics.titleGap)

firstMintList
    .padding(.top, 16)
```

## Target

Cascade **only where it earns its place** — onboarding is a rare, first-run flow with a delight budget, but stagger is decorative and must never block interaction. Per stage, both platforms, indices at a 70 ms stride:

| Stage | index 0 | index 1 | index 2+ |
| --- | --- | --- | --- |
| First mint | header (exists) | first recommended-mint row | remaining recommended rows (one index each; the "Add custom mint URL" link takes the next index after the last row) |
| Restore input (seed entry) | header (exists) | the seed input field/card | — |
| Restore mints | header (exists) | the add/paste controls block | staged-mint list container (one index for the whole list) |
| Restore progress | header (exists) | recovered-total hero | progress-rows container (one index) |

Welcome and Restore-method stay header-only (their content below the header is the ASCII field + chassis CTAs — neither cascades). The seed step stays header-only on both platforms: Android documents "the seed grid deliberately gets NO entrance motion" (`OnboardingScreen.kt:993-996`); mirror that restraint on iOS.

Rows added *after* entry (e.g. a custom mint committed later) must not replay the rise: both helpers animate on the `appeared` value change only, and late-mounted rows compose with `appeared == true`, so they mount at rest automatically — rely on that, don't special-case.

Cap: no index above 5 (last start ≤ 350 ms) — if a list is longer, remaining rows share the last index.

## Repo conventions to follow

- iOS: `stagger(appeared:index:)` (`OnboardingView.swift:326-332`) — no opacity, offset 12, blur 3, `.smooth(0.4)`, reduce-motion drops rise+blur. The `appeared` flags and `resetAppeared(for:)` (`OnboardingView.swift:302-313`) already exist per step — reuse them, add no new state.
- Android: `Modifier.riseIn(appeared, index)` + the same `appeared` local introduced by plan 002. Reduce-motion is handled inside `riseIn`.
- Android boundary from `docs/android/DESIGN-ANDROID.md`: onboarding-exempt motion must not leak into the wallet proper. `RestoreWalletFlow.kt` composables are shared with the in-app Settings restore — so on Android, apply `riseIn` **at the onboarding call sites in `OnboardingScreen.kt`** (wrapping the shared block as one unit), never inside `RestoreWalletFlow.kt` bodies.

## Steps

1. **iOS first mint** (`OnboardingView.swift:1079-1090`, `firstMintList`): wrap each recommended-mint row in `stagger(appeared: firstMintAppeared, index: 1 + rowIndex)` (the `ForEach` at `:1084` already enumerates — use `min(1 + index, 5)`), and the "Add custom mint URL" button in the next index. Do not wrap `customMintInputRow` (it has its own insert transition at `:1095`).
2. **iOS restore input** (stage at `:1297`): wrap the seed input block (the view immediately following the staggered header in that stage's VStack) in `stagger(appeared: restoreInputAppeared, index: 1)`.
3. **iOS restore mints** (stage at `:1393`): controls block index 1, staged list container index 2, same `restoreMintsAppeared`.
4. **iOS restore progress** (stage at `:1569`): recovered-total hero index 1, rows container index 2, same `restoreProgressAppeared`.
5. **Android**: mirror steps 1–4 in `OnboardingScreen.kt` with `.riseIn(appeared, index = N)` on the corresponding blocks (first-mint rows are local to `OnboardingScreen.kt` — per-row indices; the restore stages call shared `RestoreWalletFlow` composables — give each *call site* one index as a unit).
6. Leave Welcome, Restore-method, and the seed step untouched on both platforms.

## Boundaries

- Do NOT add opacity to either helper — the step crossfade owns the fade on both platforms (documented at `OnboardingView.swift:321-325` and `Motion.kt:70-74`).
- Do NOT stagger inside `RestoreWalletFlow.kt` (Android) — call-site wrapping only.
- Do NOT cascade the seed grid, the chassis, or anything the user must tap within the first 100 ms (chassis CTAs are outside the stages and stay put).
- Do NOT change list data flow or row markup — modifier wrapping only.
- If a stage's structure doesn't match the description (drift since f54a829c), STOP on that stage and report; finish the others.

## Verification

- **Mechanical**: iOS — build the CashuWallet scheme (`xcodebuild -project ios/CashuWallet.xcodeproj -scheme CashuWallet build` or via Xcode), no errors. Android — `./gradlew :app:compileDebugKotlin`.
- **Feel check** (both platforms, both branches):
  - First mint: rows settle top-to-bottom, ~70 ms apart, done within ~350 ms; tapping a row mid-cascade still selects it instantly.
  - Restore progress: header → total → rows reads as one composed entrance, not three unrelated pops.
  - Committing a custom mint later does NOT replay any rise.
  - Reduce Motion (iOS Settings > Accessibility > Motion; Android `animator_duration_scale 0`): everything renders at rest, stage crossfade only.
  - iOS Simulator > Debug > Slow Animations: confirm no opacity double-fade (blocks move/blur but never fade independently of the stage).
- **Done when**: the cascade is visible on the four stages, absent on the three excluded ones, identical stride on both platforms, and interaction is never gated on it.
