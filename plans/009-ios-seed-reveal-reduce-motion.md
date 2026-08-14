# 009 — Gate the iOS seed-reveal blur under Reduce Motion

- **Status**: TODO
- **Commit**: f54a829c
- **Severity**: LOW
- **Category**: Accessibility (flow rule: reduced-motion paths are opacity-or-nothing)
- **Estimated scope**: 1 file (`OnboardingView.swift`), 1 function

## Problem

Tapping the seed card animates its blur 9 → 0 over 0.25 s. With Reduce Motion on, the animation still runs — the only motion site in the flow that isn't gated. The onboarding brief's rule (`docs/product/onboarding-restyle-brief.md`, top of §5): reduced-motion paths are opacity-or-nothing, checked "at every motion site in this flow".

```swift
// ios/CashuWallet/Views/Main/OnboardingView.swift:925-926 — context (unchanged by this plan)
.redacted(reason: seedRevealed ? [] : .placeholder)
.blur(radius: seedRevealed ? 0 : 9)

// OnboardingView.swift:1011-1016 — current (the un-gated animation)
private func toggleSeedReveal() {
    HapticFeedback.selection()
    withAnimation(.snappy(duration: 0.25)) {
        seedRevealed.toggle()
    }
}
```

(Security note from the surrounding comment at `:918-924`: redaction, not the blur, protects the words — no animation timing can leak them. Gating the animation is purely a motion-preference fix.)

## Target

```swift
// target
private func toggleSeedReveal() {
    HapticFeedback.selection()
    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
        seedRevealed.toggle()
    }
}
```

Under Reduce Motion the reveal becomes an instant swap (blur 9 → 0 with no interpolation); otherwise unchanged.

## Repo conventions to follow

- `@Environment(\.accessibilityReduceMotion) private var reduceMotion` is already declared in this view (`OnboardingView.swift:5`).
- Exact exemplar of this pattern in the same file: `OnboardingView.swift:667` — `withAnimation(reduceMotion ? nil : .snappy) { ... }`.

## Steps

1. `OnboardingView.swift:1013` — change `withAnimation(.snappy(duration: 0.25))` to `withAnimation(reduceMotion ? nil : .snappy(duration: 0.25))`.

## Boundaries

- Do NOT touch the blur radius, the redaction, the haptic, or the hide-direction behavior.
- Nothing else in this file.

## Verification

- **Mechanical**: build the CashuWallet scheme — clean.
- **Feel check**: Settings > Accessibility > Motion > Reduce Motion ON → tapping the seed card swaps instantly (no blur resolve); OFF → the 0.25 s resolve is unchanged. VoiceOver reveal action (`:945`) behaves identically.
- **Done when**: the one-line change ships and both states behave as above.
