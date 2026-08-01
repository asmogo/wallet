---
name: wallet-ui-visual-review
description: Analyze a Cashu Wallet pull request, branch, or commit for user-visible Android and iOS changes, then produce reproducible before/after screenshots from isolated builds. Use for PR screenshots, visual change evidence, UI regression comparisons, Compose or SwiftUI before/after captures, responsive/theme/locale checks, cross-platform parity evidence, finding divergences between the iOS and Android implementations, GitHub comments containing wallet UI evidence, or proving that a change has no visual delta. Do not use for implementing UI, ordinary code review without visual evidence, one-off README screenshots, patch files, or uncommitted working-tree comparisons.
---

# Wallet UI Visual Review

Turn a committed change into trustworthy Android and/or iOS visual evidence.
Compare the actual merge-base and target under matched source, runtime, viewport,
state, locale, theme, and text-size conditions.

## Resolve intent

Collect:

1. **Target** — a PR URL/number, branch, or commit. Reject patch files and
   requests to compare an uncommitted working tree; ask for a commit or branch.
2. **Base** — infer the PR base or repository default branch. Ask only when a
   branch's intended base is ambiguous.
3. **Publishing** — keep artifacts local unless the user explicitly authorizes
   uploading images and posting a PR comment. Continue read-only analysis while
   this preference is unanswered.

Do not require a clean source checkout. Never incorporate its tracked or
untracked changes into the comparison.

## Create the isolated session

Run from the repository root:

```sh
.agents/skills/wallet-ui-visual-review/scripts/create_review_session.sh \
  --target "<PR URL, PR number, branch, or commit>"
```

Pass `--base "<ref>"` when needed. The script records the true merge-base,
creates separate detached `before` and `after` worktrees, places artifacts
outside both, and leaves the active checkout untouched. Reuse the printed
session for the whole review.

## Analyze and route before building

Read [references/analysis-playbook.md](references/analysis-playbook.md) on every
run. Route compiled changes with:

```sh
python3 .agents/skills/wallet-ui-visual-review/scripts/route_platforms.py \
  --before "$BEFORE_SHA" --after "$AFTER_SHA"
```

- Capture Android only for Android changes.
- Capture iOS only for iOS changes.
- Capture both when both compiled apps change.
- For documentation, agent, or CI-only changes, report that no app build is
  implicated.
- For platform backend/state changes, inspect the nearest affected surface and
  label equality as an expected **no visual delta**. Never invent a UI effect.

Turn every visual hypothesis into a capture-matrix row before launching a
device. Include surface, navigation, fixture, runtime, viewport, appearance,
locale, text scale, expected before/after behavior, and a useful control.

## Hunt for cross-platform divergence

Treat divergence between the Android and iOS implementations as a first-class
goal of every run, not a side effect. The wallet ships two apps that must
behave alike; your job includes surfacing where they do not.

- When both platforms are routed, add capture-matrix rows for the equivalent
  surface on each platform under matched fixture, appearance, locale, and text
  scale so the two are directly comparable.
- When only one platform changed but the change alters a shared screen's
  contract, capture the untouched platform's equivalent surface as a parity
  control.
- Compare equivalent captures and report every user-visible divergence:
  missing screens, states, or actions on one platform; different labels,
  ordering, defaults, or navigation flows; divergent layout, theme, or
  empty-state contracts.
- Label each divergence as introduced by the change or pre-existing. Do not
  silently treat one platform as the reference; report both behaviors and let
  the user decide which is correct.

## Select exact runtime images

Do not hardcode the runtime called "latest."

1. Verify the newest stable Android and iOS releases from official primary
   documentation at run time. Exclude beta, preview, Canary, and RC images
   unless the user explicitly requests preview coverage.
2. Inspect both revisions' minimum/target/compile or deployment settings.
3. Inventory the machine, passing the verified stable versions:

```sh
python3 .agents/skills/wallet-ui-visual-review/scripts/inspect_runtimes.py \
  --official-android-api "<API>" \
  --official-ios-version "<major.minor>"
```

4. Choose the newest stable runtime supported by both revisions. If it is not
   installed, ask before downloading it or before using any older fallback.
5. Add a boundary runtime only when the diff changes version gates, deployment
   targets, SDK targeting, Android versioned resources, or availability paths.

Use the same exact runtime build and device profile for each before/after pair.
Do not compare different OS image revisions. Record the guest/runtime facts,
not assumptions based on an AVD or simulator name.

## Capture Android

Read [references/android-capture.md](references/android-capture.md) whenever
Android is routed. Use an emulator by default, an explicit serial for every ADB
command, semantic navigation, deterministic system UI, and the same fixture in
both builds. Record Android release/API/build fingerprint/security patch/ABI,
resolution, density, font scale, theme, locale, app version, source SHA, and APK
hash.

## Capture iOS

Read [references/ios-capture.md](references/ios-capture.md) whenever iOS is
routed. Use one exact simulator runtime/device for the pair, separate Derived
Data per revision, the existing UI-test launch environment and accessibility
identifiers, and deterministic status-bar/appearance settings. Preserve normal
simulator signing; do not set `CODE_SIGNING_ALLOWED=NO`. Record runtime and Xcode
versions/builds, device type, pixel/point viewport, scale, Dynamic Type,
appearance, locale, app version, source SHA, and executable hash.

## Create deterministic state

Read [references/fixture-recipes.md](references/fixture-recipes.md) when the
affected screen is not reachable from a stable empty state.

- Use only synthetic wallet, mint, transaction, message, invoice, and identity
  data. Never capture a real seed, key, token, contact, balance, or payment.
- Prefer existing iOS UI-test seeds and Android semantic/onboarding paths.
- Add a minimal temporary debug-only fixture only inside both isolated
  worktrees when normal navigation cannot express the state.
- Apply logically identical fixture inputs to both revisions and verify a
  structured success result before capture.
- Remove temporary fixture edits and verify both worktrees are clean before
  handoff.

Static screenshots prove rendering, not NFC, Keychain/Keystore security,
network payment completion, background races, or hardware behavior. Test and
report those separately.

## Validate the evidence

Copy [assets/capture-manifest.example.json](assets/capture-manifest.example.json)
into the artifact directory and fill it with relative image paths. Keep
environment and build IDs stable across paired entries. Never include device
serials, simulator UDIDs, local paths, private IPs, or other machine identifiers.

Validate before reporting:

```sh
python3 \
  .agents/skills/wallet-ui-visual-review/scripts/validate_capture_manifest.py \
  "<artifact-directory>/capture-manifest.json"
```

The validator checks the versioned schema, routing, revision/build association,
hashes, path containment, sensitive machine identifiers, environment equality,
dimensions, and the complete PNG stream through valid CRCs, decompressed pixel
payload, and `IEND`. Identical before/after bytes are valid when the expected
result is no visual delta.

Visually inspect every image after validation. A valid PNG can still show the
wrong screen, animation frame, stale state, permission dialog, or keyboard.

## Report locally

Use [assets/report-template.md](assets/report-template.md). Include:

- exact target and before/after SHAs
- routed and skipped platforms with reasons
- exact capture environments
- concise diff-to-screen analysis
- side-by-side paired evidence
- cross-platform parity findings and divergences
- fixture disclosure
- intentional non-changes and visual noise
- coverage limitations

Keep the report, manifest, and images in the session artifact directory. Do not
copy review artifacts into tracked source folders unless separately requested.

## Publish only with authorization

If the user explicitly asks to post evidence, read
[references/github-publishing.md](references/github-publishing.md). Validate
first, require the uploader's `--confirm-publish` flag, post a marked PR comment,
then read it back and verify the expected image URLs. Upload refs are repository
writes even though they do not alter a source branch.

## Hand off

Provide links to the report, manifest, and images; count captures by platform;
summarize one result per surface; list every cross-platform divergence found
or state that none was observed; include a PR comment URL when published; state
that the active checkout was not modified; and name any missing runtime,
hardware, behavioral, or state coverage.
