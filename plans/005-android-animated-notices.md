# 005 — Animate Android onboarding notices and status lines

- **Status**: TODO
- **Commit**: f54a829c
- **Severity**: MEDIUM
- **Category**: Missed motion / platform parity (jarring state changes)
- **Estimated scope**: 3 files (`OnboardingScreen.kt`, `RestoreWalletFlow.kt`, `InlineNotice.kt`), 5 sites

## Problem

Error and status messages in Android onboarding pop in and out with hard cuts, shoving the layout instantly. iOS animates every one of these (`.opacity` + `.move(edge: .top)` insert with `.snappy` container reflow — e.g. `OnboardingView.swift:562, 1095, 1117`). The animated wrapper already exists — `InlineNoticeHost` (`android/.../ui/components/InlineNotice.kt:110-132`: slide-up + fade in over `tween(220)`, fade out `tween(180)`) — and has **zero** onboarding call sites.

The five hard-cut sites:

```kotlin
// OnboardingScreen.kt:781-795 — current (Welcome, startup failure: notice + retry button)
if (startupFailure != null) {
    Column(
        modifier = Modifier.padding(horizontal = CtaPadding),
        verticalArrangement = Arrangement.spacedBy(CashuTheme.spacing.snug),
    ) {
        InlineNotice(text = startupFailure.message)
        PrimaryButton(...)
    }
    Spacer(Modifier.height(CashuTheme.spacing.snug))
}

// OnboardingScreen.kt:796-801 — current (Welcome, create error)
if (errorText != null) {
    InlineNotice(text = errorText, modifier = Modifier.padding(horizontal = CtaPadding))
    Spacer(Modifier.height(CashuTheme.spacing.snug))
}

// OnboardingScreen.kt:1342-1346 — current (first mint, error)
val notice = state.customDraft.error ?: errorText
if (notice != null) {
    Spacer(Modifier.height(CashuTheme.spacing.snug))
    InlineNotice(text = notice)
}

// OnboardingScreen.kt:1347-1354 — current (first mint, "Connecting to …" status line)
if (addingMintUrl != null) {
    Spacer(Modifier.height(CashuTheme.spacing.snug))
    Text(text = "Connecting to ${shortenMintUrl(addingMintUrl)}…", ...)
}

// RestoreWalletFlow.kt:582-584 — current (restore mints, error)
if (notice != null) {
    InlineNotice(text = notice, severity = noticeSeverity)
}
```

One defect in the wrapper itself: `InlineNoticeHost` is not reduce-motion aware (it always slides), while `docs/android/DESIGN-ANDROID.md` requires onboarding motion to degrade to opacity-or-nothing.

## Target

- All five sites animate: canonical entrance = slide up from half-height + fade over `tween(220)`, exit = fade over `tween(180)` (exactly `InlineNoticeHost`'s existing values — exits subtler than entrances).
- Under reduce-motion (`rememberReducedMotion()`), entrance drops the slide and keeps the fade.
- Content below the notice reflows with the animation instead of teleporting (AnimatedVisibility animates its own height; the spacers move inside the animated block so they appear/disappear with it).

## Repo conventions to follow

- `InlineNoticeHost` (`InlineNotice.kt:110-132`) is the canonical wrapper — use it for bare `InlineNotice` sites; imitate its remember-last-text pattern so the exit fade shows content, not a blank.
- Reduce-motion source: `rememberReducedMotion()` (`Motion.kt:102-128`).
- The stage-swap RM branch (`OnboardingScreen.kt:530-531`, `fadeIn(tween(250)) / fadeOut(tween(180))`) is the exemplar for opacity-only fallbacks.

## Steps

1. `InlineNotice.kt` — make `InlineNoticeHost` reduce-motion aware:

```kotlin
val reducedMotion = rememberReducedMotion()
AnimatedVisibility(
    visible = text != null,
    modifier = modifier,
    enter = if (reducedMotion) fadeIn(tween(220))
            else slideInVertically(tween(220)) { it / 2 } + fadeIn(tween(220)),
    exit = fadeOut(tween(180)),
) { ... }
```

2. `OnboardingScreen.kt:796-801` — replace the `if (errorText != null)` block with `InlineNoticeHost(text = errorText, modifier = Modifier.padding(horizontal = CtaPadding))`, moving the trailing `Spacer` inside the host's content (extend the host with a trailing-spacing param ONLY if unavoidable; prefer wrapping site-side: `AnimatedVisibility` is inside the host, so put the Spacer in a site-local `AnimatedVisibility` sharing the same `visible` — simplest correct form: wrap notice + Spacer together in one `AnimatedVisibility` using the host's enter/exit values directly at the site).
3. `OnboardingScreen.kt:781-795` — the startup-failure block contains a button, so use a site-level `AnimatedVisibility(visible = startupFailure != null, enter/exit as above)` around the whole `Column` + `Spacer`, remembering the last non-null `startupFailure` for exit rendering (the `InlineNoticeHost:117-118` pattern).
4. `OnboardingScreen.kt:1342-1354` — wrap the notice (+ its leading spacer) and the "Connecting to…" line (+ spacer) each in `AnimatedVisibility` with the same values. The status line may skip the slide (fade only) — it's a quiet caption, not an alert.
5. `RestoreWalletFlow.kt:582-584` — replace with `InlineNoticeHost(text = notice, severity = noticeSeverity)`. This file is shared with Settings restore; `InlineNoticeHost` is app-wide vocabulary, so shared improvement is intended.

## Boundaries

- Do NOT change notice copy, severity mapping, or layout spacing values — motion only (spacers may move inside animated blocks, net layout identical).
- Do NOT introduce new tween values — 220/180 only, from `InlineNoticeHost`.
- Do NOT animate the first-mint custom-URL field row — out of scope here.
- If a site's structure has drifted from the excerpts, STOP on that site and report; finish the others.

## Verification

- **Mechanical**: `cd android && ./gradlew :app:compileDebugKotlin`. Screenshot baselines: `./gradlew :app:validateDebugScreenshotTest` — if references shift, regenerate per the workflow in `.github/workflows/android-ui-tests.yml` and include them in the PR.
- **Feel check**:
  - First mint: enter an invalid mint URL → the error slides up + fades in and the content below eases down with it; fixing the URL fades it out with no jump.
  - Add a real mint → "Connecting to…" fades in, then out.
  - Trigger a create error (airplane mode on Welcome) → notice animates; retry block (startup failure) animates as one unit.
  - Rapidly toggle validity: transitions retarget, never restart from blank, and the exit always shows the last message (remember-last pattern).
  - `animator_duration_scale 0` handling aside, explicitly set the device's Remove-animations/scale-0 and confirm fade-only (no slide).
- **Done when**: no notice or status line in onboarding appears or disappears with a hard cut, and reduce-motion degrades to fades.
