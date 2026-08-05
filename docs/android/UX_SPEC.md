# Cashu Wallet — Android UX Spec

This document is the **behavior contract** the Android rebuild must match. It describes *what the iOS app does and shows*, not *how SwiftUI builds it*. Android implements it with idiomatic Material 3.

When this spec and Material 3 disagree on the **idiom**, Material 3 wins (see `UX_MAPPING.md` for divergences). When they disagree on **information architecture or available actions**, this spec wins — the two apps must feel like the same product.

---

## 0. Product identity

Cashu Wallet is a **system utility**, not a crypto dashboard. The bar is set by Apple Wallet, Notes, Find My — and on Android, by Google Wallet, Messages, and Maps' top-app-bar utilities. Quiet, precise, native.

**Rejected:** confetti, achievement badges, "earned"/"streak" language, neon-on-black, signature gradients, hero-metric SaaS panels, mascots, NFT-style portfolio analytics, illustrated empty states.

**Prioritized:** restraint and clarity; native materials and motion; numbers given the care of a stopwatch; semantic-only color; one strong action per surface; readable by a phone-illiterate user.

### Named rules carried over from iOS DESIGN.md

| Rule | Meaning on Android |
|------|---------|
| **Semantic-Only Rule** | Use M3 `MaterialTheme.colorScheme.*` slots only. Three state hues are the *only* custom colors: `received-green` (#34C759), `pending-orange` (#FF9500), `error-red` (#FF3B30 / M3 `error`). |
| **One Green Rule** | Green appears only on **completed incoming** amounts and the incoming directional badge. Outgoing amounts use `onSurface`. Pending amounts use `onSurfaceVariant`. |
| **Quiet Pending Rule** | Pending state = clock icon + low-alpha orange tint, never a saturated pill. |
| **Tabular Figure Rule** | All balances/amounts/fees use a monospaced-digit `FontFeatureSetting` and animate digits independently (`Modifier.animateContentSize` + `AnimatedContent` with `numericContentTransform`). |
| **System-Style Rule** | All text uses `MaterialTheme.typography.*` slots so it scales with system font size. No hardcoded `sp` outside the theme file. |
| **Flat-By-Default Rule** | No elevation on rows, cards, buttons. Depth comes from M3 tonal surfaces and deliberate spacing. **One exception:** transient success toast (a floating M3 surface). |
| **CanvasDivider Rule** | Use a 0.5dp `HorizontalDivider` with 28dp leading inset where a detail screen needs explicit separation. Home and History activity rows omit dividers and rely on spacing. |
| **Share-At-Top Rule** | When a screen shows a shareable QR (invoice, request, token, transaction), `Share` lives in the `TopAppBar` actions, never in the footer button stack. |
| **Singular Button Rule** | Primary AND secondary CTAs both use `FilledTonalButton`. No `OutlinedButton`, no inverted-fill. Hierarchy via copy and disabled state. The single most-prominent action per screen (e.g. "Create Wallet") may use `Button` (filled). |
| **Iconless-CTA Rule** | Primary CTAs (Copy, Send, Receive, Continue, New Request) are text-only. No leading icons. |

---

## 1. Shell

**Bottom navigation: 3 tabs.**

| # | Tab | Icon (Material) | Destination |
|---|-----|------|--------|
| 1 | **Wallet** | `Icons.Outlined.AccountBalanceWallet` (selected: `Icons.Filled.AccountBalanceWallet`) | Home screen |
| 2 | **History** | `Icons.Outlined.History` / `Icons.Filled.History` | Activity timeline |
| 3 | **Mints** | `Icons.Outlined.AccountBalance` / `Icons.Filled.AccountBalance` | Mint list |

Settings is a pushed destination opened from the Wallet screen's settings
button; returning from it preserves the selected bottom tab. Send and Receive
are **not tabs**. They are the two primary action buttons on the Wallet screen
(alongside Scan), each opening a `ModalBottomSheet` chooser (Ecash / Bitcoin /
Contactless).

**Gating states** (resolved by `WalletManager.state`):
- `!isInitialized` → centered `CircularProgressIndicator` (full screen, no chrome).
- `needsOnboarding` → full-screen `OnboardingScreen` (no bottom nav).
- Otherwise → `WalletScaffold` with `NavigationBar`.

**Deep links** (existing `NavigationManager.pendingDeepLink`):
- `cashu:` URL → push `ReceiveTokenDetailScreen` over the current tab.
- BOLT11/BOLT12/onchain URI → switch to Wallet tab, open Send flow with prefilled payload.
- Mint URL (`https://...`) → switch to Mints tab, prefill add-mint form.

---

## 2. Onboarding

*(Rewritten 2026-08-05 to match shipped code — `ui/onboarding/OnboardingScreen.kt`
+ `OnboardingChassis.kt` + `ui/restore/RestoreWalletFlow.kt`.)*

One host (`OnboardingScreen`) built on the restyle's chassis grammar
(docs/product/onboarding-restyle-brief.md §3, revised by design review
2026-08-05): the **welcome step** carries its headline and subhead in the
bottom action block above its CTAs; **every other step** titles itself at the
top (`OnboardingStepHeader` — title + supporting copy, with an M3
`ArrowBack` icon button above it wherever a retreat exists) and pins its
actions to the bottom edge (`OnboardingChassis` — no reserved slots, a lone
primary hugs the bottom). The stage between owns all vertical slack. Steps
swap with a quiet materialize (fade + 0.96→1 scale on expressive springs,
blur-resolve on API 31+); the chassis never animates, only its content
cross-fades in place. No horizontal push (binding cross-platform decision),
no page indicator (the flow branches, so dots would imply a linear path that
doesn't exist), no bottom nav, no `TopAppBar`. System back mirrors the
on-screen back buttons and only those.

Flow: `Welcome → ShowMnemonic → FirstMint → done`, or
`Welcome → RestoreMethod → RestoreInput → RestoreMints → RestoreProgress → done`.

| Step | Top + stage | Bottom actions |
|------|-------------|----------------|
| **Welcome** | The "note becomes cash" ink piece (`WelcomeStagePiece`); startup-failure recovery + create errors pin above the actions | "Private cash. In your pocket." + subhead · `PrimaryButton` "Create Wallet" (filled-tonal) / `SecondaryButton` "Restore Wallet" / `GhostButton` "What is ecash?" (opens the concept sheet) |
| **ShowMnemonic** | Back → Welcome; "Your Seed Phrase." header + warning line; 12-word 3-column grid — masked (`"••••••"` + blur on API 31+, real words never composed) until tap-to-reveal — and a Copy ghost with clear separation | acknowledge row in the accessory slot gates "I've Saved My Seed Phrase" |
| **FirstMint** | "Pick your first mint." header; multi-select recommended-mint rows, "Add custom mint URL" expands a `CashuTextField`, inline notices | "Continue" (disabled with no selection and empty input) / "Skip for now" |
| **RestoreMethod** | Back → Welcome; "Restore Wallet" header; quiet variant of the welcome piece | "Use Seed Phrase" (Secondary styling — Android has no iCloud twin, iOS's chooser has two options) |
| **RestoreInput** | Back → Welcome (matching iOS); "Restore Wallet." header; monospaced seed editor with paste/clear corner control, live word counter | "Next" (disabled until 12 words) |
| **RestoreMints** | Back → RestoreInput (clears staged list); "Recover Funds." header; URL field, Add / Paste / Nostr capsule chips, staged mint rows | "Restore from N mints" (disabled until ≥1 staged) |
| **RestoreProgress** | "Recover Funds." header (no back — forward-only); recovered-sats total (mono digits, no roll) + live per-mint rows with expressive loaders and Retry | "Continue" (disabled until every mint settles) |

Information sheet "What is ecash?" — a `ModalBottomSheet` (hidden/expanded
detents only) with three bearer-cash beats and a "Got it" button.

**Done state** triggers `walletManager.completeOnboarding()` (create path,
also reachable via "Skip for now") or `walletManager.completeRestore()`
(restore path) → app re-evaluates the gate and renders `WalletScaffold`.

---

## 3. Wallet (Home)

**Layout — pinned top, scrolling body.** Use a `Scaffold` with a top-aligned non-scrolling section and a `LazyColumn` body. The body fades into the pinned section via a vertical gradient mask at the top (already implemented on iOS Home; preserve).

### 3.1 Pinned top (fixed)

Top-to-bottom inside the pinned region:

1. **Mint chip** — `AssistChip` with active mint name. Tap opens `DropdownMenu` listing all mints (checkmark on active) + "Change mint…" item that opens a `ModalBottomSheet` mint picker.
2. **Balance** — `displayLarge` or larger, bold, monospaced digits. Tappable to toggle ₿ vs sat unit (persists in `SettingsManager.useBitcoinSymbol`). Animates digit-by-digit on change.
3. **Fiat sub-line** — only if `settings.showFiatBalance && priceService.btcPriceUsd > 0`. `titleMedium`, `onSurfaceVariant`, monospaced digits. Silently updates on price ticks (no animation).
4. **Action row.** Carve-out from the original "triptych" spec: the current build matches iOS by placing **Receive** and **Send** as two equal-width `FilledTonalButton`s, with **Scan** living as a separate `FilledTonalIconButton` (M3 default size) in the top-right corner of the pinned region. Button height is 56dp (M3 standard CTA height). Tap Receive/Send → bottom-sheet chooser; tap Scan → full-screen `ScannerScreen`.

`TopAppBar` is empty / hidden on Home (the pinned region serves the role).

### 3.2 Scrolling body

- **Notification toast** (top inset) — if `walletManager.lastNotification` non-null. Floating M3 surface with leading icon, message, and dismiss `IconButton`. Auto-dismiss after 5s. Toast carries the only allowed shadow in the app.
- **"Recent activity" section header** — `labelMedium`, uppercase, letter-spaced, `onSurfaceVariant`. **Padding: 16dp top, 8dp bottom** (carve-out from the original 28dp top spec — matches iOS rhythm where `HistoryView` and `SettingsView` section headers both use 16pt top). Rendered via the shared `SectionHeader` component for consistency across Home, History, Settings, and Mints.
- **Up to 5 completed transaction rows** — the latest settled sent/received payments, including payments received through reusable requests or offers. Generated receive artifacts and pending, failed, or expired transactions stay in History. Same anatomy as History rows (see §4.2). Rows use spacing only, with no separators.
- **"View all activity" `TextButton`** — bottom of section, navigates to History tab.

**Empty state**: if no mints, replace the activity section with `EmptyState(icon = Icons.Outlined.AccountBalance, title = "Add a mint to get started", supporting = "Mints custody your ecash. Go to the Mints tab to add one.", actionLabel = "Add mint", onAction = …)`. If mints exist but no transactions, show `EmptyState(icon = Icons.Outlined.History, title = "No transactions yet", supporting = "Your activity will show up here.")`.

### 3.3 Receive chooser sheet

`ModalBottomSheet`, `skipPartiallyExpanded = true`, height wraps content. Options as a vertical `Column` of M3 `ListItem`s with **cascade-in animation** (each item: 0.07s stagger, 12dp horizontal slide-in, fade). Tap an option → dismiss the chooser → open the relevant flow sheet.

| Label | Leading icon | Action |
|-------|---------|--------|
| **Ecash** | `Icons.Outlined.Money` (banknote) | Open `ReceiveEcashScreen` flow sheet (wrap-content ≈ iOS `.medium`) |
| **Bitcoin** | `Icons.Outlined.CurrencyBitcoin` | Open `ReceiveLightningScreen` flow sheet (full height) |

> **Revised 2026-07:** the money flows (Send, Send Ecash, Receive Ecash, Receive Lightning) are presented as native M3 modal bottom sheets via `ui.shell.WalletFlowSheetHost`, not pushed destinations — restoring iOS sheet parity. Each screen renders a `SheetHeader` (close/back + title + actions) instead of a `TopAppBar`. Dismissal is blocked while money is in flight.

### 3.4 Send chooser sheet

Same anatomy as Receive chooser. Cascade-in.

| Label | Leading icon | Action |
|-------|---------|--------|
| **Ecash** | `Icons.Outlined.Money` | Push `SendEcashScreen` |
| **Bitcoin** | `Icons.Outlined.CurrencyBitcoin` | Push `SendLightningScreen` |
| **Contactless** *(only if device has NFC)* | `Icons.Outlined.Nfc` | Push `ContactlessScreen` |

### 3.5 Scanner

Full-screen destination (route `scanner/{target}`). Pure black background, camera preview, white viewfinder cutout, top `IconButton` close (×). On successful scan, dismiss and route per payload type (see Shell deep-link rules). Keep current ML Kit barcode implementation; only re-chrome.

---

## 4. History

Top-level destination from the History tab. `CenterAlignedTopAppBar(title = "History")` (carve-out from the original `LargeTopAppBar` spec — the three top-level destinations Wallet, History, and Mints use compact app bars for a uniformly dense feel that matches iOS inline titles). Hides on scroll via `exitUntilCollapsedScrollBehavior`. Trailing actions: filter `IconButton` + search `IconButton` (opens M3 `SearchBar`).

### 4.1 Filter & search

- **Filter menu** — `IconButton(Icons.Outlined.FilterList)` opens `DropdownMenu` with single-select: All transactions / Pending only / Completed only. Filter icon switches to filled variant when any non-default filter is active. Selection emits haptic feedback.
- **Search** — entering search collapses `LargeTopAppBar` to a full-width `SearchBar`. Matches by description (transaction kind/type) and amount substring. Resets pagination on every keystroke.

### 4.2 Timeline

`LazyColumn`. Items are a unified `HistoryItem` (transaction or Cashu Request), sorted by date descending, grouped into date buckets.

**Section header** (date bucket): `labelMedium`, uppercase, letter-spaced, `onSurfaceVariant`. Examples: "TODAY", "YESTERDAY", "THIS WEEK", "JUNE 2026".

**Row anatomy:**

| Slot | Contents |
|------|---------|
| Leading (40dp) | Method icon (Ecash custom glyph / `Icons.Filled.Bolt` for Lightning / `Icons.Outlined.CurrencyBitcoin` for on-chain) **with a bottom-trailing 16dp status badge** on a `surface`-colored circle. Badge swaps via `AnimatedContent` w/ fade-through (~280ms). |
| Title (top) | `bodyLarge`, e.g. "Lightning received", "Bitcoin sent", "Sent ecash". *(2026-07-21: a BOLT11 mint quote still awaiting payment titles as "Lightning invoice" — `WalletTransaction.isUnpaidInvoice` via `TransactionDisplay.title()` — flipping to "Lightning received" only once paid. An unpaid invoice past its quote expiry keeps that title with status **Expired**: excluded from the Pending filter, QR/Copy/Share retired in detail, amount stays bare + muted.)* |
| Subtitle (bottom) | `bodySmall`, `onSurfaceVariant`, relative timestamp ("2 hr ago"). |
| Trailing top | Amount: `bodyLarge` medium, monospaced digits. Completed incoming gets `+`; outgoing is unsigned. Color rules below. |
| Trailing bottom | Converted sub-amount: `bodyMedium` regular, `onSurfaceVariant`, monospaced. Only if `showFiatBalance && btcPriceUsd > 0`. The neighboring size and weight keep both currencies inside one amount block. |

**Status badge colors:**
- Pending: `Icons.Outlined.Schedule` (clock), `pending-orange`, pulsing alpha animation.
- Completed incoming: `Icons.Filled.ArrowDownward`, `received-green`.
- Completed outgoing: `Icons.Filled.ArrowUpward`, `onSurface`.

**Amount color:**
- Pending: `onSurfaceVariant`.
- Completed incoming: `received-green`, prefixed with `+`.
- Completed outgoing: `onSurface`, unsigned. Direction is already carried by the title and arrow.
- Failed: `onSurface`.

**Divider:** none. Transaction and request rows use spacing and section grouping instead of horizontal rules.

**Entrance:** first 8 rows on initial render animate in with 35ms stagger, 6dp y-offset → 0, fade in. Subsequent loads/filters re-render snappily without stagger.

**Pagination:** initial 30 items; load 30 more when within 5 items of the bottom.

**Long-press menu (Cashu Request rows only):** opens `DropdownMenu` with "Remove from history" (destructive). Tap → `AlertDialog` confirm → `CashuRequestStore.delete(id)`.

**Tap targets:**
- Transaction row → push `TransactionDetailScreen` (route argument: transaction ID).
- Cashu Request row → push `CashuRequestDetailScreen` (route argument: request ID).

### 4.3 Empty states

- No transactions and no filter applied: `EmptyState(icon = Icons.Outlined.Bolt, title = "No transactions yet", supporting = "Your transaction history will appear here.")`.
- Filtered (e.g. "Pending only") and result is empty: `EmptyState(icon = Icons.Outlined.Schedule, title = "No pending transactions")`.

---

## 5. Mints

Pushed top-level destination from the Mints tab. `CenterAlignedTopAppBar(title = "Mints")` (compact — see §4 for the cross-tab carve-out from the original Large variant).

### 5.1 List

`LazyColumn` with:
1. **Mints section** — each mint as a row (see anatomy below).
2. **"Discover mints"** `ListItem` with leading `Icons.Outlined.Search` → pushes `MintDiscoveryScreen`.
3. **Add mint inline form** — two `OutlinedTextField`s (URL, optional nickname) + `TextButton("Paste URL from clipboard")` + `FilledTonalButton("Add")` (disabled until URL non-empty and adding-in-progress is false).
4. **Inline error** below the Add button on failure: `bodyMedium`, `error` color.

**Mint row anatomy:**

| Slot | Contents |
|------|---------|
| Leading (40dp) | `AsyncImage` of `mint.iconUrl` if present, else a colored circle (deterministic by mint URL hash) with mint's first letter. Bottom-trailing **green dot** if this is the active mint. |
| Title | `bodyLarge`, mint nickname or domain. |
| Subtitle | `bodySmall`, `onSurfaceVariant`, mint URL middle-truncated. |
| Below subtitle | Row of method `AssistChip`s (very small): "Lightning" / "Bitcoin" / "Ecash". Tonal chip color hints at method (yellow/orange/blue), low-saturation. |
| Trailing | None for plain navigation rows (whole row is the tap target). |

Tap row → push `MintDetailScreen(url)`.

### 5.2 Mint Detail

Pushed route. `LargeTopAppBar(title = mint.name)`. Loads `MintInfo` asynchronously; shows `LinearProgressIndicator` at the top edge while loading.

`LazyColumn` of sections, each as a `Card`-less group with `SectionHeader` and `ListItem` children (use `CanvasDivider` inside groups):

| Section | Rows |
|---------|------|
| **Header** | Large icon (72dp) + name + URL (copyable on tap, `Icons.Outlined.ContentCopy` trailing). Pubkey as monospaced `bodySmall`, copyable. |
| **About** | Mint description (multi-paragraph). |
| **Message of the day** | If present. |
| **Contact** | Email / Twitter / etc. — each row tappable to open external app. |
| **Software** | Name, version. |
| **Payment methods** | Per-method: name + min/max amounts + fees. |
| **Supported NUTs** | Comma-separated NUT numbers, monospaced. |
| **Wallet** | Balance on this mint, monospaced. |
| **Terms of Service** | Link row → opens browser. |
| **Actions** | `TextButton("Remove Mint", colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error))`. Tap → `AlertDialog` "Remove mint?" / "Cancel" / "Remove". |

### 5.3 Discover Mints

Pushed route (not a sheet — it's a search list). `LargeTopAppBar(title = "Discover")` + M3 `SearchBar` below. List shows curated/recommended mints from `MintDiscoveryManager`. Each row: name, description, method chips, and trailing `FilledTonalButton("Add")` (changes to "Added" check on success).

---

## 6. Settings

Pushed destination opened from the Wallet screen's settings button.
`CenterAlignedTopAppBar(title = "Settings")` uses the same compact treatment as
the tab destinations and includes Android-native back navigation.

`LazyColumn` of section groups. Each group:
- Group header — `labelMedium`, uppercase, letter-spaced, `onSurfaceVariant`, 24dp top, 8dp bottom.
- Group body — rows as M3 `ListItem` with trailing `Icons.AutoMirrored.Filled.KeyboardArrowRight`. `CanvasDivider` between rows.

| Section | Rows | Pushed destination |
|---------|------|--------------------|
| **Backup** | Backup & Restore | `BackupScreen` |
| **Payments** | Lightning, P2PK | `LightningScreen`, `P2PKScreen` |
| **Integrations** | Nostr, Nostr Wallet Connect | `NostrScreen`, `NWCScreen` |
| **Privacy & Display** | Privacy, Appearance | `PrivacyScreen`, `AppearanceScreen` |
| **About** | "Learn about Cashu", "Protocol Specs (NUTs)" | External browser intents |
| **Danger** | "Delete Wallet" (`error` color text) | Triggers `AlertDialog` |

Footer below all groups: app name + version, `bodySmall`, centered, `onSurfaceVariant`.

### 6.1 Sub-screens

| Screen | Contents |
|--------|---------|
| **BackupScreen** | Seed display (12 words, numbered 2-column grid, long-press to copy phrase). `FilledTonalButton("Copy phrase")`, `FilledTonalButton("Verify phrase")` (toggles to the verify quiz inline), `TextButton("Restore from seed")`. |
| **LightningScreen** | Lightning address row (configured value or "Set up Lightning address" CTA). Tap → push setup sub-screen with username `OutlinedTextField` + domain dropdown + save. |
| **P2PKScreen** | List of pubkeys (monospaced, middle-truncated, copy + delete trailing icons). `FilledTonalButton("Generate key")`, `FilledTonalButton("Import key")`. |
| **NostrScreen** | Intro prose, then `KeyCard` for the active key (tap-to-copy npub, long-press for npub/hex, "Reveal nsec" → `PrivateKeyRevealSheet`). `SelectionRow` pair for key source, plain action rows for generate / import / reset. Relays: inline `wss://` field with submit, rows with copy + destructive remove, confirmed reset. Wallet Connect `NavRow`. |
| **NWCScreen** | Connection list. Each row: connection nickname, copy connection string, revoke action. "Generate connection string" `FilledTonalButton`. |
| **PrivacyScreen** | M3 `Switch` rows: "Show balance on lock screen", "Hide transaction amounts", etc. |
| **AppearanceScreen** | Theme `SegmentedButtonRow` (Light / Dark / System). `Switch` rows: "Show fiat balance", "Use ₿ symbol". |

### 6.2 Delete Wallet

`AlertDialog` triggered by Danger row.
- Title: "Delete Wallet"
- Body: "Are you sure? This action cannot be undone. Back up your seed phrase first."
- Cancel `TextButton` + "Delete" `TextButton(colors = … error)`.
- Confirm → `walletManager.deleteWallet()` → app re-evaluates the gate (returns to Onboarding).

---

## 7. Send flows

Full-height `ModalBottomSheet` flows hosted by `ui.shell.WalletFlowSheetHost` (**revised 2026-07** — previously pushed destinations; converted for iOS `.large`-sheet parity). Each is a single screen with **two faces** swapped via `AnimatedContent` (250ms fade-through cross-fade), headed by a `SheetHeader` instead of a `TopAppBar`. Sheet dismissal (swipe/scrim/back) is blocked while a payment or token generation is in flight; system back unwinds faces before the sheet closes.

### 7.1 Send Ecash

**Face A — Input.** `TopAppBar(title = "Send ecash", navigationIcon = Close)`.

Body, top-to-bottom:
1. **Mint selector** — `AssistChip` with active mint. Tap → `ModalBottomSheet` mint picker.
2. **Amount display** — large, centered, monospaced. Tappable to switch sats ↔ fiat as the primary unit.
3. **Optional memo** — `OutlinedTextField`, single line, label "Memo (optional)".
4. **P2PK lock toggle** — `IconButton(Icons.Outlined.Lock)` in `TopAppBar` trailing. Expanded state reveals an `OutlinedTextField` for recipient pubkey.
5. **Error supporting text** — `error` color, slide-in/out.
6. **Number pad** — custom `NumberPadAmountInput` (already exists in `Views/Send/Components/`). Keep that logic; re-skin to use M3 tokens.
7. **Send `FilledTonalButton`** — bottom-pinned, full width, disabled if amount is 0.

On tap Send: per iOS DESIGN.md and the memory file *No Send-confirm gate* — **fire immediately**, no confirm modal. Loading spinner replaces button text. On success, face swaps to B.

**Face B — Token display.** `TopAppBar(title = "Pending ecash", navigationIcon = Close, actions = [Share])`.

Body:
1. **QR card** — white-on-surface card, rounded 20dp, 16dp padding, `QRCodeView` 280dp. Long-press → context dropdown menu (Copy, Share).
2. **Amount** — large, centered, monospaced, `onSurfaceVariant`.
3. **Memo** if present, `bodyMedium`, centered.
4. **Status row** — "Waiting for recipient" with subtle pulsing dot. When poll detects claim, swap to "Token claimed" with `received-green` `Icons.Filled.CheckCircle` and bounce-in animation, hold 2.5s, then offer a "Send another" `FilledTonalButton`.
5. **Copy `FilledTonalButton`** — full width. Tap → copies token, label becomes "Copied" for 2s.

### 7.2 Send Lightning

Same two-face shape. Input face accepts: invoice (BOLT11), offer (BOLT12), Lightning address, on-chain address — parsed by existing `PaymentRequestDecoder`.

Input face:
- **Mint selector** chip.
- **Decoded payload card** — shows destination type, amount (if known), description, expiry.
- **Amount entry** if the request is amountless.
- **Pay `FilledTonalButton`** — disabled until valid; fires immediately on tap.

Display face: spinner during payment, then success or failure card with preimage / failure reason. Share action in `TopAppBar` for the preimage / txid.

### 7.3 Contactless

Pushed full-screen destination. Pure NFC reader UI: animated wave icon, "Hold device near recipient", `IconButton(Icons.Outlined.Close)` to cancel. On read, parse payload and route to the appropriate send flow with prefill.

---

## 8. Receive flows

Same two-face pattern as Send. Receive Ecash is a **wrap-content** flow sheet (≈ iOS `.medium` detent); Receive Lightning is full height (**revised 2026-07** — previously pushed destinations).

### 8.1 Receive Ecash

**Face A — Input.** `SheetHeader(title = "Receive ecash", navigationIcon = Close, actions = [Scan])`.

Body:
1. **Token field** — `CashuTextField`, multi-line (6–8 lines, scrolls internally), monospaced, placeholder "cashuB…". The paste (`Icons.Outlined.ContentPaste`) / clear (`Icons.Filled.Cancel`) affordance is **overlaid at the field's bottom-trailing corner** (iOS parity) — never in the vertically-centered trailing slot.
2. **Error inline notice** if validation fails.
3. **Continue** — `PrimaryButton`, disabled when empty. On tap: validate via `TokenParser`. If valid, swap to face B (token detail). If valid but P2PK-locked to a key the wallet doesn't have, show inline error and disable Continue.
4. **New Request** — `SecondaryButton` (tonal; one step quieter than Continue).

**Face B — Token detail** (the *Receive Token Detail* face).
- Amount (large, centered).
- Inspector rows: Fee (with loading spinner while computing), Mint (truncated), P2PK status (e.g. "Locked to your key").
- "Receive" `FilledTonalButton` — fires immediately, no confirm. On success: success toast, dismiss back to caller.
- "Receive later" `TextButton` — saves to `PendingReceiveTokens`; row appears in History.

**Alternative Face A flow:** "Create Cashu Request" `TextButton` at the bottom of face A. Tap → pushes `CashuRequestDetailScreen` (a fresh request).

### 8.2 Receive Lightning

`TopAppBar(title = "Receive Bitcoin", navigationIcon = Close)`.

**Face A — Input:**
- **Mint selector** chip.
- **Method `SegmentedButtonRow`** — BOLT11 / BOLT12 / On-chain (only methods the active mint supports).
- **Amount entry** (centered large display + number pad), or "Amountless" toggle for BOLT12.
- **"Create request" `FilledTonalButton`** — disabled until valid.

**Face B — Display:**
- QR card.
- Amount (if specified).
- Status block: "Waiting for payment…" with pulsing clock; on payment received, swap to "Payment received!" with bounce `Icons.Filled.CheckCircle` (`received-green`), hold 2.5s, then settle to persistent "N payments received".
- Expiry timer if applicable ("Expires in 14m 32s").
- **Copy `FilledTonalButton`** — copies invoice/address.
- **Share** in `TopAppBar` trailing.

Polling cadence and celebration sequence match iOS exactly.

### 8.3 Cashu Request Detail

Pushed route (or rendered as Face B of Receive Ecash). `TopAppBar(title = "Cashu Request", actions = [Share])`.

Body:
- QR card.
- Amount (if fixed; otherwise hidden).
- Status: same waiting / live-burst / persistent count states as Receive Lightning.
- **Inspector rows** — `ListItem`s with leading icon, label, trailing value, and (on editable rows) a trailing pencil `IconButton`. Inspector divider is 0.5dp at 8dp horizontal inset (tighter than canvas).

| Row | Editable | Tap behavior |
|-----|---------|--------------|
| Mint | Yes | Opens `ModalBottomSheet` mint picker; on select, regenerates request. |
| Amount | Yes | Opens `ModalBottomSheet` with number pad; on confirm, regenerates request. |
| Unit | No | — |
| Created | No | — |

- **Copy `FilledTonalButton`** — copies encoded request.
- **New Request `TextButton`** — regenerates from scratch.

### 8.4 Receive Token Detail (deep-link entry)

When a `cashu:` deep link arrives, push this screen over whatever tab is active. Same shape as Receive Ecash Face B. Has its own `TopAppBar(title = "Receive Ecash", navigationIcon = Close)`. On Receive, dismiss to the previous tab. On Receive Later, save and dismiss.

---

## 9. Transaction detail

Pushed route from History (or from Home recent activity). `TopAppBar(title = "", navigationIcon = Close, actions = [Share if shareable])`.

Body, top-to-bottom:
1. **QR card** if the transaction has a shareable payload (token / invoice / address); else a large centered method icon with status badge.
2. **Amount** (large, monospaced, colored per status rules).
3. **Status row** — same icons + colors as History row.
4. **Inspector rows**: Type, Fee, Unit, State, Mint, Request (truncated, monospaced), Proof / preimage / txid (truncated, monospaced).
5. **External link row** — "View in block explorer" for on-chain.
6. **Copy `FilledTonalButton`** if there is a copyable payload (footer).

Long-press on QR opens `DropdownMenu` (Copy, Share).

---

## 10. Cross-cutting

### 10.1 Buttons

| Use | Component |
|-----|---------|
| Primary CTA | `FilledTonalButton`, full width, 56dp min height, body weight semibold, text-only. |
| Secondary CTA | `FilledTonalButton` (same — Singular Button Rule). |
| The single most-prominent action on Onboarding | `Button` (filled). |
| Inline action (Copy, Paste) | `TextButton`. |
| Icon-only | `IconButton`. |
| Destructive | `TextButton` with `contentColor = error`. |

Pressed state: native M3 ripple. Disabled state: M3 default (opacity reduction). Haptic feedback on press for primary actions (`HapticFeedbackType.LongPress` or the existing `HapticFeedback` utility).

### 10.2 Bottom sheets

`ModalBottomSheet` with `skipPartiallyExpanded = true` (matches iOS fixed-detent feel). Drag indicator visible. Background scrim. Sheets used:

| Sheet | Use |
|-------|-----|
| Receive chooser | 2–3 list items, cascade-in. |
| Send chooser | 2–3 list items, cascade-in. |
| Mint picker | List of mints, single-select. |
| Amount picker (for Cashu Request edit) | Number pad. |
| QR detail (NWC, Nostr) | QR card + copy/share. |

Avoid nesting bottom sheets on top of bottom sheets when avoidable. iOS does this for sub-pickers from Cashu Request Detail; on Android, the parent here is a *pushed screen*, so the picker can be a bottom sheet over it without nesting.

### 10.3 Dialogs

`AlertDialog` for confirmations (delete mint, delete wallet, remove Cashu Request) and one-decision alerts. Title + body + Cancel / destructive action.

### 10.4 Toasts and banners

- **Success notification** (token received) → floating M3 surface at top, slides down from above, 5s auto-dismiss, dismissible. Shadow allowed (sole exception to flat rule).
- **Inline error** → `error`-colored supporting text below the offending field. No global error toast.
- **Network errors** → red banner with retry button at the top of the affected screen.

### 10.5 Empty states

`EmptyState` composable with: `Icon` (32–48dp, `onSurfaceVariant`), title (`titleMedium`), supporting (`bodyMedium`, `onSurfaceVariant`), optional CTA (`FilledTonalButton`). Centered vertically when alone on a screen; left-aligned when it shares space.

### 10.6 Loading

- Full screen → centered `CircularProgressIndicator`.
- Top of screen, async → `LinearProgressIndicator` at the very top edge.
- Inline (button) → swap label with small `CircularProgressIndicator` (16dp).

### 10.7 Motion

Match iOS named animations as closely as Compose allows.

| iOS animation | Compose recipe |
|----------------|-----------------|
| Row stagger | `LazyColumn` items use `animateItemPlacement()` + `AnimatedVisibility` with 35ms-per-index `enterDelay`, capped at 8. |
| Badge symbol-replace | `AnimatedContent(targetState = badgeState, transitionSpec = { fadeIn(tween(280)) togetherWith fadeOut(tween(280)) })`. |
| Chooser cascade | `AnimatedVisibility` per item, 70ms-per-index delay, slide-in horizontally (12dp) + fade. |
| Press feedback | M3 native ripple + scale-on-press via `Modifier.scale()` keyed to `interactionSource.collectIsPressedAsState()`. |
| Sheet cross-fade (two-face) | `AnimatedContent` with `fadeIn(tween(250)) togetherWith fadeOut(tween(250))`. |
| Payment-received celebration | `AnimatedVisibility(enter = scaleIn(spring(0.5f, 0.7f)) + fadeIn, exit = fadeOut)` + 2.5s hold via `LaunchedEffect(Unit) { delay(2500); … }`. |
| Waiting-pulse | `rememberInfiniteTransition().animateFloat(... infiniteRepeatable(reverse))` on alpha. |

Honor `LocalAccessibilityManager.current` reduce-motion preference — skip non-essential animations.

### 10.8 Haptics

- Selection (tab change, filter change, sheet open): `HapticFeedbackType.TextHandleMove`.
- Success (receive completed): native success haptic (use `View.performHapticFeedback(HapticFeedbackConstants.CONFIRM)` via `LocalView.current`).
- Error (validation failed): `HapticFeedbackConstants.REJECT`.

### 10.9 Accessibility

- Every interactive composable has `Modifier.semantics { contentDescription = … }` or an explicit string parameter.
- Amounts announced as "Balance, 42000 satoshis" not "forty-two K".
- State conveyed by icon + color, never color alone (Pending = clock + orange).
- All text scales with system font size (no hardcoded sp outside theme).
- `Modifier.minimumInteractiveComponentSize()` on small touch targets (already default on `IconButton`).

### 10.10 Notifications (in-app event flow)

These pre-existing NotificationCenter events on iOS map to Kotlin `SharedFlow` or `StateFlow` on the existing managers:

| Event | Producer | Consumers |
|-------|---------|------------|
| Token received | `WalletManager.receiveTokens` → emit on `notifications` flow | Home toast, CashuRequestDetail celebration. |
| Transactions updated | `WalletManager.state.transactions` change | History list, Home recent. |
| Cashu Requests updated | `CashuRequestStore` flow | History list. |

---

## 11. Surface inventory (mapping anchor)

| iOS surface | Android screen / route | Notes |
|--------------|--------------------------|-------|
| Onboarding | `OnboardingScreen` (multi-step) | No bottom nav. |
| Tab: Wallet (`MainWalletView`) | `home/HomeScreen` | 3-tab `WalletScaffold` host; opens Settings as a pushed route. |
| Tab: History (`HistoryView`) | `history/HistoryScreen` | `CenterAlignedTopAppBar` (see §4 carve-out). |
| Tab: Mints (`MintsListView`) | `mints/MintsScreen` | Inline add form + Discover. |
| Settings (`SettingsView`) | `settings/SettingsScreen` | Pushed from Wallet; group list. |
| Mint Detail | `mints/MintDetailScreen` (pushed) | |
| Mint Discovery (sheet) | `mints/MintDiscoveryScreen` (pushed) | Search list → pushed route, not sheet. |
| Settings sub-screens | `settings/{Backup,Lightning,P2PK,Nostr,NWC,Privacy,Appearance}Screen` (pushed) | |
| Send chooser (sheet from Home) | `home/sheets/SendChooserSheet` (ModalBottomSheet) | Cascade in. |
| Receive chooser (sheet from Home) | `home/sheets/ReceiveChooserSheet` | Cascade in. |
| Send (unified, `.large` sheet) | `send/UnifiedSendScreen` (flow sheet, full height) | Multi-step faces; hosted by `WalletFlowSheetHost`. |
| Send Ecash (full sheet) | `send/SendEcashScreen` (flow sheet, full height) | Two-face cross-fade; swaps in-sheet from Send. |
| Contactless | `Views/Send/ContactlessPayView` (shell overlay) | |
| Receive Ecash (medium/large sheet) | `receive/ReceiveEcashScreen` (flow sheet, wrap-content) | Two-face. |
| Receive Lightning (full sheet) | `receive/ReceiveLightningScreen` (flow sheet, full height) | Two-face. |
| Cashu Request Detail (sheet/push) | `receive/CashuRequestDetailScreen` (pushed) | |
| Transaction Detail (sheet) | `history/TransactionDetailScreen` (pushed) | |
| Receive Token Detail (full-screen cover) | `receive/ReceiveTokenDetailScreen` (pushed) | Deep-link entry. |
| Scanner (full-screen cover) | `home/ScannerScreen` (pushed) | |

---

## 12. Verification checklist (per screen)

When rebuilding any screen, confirm it:

1. Matches the iOS counterpart's **information density** (no missing data; no extra surface area).
2. Offers the **same actions in roughly the same place** (top-right ≈ `TopAppBar` actions; primary footer ≈ bottom-pinned button).
3. Routes to and from the **same neighboring screens** (Home → Send/Receive choosers → flow screens → back to Home; History row → Detail → back).
4. Handles **empty / loading / error / offline / no-mint-configured** states.
5. Respects light **and** dark themes.
6. Renders correctly at default and AX5 system font scales.
7. Works on minSdk (API 26 / Android 8) and current target (API 36 / Android 14+).

Run on both a Pixel 6+ emulator and a Pixel 4 / API 26 emulator before declaring a screen done.
