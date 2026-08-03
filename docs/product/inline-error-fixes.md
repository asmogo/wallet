# Inline Errors — One Contract, Two Native Expressions

The actionable sequel to [`inline-error-audit.md`](inline-error-audit.md), which
inventoried 47 Android and 45 iOS inline-error call sites and found 12 Android
and 8 iOS visual variants.

## The premise this document changes

The audit's first instinct was "make the two platforms match." That is the wrong
target, and `DESIGN.md` already says so:

> The system commits to native materials, native typography, native motion, and
> the native semantic palette. […] Colour is reserved for state, never for brand.
> — `docs/product/DESIGN.md:158`

Pixel-matching error UI across Android and iOS fights that on both sides at once:
it means overriding Material 3's text-field conventions on Android *and* keeping
non-Apple tinted boxes on iOS.

**The target is: converge on semantics, diverge on expression.** Share the
severity vocabulary, the copy, the rule deciding *which channel* an error uses,
and the accessibility guarantee. Let Material 3 and the HIG each render that
their own way. Two apps that behave identically and each look like they belong on
their OS.

This is well-supported by the code, because **both platforms already have the
native machinery and bypass it**:

| | Native mechanism present | Currently |
|---|---|---|
| Android field validation | `CashuTextField` forwards `supportingText` to M3's own slot (`CashuTextField.kt:66`) | **no caller passes it** — a separate box is drawn instead |
| Android container colour | `errorContainer` / `onErrorContainer` defined in both schemes (`Color.kt:49,92`) | unused; `InlineNotice` derives `error.copy(alpha = 0.18f)` |
| Android transient | `SnackbarHost` wired (`CashuApp.kt:256`, `WalletFlowHost.kt:145`) | not used for errors |
| Android a11y | `Modifier.semantics { error() }` | **zero uses**; `liveRegion` at 6 of 47 sites |
| iOS screen-level | `ContentUnavailableView` (iOS 17+; deployment target is **18.0**) | **zero uses** |
| iOS floating surface | `.regularMaterial` / Liquid Glass (`LiquidGlassModifiers.swift`) | error surfaces use flat `Color.opacity()` |
| iOS a11y | `AccessibilityNotification.Announcement` | in `ErrorBannerView` only; the `SendView.swift:294` clone drops it |

Two structural facts that constrain the design:

- **iOS has no `Form` or `List` anywhere.** The nine `*Section` symbols are custom
  Swift structs, not SwiftUI `Section`. `Section(footer:)` — the HIG-native home
  for validation text in a grouped list — is therefore unavailable without
  restructuring every settings screen. Field validation goes directly under the
  field instead.
- **Android's fields are deliberately indicator-less.** `CashuTextField.kt:83-86`
  sets every indicator colour to `Transparent`, including `errorIndicatorColor`.
  That is a documented house choice and this plan keeps it; error state reads
  through the container tint and the supporting text instead.

---

## 1. The shared contract

This is what "consistent" now means. Everything in this section is identical on
both platforms.

### 1a. Severity vocabulary

Four cases, same names, same meanings. iOS gains `success`; Android renames
`Warning` → `Caution`.

| Case | Means | Example |
|---|---|---|
| `error` | The action failed or is blocked. Something broke. | "Couldn't reach the mint." |
| `caution` | Non-blocking. Proceed carefully, or this won't work here. | "Insufficient balance" |
| `info` | A neutral precondition, not a failure. | "This request asks for a mint you haven't added." |
| `success` | Confirmation. | "Backed up to your relays." |

`caution` is the better word for the orange tier: orange also means *pending*
elsewhere in the app, and "warning" invites the warning-triangle glyph that
Material reserves for something else. `ErrorBannerView.swift:8-11` already
documents this reasoning — Android just never adopted the name.

### 1b. The placement decision rule

**This is the core of the document.** One question decides the channel; only the
rendering differs by platform.

| Ask, in order | Channel | Android (M3) | iOS (HIG) |
|---|---|---|---|
| 1. Can the user fix it in a field right here? | **Field-adjacent** | `supportingText` + `isError` | caption under the field, no container |
| 2. Does it block the primary action until resolved? | **In-context** | tonal container on `errorContainer` | containerless notice, icon + text |
| 3. Does it block the whole screen? | **Screen-level** | in-context container + retry action | **`ContentUnavailableView`** |
| 4. Already happened, nothing to fix here? | **Transient** | **`Snackbar`** | bottom-pinned banner on `.regularMaterial` |

Two corollaries worth stating explicitly:

- **One error, one channel.** Today eight Android sites signal the same error
  twice — the field tints *and* a notice box appears below it. Pick one. For
  field-attached errors, Material says the field.
- **Never a raw coloured string.** Every error goes through a component. This is
  the contract `InlineNotice`'s own KDoc already claims ("Screens never render
  raw red text") and which 17 call sites break.

### 1c. Copy

One string per error, curated through `WalletErrors` / `userFacingWalletMessage`
on both platforms. No raw `error.localizedDescription` — five iOS sites leak it
today (`NostrSettingsSection.swift:180,206,225`, `P2PKSettingsSection.swift:447`,
`OnboardingView.swift:1631`).

Say what broke, then what to do about it. Where a message carries an amount or a
mint name, it belongs on the second line, not spliced into the first.

### 1d. Accessibility guarantee

Every error is announced, **with its severity**, on every platform, from the
component — never left to the call site.

- **Android**: `Modifier.semantics { error(text) }` on the field for
  field-adjacent errors; `liveRegion = LiveRegionMode.Polite` on the in-context
  container.
- **iOS**: `AccessibilityNotification.Announcement` prefixed with
  `severity.announcementPrefix`, plus `.accessibilityElement(children: .combine)`.

Android has zero `semantics { error() }`, and `liveRegion` at only 6 of 47 sites
(`SendEcashScreen.kt:1105,1112,1238`, `TransactionDetailScreen.kt:296,303,361`) —
so the mechanism is known and simply not systematic. On iOS the most-seen error of
all, the insufficient-balance notice at `SendView.swift:294`, silently drops the
announcement its own shared component would have provided.

Moving this into the components is what makes it systematic: a call site should
not be able to forget it.

### 1e. Timing

Validate on commit, not per keystroke. Clear on edit. Identical rule both
platforms, so the two apps *behave* the same even where they look different.

---

## 2. What stays divergent — deliberately

Recorded so a future reviewer doesn't "fix" it back into uniformity.

| | Android | iOS |
|---|---|---|
| `error` glyph | `Icons.Filled.Error` — filled circle, M3's field-error convention | `exclamationmark.triangle.fill` — SF Symbols convention |
| `caution` glyph | `Icons.Filled.Warning` — triangle | `exclamationmark.circle.fill` |
| Inline container | tonal container on `errorContainer` | **none** — Apple doesn't box validation text |
| Type | M3 type scale (`bodySmall` / `labelMedium`) | Dynamic Type (`.footnote` / `.caption`) |
| Transient channel | `Snackbar` | bottom-pinned banner |
| Screen-level | container + retry | `ContentUnavailableView` |

**The glyphs are inverted between platforms, and that is correct.** Material uses
the filled circle for field errors and reserves the triangle for warnings; Apple
leans on the triangle for errors. Under this philosophy they are allowed —
required — to differ. Anyone reading the two catalogs side by side will see
this immediately; it is the intended outcome, not a defect.

---

## 3. Android component contract (Material 3)

### 3a. One component per channel, not one component with flags

`InlineNotice` becomes strictly the **in-context** surface. The `tinted`
parameter disappears: field errors leave via `supportingText`, transient errors
leave via `Snackbar`, so there is no longer a case for an untinted variant.

### 3b. Use the M3 role pairs

`InlineNotice.kt:75-79` currently paints full-strength `colorScheme.error` text on
a container derived as `error.copy(alpha = 0.18f)`. Material's role contract is
that container fills pair with their `on*Container` content role —
`errorContainer` / `onErrorContainer`, both of which this app defines in light and
dark (`Color.kt:49-50, 92-93`) and neither of which it uses.

Contrast has not been measured and may well pass today; the point is that the
app maintains a parallel colour system beside the one Material already gives it,
which is why the field tint (`0.12`) and the notice tint (`0.18`) drifted apart
in the first place.

| Severity | Container | Content |
|---|---|---|
| `error` | `colorScheme.errorContainer` | `colorScheme.onErrorContainer` |
| `caution` | `CashuTheme.colors.pendingContainer` | new `onPendingContainer` |
| `info` | `colorScheme.surfaceContainerHigh` | `colorScheme.onSurfaceVariant` |
| `success` | `CashuTheme.colors.receivedContainer` | new `onReceivedContainer` |

The `pending`/`received` extensions stay — they are the app's own semantic tier
and Material has no equivalent — but each gains a matching content role instead
of reusing the tint colour as text.

### 3c. Field errors move to `supportingText`

The mechanism is already wired; no caller uses it. Eight sites, each currently
double-signalling:

| Screen | Field | Notice to delete |
|---|---|---|
| Add Mint sheet | `AddMintSheet.kt:118` | `:143` |
| Onboarding first mint | `OnboardingScreen.kt:943` | `:968` |
| Restore seed | `RestoreWalletFlow.kt:233` | `:286` |
| Nostr add relay | `NostrScreen.kt:230` | `:234` |
| Import nsec dialog | `NostrScreen.kt:365` | `:368` |
| Import P2PK dialog | `AdvancedKeysScreen.kt:195` | `:197` |
| Nostr key field | `NostrComponents.kt:220` | `:160` |
| Send P2PK recipient | `SendEcashScreen.kt:954` | `:957` (bare `Text`, variant V7) |

Also change `errorContainerColor` at `CashuTextField.kt:81` from
`error.copy(alpha = 0.12f)` to the `errorContainer` token, and correct the comment
above it — it claims to match `InlineNotice`'s tint and does not.

### 3d. Other changes

- Rename `NoticeSeverity.Warning` → `Caution`.
- Add `liveRegion` to the in-context container; add `semantics { error() }` to
  fields.
- Move the entrance/exit animation into the component (`InlineNoticeHost`'s
  behaviour becomes the default), retiring the six per-call-site treatments.

---

## 4. iOS component contract (SwiftUI / HIG)

### 4a. Collapse to one inline type plus two native presentations

**`InlineNotice`** — the inline channel (field-adjacent and in-context).
**No container, ever.** Apple's own apps render validation as plain coloured
caption text directly under the control; Settings and App Store account creation
both do exactly this. Keep `title` / `detail` / `showsIcon`; **delete `tinted`**.
Always posts the announcement.

**`.errorBanner`** — the floating channel. `ErrorBannerView` stops being a
standalone inline component and becomes this modifier's internals. Because it
floats over content, this is the one error surface where a material is right:
`.regularMaterial`, through the existing `LiquidGlassModifiers` on iOS 26+.
Drops the `.footnote`/`.caption` split and the `Color(.separator)` border, which
exist nowhere else in the app.

**`ContentUnavailableView`** — the screen-level channel. Native, available at the
18.0 target, currently unused. No wrapper needed:

```swift
ContentUnavailableView {
    Label("Mint unreachable", systemImage: "exclamationmark.triangle.fill")
} description: {
    Text("Showing saved information.")
} actions: {
    Button("Retry") { await refresh() }
}
```

### 4b. Semantic colours only

`DESIGN.md` says "zero custom color extensions." Four sites use bare `Color.red` /
`.red`, which skips the system's dark-mode and increase-contrast adaptation:
`SendView.swift:3294`, `ScannerWrapperView.swift:283`,
`ReceiveLightningView.swift:692`, `MintDetailView.swift:245`. Route them through
`ErrorSeverity.foreground` (`Color(.systemRed)`), or `Color(.systemOrange)` for
caution — `.orange` at `ErrorBannerView.swift:28` should become `Color(.systemOrange)`
for the same reason.

### 4c. Glyph discipline

Filled SF Symbols only. Three sites use unfilled variants — `SendView.swift:3289`
(`exclamationmark.circle`), `:2651` (`exclamationmark.triangle`) — and
`SendView.swift:3289` additionally pairs the *caution* glyph with *error* red.

---

## 5. Migration order

Sequenced so every phase is independently reviewable and shippable. **None of
this is in the audit PR**; each phase is its own PR.

| Phase | Work | Scale |
|---|---|---|
| 1 | Components only — `InlineNotice.kt`, `CashuTextField.kt`, `ErrorBannerView.swift`. Catalogs re-recorded, so the whole visual delta is two screenshots per side. | 3 files |
| 2 | Field-attached errors → `supportingText` (Android, table in §3c) / caption (iOS) | ~8 + ~10 sites |
| 3 | Hand-rolled variants retired — Android V7–V10, iOS H1/H2/H4. **Start with `SendView.swift:294`**: it is the reference standard *and* the one dropping accessibility. | ~17 sites |
| 4 | Transient errors → `Snackbar` / banner | ~6 sites |
| 5 | Screen-level → `ContentUnavailableView` | ~4 iOS sites |
| 6 | Copy fixes — duplicate "sat-denominated" strings, missing `detail` at `UnifiedSendScreen.kt:935`, the five `localizedDescription` leaks | 8 strings |
| 7 | Dead code — `CashuTextField.supportingText` becomes live; delete `AmountEntryView.swift` (no production call site) | subtractive |

Phase 1 is the only one that changes appearance broadly; 2–7 are mechanical once
it lands. The Compose screenshot catalog added by the audit PR guards phase 1 —
`:app:validateDebugScreenshotTest` will fail loudly with a visual diff, which is
the point.

---

## 6. Channel assignment

Grouped by screen. Phase numbers refer to §5.

### Android

| Screen | Sites | Channel | Phase |
|---|---|---|---|
| Add Mint sheet, Onboarding first mint, Restore seed, Nostr relay/nsec, P2PK import, Send recipient | 8 (§3c table) | **Field-adjacent** | 2 |
| Send amount — insufficient balance | `SendEcashScreen.kt:656`, `UnifiedSendScreen.kt:935` | **In-context** | 1 |
| Unified Send confirm — routing/quote states | `UnifiedSendScreen.kt:1092–1155` | **In-context** | 1 |
| Receive — token hints, unknown-mint trust | `ReceiveEcashScreen.kt:278,307`, `ReceiveEcashDetailScreen.kt:305` | **In-context** | 1 |
| Cashu Request readiness | `CashuRequestDetailScreen.kt:340` | **In-context** | 1 |
| Nostr — no relays configured | `NostrScreen.kt:251` | **In-context** | 1 |
| Lightning / NWC service status | `LightningScreen.kt:213,318`, `NwcSettingsScreen.kt:141` | **In-context** | 1 |
| Mint detail — info fetch failed (+ Retry) | `MintDetailScreen.kt:200` | **Screen-level** | 1 |
| Contactless — NFC unavailable/disabled | `ContactlessPayView.kt:214,216` | **Screen-level** | 1 |
| Mint-list backup failed; set-default failed | `BackupRestoreScreen.kt:119`, `MintDetailScreen.kt:466` | **Transient** | 4 |
| Token claim-check results | `SendEcashScreen.kt:1100,1108`, `TransactionDetailScreen.kt:291,299` | **Transient** | 4 |
| Scanner overlay | `ScannerView.kt:337` | **Transient** | 3, 4 |
| Restore per-mint failure row | `RestoreWalletFlow.kt:896` | keep as row state; adopt `onErrorContainer` | 3 |
| Seed/key warning heroes | `OnboardingScreen.kt:574`, `BackupScreen.kt:95`, `P2PKComponents.kt:195,477` | **Not errors** — leave as content | — |

### iOS

| Screen | Sites | Channel | Phase |
|---|---|---|---|
| Add Mint, Connect Mint, Nostr relay/nsec, P2PK import, Onboarding first mint, Restore seed | `AddMintSheet.swift:75`, `ConnectMintView.swift:82`, `NostrSettingsSection.swift:277`, `SettingsView.swift:1330,1700`, `OnboardingView.swift:851`, `SettingsView.swift:653`, `OnboardingView.swift:1129` | **Field-adjacent** | 2 |
| Send — insufficient balance (`sendInputNotice`) | `SendView.swift:242,248,294` | **In-context** | 3 |
| Unified Send / Melt confirm | `SendView.swift:1473,1852,1861,2292,2301,3217,3227,3382,3391` | **In-context** | 1 |
| Receive — hints, unknown-mint trust, request readiness | `ReceiveView.swift:102`, `ReceiveTokenDetailView.swift:227,237`, `CashuRequestDetailView.swift:215,318` | **In-context** | 1 |
| Mint detail — fetch failed | `MintDetailView.swift:55` | **Screen-level** → `ContentUnavailableView` | 5 |
| Wallet delete / iCloud backup failure | `SettingsView.swift:126,1558` | **Transient** (already `.errorBanner`) | 1 |
| Scanner overlay | `ScannerWrapperView.swift:275` | **Transient** | 3, 4 |
| Restore per-mint failure row | `SettingsView.swift:945`, `OnboardingView.swift:1473` | keep as row state | 3 |
| Warning heroes, provenance badges | `SettingsView.swift:1391`, `P2PKSettingsSection.swift:224,654`, `OnboardingView.swift:651` | **Not errors** — leave as content | — |

Sites marked *not errors* are warning-**styled** content, not failures. They keep
their treatment; they are listed so the migration doesn't sweep them up.

---

## 7. How to tell it worked

- Every error on both platforms reaches the user through exactly one channel,
  chosen by §1b, and no screen renders a raw coloured string.
- VoiceOver and TalkBack both announce every error with its severity tier.
- The two component catalogs added by the audit PR show Android and iOS looking
  *deliberately different* — Material containers vs Apple captions — while the
  severity set, copy, and behaviour read identically.
- `:app:validateDebugScreenshotTest` guards the Android half in CI.
- No `Color.red`, no `error.copy(alpha =`, no `supportingText = null` where a
  field can fail.
