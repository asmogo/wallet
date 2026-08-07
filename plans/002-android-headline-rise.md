# 002 — Wire the headline rise on every Android onboarding step

- **Status**: TODO
- **Commit**: f54a829c
- **Severity**: MEDIUM
- **Category**: Missed motion / platform parity (spec'd but unimplemented)
- **Estimated scope**: 2 files (`OnboardingScreen.kt`, possibly `RestoreWalletFlow.kt` — headers only), ~7 sites

## Problem

The shared onboarding motion spec (`docs/product/onboarding-restyle-brief.md` §5, the binding cross-platform table) says every step's headline enters with "y +10→0 … ~260 ms" and the element cascade reuses "the existing stagger helper". On iOS this ships: every stage header rises 12 pt with a 3 pt blur resolve (`OnboardingView.swift:326-332`, called at 8 sites). On Android, the twin primitive was built and promoted for exactly this purpose — and has **zero call sites** (verified by grep):

```kotlin
// android/app/src/main/java/com/cashu/me/ui/theme/Motion.kt:80-100 — current, UNUSED
/**
 * iOS onboarding entrance-stagger twin: content blocks rise 12dp into place,
 * 400ms, [CashuMotion.StaggerStepMs] per index. No opacity — the step
 * crossfade owns the fade, and doubling it flickers (binding onboarding
 * decision); no blur — `Modifier.blur` is API 31+ and the rise carries the
 * effect alone. Reduce-motion renders the resting state.
 * ...
 */
@Composable
fun Modifier.riseIn(appeared: Boolean, index: Int): Modifier { ... }

/** One-shot entrance trigger for [riseIn] call sites. */
@Composable
fun rememberAppeared(): Boolean { ... }
```

Result: Android headlines just cross-fade in with the stage — flat compared to iOS, and out of spec.

The seven header sites (all `OnboardingStepHeader(` calls):

- `android/.../ui/onboarding/OnboardingScreen.kt:593` (restore-branch stage, inline in the step `when`)
- `OnboardingScreen.kt:609` (restore-branch stage)
- `OnboardingScreen.kt:640` (restore-branch stage)
- `OnboardingScreen.kt:668` (restore-branch stage)
- `OnboardingScreen.kt:775` (Welcome — excerpt below)
- `OnboardingScreen.kt:988` (seed step)
- `OnboardingScreen.kt:1236` (first mint)

```kotlin
// OnboardingScreen.kt:775-779 — current (Welcome; the others are analogous)
OnboardingStepHeader(
    title = "Private cash.\nIn your pocket.",
    subhead = "An ecash wallet for Bitcoin and Lightning.",
    modifier = Modifier.padding(top = OnboardingMetrics.TitleGap),
)
```

## Target

Every one of the seven headers rises into place on stage entry, exactly as `riseIn` already implements: 12 dp translateY → 0, 400 ms, `FastOutSlowInEasing`, `index = 0` (no extra delay), no opacity (the stage cross-fade owns the fade), resting state under reduce-motion. This matches iOS's actual shipped values (`.smooth(duration: 0.4)`, offset 12) — the brief's "~260 ms / +10" was approximate; parity with iOS's real values wins.

Pattern per site:

```kotlin
val appeared = rememberAppeared()
OnboardingStepHeader(
    title = "Private cash.\nIn your pocket.",
    subhead = "An ecash wallet for Bitcoin and Lightning.",
    modifier = Modifier
        .padding(top = OnboardingMetrics.TitleGap)
        .riseIn(appeared, index = 0),
)
```

## Repo conventions to follow

- `riseIn` / `rememberAppeared` live in `com.cashu.me.ui.theme` (`Motion.kt:80-100`) — import from there; do NOT copy the implementation or invent a parallel one.
- `riseIn` is a `@Composable` Modifier extension — chain it at the call site inside the composable, as its own doc intends.
- Each stage's content is a fresh composition inside the step `AnimatedContent` (`OnboardingScreen.kt:520-541`), so `rememberAppeared()` (a `LaunchedEffect(Unit)` one-shot) naturally fires per stage entry, including the Welcome cold launch — same behavior as iOS's `triggerEntrance` (`OnboardingView.swift:315-319`).
- iOS exemplar being mirrored: `OnboardingView.swift:541` — `stagger(appeared: welcomeAppeared, index: 0) { OnboardingStepHeader(...) }`.

## Steps

1. For each of the seven sites listed above: declare `val appeared = rememberAppeared()` in the nearest enclosing composable scope, and append `.riseIn(appeared, index = 0)` to the `OnboardingStepHeader` modifier chain (after existing padding).
   - Sites :593/:609/:640/:668 sit inline inside the step `when` branches — declare `appeared` at the top of that branch's lambda.
   - Sites :775, :988, :1236 sit inside extracted stage composables (`WelcomeStageContent`, the seed stage, the first-mint stage) — declare `appeared` next to the other locals.
2. Add imports `com.cashu.me.ui.theme.riseIn` and `com.cashu.me.ui.theme.rememberAppeared` where missing.
3. If any restore-branch header turns out to live in `RestoreWalletFlow.kt` rather than `OnboardingScreen.kt`, apply the same pattern there **only if** that composable is exclusively reached from onboarding; otherwise wrap at the onboarding call site instead (per `docs/android/DESIGN-ANDROID.md`, onboarding-exempt motion must not leak into the wallet proper).

## Boundaries

- Header (`OnboardingStepHeader`) only — do NOT cascade other content blocks (that's plan 003, which depends on this one).
- Do NOT add opacity or blur to `riseIn` — its doc comment records why both are deliberately absent.
- Do NOT touch `Motion.kt` itself; the primitive is correct as-is.
- If a step already animates its header some other way when you get there (drift since f54a829c), STOP and report.

## Verification

- **Mechanical**: `cd android && ./gradlew :app:compileDebugKotlin` — clean.
- **Feel check** (fresh install, walk all branches: create-wallet path and restore path):
  - Every step's headline settles upward ~12 dp as the stage materializes; no double-fade flicker (the rise carries no opacity of its own).
  - Cold launch: Welcome headline rises once; rotating the device does NOT replay it mid-view (state survives recomposition, `rememberAppeared` is per-composition — confirm no visible replay on config change; if it replays, note it in the PR rather than improvising a fix).
  - `adb shell settings put global animator_duration_scale 0` → headlines render at rest, no rise.
  - Side-by-side with iOS Simulator: rise distance and settle feel comparable (iOS: 12 pt / 0.4 s `.smooth`).
- **Done when**: all seven headers rise on entry, reduce-motion renders resting state, and no non-header block animates.
