# Diff-to-screen analysis playbook

Use this reference on every visual-review run.

## Resolve the comparison

For a PR, define `after` as the fetched PR head and `before` as the merge-base
of that exact head and the PR's configured base branch. Do not substitute the
current base tip, `head~1`, or the user's checkout.

For a branch or commit, resolve the target and intended base, fetch when
necessary, and compute the merge-base. Build the recorded SHAs from their
separate worktrees.

This skill does not accept patch files or uncommitted working-tree state. Those
inputs cannot provide an independently identifiable after revision.

## Route compiled changes

Run:

```sh
python3 .agents/skills/wallet-ui-visual-review/scripts/route_platforms.py \
  --before "$BEFORE_SHA" --after "$AFTER_SHA"
```

The helper treats compiled files under `android/` and `ios/` as platform
changes, then classifies their likely visual impact:

- `direct`: views, Compose/SwiftUI components, resources, assets, manifests,
  themes, or navigation presentation changed.
- `indirect`: model, storage, service, or platform state changed and may surface
  through otherwise unchanged UI.
- `none`: no compiled Android or iOS app file changed.

Inspect the focused diff even after routing. Generated output is orientation,
not proof.

## Trace changes to surfaces

For each changed symbol or resource, answer:

1. Which screen or component consumes it?
2. Which state branch selects it?
3. What navigation path reaches it?
4. What wallet state, mint, transaction, permission, theme, locale, width, or
   OS version makes it visible?
5. Does it affect empty state, populated state, fresh install, restored state,
   or all of them?

Useful repository starting points:

| Area | Android | iOS |
|---|---|---|
| App gate and shell | `App/MainActivity.kt`, `ui/shell/` | `CashuWalletApp.swift`, `ContentView.swift` |
| Onboarding | `ui/onboarding/` | `Views/Main/OnboardingView.swift` |
| Wallet/home | `ui/home/` | `Views/Main/MainWalletView.swift` |
| History | `ui/history/` | `Views/History/` |
| Mints | `ui/mints/` | `Views/Mints/` |
| Send/receive | `ui/send/`, `ui/receive/` | `Views/Send/`, `Views/Receive/` |
| Settings/security | `ui/settings/`, `ui/security/` | `Views/Settings/` |
| Shared visual tokens | `ui/theme/`, `ui/components/` | `Views/Components/`, asset catalogs |
| UI fixtures/tests | `src/androidTest/`, `src/debug/` | `CashuWalletUITests/`, `IntegrationTestConfig.swift` |

Files move. Re-establish the map with `rg --files` and symbol searches at both
revisions.

## Build the capture matrix

Create the matrix before building:

| Field | Required decision |
|---|---|
| Platform | Android or iOS |
| Surface | Human-readable screen/component |
| Entry path | Semantic actions from launch |
| Fixture | Exact synthetic state and fixed inputs |
| Runtime | Exact stable OS image and build |
| Device | Device type and viewport |
| Appearance | Light/dark/system |
| Locale | Exact language/region |
| Text scale | Font scale or Dynamic Type category |
| Expected before | Concrete visible contract |
| Expected after | Concrete visible contract |
| Control | Useful unchanged state, if any |

Keep the matrix minimal while exercising every changed branch. A responsive
layout may need several widths; a color change may need light and dark; a
locale change needs the picker and selected locale; a backend-only fix usually
needs one nearest-surface equality control.

## Pair platforms for parity comparison

Divergence between the Android and iOS implementations is a first-class
finding. When both platforms are in scope, plan the matrix so equivalent
surfaces are captured on both under matched fixture, appearance, locale, and
text scale; otherwise the captures cannot be compared. When only one platform
changed but the change touches a shared screen's contract, add the other
platform's equivalent surface as a parity control.

For each paired surface, ask whether the two apps show the same screens,
states, actions, labels, ordering, defaults, navigation flows, and empty-state
contracts. Record each divergence and whether the change introduced it or it
pre-existed. Never assume one platform is the reference implementation.

## Add runtime boundaries deliberately

Add another runtime only when the focused diff contains evidence such as:

- Android `Build.VERSION`, `VERSION_CODES`, `@RequiresApi`, `minSdk`,
  `targetSdk`, `compileSdk`, or `values-vNN`/`drawable-vNN` resources.
- iOS `#available`, `@available`, deployment-target changes, SDK checks, or
  version-specific Liquid Glass/fallback paths.

Capture the newest stable common runtime first. Add the meaningful boundary
runtime only if it is supported by both revisions and needed to exercise a
distinct path. Never add arbitrary legacy coverage to make a report look more
complete.

## Separate visual and behavioral proof

Screenshots can prove layout, visible state, labels, resource selection,
appearance, and locale rendering. They cannot prove:

- cryptographic or secure-storage correctness
- real mint, Lightning, on-chain, Nostr, or Cashu delivery
- NFC hardware exchange
- background lifecycle or race behavior
- accessibility announcements without semantic inspection

Use repository tests or hardware validation for those claims and list the
limitation in the report.

## Control visual noise

Stabilize or disclose:

- status-bar time, network, and battery
- keyboard visibility and focus
- animations and loading indicators
- random identifiers, seeds, and timestamps
- asynchronous balance, quote, and transaction state
- dynamic color or wallpaper-dependent palettes
- simulator/emulator system dialogs

Do not describe noise as a product change.
