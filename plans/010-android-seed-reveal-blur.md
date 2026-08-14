# 010 — Animate the Android seed reveal (show direction only)

- **Status**: TODO
- **Commit**: f54a829c
- **Severity**: LOW
- **Category**: Platform parity (reveal hard-cuts; iOS resolves from blur) — feel-check gated
- **Estimated scope**: 1 file (`OnboardingScreen.kt`), 1 site

## Problem

Tapping the Android seed card hard-cuts between masked and revealed. iOS resolves the blur 9 → 0 over 0.25 s on reveal, with the un-redact masked under the blur (`OnboardingView.swift:918-926, 1011-1016`). The **hide** direction's hard cut on Android is documented and deliberate — keep it:

```kotlin
// android/.../ui/onboarding/OnboardingScreen.kt:963-970 — current (comment is binding for hide)
// Tapping the card toggles the phrase, like iOS — the seed should be easy
// to put away once it's been written down, not stuck on screen for the
// rest of the step. Hiding re-composes the "••••••" placeholders, so the
// real words stop being drawn on the same frame the blur returns.
fun toggleReveal() {
    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
    revealed = !revealed
}

// OnboardingScreen.kt:1161 — current (static blur; SeedBlurRadius = 9.dp at :149)
.then(if (revealed) Modifier else Modifier.blur(SeedBlurRadius))
```

On reveal, the placeholders swap to real words and the 9 dp blur vanishes in one frame — a flicker where iOS has a resolve.

## Target

Asymmetric blur animation — animated on reveal, snapped on hide (preserving the same-frame masking contract):

```kotlin
// target — replaces the .then(...) at :1161
val reducedMotion = rememberReducedMotion()
val blurRadius by animateDpAsState(
    targetValue = if (revealed) 0.dp else SeedBlurRadius,
    animationSpec = if (revealed && !reducedMotion) {
        tween(durationMillis = 250, easing = FastOutSlowInEasing)   // reveal: resolve like iOS .snappy(0.25)
    } else {
        snap()                                                       // hide (and reduce-motion): same-frame, as documented
    },
    label = "seed-reveal-blur",
)
...
.then(if (blurRadius > 0.dp) Modifier.blur(blurRadius) else Modifier)
```

Word content still swaps instantly (placeholders ↔ real words on the `revealed` flip) — on reveal the real words compose on frame 0 *under* the 9 dp blur and resolve, exactly iOS's "un-redact masked under that blur". On hide, `snap()` returns the full blur the same frame the placeholders come back — the documented contract holds.

API note: `Modifier.blur` is a no-op below API 31 (already true of the static blur today) — behavior there remains today's hard cut. That is acceptable; do not add a fallback.

## Repo conventions to follow

- `SeedBlurRadius` (`OnboardingScreen.kt:149`) stays the single source of the radius.
- Reduce-motion: `rememberReducedMotion()` (`Motion.kt:102-128`) → snap both directions (opacity-or-nothing rule, `DESIGN-ANDROID.md`).
- Keep the `:963-966` comment and extend it: hide snaps by design; reveal resolves.

## Steps

1. `OnboardingScreen.kt` — inside the composable that applies the blur at `:1161` (`SeedPhraseReveal`'s card), hoist `revealed` handling to add the `animateDpAsState` above and swap the static `.blur(SeedBlurRadius)` for the animated form. (`revealed` is passed in — the animate state lives next to where the modifier is built.)
2. Update the comment block.

## Boundaries

- Do NOT animate the placeholder ↔ word text swap, the redaction semantics, or TalkBack behavior (`:1036-1039` masking semantics stay).
- Do NOT animate the hide direction.
- Do NOT change `SeedBlurRadius`.
- If the blur site has drifted, STOP and report.

## Verification

- **Mechanical**: `cd android && ./gradlew :app:compileDebugKotlin`; screenshot goldens for the seed step must be unchanged at rest (`:app:validateDebugScreenshotTest`).
- **Feel check — this plan is feel-gated** (code review can't judge a blur resolve): on an API 31+ device, tap to reveal at `animator_duration_scale 5` — words should *resolve* out of the blur with no placeholder flash mid-animation. If placeholders visibly linger under the blur before the swap (they shouldn't — the swap is frame 0), or the resolve reads as smearing rather than focusing, report back with a screen recording instead of shipping. Hide: still an instant cut. Reduce-motion: instant both ways.
- **Done when**: reveal resolves like iOS side-by-side, hide is unchanged, and the recording is attached to the PR (repo convention: UI PRs need matched visual evidence).
