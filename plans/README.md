# Motion plans

Plans 001–011 came from the onboarding audit of 2026-08-06 at commit
`f54a829c`. Plans 012–014 come from the native UI and motion sweep of
2026-08-31 at commit `fa754037`. The app-wide motion budget and platform-native
behavior remain the governing constraints.

Headline: iOS implements the shared spec nearly completely; Android built the primitives (`riseIn`, `GhostButton(animatedLabel:)`, `InlineNoticeHost`, `IconSwap`) but never wired several of them up. Most plans are wiring, not new motion design.

## Plans

| # | Plan | Platform | Severity | Status |
| --- | --- | --- | --- | --- |
| 001 | [Copy → Copied morph](001-android-copy-copied-morph.md) | Android | MEDIUM | TODO |
| 002 | [Headline rise on every step](002-android-headline-rise.md) | Android | MEDIUM | TODO |
| 003 | [70 ms element cascade](003-element-cascade-both-platforms.md) | Both | MEDIUM | TODO |
| 004 | [Restore progress: row phases + rolling total](004-android-restore-progress-motion.md) | Android | MEDIUM | TODO |
| 005 | [Animated notices and status lines](005-android-animated-notices.md) | Android | MEDIUM | TODO |
| 006 | [Stage swap: exit blur + overlap](006-android-stage-swap-exit-blur-overlap.md) | Android | MEDIUM | TODO |
| 007 | [Chassis accessory fade](007-android-chassis-accessory-fade.md) | Android | LOW | TODO |
| 008 | [App-gate reduce-motion branch](008-android-app-gate-reduce-motion.md) | Android | LOW | TODO |
| 009 | [Seed-reveal Reduce Motion gate](009-ios-seed-reveal-reduce-motion.md) | iOS | LOW | TODO |
| 010 | [Seed reveal blur resolve](010-android-seed-reveal-blur.md) | Android | LOW | TODO |
| 011 | [Haptic parity](011-android-haptic-parity.md) | Android | LOW | TODO |
| 012 | [Reduce Motion press feedback](012-reduced-motion-press-feedback.md) | Both | HIGH | DONE |
| 013 | [Quiet full-tab empty states](013-quiet-full-tab-empty-states.md) | Both | MEDIUM | DONE |
| 014 | [Payment terminal state coherence](014-payment-terminal-state-coherence.md) | Both | HIGH | DONE |

## Recommended execution order

1. **001** — smallest, highest-visibility win; also touches `Buttons.kt`, so land before 005/004 to avoid churn.
2. **002 → 003** — 003 depends on 002 (`riseIn` wiring + the shared `appeared` locals).
3. **005** — notices; independent.
4. **004** — restore progress; independent (shares `RestoreWalletFlow.kt` with 005's last site and 011 — coordinate if run in parallel).
5. **011** — haptics; touches the same handlers as 004's screen, so after it.
6. **006, 007, 008, 010** — independent Android polish, any order. 006's Part B is feel-check gated.
7. **009** — one-line iOS change, any time.
8. **012**: shared accessibility prerequisite for all frequent controls.
9. **013**: independent high-frequency motion restraint.
10. **014**: terminal semantics plus Android contactless lifecycle; execute
    after 012 so the shared Done button already honors Reduce Motion.

## Dependencies

- 003 depends on 002.
- 004, 005, 011 all edit `RestoreWalletFlow.kt` — rebase-coordinate.
- 001 and 005 both touch components used elsewhere (`Buttons.kt`, `InlineNotice.kt`) — behavior for non-onboarding callers must not change (each plan's Boundaries section pins this).
- 014 depends on the shared button accessibility behavior in 012 for its new
  Android contactless Done action.

## Repo-wide execution notes

- Android UI changes that shift Compose screenshot references: regenerate via the workflow in `.github/workflows/android-ui-tests.yml` (`:app:validateDebugScreenshotTest`) and commit the new baselines with the PR.
- UI PRs need matched before/after visual evidence per repo convention (see `.agents/skills/wallet-ui-visual-review`).
- Reduce-motion checks: iOS = Settings > Accessibility > Motion; Android = `adb shell settings put global animator_duration_scale 0` (restore `1`).
- Verify each plan's excerpts against `f54a829c` before editing; on drift, stop and report rather than improvise (each plan repeats this).
