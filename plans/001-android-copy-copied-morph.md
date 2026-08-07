# 001 — Animate the seed step's Copy → Copied swap (Android)

- **Status**: TODO
- **Commit**: f54a829c
- **Severity**: MEDIUM
- **Category**: Cohesion / platform parity (feedback animation)
- **Estimated scope**: 2 files, ~15 lines

## Problem

On the Android seed-phrase step, tapping **Copy** hard-cuts both the label ("Copy" → "Copied") and the leading icon (copy glyph → check) with zero transition — at the exact moment the user is staring at the button. iOS morphs both (`ios/CashuWallet/Views/Main/OnboardingView.swift:973-977` uses `.contentTransition(.symbolEffect(.replace))` on the icon and `.contentTransition(.opacity)` + `.animation(.snappy, value: seedCopied)` on the label).

```kotlin
// android/app/src/main/java/com/cashu/me/ui/onboarding/OnboardingScreen.kt:1016-1030 — current
GhostButton(
    text = if (copied) "Copied" else "Copy",
    leadingIcon = if (copied) Icons.Filled.Check else Icons.Outlined.ContentCopy,
    onClick = {
        clipboard.setText(AnnotatedString(words.joinToString(" ")))
        copied = true
        scope.launch {
            delay(3_000)
            copied = false
        }
    },
    // The card edge already separates the link from the words, so
    // the total gap is 16 (snug + snug), not the bare grid's 20.
    modifier = Modifier.padding(top = CashuTheme.spacing.snug),
)
```

`GhostButton` already has an opt-in animated label (`android/app/src/main/java/com/cashu/me/ui/components/Buttons.kt:304` — `animatedLabel: Boolean = false`; the AnimatedContent cross-fade lives at `Buttons.kt:331-355`), but this call site doesn't opt in. Even with it on, the leading icon would still hard-cut, because the icon is drawn *outside* the label's `AnimatedContent`:

```kotlin
// android/app/src/main/java/com/cashu/me/ui/components/Buttons.kt:323-330 — current
if (leadingIcon != null) {
    Icon(
        imageVector = leadingIcon,
        contentDescription = null,
        modifier = Modifier.size(GhostButtonIconSize),
    )
    Spacer(Modifier.width(CashuTheme.spacing.tight))
}
```

## Target

- The call site passes `animatedLabel = true` — label cross-fades with the width size-spring GhostButton already implements.
- When (and only when) `animatedLabel` is true, the leading icon animates through the app's existing `IconSwap` component (`android/app/src/main/java/com/cashu/me/ui/components/IconSwap.kt:36-64`): outgoing icon fades on `spring(stiffness = Spring.StiffnessMedium)`, incoming fades in + scales from `0.8f` on the same spring. `IconSwap` is documented as "the Compose equivalent of iOS `.contentTransition(.symbolEffect(.replace))`" and is already used for exactly this pattern (copy-confirm checks — see its doc comment).

No new specs, no new components — this is pure wiring of existing vocabulary.

## Repo conventions to follow

- Glyph replacement = `IconSwap` (`IconSwap.kt:36`). Exemplar call: `OnboardingScreen.kt:929-938` (the acknowledge row's circle ↔ filled check).
- Motion-scheme specs in `GhostButton` are captured into locals outside the non-composable `transitionSpec` lambda (`Buttons.kt:308-311`) — don't move them.
- Compose animations honor the system animator duration scale, so reduce-motion (scale 0) degrades to an instant swap automatically; no explicit gate needed here (matches `IconSwap`'s other call sites).

## Steps

1. `android/app/src/main/java/com/cashu/me/ui/onboarding/OnboardingScreen.kt:1016` — add `animatedLabel = true` to the `GhostButton(...)` call shown above.
2. `android/app/src/main/java/com/cashu/me/ui/components/Buttons.kt:323-330` — branch the leading-icon block on `animatedLabel`:

```kotlin
if (leadingIcon != null) {
    if (animatedLabel) {
        IconSwap(
            icon = leadingIcon,
            contentDescription = null,
            iconSize = GhostButtonIconSize,
        )
    } else {
        Icon(
            imageVector = leadingIcon,
            contentDescription = null,
            modifier = Modifier.size(GhostButtonIconSize),
        )
    }
    Spacer(Modifier.width(CashuTheme.spacing.tight))
}
```

(`IconSwap` is in the same package `com.cashu.me.ui.components`; no import needed.)

## Boundaries

- Do NOT change `GhostButton`'s default behavior — `animatedLabel` stays `false` by default, so every other caller is untouched.
- Do NOT touch the trailing-icon path or any other button style.
- Do NOT add a scale/bounce beyond `IconSwap`'s built-in `0.8f` entrance.
- If the code at the cited lines doesn't match the excerpts (drift since f54a829c), STOP and report.

## Verification

- **Mechanical**: `cd android && ./gradlew :app:compileDebugKotlin` — compiles clean.
- **Feel check** (fresh install → onboarding → seed step):
  - Tap **Copy**: the check glyph grows in from 0.8 while the copy glyph fades; the label cross-fades and the button width springs to the shorter "Copied" without clipping.
  - Spam-tap Copy: transitions retarget mid-flight (AnimatedContent), never restart from blank.
  - After the 3 s revert, the swap back is equally smooth.
  - `adb shell settings put global animator_duration_scale 0` → swap is instant, no half-rendered frames. (Restore with `... 1`.)
- **Done when**: both glyph and label animate on copy and on the 3 s revert, and no other GhostButton caller changes appearance.
