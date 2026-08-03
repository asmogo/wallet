# Inline Error Consistency Audit — Android ↔ iOS

## Background

The wallet surfaces in-context errors at **47 Android call sites and 45 iOS call
sites**. They are supposed to look and behave alike. They do not: this audit
found **12 distinct visual variants on Android and 8 on iOS**, plus disagreements
inside the two apps' shared components themselves.

Nothing measures this today. `docs/product/DESIGN.md` documents `ErrorBannerView`
and never mentions `InlineNotice`. The Compose screenshot baselines deliberately
pass `error = null` / `errorMessage = null`, so before this branch **not one
inline-error state was rendered by any test on either platform**.

This document is the audit and the proposal. It does not change any call site.
The migration is a follow-up, `docs/product/inline-error-fixes.md`, mirroring how
`button-audit-prompt.md` was followed by `button-fixes-prompt.md`.

## The reference standard

The insufficient-balance notice on the Send amount face is the shape everything
else should follow: severity glyph, a short line naming what is wrong, a quieter
second line carrying the specifics.

> ⚠️ **Insufficient balance**
> You have 21,000 sat in Testnut mint.

Two problems with using it as the standard as it stands. On Android it is a
tinted box; on iOS it is a hand-rolled clone of the shared component
(`SendView.swift:294`) rather than the component itself. And the same state
renders **without** the detail line at `UnifiedSendScreen.kt:935`.

---

## 1. The shared components disagree

| | Android `InlineNotice` | iOS `InlineNotice` |
|---|---|---|
| File | `ui/components/InlineNotice.kt:51` | `Views/Components/ErrorBannerView.swift:123` |
| Severities | 4 — `Error / Warning / Info / Success` | **3** — no `success` |
| `error` glyph | `Icons.Outlined.ErrorOutline` (outlined circle) | `exclamationmark.triangle.fill` |
| `caution` glyph | `Icons.Filled.Error` (filled circle) | `exclamationmark.circle.fill` |
| `tinted` default | **`true`** | **`false`** |
| `title:` | absent | present |
| `showsIcon:` | absent | present |
| Row alignment | `Alignment.Top` | `.firstTextBaseline` |
| Title type | `labelMedium` | `.caption` |
| Detail type | `labelSmall` | `.caption2` |
| Corner / pad / gap | 12dp / 10dp / 6dp | 12pt / 10pt / 6pt ✅ matched |
| Animation | none (`InlineNoticeHost` wraps it) | none (every call site rolls its own) |

**iOS ships a second surface Android has no counterpart for.**
`ErrorBannerView` (`ErrorBannerView.swift:58`) renders at `.footnote` instead of
`.caption` and adds a `Color(.separator)` 0.5pt border that appears nowhere on
Android. The two are used interchangeably:

- `OnboardingView.swift:220` and `:227` stack **both** in one `VStack`.
- Seed-phrase validation uses the bordered banner (`SettingsView.swift:653`),
  nsec validation uses the borderless notice (`SettingsView.swift:1330`).
- `MintDetailView.swift:55` places the banner inline in a `ScrollView`, which its
  own doc comment tells callers not to do.

**Severity semantics also drift.** Android derives the `Error` container inline
as `error.copy(alpha = 0.18f)` while `Warning`/`Success` use dedicated
`CashuTheme.colors.*Container` tokens and `Info` uses `surfaceContainerHigh` —
four containers, three derivation strategies. `CashuTextField` tints its error
container at `error.copy(alpha = 0.12f)` (`CashuTextField.kt:81`), so a field and
the notice directly beneath it render **two different reds**, and the comment on
the line above claims they match.

---

## 2. Call-site inventory

47 Android + 45 iOS (38 `InlineNotice`, 7 `ErrorBannerView`). Full enumeration:

```sh
# Android
grep -rn --include="*.kt" -E "InlineNotice\(|InlineNoticeHost\(" android/app/src/main
# iOS
grep -rn --include="*.swift" -E "InlineNotice\(|ErrorBannerView\(|\.errorBanner\(" ios/CashuWallet
```

Concentrations worth knowing: `UnifiedSendScreen.kt` carries 11 Android sites;
`SendView.swift` carries 9 iOS sites. Settings is the next densest on both.

---

## 3. Variant catalogue

Rendered evidence lives in the two catalogs added with this audit — see
[§6](#6-evidence).

### Android

| V | Surface | Container | Icon | Title | Detail | Align | Sites |
|---|---|---|---|---|---|---|---|
| V1 | `InlineNotice` Error | 12dp, `error@18%` | `Outlined.ErrorOutline` 14dp | `labelMedium`/`error` | `labelSmall`/`onSurfaceVariant` | Top | 26 |
| V2 | `InlineNotice` Warning | 12dp, `pendingContainer` | `Filled.Error` 14dp | `labelMedium`/`pending` | same | Top | 13 |
| V3 | `InlineNotice` Info | 12dp, `surfaceContainerHigh` | `Outlined.Info` 14dp | `labelMedium`/`onSurfaceVariant` | same | Top | 7 |
| V4 | `InlineNoticeHost` | as V1 | as V1 | as V1 | as V1 | Top | 2 |
| V5 | `InlineNotice` + bespoke `AnimatedVisibility` | as V2 | as V2 | as V2 | conditional | **BottomCenter** | `SendEcashScreen.kt:643` |
| V6 | `InlineNotice` + `AnimatedContent` | as V2 | as V2 | as V2 | — | Top | `ReceiveEcashScreen.kt:255` |
| **V7** | **bare error `Text`** | none | none | `bodySmall`/`error` | none | start | `SendEcashScreen.kt:957`, `ScannerView.kt:337` |
| **V8** | **error `Text` as row subtitle** | none | none | `labelSmall`/`error` | none | start | `RestoreWalletFlow.kt:891` |
| **V9** | **icon+text warning row** | none | `Filled.Warning` 12/14dp | `labelMedium`/`bodySmall` in `pending` | none | **CenterVertically** | `OnboardingScreen.kt:574`, `P2PKComponents.kt:195` |
| **V10** | **centered warning hero** | none | `Filled.Warning` 28/32dp | `titleMedium`/`onSurface` | `bodyMedium` | **Center** | `BackupScreen.kt:95`, `P2PKComponents.kt:477` |
| V11 | row-embedded status colour | none | `Outlined.WarningAmber` / `Outlined.Timer` / none | inherits row | none | row | `ReceiveTokenReview.kt:309`, `MintDetailScreen.kt:243` |
| V12 | field container tint | `shapes.large`, `error@12%` | none | reddened label | dead param | field | 8 sites |

### iOS

| V | Surface | Border | Icon | Message | Detail | Sites |
|---|---|---|---|---|---|---|
| V1 | `InlineNotice` bare | no | `.caption.semibold` | `.caption`/severity | `.caption2`/`.secondary` | 27 |
| V2 | `InlineNotice(tinted:)` | no | same | same | same | 6 |
| V3 | `InlineNotice` + `title:` | no | same | **`.caption2`/`.secondary`** | `.caption2` | 6 |
| V4 | `InlineNotice(showsIcon:false)` | no | none | `.caption`/severity | — | 2 |
| **V5** | **`ErrorBannerView`** | **yes, `separator` 0.5pt** | `.footnote.semibold` | **`.footnote`**/severity | — | 7 |
| **H1** | **`sendInputNotice` clone** | no | `.caption.semibold` | `.caption`/severity | `.caption2` | `SendView.swift:294` |
| **H2** | **bare red caption row** | no | `exclamationmark.circle` *(unfilled)* | `.caption`/**`Color.red`** | — | `SendView.swift:3289` |
| **H4** | **solid-red block** | no | none | body/`.primary` on **solid `Color.red`**, radius **10** | — | `ScannerWrapperView.swift:275` |

---

## 4. Ranked findings

1. **`SendView.swift:294` reimplements the shared component.** `sendInputNotice`
   is a near-copy of `InlineNotice(tinted: true, detail:)` with `.top`/spacing 8
   instead of `.firstTextBaseline`/6 — and it **drops the VoiceOver `"Caution. "`
   prefix** the real component supplies. This renders the exact banner in the
   reference standard above.
2. **The two scanner overlays share nothing.** Android
   (`ScannerView.kt:337`) puts themed `colorScheme.error` text on an *unthemed*
   black camera surface; iOS (`ScannerWrapperView.swift:275`) uses a **solid**
   `Color.red` block with no icon, no severity token, default body font, and
   radius 10 instead of 12.
3. **One error, two reds.** `SendEcashScreen.kt:957` prints bare `bodySmall` red
   text under a field that is *already* `isError`, so `error@0.12` (field) sits
   directly under full-strength error text.
4. **iOS `.caption` vs `.footnote`** — the two shared surfaces disagree on body
   size and appear stacked in one `VStack` at `OnboardingView.swift:220`/`:227`.
5. **Five warning glyphs, four icon sizes on Android** — `Filled.Warning`,
   `Filled.Error`, `Outlined.ErrorOutline`, `Outlined.WarningAmber`,
   `Outlined.Info`, at 12 / 14 / 28 / 32dp.
6. **Same validation, different component (iOS)** — seed phrase uses the banner
   (`OnboardingView.swift:1129`, `SettingsView.swift:653`); nsec uses the notice
   (`SettingsView.swift:1330`, `:1700`).
7. **Copy drift** — `"Cashu Wallet can only pay sat-denominated Cashu Requests."`
   (localised, `SendView.swift:1199`) vs `"This wallet can only pay
   sat-denominated Cashu Requests."` (not localised,
   `ScannerWrapperView.swift:503`).
8. **Missing detail line** — `"Insufficient balance"` carries its amount detail
   at `SendEcashScreen.kt:656` but not at `UnifiedSendScreen.kt:935`.
9. **`Color.red` vs `Color(.systemRed)`** — `SendView.swift:3289`,
   `ScannerWrapperView.swift:283`, `ReceiveLightningView.swift:692`,
   `MintDetailView.swift:245` bypass the token.
10. **Raw `error.localizedDescription` leaks** past the curated
    `WalletErrors.swift` mapping at `NostrSettingsSection.swift:180/206/225`,
    `P2PKSettingsSection.swift:447`, `OnboardingView.swift:1631`.
11. **Animation is per-call-site.** Six treatments across Android, five across
    iOS, including many sites with none at all.
12. **Dead code** — `CashuTextField.supportingText` is declared and never passed.
    `Components/AmountEntryView.swift` (including its own severity-less
    `"Insufficient balance"`) has no production call site.

### Adjacent treatments — documented, not screenshotted

Warning-styled surfaces that are not inline errors but share the tokens, and so
constrain any unification:

| Treatment | Android | iOS |
|---|---|---|
| Hero warning block | `BackupScreen.kt:95`, `P2PKComponents.kt:477` | `SettingsView.swift:1391`, `P2PKSettingsSection.swift:654` |
| Row status colour | `MintDetailScreen.kt:243` (Offline) | `MintDetailView.swift:245` |
| Expiry countdown < 60s | `ReceiveLightningScreen.kt:1437` | `ReceiveLightningView.swift:692` |
| Field error tint | `CashuTextField.kt:81` | *(no equivalent — iOS never tints the field)* |
| Key-provenance badge | `P2PKComponents.kt:195` | `P2PKSettingsSection.swift:224` |

---

## 5. Recommended unified spec

One recommendation per item, with the churn it costs.

| # | Change | Churn |
|---|---|---|
| 1 | **One severity vocabulary, 4 cases both platforms**: `error / caution / info / success`. iOS gains `success`; Android renames `Warning` → `Caution`. | iOS +1 case; Android rename at 13 sites |
| 2 | **One glyph table, all filled.** Adopt iOS's mapping so the reference standard's look is preserved: `error` = triangle-fill, `caution` = circle-exclamation-fill, `info` = info-circle-fill, `success` = check-circle-fill. ⚠️ Compose trap: `Icons.Filled.Error` **is** the circle; `Icons.Filled.Warning` is the triangle. | Android `Error` glyph changes app-wide |
| 3 | **Collapse iOS to one surface.** `ErrorBannerView` becomes a *presentation* of `InlineNotice` (adds retry/dismiss/bottom-pinning), not a second visual language. Drops the `.footnote`/`.caption` split and the 0.5pt border. | 7 iOS sites re-render |
| 4 | **Align `tinted` default to `true`** (Android's, and the reference standard's). | ~27 iOS sites change appearance — the reason this is a separate PR |
| 5 | **`Alignment.Top` on both.** iOS moves off `.firstTextBaseline`; it is the alignment that survives multi-line copy and large Dynamic Type. | iOS only, invisible at one line |
| 6 | **Add `title:` and `showsIcon:` to Android** for parity. | additive |
| 7 | **Reconcile the tint alphas** — `CashuTextField`'s `0.12` vs the notice's `0.18`. Pick one and derive both from a token. | 1 line + token |
| 8 | **Move animation into the component**, reduce-motion aware; delete the per-call-site transitions. | 11 sites simplify |
| 9 | **Retire the hand-rolled variants**, in the order of §4. Start with `sendInputNotice` — it is the reference standard and it is the one losing accessibility. | ~17 sites |
| 10 | **Copy fixes** — dedupe the two "can only pay sat-denominated" strings, restore the missing `detail` at `UnifiedSendScreen.kt:935`, route the 5 raw `localizedDescription` sites through `WalletErrors`. | 8 strings |
| 11 | **Delete dead code** — `CashuTextField.supportingText`, `AmountEntryView.swift`. | subtractive |

**Forward dependency, not actionable on `main`:** neither component is wired to a
type ladder. `main` has no `CashuTextRole`; it arrives with the
`typography-system` branch. Whichever lands second should adopt the other's
tokens rather than re-deriving raw `.caption` / `labelMedium`.

---

## 6. Evidence

### Component catalogs

Both platforms now render every severity, both `tinted` defaults, and facsimiles
of the hand-rolled variants, so the divergence is visible in one frame per side.

- **Android** — `android/app/src/screenshotTest/.../InlineErrorCatalogTest.kt`,
  four references committed under `app/src/screenshotTestDebug/reference/`.
  CI's existing `validateDebugScreenshotTest` job now guards inline-error
  rendering. Re-record with `:app:updateDebugScreenshotTest`.
- **iOS** — `ios/CashuWallet/Views/Debug/ComponentCatalogView.swift`, `#if DEBUG`,
  reachable only via `SHOW_COMPONENT_CATALOG=matrix|variants`:

  ```sh
  SIMCTL_CHILD_SHOW_COMPONENT_CATALOG=matrix \
    xcrun simctl launch --terminate-running-process <udid> com.cashu.me
  ```

> **The facsimiles are reproductions, not the live views.** Every hand-rolled
> variant is a `private` member of its screen and cannot be called from a
> harness. Each is copied from its source and labelled with that source. They
> evidence what the styling looks like; they are not proof of what those screens
> render. The real-screen captures below are.

### Capture environments

| | Android | iOS |
|---|---|---|
| Runtime | Android 17, API 37 | iOS 26.2 (23C54) |
| Build | `google/sdk_gphone64_arm64/emu64a:17/CE2A.260420.019/15611780:userdebug/dev-keys` | Xcode 17F113 |
| Security patch | 2026-05-05 | — |
| Device | emulator, arm64-v8a | iPhone 17 Pro simulator |
| Viewport | 1080×2424 px @ 420dpi | 1206×2622 px @ 3x |
| Theme / locale / text scale | dark / en-US / 1.0 | dark / en-US / default |
| Source | `audit/inline-error-parity` | same |

No `capture-manifest.json` accompanies this audit. The skill's validator
(`validate_capture_manifest.py`) is built for **before/after** pairs and requires
`before_sha`/`after_sha`; this is a single-revision parity comparison across two
platforms, so the environment facts are recorded here instead rather than faked
into that schema.

### Coverage gaps

Stated plainly rather than papered over. Six real-screen pairs were planned; one
pair and two supporting captures were obtained.

| Surface | Status |
|---|---|
| Mint connect failure | ✅ **pair captured** — Android `OnboardingScreen.kt:968` vs iOS `AddMintSheet.swift:75` |
| Seed-phrase warning row (V9) | ✅ Android captured (`OnboardingScreen.kt:574`), iOS not reached |
| Send — insufficient balance | ❌ Send is gated on balance > 0; needs a funded wallet via a live mint, not a seed flag |
| Restore — invalid seed | ❌ the seed `TextEditor` does not accept synthetic keystrokes or the paste affordance |
| Scanner — rejected payload | ❌ the iOS simulator has no camera; evidenced from code and catalog facsimile only |
| Receive — unknown mint trust | ❌ needs a real ecash token from an unknown mint |
| Nostr — invalid relay URL | ❌ not reached before capture was stopped |

Static screenshots prove rendering only. They do **not** prove animation or
VoiceOver — the missing `"Caution. "` prefix at `SendView.swift:294` is a code
finding and appears in no image.
