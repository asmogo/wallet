---
name: Cashu Wallet
description: Privacy-first iOS wallet for Cashu ecash (incl. NUT-18 Cashu Requests over Nostr), Lightning (BOLT11 + BOLT12), on-chain Bitcoin, and NFC.
colors:
  accent-ink: "#000000"
  primary-text: "#000000"
  secondary-text: "#3C3C434D"
  separator-hair: "#3C3C4349"
  surface: "#FFFFFF"
  state-confirmed: "#34C759"
  state-pending: "#FF9500"
  state-error: "#FF3B30"
  selection-tint: "#0000001F"
  pending-tint: "#FF95001A"
  error-tint: "#FF3B302E"
typography:
  # Reified in ios/CashuWallet/DesignSystem/CashuTextRole.swift and
  # android .../ui/theme/Type.kt. Sizes are iOS pt at the default text size;
  # tracking is em, resolved against the live size. See DESIGN.md section 3.
  amountHero:
    fontSize: "52px"
    fontWeight: 600
    lineHeight: 1.1
    letterSpacing: "-0.015em"
    fontFeature: "tnum"
  amountConfirm:
    fontSize: "40px"
    fontWeight: 600
    lineHeight: 1.1
    letterSpacing: "-0.01em"
    fontFeature: "tnum"
  amountCompact:
    fontSize: "28px"
    fontWeight: 600
    lineHeight: 1.15
    fontFeature: "tnum"
  amountRow:
    fontSize: "17px"
    fontWeight: 500
    lineHeight: 1.29
    fontFeature: "tnum"
  title:
    fontSize: "28px"
    fontWeight: 600
    lineHeight: 1.14
  title3:
    fontSize: "20px"
    fontWeight: 500
    lineHeight: 1.2
  bodyEmphasis:
    fontSize: "17px"
    fontWeight: 600
    lineHeight: 1.29
  body:
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.29
  textLink:
    fontSize: "15px"
    fontWeight: 500
    lineHeight: 1.3
  metadata:
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.31
  caption:
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.33
  overline:
    fontSize: "12px"
    fontWeight: 600
    lineHeight: 1.33
    letterSpacing: "0.06em"
    textTransform: "uppercase"
  monoCaption:
    fontFamily: "SF Mono, ui-monospace, Menlo, monospace"
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.36
rounded:
  hairline: "8px"
  card: "12px"
  surface: "14px"
  large: "20px"
  capsule: "9999px"
spacing:
  micro: "4px"
  tight: "6px"
  snug: "8px"
  default: "12px"
  comfortable: "16px"
  loose: "20px"
  section: "24px"
  page: "28px"
components:
  button-glass:
    backgroundColor: "{colors.selection-tint}"
    textColor: "{colors.primary-text}"
    rounded: "{rounded.capsule}"
    padding: "18px 24px"
    typography: "{typography.body-emphasis}"
  button-utility:
    backgroundColor: "transparent"
    textColor: "{colors.secondary-text}"
    rounded: "{rounded.capsule}"
    padding: "6px 16px"
    typography: "{typography.caption}"
  row-history:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.primary-text}"
    padding: "12px 16px"
    typography: "{typography.body-emphasis}"
  badge-pending:
    backgroundColor: "{colors.pending-tint}"
    textColor: "{colors.state-pending}"
    rounded: "{rounded.capsule}"
    padding: "4px 8px"
    typography: "{typography.caption-emphasis}"
  badge-confirmed:
    backgroundColor: "transparent"
    textColor: "{colors.state-confirmed}"
    rounded: "{rounded.capsule}"
    padding: "4px 8px"
    typography: "{typography.caption-emphasis}"
  transaction-icon:
    backgroundColor: "Color(.secondarySystemFill)"
    textColor: "{colors.secondary-text}"
    rounded: "circle"
    iconSymbol: "arrow.down (incoming) / arrow.up (outgoing)"
    iconSize: "16px"
    note: "Leading 36x36 history-row glyph (TransactionIcon). Pure directional arrow, always muted; direction is the arrow's orientation, never colour. The primary amount carries state: green +amount for completed incoming, unsigned .primary for completed outgoing, .secondary for pending/expired. Carve-out: supersedes the prior kind-glyph + corner directional badge model."
  row-inspector-editable:
    backgroundColor: "transparent"
    textColor: "{colors.primary-text}"
    secondaryTextColor: "{colors.secondary-text}"
    padding: "12px 8px"
    typography: "{typography.body}"
    trailingHintSymbol: "pencil"
    leadingSymbol: null
    note: "Cashu Request detail. Label + value only, no leading field icon (Iconless-Row Rule). Tap opens a medium-detent sub-sheet."
  divider-canvas:
    backgroundColor: "{colors.separator-hair}"
    height: "0.5px"
---

# Design System: Cashu Wallet

## 1. Overview

**Creative North Star: "The System Utility"**

Cashu Wallet should feel like one of Apple's own first-party apps — Wallet, Notes,
Find My, Health — quietly slotted into iOS rather than painted on top of it. The
target sensation when a user picks it up for the first time: "this is the wallet
Apple would have shipped if Apple shipped ecash." Identity is deliberately absent,
because the identity *is* "behaves correctly on iPhone."

The system commits to native materials, native typography, native motion, and the
native semantic palette. Liquid Glass on iOS 26+ is the single concession to the
current OS generation; below 26, the same surfaces fall back to system materials
(`.thinMaterial`, `.quaternary`) without losing structural intent. Colour is
reserved for state, never for brand. Numbers get the typographic care of a
chronograph face. Pending values stay quiet; only confirmed values are allowed
green.

What this system explicitly rejects, pulled verbatim from docs/product/PRODUCT.md:

- Gamified crypto consumer apps (MetaMask, Coinbase Wallet, Trust Wallet)
- Hero-metric SaaS dashboards
- Neon-on-black "crypto default" aesthetic
- Heavy custom branding (mascots, illustrated empty states, signature gradients)

**Key Characteristics:**

- Semantic-only palette. Zero custom color extensions. `Color.primary`,
  `Color.secondary`, `Color.accentColor` plus three state hues (green, orange, red).
- Inverted-ink `AccentColor`: pure black in light mode, pure white in dark mode.
  Pure black/white appears here, in scanner overlays, and inside QR codes only.
- One sans family: San Francisco at native iOS text styles. No display pairings,
  no custom fonts, no fluid clamps.
- Liquid Glass on iOS 26+ for primary interactive surfaces. Quiet fallbacks below.
- Hairline `CanvasDivider` (0.5pt at `Color(.separator)`) where a single-canvas
  detail needs separation. Home and History activity rows use spacing alone.
  No card stacks, no nested containers — with one narrow, documented exception
  for the seed cards (The Seed Card Exception, §5).
- Motion is exponential ease-out, in the 180–350ms range. Seven named animations
  carry the full vocabulary: row stagger, badge symbol-replace, chooser cascade,
  press feedback, sheet cross-fade (in-sheet flow swap), payment-received
  celebration, and waiting-pulse. Nothing decorative beyond that.
- One inspector pattern for editable detail rows (Cashu Request → Mint, Amount):
  secondary label + trailing value (medium weight, middle-truncated) + trailing
  `pencil` hint glyph. Tap opens a `.medium`-detent sub-sheet rather than pushing
  a screen. No leading field icon — see The Iconless-Row Rule, §5.

### Unified activity detail sheets (2026-09-06)

History and Home activity details share native sheet presentation on iOS and
Android, while retaining the existing payment-specific content and actions.

- Every transaction and stored receive request opens a sheet over its list with
  a centered title and drag handle. Dismiss by swipe, native accessibility escape,
  or Android Back. No redundant top-left close X.
- Show a visible Share action at the top right whenever the payment artifact is
  shareable. QR context-menu Copy/Share and the visible Copy button remain.
- Keep QR codes immediately visible in their original position above the amount.
  Preserve adaptive QR sizing, compact amounts beside a QR, normal receipt amounts,
  and the existing rows and spacing. No QR disclosure or collapse animation.
- Preserve the green check for completed receipts and red cross for failed
  receipts, plus the lifecycle text. Reusable requests retain their payment-count
  status and live QR after receiving payments.
- Keep Copy, New Request, and inline Mint/Amount/Unit editing directly available
  on Cashu Requests. Reuse the existing request view and its delivery behavior.
- Preserve pending outbound invoice/address QR and copy/share availability,
  settled ecash Copy, explorer/proof references, and manual token status checks.
  Settled one-shot codes retire as before.
- Unclaimed incoming ecash opens the shared sheet with Receive to enter the
  claim flow. Keep action footers visible while long detail content scrolls.

## 2. Colors: The Inverted-Ink Palette

A semantic-only palette built on iOS system colors plus three state hues. The
single committed brand choice is the inverted `AccentColor`: black on light, white
on dark.

### Primary

- **System Ink** (light `#000000` / dark `#FFFFFF`): the `AccentColor` defined in
  `ios/CashuWallet/Resources/Assets.xcassets/AccentColor.colorset`. Used for tints and
  the 15% primary-color frost behind every `glassButton()` capsule (see
  `FullWidthCapsuleButtonStyle`). The ink reads as system label everywhere; there
  is no inverted-fill variant — Liquid Glass is the singular primary surface.

### Neutral

- **Label** (`Color.primary`, light `#000000` / dark `#FFFFFF`): every body line
  and every non-state text element. Roughly 14+ direct usages.
- **Secondary Label** (`Color.secondary`, light `#3C3C434D` / dark `#EBEBF599`):
  timestamps, captions, hint text, the truncated Lightning address chip, the
  unit-toggle ("sats" / "₿") label.
- **Surface** (`Color(.systemBackground)`, light `#FFFFFF` / dark `#000000`): the
  canvas behind every screen, and every background that needs to contrast with
  `.primary` ink.
- **Hairline** (`Color(.separator)`, light `#3C3C4349` / dark `#54545899`): the
  fill of `CanvasDivider` (0.5pt). The only separator on a canvas.

### State

State colors are iOS system semantics, never custom hex. They appear at full
opacity for foreground (icon, status text) and at low opacity (10–18%) when used
as a tinted background.

- **Confirmed Green** (`Color.green`, ≈ `#34C759` / `#30D158`): green is the
  receiver's reward. A completed incoming transaction or received Cashu Request
  uses green for its primary `+amount`; outgoing amounts remain `.primary`, and
  pending/expired amounts remain `.secondary`. Green also lives in
  **off-row / detail-surface success states**: the
  default-mint indicator dot; the `checkmark.seal.fill` "N payments received"
  status and `checkmark.circle.fill` toast inside `CashuRequestDetailView`; the
  64pt `checkmark.circle.fill` success icon on `PaymentStatusView`; and the same
  64pt completed check on the transaction detail sheet (`TransactionDetailView`).
  *As of 2026-07-05 the home received-delta beat is no longer green.* The leading
  directional arrow is always `.secondary` regardless of direction or state;
  only the received primary amount turns green on a ledger row.
- **Pending Orange** (`Color.orange`, ≈ `#FF9500` / `#FF9F0A`): foreground for the
  "Waiting for payment…" clock on a Cashu Request and the amber
  `exclamationmark.triangle.fill` caution on `PaymentStatusView`. It does **not**
  appear on a transaction *row* — a pending row is the muted `.secondary` amount
  alone (amended 2026-06-01) — nor on the transaction detail sheet, whose pending
  state is a monochrome "Pending" `Status` row (2026-07-05(c)). When used as a
  background it lives at `.opacity(0.1)` — the quiet-pending principle made visual.
- **Error Red** (`Color.red`, ≈ `#FF3B30` / `#FF453A`): the `.failed` status
  foreground and destructive-action accents. As a tint background it appears at
  `.opacity(0.18)` (e.g. the authorizing-overlay destructive surface).

### Selection / Pressed

- **Selection Tint** (`Color.primary.opacity(0.12)`): selected toggle capsules in
  Receive Lightning, multi-select chips. Tints, never fills.
- **Press feedback**: opacity drop to `0.7` (disabled to `0.4`) inside
  `FullWidthCapsuleButtonStyle`, plus the `PressableButtonStyle` 0.97 scale (0.09s
  down, 0.18s spring back). No color shift.

### Named Rules

**The Semantic-Only Rule.** No file in `ios/CashuWallet/` defines a custom
`extension Color`. If a new color is needed, it is either a system semantic
(`Color.primary`, `Color.secondary`, `Color.accentColor`, `Color(.systemBackground)`,
`Color(.separator)`) or one of three state hues at a stated opacity. There is no
fourth case.

**The One Green Rule.** *Amended 2026-07-21:* within a ledger row, green belongs
only to the primary amount of completed incoming money: green `+amount` for an
incoming transaction or received Cashu Request. A completed outgoing amount is
unsigned `.primary`; pending and expired amounts are unsigned `.secondary`.
The title, timestamp, leading arrow, and converted sub-amount never turn green.
The shared `TransactionAmountColumn` is the canonical implementation; do not
re-derive the sign or color elsewhere. Direction for outgoing rows is already
carried by the title and upward arrow, so a minus sign adds noise without new
information.

Outside ledger rows, confirmed green also appears in deliberate success and
selection states, including:
1. The **default-mint indicator dot** — a small green dot on a mint's icon
   (Mints list `MintsListView`, mint profile `MintDetailView`) marking the
   user's selected default mint. A *selection* marker (same axis as "Set as
   Default"), carries no amount or arrow, never appears on a transaction row
   (added 2026-05-31).
*Amended 2026-07-05: the home-screen received-delta beat is no longer green.* The
green `✓ +amount` celebration under the balance was retired as corny; the hero
balance now rolls upward (`.contentTransition(.numericText())`) and a **monochrome**
`+amount` (`.secondary`, in `MainWalletView.receivedDeltaBeat`) confirms the exact
receipt in the fiat slot, with a `.success` haptic for background receipts.

*Amended 2026-07-05(b)→(c): what was "corny" was the **small** green
`checkmark.circle.fill` + "Received" **worded badge**, not green itself.* The brief
2026-07-05(b) removal of the green check from `PaymentStatusView` and the detail
sheet was **reverted**. `PaymentStatusView` success keeps its 64pt green
`checkmark.circle.fill` (`.symbolEffect(.bounce)`) with the amount as a detail row
— unchanged from before. The detail sheet regains a green check too, but as the
**large** 64pt one (below); only the small worded "✓ Received" badge stays retired.
`CashuRequestDetailView`'s green pills + "N payments received" seal are unchanged
(their own later pass).

The detail sheet (`TransactionDetailView`) is a **hero state slot above a crisp
`.primary` amount hero**. A completed transaction opens as a compact native
receipt sheet over its activity list, with no explicit close control; swipe or
tap the scrim to dismiss. The presenting canvas takes a restrained 2–2.5pt blur
beneath the native dimming scrim. Pending, failed, expired, QR, and claim/check states
retain the large detail workspace. The slot resolves by state: an **actionable request**
shows its QR (unclaimed outgoing token — gated on `status == .pending` since the
token string is retained after claim — a pending invoice, or a reusable BOLT12
offer, `lno` prefix); a **completed** transaction shows the 64pt green
`checkmark.circle.fill`; a **failed** one shows the 64pt red `xmark.circle.fill`;
both bounce in on open (`.symbolEffect(.bounce, value: didAppear)`), matching the
payment-success entrance. A **pending, no-QR** transaction shows no glyph. The old
directional-arrow-on-a-circle hero and the small green "✓ Received" badge are gone.
State also rides an explicit **`Status` row** — the first detail row, monochrome
value (the hero glyph already carries the colour): completed → **Claimed** (ecash)
/ **Paid** (lightning) / **Confirmed** (on-chain); pending → **Pending**; failed →
**Failed**; expired → **Expired** *(added 2026-07-21: an unpaid BOLT11 invoice
past its quote expiry — the QR/Share/Copy retire with it and the hero stays
empty like a pending no-QR row; no red X, since nothing failed, the invoice
simply lapsed. A quote paid before expiry stays **Pending** even past expiry —
NUT-04 lets it be minted afterwards)*. A **`Date` row** follows. Metadata is a
plain two-column label/value list with no leading field icons; only copyable
values receive a trailing affordance. Remaining rows are conditional essentials —
**Fee** when `> 0`, **Mint** always; the **Unit** row and the settled **Request**
row stay dropped (`unitLabel` is always BTC/SAT; the live request is the QR/Copy).
Opaque reference values, including **Payment Proof**, render as
`prefix(8)…suffix(6)` while their Copy action preserves the full value.
On-chain keeps **Address** / **Transaction ID** and its address QR. The **Type**
row stays omitted (the nav title names kind/direction).

**The Settled-Ecash Receipt carve-out.** *Added 2026-07-05.* A **settled ecash
token** (completed, either direction) additionally exposes the **bottom Copy
button as a quiet secondary tonal action** — it copies the raw token string as a *record* of what was
received/sent. This is a deliberate exception to the actionability gate above: a
claimed token is spent, so the QR hero and top **Share stay retired** for it (the
green-check "done" hero and the "Claimed" Status row already read the screen as
settled). Only the *passive* Copy is extended, via a `copyableContent` slot
distinct from `showsQR` — a spent token must never be re-presented as a scannable
or shareable payment code. Consistent with the Share-At-Top Rule below, which
governs sheets that *display a shareable QR artifact* (a settled ecash row shows
none). Received tokens are persisted at redeem time for this — Copy surfaces only
on rows received/sent after this shipped, since older received tokens were
discarded and can't be recovered.

**The Quiet Pending Rule.** *Amended 2026-06-01.* On **any list row** —
transaction or Cashu Request — pending/waiting is conveyed by the muted
`.secondary` amount **alone**: no badge, no icon, no orange. (The
`arrow.triangle.2.circlepath` per-row refresh button *and* the waiting-request
leading `clock` were both removed; manual re-check lives on History
pull-to-refresh — `.refreshable { syncPendingMintQuotes(); checkAllPendingTokens() }`.)
The muted-orange pending language survives only off the list, on the
"Waiting for payment…" status clock inside `CashuRequestDetailView`. (The detail
sheet's pending state is now a monochrome "Pending" `Status` row — no orange,
2026-07-05(c).) Never a full-saturation pill, never a loud "PENDING" wordmark.

*Amended 2026-07-21: only a completed incoming row uses a sign: green `+amount`.
Completed outgoing rows are unsigned and `.primary`; their title and upward arrow
already carry direction. Pending and expired rows are also unsigned and muted.
Cashu Request / Reusable Invoice rows follow the same rule: waiting is bare and
muted, received is green with `+`.*

*Amended 2026-07-21: **expired** rows (`isUnsettled` = pending or expired) keep
the same bare, muted amount — an expired invoice never credited the balance, so
it must not read as settled.*

**The Fiat Sub-Amount Rule.** When
`settings.showFiatBalance && priceService.btcPriceUSD > 0`, any sat-unit row
renders its configured primary amount with the converted value below it in
`.system(.subheadline, design: .rounded).weight(.regular) / .secondary /
.monospacedDigit()`. The primary value is the neighboring
`.system(.body, design: .rounded).weight(.medium)`: enough hierarchy to preserve
the configured primary currency without making the conversion read like tiny
metadata. Cashu Request "any amount" rows (no fixed expected total) render no
trailing element and therefore no fiat. Fiat re-renders silently on price
ticks; no `.contentTransition`. Same gate as the hero balance fiat line, so
turning fiat off in Settings clears the entire app uniformly.

**The Amount Column Rule.** No list row has a left-of-amount indicator anymore
— both the transaction `arrow.triangle.2.circlepath` refresh button and the
waiting-Cashu-Request `clock` were removed (2026-06-01). Every row's amount
anchors to the trailing edge so the column reads as one straight vertical line
down the list. The `Spacer(minLength:)` before the amount column pushes the
amount right; the trailing edge stays fixed.

## 3. Typography

*Rewritten 2026-08-03. The system below is reified in code — it is no longer
prose that the implementation is expected to follow by hand. That gap is what
produced 465 `.font()` call sites across ~65 distinct specs, six sizes serving
one amount role, and a home balance in a different typeface from the amount you
type one screen later.*

**Body Font:** San Francisco (`SF Pro`), via the iOS system font stack. No
`Font.custom(...)`, no font files in `Resources/`. **This is an iOS-specific
rule**, and the reason is worth recording: SF Symbols are drawn to SF Pro's cap
height and weight axis, so pairing them with any other family desynchronises
icon-and-label alignment across every `Label`, settings row and the tab bar —
and alerts, action sheets, the share sheet and the keyboard render in SF Pro
regardless, so a bundled body face would leave the app permanently mixed-face.
Android incurs neither cost and ships Geist; see DESIGN-ANDROID.md.

**Mono Font:** San Francisco Mono, used for token IDs, mnemonic words, and any
place a hex/base58 string would otherwise blur.

**Character:** the silent typographic confidence of a native iOS app. Type is
applied by *role*, through `.cashuText(_:)` and `.cashuAmount(_:value:)` — never
by a bare `.system(size:)` or a hand-written `.tracking()`. A role carries font,
face, weight, tracking, casing, line limit and numeric treatment as one value,
because those travelling separately is exactly how a call site came to take the
size and forget the tracking, or take the tabular figures and forget the digit
transition.

### The roles

Defined in `ios/CashuWallet/DesignSystem/CashuTextRole.swift`.

| Role | Size | Weight | Tracking | Notes |
|---|---|---|---|---|
| `amountHero` | 52pt, scaled vs `.largeTitle`, capped 70 | semibold | −0.015em | balance **and** amount entry |
| `amountConfirm` | 40pt, vs `.title`, capped 56 | semibold | −0.010em | transaction detail |
| `amountCompact` | 28pt, vs `.title2`, capped 40 | semibold | −0.005em | Lightning, Cashu Request, QR-adjacent |
| `amountRow` | `.body` | medium | 0 | list rows, fee lines, sub-balances |
| `numberPadKey` | `.title` | regular | 0 | tabular, so keys don't shift width |
| `title` | `.title` | semibold | 0 | onboarding heroes, modal headings |
| `title3` | `.title3` | medium | 0 | in-flow section heads |
| `bodyEmphasis` | `.body` | semibold | 0 | button labels, row titles |
| `body` | `.body` | regular | 0 | prose, settings rows, detail values |
| `textLink` | `.subheadline` | medium | 0 | borderless tertiary actions |
| `metadata` | `.footnote` | regular | 0 | timestamps, secondary row text |
| `caption` | `.caption` | regular | 0 | incidental chrome only |
| `overline` | `.caption` | semibold | 0.06em | uppercase section headers |
| `monoBody` / `monoCaption` | `.subheadline` / `.caption2` | regular | 0 | hex, mnemonics, npubs |

**Metadata sits at `.footnote` (13pt), not `.caption` (12pt).** Metadata is
already demoted by secondary ink; stacking the 12pt floor on top of that is a
double demotion that pushes it under the legibility line. `caption` and
`caption2` are reserved for genuinely incidental chrome.

### Notes on particular roles

- **The amount ladder is four rungs and no more.** Amounts are typed by role,
  never by point size. Six sizes serving this one job (64/56/53/48/44/32) is how
  the balance and the amount being typed one screen later ended up in different
  typefaces at different weights. `amountHero` covers the balance *and* live
  entry deliberately: they are the same object and now say so.
- **No `design: .rounded`.** It previously applied to the send/receive heroes
  but not the home balance, so the two most important numbers in the app were
  set in different faces. Everything is SF Pro.
- **Navigation-bar titles** — including the sheet/flow screens (Send, Pending
  Ecash, Pay, Receive, Lightning Invoice) — use the **native inline title**
  (`.navigationTitle` + `.navigationBarTitleDisplayMode(.inline)`), so they
  centre to the screen and scale via the system. Do not use `title3` or an
  ad-hoc `.principal` font for a nav-bar title.
- **Text Link** is always applied via `.textLinkButton()`
  (`TextLinkButtonStyle`), never hand-rolled per site: "Skip" / "Skip for now",
  "What is ecash?", "Copy", "Add custom mint URL".
- **Overline** is the only uppercase in the system, and casing lives in the role
  so no call site has to remember it. Use the shared `SectionHeader`.

### Named Rules

**The Semantic-Only Rule.** No file in `ios/CashuWallet/` defines a custom
`extension Color`. If a new color is needed, it is either a system semantic
(`Color.primary`, `Color.secondary`, `Color.accentColor`, `Color(.systemBackground)`,
`Color(.separator)`) or one of three state hues at a stated opacity. There is no
fourth case.

**The One Green Rule.** *Amended 2026-07-21:* within a ledger row, green belongs
only to the primary amount of completed incoming money: green `+amount` for an
incoming transaction or received Cashu Request. A completed outgoing amount is
unsigned `.primary`; pending and expired amounts are unsigned `.secondary`.
The title, timestamp, leading arrow, and converted sub-amount never turn green.
The shared `TransactionAmountColumn` is the canonical implementation; do not
re-derive the sign or color elsewhere. Direction for outgoing rows is already
carried by the title and upward arrow, so a minus sign adds noise without new
information.

Outside ledger rows, confirmed green also appears in deliberate success and
selection states, including:
1. The **default-mint indicator dot** — a small green dot on a mint's icon
   (Mints list `MintsListView`, mint profile `MintDetailView`) marking the
   user's selected default mint. A *selection* marker (same axis as "Set as
   Default"), carries no amount or arrow, never appears on a transaction row
   (added 2026-05-31).
*Amended 2026-07-05: the home-screen received-delta beat is no longer green.* The
green `✓ +amount` celebration under the balance was retired as corny; the hero
balance now rolls upward (`.contentTransition(.numericText())`) and a **monochrome**
`+amount` (`.secondary`, in `MainWalletView.receivedDeltaBeat`) confirms the exact
receipt in the fiat slot, with a `.success` haptic for background receipts.

*Amended 2026-07-05(b)→(c): what was "corny" was the **small** green
`checkmark.circle.fill` + "Received" **worded badge**, not green itself.* The brief
2026-07-05(b) removal of the green check from `PaymentStatusView` and the detail
sheet was **reverted**. `PaymentStatusView` success keeps its 64pt green
`checkmark.circle.fill` (`.symbolEffect(.bounce)`) with the amount as a detail row
— unchanged from before. The detail sheet regains a green check too, but as the
**large** 64pt one (below); only the small worded "✓ Received" badge stays retired.
`CashuRequestDetailView`'s green pills + "N payments received" seal are unchanged
(their own later pass).

The detail sheet (`TransactionDetailView`) is a **hero state slot above a crisp
`.primary` amount hero**. A completed transaction opens as a compact native
receipt sheet over its activity list, with no explicit close control; swipe or
tap the scrim to dismiss. The presenting canvas takes a restrained 2–2.5pt blur
beneath the native dimming scrim. Pending, failed, expired, QR, and claim/check states
retain the large detail workspace. The slot resolves by state: an **actionable request**
shows its QR (unclaimed outgoing token — gated on `status == .pending` since the
token string is retained after claim — a pending invoice, or a reusable BOLT12
offer, `lno` prefix); a **completed** transaction shows the 64pt green
`checkmark.circle.fill`; a **failed** one shows the 64pt red `xmark.circle.fill`;
both bounce in on open (`.symbolEffect(.bounce, value: didAppear)`), matching the
payment-success entrance. A **pending, no-QR** transaction shows no glyph. The old
directional-arrow-on-a-circle hero and the small green "✓ Received" badge are gone.
State also rides an explicit **`Status` row** — the first detail row, monochrome
value (the hero glyph already carries the colour): completed → **Claimed** (ecash)
/ **Paid** (lightning) / **Confirmed** (on-chain); pending → **Pending**; failed →
**Failed**; expired → **Expired** *(added 2026-07-21: an unpaid BOLT11 invoice
past its quote expiry — the QR/Share/Copy retire with it and the hero stays
empty like a pending no-QR row; no red X, since nothing failed, the invoice
simply lapsed. A quote paid before expiry stays **Pending** even past expiry —
NUT-04 lets it be minted afterwards)*. A **`Date` row** follows. Metadata is a
plain two-column label/value list with no leading field icons; only copyable
values receive a trailing affordance. Remaining rows are conditional essentials —
**Fee** when `> 0`, **Mint** always; the **Unit** row and the settled **Request**
row stay dropped (`unitLabel` is always BTC/SAT; the live request is the QR/Copy).
Opaque reference values, including **Payment Proof**, render as
`prefix(8)…suffix(6)` while their Copy action preserves the full value.
On-chain keeps **Address** / **Transaction ID** and its address QR. The **Type**
row stays omitted (the nav title names kind/direction).

**The Settled-Ecash Receipt carve-out.** *Added 2026-07-05.* A **settled ecash
token** (completed, either direction) additionally exposes the **bottom Copy
button as a quiet secondary tonal action** — it copies the raw token string as a *record* of what was
received/sent. This is a deliberate exception to the actionability gate above: a
claimed token is spent, so the QR hero and top **Share stay retired** for it (the
green-check "done" hero and the "Claimed" Status row already read the screen as
settled). Only the *passive* Copy is extended, via a `copyableContent` slot
distinct from `showsQR` — a spent token must never be re-presented as a scannable
or shareable payment code. Consistent with the Share-At-Top Rule below, which
governs sheets that *display a shareable QR artifact* (a settled ecash row shows
none). Received tokens are persisted at redeem time for this — Copy surfaces only
on rows received/sent after this shipped, since older received tokens were
discarded and can't be recovered.

**The Quiet Pending Rule.** *Amended 2026-06-01.* On **any list row** —
transaction or Cashu Request — pending/waiting is conveyed by the muted
`.secondary` amount **alone**: no badge, no icon, no orange. (The
`arrow.triangle.2.circlepath` per-row refresh button *and* the waiting-request
leading `clock` were both removed; manual re-check lives on History
pull-to-refresh — `.refreshable { syncPendingMintQuotes(); checkAllPendingTokens() }`.)
The muted-orange pending language survives only off the list, on the
"Waiting for payment…" status clock inside `CashuRequestDetailView`. (The detail
sheet's pending state is now a monochrome "Pending" `Status` row — no orange,
2026-07-05(c).) Never a full-saturation pill, never a loud "PENDING" wordmark.

*Amended 2026-07-21: only a completed incoming row uses a sign: green `+amount`.
Completed outgoing rows are unsigned and `.primary`; their title and upward arrow
already carry direction. Pending and expired rows are also unsigned and muted.
Cashu Request / Reusable Invoice rows follow the same rule: waiting is bare and
muted, received is green with `+`.*

*Amended 2026-07-21: **expired** rows (`isUnsettled` = pending or expired) keep
the same bare, muted amount — an expired invoice never credited the balance, so
it must not read as settled.*

**The Fiat Sub-Amount Rule.** When
`settings.showFiatBalance && priceService.btcPriceUSD > 0`, any sat-unit row
renders its configured primary amount with the converted value below it in
`.system(.subheadline, design: .rounded).weight(.regular) / .secondary /
.monospacedDigit()`. The primary value is the neighboring
`.system(.body, design: .rounded).weight(.medium)`: enough hierarchy to preserve
the configured primary currency without making the conversion read like tiny
metadata. Cashu Request "any amount" rows (no fixed expected total) render no
trailing element and therefore no fiat. Fiat re-renders silently on price
ticks; no `.contentTransition`. Same gate as the hero balance fiat line, so
turning fiat off in Settings clears the entire app uniformly.

**The Amount Column Rule.** No list row has a left-of-amount indicator anymore
— both the transaction `arrow.triangle.2.circlepath` refresh button and the
waiting-Cashu-Request `clock` were removed (2026-06-01). Every row's amount
anchors to the trailing edge so the column reads as one straight vertical line
down the list. The `Spacer(minLength:)` before the amount column pushes the
amount right; the trailing edge stays fixed.

## 3. Typography

*Rewritten 2026-08-03. The system below is reified in code — it is no longer
prose that the implementation is expected to follow by hand. That gap is what
produced 465 `.font()` call sites across ~65 distinct specs, six sizes serving
one amount role, and a home balance in a different typeface from the amount you
type one screen later.*

**Body Font:** San Francisco (`SF Pro`), via the iOS system font stack. No
`Font.custom(...)`, no font files in `Resources/`. **This is an iOS-specific
rule**, and the reason is worth recording: SF Symbols are drawn to SF Pro's cap
height and weight axis, so pairing them with any other family desynchronises
icon-and-label alignment across every `Label`, settings row and the tab bar —
and alerts, action sheets, the share sheet and the keyboard render in SF Pro
regardless, so a bundled body face would leave the app permanently mixed-face.
Android incurs neither cost and ships Geist; see DESIGN-ANDROID.md.

**Mono Font:** San Francisco Mono, used for token IDs, mnemonic words, and any
place a hex/base58 string would otherwise blur.

**Character:** the silent typographic confidence of a native iOS app. Type is
applied by *role*, through `.cashuText(_:)` and `.cashuAmount(_:value:)` — never
by a bare `.system(size:)` or a hand-written `.tracking()`. A role carries font,
face, weight, tracking, casing, line limit and numeric treatment as one value,
because those travelling separately is exactly how a call site came to take the
size and forget the tracking, or take the tabular figures and forget the digit
transition.

### The roles

Defined in `ios/CashuWallet/DesignSystem/CashuTextRole.swift`.

| Role | Size | Weight | Tracking | Notes |
|---|---|---|---|---|
| `amountHero` | 52pt, scaled vs `.largeTitle`, capped 70 | semibold | −0.015em | balance **and** amount entry |
| `amountConfirm` | 40pt, vs `.title`, capped 56 | semibold | −0.010em | transaction detail |
| `amountCompact` | 28pt, vs `.title2`, capped 40 | semibold | −0.005em | Lightning, Cashu Request, QR-adjacent |
| `amountRow` | `.body` | medium | 0 | list rows, fee lines, sub-balances |
| `numberPadKey` | `.title` | regular | 0 | tabular, so keys don't shift width |
| `title` | `.title` | semibold | 0 | onboarding heroes, modal headings |
| `title3` | `.title3` | medium | 0 | in-flow section heads |
| `bodyEmphasis` | `.body` | semibold | 0 | button labels, row titles |
| `body` | `.body` | regular | 0 | prose, settings rows, detail values |
| `textLink` | `.subheadline` | medium | 0 | borderless tertiary actions |
| `metadata` | `.footnote` | regular | 0 | timestamps, secondary row text |
| `caption` | `.caption` | regular | 0 | incidental chrome only |
| `overline` | `.caption` | semibold | 0.06em | uppercase section headers |
| `monoBody` / `monoCaption` | `.subheadline` / `.caption2` | regular | 0 | hex, mnemonics, npubs |

**Metadata sits at `.footnote` (13pt), not `.caption` (12pt).** Metadata is
already demoted by secondary ink; stacking the 12pt floor on top of that is a
double demotion that pushes it under the legibility line. `caption` and
`caption2` are reserved for genuinely incidental chrome.

### Hierarchy

- **Balance** (`.largeTitle.bold()` + `.monospacedDigit()` + `.contentTransition(.numericText())`):
  the wallet balance and the recovered-amount counter. Tabular figures, animated
  digit-by-digit on change. The single most important typographic moment in the
  app. `MainWalletView.swift:93`, `AnimatedBalanceView.swift`.
- **Onboarding Hero** (`.largeTitle.weight(.heavy)` + `.tracking(-0.5)`): one
  treatment for every step's title, welcome included — all of them the top
  `OnboardingStepHeader` in `OnboardingChassis.swift`.
- **Title** (`.title.weight(.heavy)` / `.weight(.semibold)`): the "What is
  ecash?" concept-sheet heading. `OnboardingView.swift` (`conceptSheet`).
- **Title3** (`.title3.weight(.medium)`): in-flow section heads such as the
  send/receive transaction-type label, and in-body modal headings.
  `MainWalletView.swift:165`. Note: navigation-bar titles — including the
  sheet/flow screens (Send, Pending Ecash, Pay, Receive, Lightning Invoice) —
  use the **native inline title** (`.navigationTitle` + `.navigationBarTitleDisplayMode(.inline)`,
  ~17pt), so they center to the screen and scale via the system. Do not use
  Title3 (or an ad-hoc `.principal` font) for a nav-bar title.
- **Body Emphasis** (`.body.weight(.semibold)`): primary button labels (inside
  `glassButton()` / `FullWidthCapsuleButtonStyle`), history row title.
- **Body** (`.body`): default for prose, settings rows, detail values.
- **Text Link** (`.subheadline.weight(.medium)`, `.secondary`): borderless
  tertiary actions — "Skip" / "Skip for now", "Copy",
  "Add custom mint URL". Always applied via `.textLinkButton()`
  (`TextLinkButtonStyle`), never hand-rolled per site.
- **Callout** (`.callout`): supporting descriptive text under hero headings,
  e.g. "An ecash wallet for Bitcoin and Lightning." — the onboarding chassis
  subhead slot (`OnboardingChassis.swift`).
- **Caption Emphasis** (`.caption.weight(.semibold)`, tracking `0.06em`,
  uppercase): history section headers ("TODAY", "YESTERDAY", "THIS WEEK").
  `HistoryView.swift:140`.
- **Caption** (`.caption` / `.caption2`): timestamps, pending badges, unit toggle.
- **Mono Caption** (`.system(.caption2, design: .monospaced)`): truncated
  Lightning addresses, token IDs, anywhere a hex string would otherwise mush.
  `MainWalletView.swift:138`.

### Named Rules

**The Tabular Figure Rule.** Every balance, amount, and fee chains
`.monospacedDigit()`. Every numeric value that changes chains
`.contentTransition(.numericText(value:))` so digits slide rather than reflow.
This is non-negotiable; numeric jitter on a money value reads as broken.

**The System-Style Rule.** *Amended 2026-08-03.* Text is applied by role
(`.cashuText(_:)` / `.cashuAmount(_:value:)`), and roles resolve to named iOS
text styles so Dynamic Type works from xSmall through AX5. A bare
`.system(size:)` outside `DesignSystem/` is a bug; the only exceptions are SF
Symbol glyph sizes and the ActivityOrb. No `.system(size: 14)` to "make it fit";
pick the right role and let the layout breathe.

**The Leading Rule.** *Added 2026-08-03.* A size change is a line-box change.
Hero roles carry their own leading, and a reserved height for a hero is computed
from `CashuTextRole.lineHeight(at:fonts:)` — never from a constant. A constant
box around scaled text is a crop waiting to happen: the home status line held an
18pt slot around a `.body`, whose line box is ~22pt, so it was clipping at the
*default* text size. Reserved heights must stay fixed within a text size, so a
unit swap cannot reflow the canvas, while growing with it, so large text is not
cropped. (Android enforces the same rule mechanically via `TextStyle.atSize`;
see DESIGN-ANDROID.md.)

**The Size-Role Rule.** *Added 2026-08-03.* Amounts are typed by role —
`amountHero` / `amountConfirm` / `amountCompact` / `amountRow` — never by point
size. Six sizes serving one role is how the same number came to render in two
typefaces on adjacent screens.

**The Lockup Rule.** *Added 2026-08-03.* A unit is never joined into a numeral
string. Formatters return `AmountParts { value, affix }` and `AmountLockup`
composes the two, subordinating a unit *word* on three axes — half the size, one
weight step down, secondary ink — while leaving a currency *symbol* at full ink
and weight. The unit sits on the digits' **baseline**, not their cap line: a unit
word is lowercase, so its visual mass is at x-height, and lifting it to the cap
line leaves it floating like a superscript. At parity the unit occupied roughly a
third of the lockup while carrying none of the information.

**Tracking is expressed in em, never in points.** A point value is correct at one
text size and wrong at every other. Five of the six hand-rolled section headers
froze `.tracking(1.2)` — 0.1em at 12pt, nearly double the documented 0.06em.

## 4. Elevation

The system is **flat by default with one elevation layer**: Liquid Glass on iOS
26+, falling back to `.thinMaterial` or `.quaternary` below. Surfaces sit
directly on the canvas; depth comes from material translucency and the
`CanvasDivider` hairline, not from shadows.

There are **no** `.shadow(...)` modifiers in the production view tree. Depth is
carried entirely by Liquid Glass materials and the `CanvasDivider` hairline; the
only "lift" the system ships is a single subtle press scale (0.97 via
`PressableButtonStyle`, 0.09s down / 0.18s spring back). (The home-screen success
toast that once held the lone shadow was retired in favor of the balance-anchored
received-delta beat — see Notifications.)

### Material Vocabulary

- **Liquid Glass — Regular** (iOS 26+, `.glassEffect(.regular, in: shape)`):
  primary interactive containers (unit toggle, action buttons, capsule chips on
  the main canvas). Adapts to ambient color; behaves correctly under scroll.
- **Liquid Glass — Interactive** (iOS 26+, `.regular.interactive()`): when the
  surface must respond to press with the system's own glass distortion. Used by
  `.liquidGlass(in:, interactive: true)`.
- **Fallback — Thin Material** (`.thinMaterial`): input fields, token chips,
  receive/send container surfaces on iOS < 26. ~14 usages.
- **Fallback — Quaternary Fill** (`Color.quaternary`): when the surface is too
  small or too dense for a material blur to read cleanly.

### Named Rules

**The Flat-By-Default Rule.** No drop shadows on cards, buttons, rows, or any
surface that lives *in* the canvas. No glow rings, no inner shadows, no glossy
highlights. Depth on the canvas is conveyed by translucent materials and
hairline `CanvasDivider`s, not by elevation geometry.

**No-Shadow Absolute.** There are zero `.shadow(...)` modifiers in the app, and
no exceptions. The Floating-Toast Exception that once permitted a single soft
shadow on `NotificationBadgeView` is retired along with the toast itself (the
home receive confirmation now lives on the balance — see Notifications). If you
find yourself reaching for a shadow, the layout is wrong; the alternative is a
hairline `CanvasDivider`, a material change, or Liquid Glass.

**The Glass-As-Surface Rule.** Liquid Glass is a *surface*, not a *decoration*.
It belongs on container shapes (`Capsule`, `RoundedRectangle(cornerRadius: 12)`)
that hold real interactive content. It never wraps text purely for visual
texture. The general absolute ban on "glassmorphism as default" still applies;
this app earns its glass because the underlying iOS 26 API is genuinely the
right tool for the job.

## 5. Components

### Buttons

- **Shape:** `Capsule()` is the default for every full-width action — primary
  and otherwise. `RoundedRectangle(cornerRadius: 12)` for inline pill chips
  and notification cards. No rectangular buttons.
- **Primary & Secondary — `.glassButton()`** (= `FullWidthCapsuleButtonStyle`):
  full-width Liquid Glass capsule rendered with `.regular.tint(Color.primary
  .opacity(0.15)).interactive()` on iOS 26+, falling back to `.quaternary` on
  iOS 18–25. `.body.weight(.semibold)`, `.padding(.vertical, 18)`. Pressed
  state: opacity 0.85 with a `.snappy(0.18)` animation. Disabled: opacity 0.4.
  **This is the only button surface vocabulary in the app.** Defined in
  `ios/CashuWallet/Views/Components/LiquidGlassModifiers.swift`. Used everywhere a
  button needs a visible affordance: Create Wallet, Continue, Pay, Send,
  Receive, Copy, Restore, etc.
- **Text link — `.textLinkButton()`** (= `TextLinkButtonStyle`): the canonical
  borderless, text-only tertiary action. `.subheadline.weight(.medium)`,
  `.secondary`, press-dim to 0.6, disabled 0.4 — the same feedback family as
  `glassButton()`. The style owns font + color + feedback only; layout
  (full-width, padding, an optional leading SF Symbol like the "+" on "Add
  custom mint URL") stays at the call site, since text links range from inline
  ("Copy") to full-width ("Skip", "Add custom mint URL"). Used for "Skip" /
  "Skip for now", "Copy", and "Add custom mint URL". Defined
  in `ios/CashuWallet/Views/Components/LiquidGlassModifiers.swift`.
- **Utility — `.buttonStyle(.plain)`** with a bare SF Symbol (no text label),
  often wrapped in `.liquidGlass(in: Capsule(), interactive: true)` when the
  symbol earns a glass surface. Reserved for **icon-only** actions: the
  unit-symbol toggle on the main wallet, the truncated Lightning address copy
  chip, the "Back" chevron, and inline chevron disclosures. Text links go
  through `.textLinkButton()`, not raw `.plain`.
- **Home action row — raw `.liquidGlass(in: Capsule(), interactive: true)`**:
  the Receive / Scan / Send triptych in `MainWalletView` uses inline glass
  rather than `glassButton()` because it needs `GlassEffectContainer` (iOS 26
  merged-glass effect) and three different shapes (Capsule + Circle + Capsule).
  Typography and padding match `FullWidthCapsuleButtonStyle` exactly
  (`.body.weight(.semibold)`, `.padding(.vertical, 18)`) so it reads as one
  family.
- **Send/Receive-method row (carve-out) — round filled icon buttons.** The Send
  and Receive sheets offer their "ways to send/receive" — Scan · Ecash · Tap /
  Scan · Ecash · Bitcoin — as a centered row of **circular** icon buttons
  (`CircularGlassIconButton`): a 72pt `.quaternary` circle, a monochrome
  `.title` SF Symbol, 40pt row gaps, and a one-word `.caption.weight(.medium)`
  label below, with `PressableButtonStyle` press feedback. The metrics mirror
  Android's `CircularMethodButton` (72dp circle · 32dp icon · 40dp gap) for
  cross-platform parity. This is Apple's sheet-action-circle
  pattern (Maps, Find My, Wallet) — deliberately **not** Liquid Glass: the row
  scrolls with the sheet's content, and the content layer gets no glass. Glass
  here would sit on the sheet's own glass background (glass can't sample
  glass) and turn near-invisible under the system Clear appearance; the
  semantic fill renders identically under Clear and Tinted and adapts to
  Increase Contrast. Same surface on all OS versions. The carve-out beyond the
  full-width capsule stays justified because the SF Symbol *is* the affordance
  (icon-only, no text on the surface).
- **Press feedback — `PressableButtonStyle`**: 0.97 scale on press down
  (`.snappy(0.09)`), spring back on release (`.snappy(0.18)`). Apply only
  where the glass style doesn't already carry feedback (the chooser
  cascade).

### History Rows

The canonical list pattern. Defined in
`ios/CashuWallet/Views/History/HistoryView.swift`.

- **Leading**: a single directional arrow on a soft neutral circle, via
  `TransactionIcon` — `arrow.down` for incoming, `arrow.up` for outgoing,
  16pt `.medium`, `Color.secondary` on a 36×36 `Color(.secondarySystemFill)`
  circle that reads cleanly against either canvas. The arrow is **always
  muted**: direction is carried by the arrow's orientation, never by colour.
  State colour lives only on the trailing amount (see the One Green Rule).
  Payment method (ecash / Lightning / on-chain) is no longer drawn here — it
  is named in the title text.
  *Carve-out (felt-influenced):* this replaces the earlier kind-glyph +
  corner directional badge model. Rationale: a single quiet arrow is more
  aligned with the "System Utility" North Star and removes redundant colour
  (the amount already signals direction and confirmation).
- **Title**: left-aligned, `.body.weight(.medium)`, single line. **Kind-first,
  capitalized kind, lowercase verb** across all six cases — "Ecash received",
  "Ecash sent", "Lightning received", "Lightning paid", "Bitcoin received",
  "Bitcoin sent". Single source of truth: `WalletTransaction.displayTitle`
  (Models.swift), reused by the History/Home rows **and** the transaction detail
  nav title, so a row and the sheet it opens always read identically. *(2026-06-01:
  was verb-first lowercase "Received ecash"; unified to kind-first.)*
  *(2026-07-21: a BOLT11 mint quote still awaiting payment titles as
  **"Lightning invoice"** — `isUnpaidInvoice` — flipping to "Lightning received"
  only once the invoice is paid. "Received" must never assert money that hasn't
  arrived; this also covers the expired state, which keeps the invoice title.
  Mirrors the request-row precedent `CashuRequest.displayTitle`.)*
- **Timestamp**: `.caption`, `Color.secondary`, immediately under the title.
  Formatted with `RelativeDateTimeFormatter(.abbreviated)` ("2 hr ago", "3 d ago").
- **Trailing amount**: `.system(.body, design: .rounded).weight(.medium)
  .monospacedDigit()`, `.contentTransition(.numericText(value:))`. Completed
  incoming → green `+amount`; completed outgoing → unsigned `.primary`; pending
  or expired → unsigned `.secondary`.
- **Pending indicator**: none on the row. Pending is the muted `.secondary`
  amount alone (the `arrow.triangle.2.circlepath` refresh button was removed
  2026-06-01). Manual re-check is History pull-to-refresh
  (`syncPendingMintQuotes()` + `checkAllPendingTokens()`).
- **Separator**: none. Home and History activity rows flow on the canvas with
  spacing and section grouping carrying the rhythm.
- **Entrance**: none — rows appear in place. *(Retired 2026-07-06.)* The list
  once staggered its first eight rows in on appearance, but the History tab is
  swapped for `Color.clear` when unselected (`MainTabView.tabContent`, a
  deliberate "fast boot" lazy-mount), so `HistoryView` **remounts on every
  visit** and the `hasAppearedOnce`-gated stagger replayed each time — reading as
  an unwanted swoop-in on every Home→History switch, not a once-only flourish.
  Since the remount is load-bearing and can't cheaply be made to persist the
  flag, the entrance animation was removed outright: no offset, no per-row delay,
  no fade. Scroll-reset on filter change still animates via `.snappy(0.25)`
  (`proxy.scrollTo`); that is a reflow, not an entrance.

### Cashu Request Rows (inline in the timeline)

Cashu Requests sit **inline in the chronological transaction timeline**,
anchored to `request.createdAt`, grouped into the same TODAY / YESTERDAY /
THIS WEEK / … buckets as transactions. They are not pinned to a separate
section. Defined in `HistoryView.swift` → `cashuRequestRow(request:, staggerIndex:)`.

- **Leading**: `TransactionIcon(direction: .incoming)` — a muted `arrow.down`
  on the same 36×36 neutral circle as transaction rows (a Cashu Request is,
  structurally, an incoming-ecash event in waiting). Static: the row's amount
  and title carry the waiting → received transition, not the icon.
- **Title**: "Cashu Request", `.body.weight(.medium)`, single line. Stays
  the same across all states; the badge carries status.
- **Subtitle**: `formatRelativeDate(request.createdAt)`, `.caption`,
  `.secondary` — matches transaction rows exactly. The payment count
  ("3 payments received") is no longer surfaced on the row; it lives in
  `CashuRequestDetailView`.
- **Trailing amount** (`.body` medium primary with a `.subheadline` regular
  conversion, matching every other amount):
  - Fixed-amount + waiting: `amount` in `.secondary`, no indicator — the muted
    amount alone signals waiting (the target is visible while pending).
  - Fixed-amount + received: `+amount` in `.green`, monospaced digit,
    `.contentTransition(.numericText(value:))`. Cumulative for multi-payment.
  - Any-amount + waiting: no trailing element at all.
  - Any-amount + received: `+\(totalReceived)` in `.green`, cumulative.
- **Duplicate suppression**: when a payment lands, `WalletManager
  .receiveCashuRequestPayment` diffs the mint's incoming transaction ids
  before/after the receive, identifies the new CDK tx id, and stores it on
  `CashuRequest.receivedPayments`. `HistoryView` computes
  `requestClaimedTxIds` from the store and drops those transactions from the
  unified `filteredItems` list, so the request row is the *single*
  representation of the event. The CDK transaction record stays in storage
  (balance math intact); only the row is hidden.
- **Tap target**: a `NavigationLink` to `CashuRequestDetailView`. Transaction
  rows still open as a `.sheet(item:)`. The "requests are navigable content;
  transactions are modal records" asymmetry stays.
- **Long-press delete**: a `.contextMenu` exposes a destructive
  "Remove from history" entry that sets a `requestPendingDeletion` state,
  driving a `.confirmationDialog`. Confirm calls
  `CashuRequestStore.delete(id:)`. The deletion is local only — the encoded
  request remains valid for any sender still holding the QR; only the row
  goes away.

### Inputs

- **TextField** (Send/Receive): bare `TextField("placeholder", text:)` with no
  `.textFieldStyle`. Placement provides the affordance — typically inside a
  `.thinMaterial` `RoundedRectangle(cornerRadius: 14)` container.
- **TextField** (Settings): historically `.textFieldStyle(.roundedBorder)` — the
  system rounded style. *Carve-out (2026-07-05): the Nostr relay field dropped
  `.roundedBorder` for the `.thinMaterial`/`liquidGlass`
  `RoundedRectangle(cornerRadius: 14)` input used by `ImportP2PKSheet`, so the
  Nostr settings hub reads as one family with Locked Ecash. New settings inputs
  should follow that glass field, not `.roundedBorder`.* Any remaining
  `.roundedBorder` fields are legacy.
- **Amount entry**: never a raw TextField. The dedicated
  `ios/CashuWallet/Views/Components/AmountEntryView.swift` view owns this — a
  full-screen canvas with `CurrencyAmountDisplay`, fiat-primary toggle, mint
  selector, and inline number pad. Amount is a *moment*, not a form field.

### Sheets

Sheets are the dominant modal pattern. Full-screen covers are the full-screen
*payment pages* — token claim, scan-routed melt / Cashu-request pay, held
NUT-18 approval — screens that must read as brand-new with nothing visible
beneath. The camera scanner itself is a `.sheet` everywhere.

**Sheet-navigation contract** (mirrored on Android by `AuthenticatedShell`):

- **One flow surface at a time.** `NavigationManager` owns a single home-sheet
  slot (`WalletSheet`) and a single full-screen cover slot (`FlowCover`).
  Story progression *replaces* — either an in-place `.sheet(item:)` content
  swap (Send → Send Ecash, Receive → Bitcoin, Receive → Send payable) or a
  parked handoff via `NavigationManager.present`, which closes the outgoing
  surface and presents the next one from `onDismiss`. Surfaces never stack;
  the scanner self-dismisses before its result presents.
- **Dismissal abandons to the wallet.** Swipe-down or X from any flow surface
  lands on the screen beneath (normally Home) — never on an earlier sheet.
  In-sheet chevrons/pills own internal step-back.
- **Dismissal locks only while money moves.** `interactiveDismissDisabled` +
  a hidden/disabled close button during the irreversible execution window
  (melt executing, token generating, claim processing); every waiting or
  composing phase stays freely dismissible.
- **Interrupts defer until idle.** Deep-linked tokens and held NUT-18
  approvals queue in `NavigationManager` / `CashuRequestListener` and present
  only when no flow surface is open, the runtime is ready, and the app is
  unlocked. Nothing is dropped — skipped items re-present on the next idle
  transition.

Presentation styles:

- **Default**: `.sheet(item:)` + `.presentationDetents([.large])` +
  `.presentationDragIndicator(.visible)`. Use for any flow that has its own
  internal navigation (Send, Receive, Mints).
- **Adaptive**: `.presentationDetents([.medium, .large])`. Use for inspection-
  style sheets (Settings → Backup, single-mint detail).
- **Content-fit**: the unified Send/Receive input faces measure their body and
  drive `.presentationDetents([.height(measured)])` so Scan · Ecash · Tap stay
  thumb-reachable; later steps expand to `.large`.
- **Fixed height**: `.presentationDetents([.height(340)])` for compact
  confirmation surfaces (`AuthorizingOverlay`). Pair with
  `.presentationBackgroundInteraction(.disabled)` to lock the underlying canvas.
- **Sub-sheets on a sheet**: `CashuRequestDetailView` opens
  `CashuRequestMintPickerSheet` and `CashuRequestAmountPickerSheet` as nested
  sheets at `.presentationDetents([.medium])`. The parent stays put; the
  sub-sheet is a transient editor and dismisses on selection. Transient
  value-returning editors (mint/unit/amount pickers, in-flow scanners) are the
  one sanctioned exception to "never stack" — they return to the step beneath,
  they are not story progression.
- **Confirmation dialogs**: `.confirmationDialog(...)` for destructive
  actions (remove mint, sign out). Never a custom alert sheet.
- **Sheet background (carve-out, 2026-06-29)**: full-screen `.large` flows and
  `.fullScreenCover`s pin to the flat canvas via `canvasSheetBackground()` so they
  read seamless with home. Bottom-sheet pickers, choosers, and inspectors
  (`.medium` / `.height(...)` detents) instead keep SwiftUI's **default**
  translucent sheet background — they should read as floating layers, not as the
  home canvas.

### Cashu Request Inspector

The signature surface of the NUT-18 receive flow.
`ios/CashuWallet/Views/Receive/CashuRequestDetailView.swift`. The view runs in two
contexts: full-screen when `UnifiedReceiveView` mints a fresh request, or —
from History — presented as its **own bottom `.sheet`** (each wrapped in a
`NavigationStack` at the call site for its toolbar).
**Detail surfaces are always bottom sheets, never pushed** — tapping any
History item or completed Home transaction slides up the same way, so the two
never diverge into a push vs. sheet split. The same content scales to both
contexts.

- **QR**: 280×280 `QRCodeView(content:, showControls: false, staticOnly: true)`
  on a `Color.white` `RoundedRectangle(cornerRadius: 20)` with 16pt padding.
  White is intentional and one of the three explicit exceptions to "no
  `.white`" in the palette rules (the others being scanner overlay and QR
  contexts themselves). Context menu on long-press exposes Copy + Share.
- **Amount**: when set, rendered through `CurrencyAmountDisplay` at
  `primarySize: 32` so it doesn't compete with the QR but still reads as the
  dominant numeric element.
- **Status badge**: three exclusive states, all `.subheadline.weight(.medium)`,
  no surrounding pill:
  - Waiting → `clock` SF Symbol with `.symbolEffect(.pulse, options: .repeating)`
    + "Waiting for payment…", `Color.orange`, no animation on appearance.
  - Received (live) → `checkmark.circle.fill` with `.symbolEffect(.bounce)` +
    "Payment received!", `Color.green`, slid in via
    `.scale(scale: 0.9).combined(with: .opacity)` under `.spring(0.5, 0.7)`. Gated to the
    on-screen request (the `.cashuTokenReceived` notification carries the
    `requestId`). In the **receive flow** (watching a fresh request, `onClose`
    set) it dwells ~1.2s then the sheet auto-dismisses — mirroring the Lightning
    invoice. When **inspecting** an existing request from History it holds
    2.5s then reverts to the persistent count (no dismiss).
  - Received (persistent) → `checkmark.seal.fill` + "N payments received",
    `Color.green`. Quiet — no symbol effect, no animation.
- **Editable inspector rows** (Mint, Amount): see `row-inspector-editable`
  in the YAML frontmatter. Tap opens the appropriate `.medium`-detent
  sub-sheet. Selecting a value calls back into the parent which regenerates
  the request — the QR rotates, the new request gets a new id, and the
  `CashuRequestStore` archives the prior one.
- **Read-only rows** (Unit, Created): same row shape, no pencil glyph, no
  tap target.
- **Row dividers**: 0.5pt `Rectangle().fill(Color.primary.opacity(0.08))`
  with 8pt horizontal inset — *not* `CanvasDivider()`. The inspector lives in
  a narrower container than a single-canvas list, and the lighter tint reads
  better when stacked tightly between editable rows. (If this divergence
  bothers a reader, the right fix is to add an `inset` and `tint` parameter
  to `CanvasDivider`, not to introduce a third hairline.)
- **Actions**: two siblings via `glassButton()` — "Copy" (stays visually stable
  and raises the shared confirmation toast) and "New Request" (regenerates,
  rotating the QR). Order matters: the existing request lives on the left
  because it is the thing you'd usually share; the destructive-ish rotate
  lives on the right.

### Notifications

- **Received delta beat** (home screen): when `cashuTokenReceived` fires, the
  hero balance rolls upward via `.contentTransition(.numericText())` +
  `.animation(.snappy, value:)` (the same numeric roll as the Send/Receive
  `CurrencyAmountDisplay`) and a transient **monochrome** `+amount` (`.secondary`,
  grouped through `AmountFormatter`, no unit, no directional arrow, no checkmark)
  takes over the fiat sub-amount slot beneath the balance, scaling in via
  `.scale(scale: 0.9).combined(with: .opacity)` / `.spring(0.5, 0.7)`, holding 2.5s, then
  fading as the fiat line returns; reduce-motion collapses it to an opacity
  cross-fade. The rolling total is the primary signal — the `+amount` just names
  the exact receipt. A `.success` haptic fires only for background receives whose
  poster sets `"homeHaptic"` (e.g. npub.cash); in-flow receives own their haptic on
  `PaymentStatusView` / `CashuRequestDetailView`, so the home beat stays silent to
  avoid a double-buzz. Defined in `MainWalletView` (`balanceStatusLine` /
  `receivedDeltaBeat`). *Amended 2026-07-05: de-greened — the green `✓` celebration
  was retired as corny; the balance roll now carries the moment.*
- **`ErrorBannerView`**: inline red banner for in-context errors. Screen-level
  async/system failures, `.footnote`, bordered. Prefer the `.errorBanner(_:)`
  modifier to pin it to the bottom safe area.
- **`InlineNotice`**: the control-tied notice for preconditions and validation —
  the thing that sits under a field or amount and says why you can't proceed.
  `.caption`, no border, optional `title`/`detail`/`tinted`. Shares
  `ErrorSeverity` with the banner. This is the surface most error copy uses
  (~38 call sites) and it was previously undocumented here.
  > These two disagree on body size and border, and are used interchangeably for
  > the same kinds of failure. See `inline-error-audit.md` for the divergence
  > inventory and the proposed collapse into one surface.

### Signature: ActivityOrb

`ios/CashuWallet/Views/Components/ActivityOrbView.swift` — a pulsing `circle.dotted`
SF Symbol that fades in (`.easeIn(0.3)`), rotates linearly forever
(`.linear(2).repeatForever()`), and fades out (`.easeOut(0.5)`) when work
finishes. Used as a quiet "something is happening in the background" indicator
that doesn't block interaction. The closest thing this system has to a logo
moment — and it is still a system glyph at a system color.

### Named Rules

**The CanvasDivider Rule.** Single-canvas detail screens such as Lightning
Invoice detail use `CanvasDivider` between rows. Raw `Divider()` is legacy.
There are no card stacks. Home and History transaction activity are an explicit
carve-out: their rows flow without hairlines, separated by spacing and grouping.

*Carve-out (Settings, 2026-06-28):* the Settings screen and its detail
subscreens drop hairlines entirely — rows flow on the bare canvas, separated by
section-group spacing alone, each with a plain leading SF Symbol
(`SettingsRowIcon`). A "Family wallet" treatment requested by the user. Settings
is no longer governed by this rule; History and the Lightning Invoice detail
still are. Icons stay plain and monochrome — no tile, no box, no color (the
Semantic-Only Rule holds).

**The Monochrome-Glyph Rule.** Iconography is monochrome SF Symbols at system
colors — never emoji, never `PaymentMethodKind.symbol` glyphs. *Carve-out
(currency picker, 2026-06-28):* a flag **emoji** is permitted as the leading
avatar in `CurrencyPickerSheet`, and only there — clipped inside the circular
`CurrencyAvatar` so it reads as a contained flag chip (the Family idiom), not
loose inline emoji. Everywhere else the no-emoji rule stands.

**The Plain-Button Rule.** Utility actions (close `xmark`, copy, refresh,
chevron disclosure) use `.buttonStyle(.plain)` with an SF Symbol. They do not
wear glass material unless the symbol genuinely needs the affordance of being
"an interactive surface" (the unit toggle, the lightning address chip). Most
of the time, plain is correct.

**The Singular-Button Rule.** When a button needs a surface, that surface is
Liquid Glass via `.glassButton()` (or, for the home action row, the inline
`.liquidGlass(in: Capsule(), interactive: true)` that matches it). There is no
stroked-capsule outline variant, no inverted-ink fill variant, no
`.buttonStyle(.bordered)`. Hierarchy between two CTAs comes from **order,
copy, and disabled state** — never from a parallel button vocabulary. A
"secondary" Liquid Glass button stacked under a "primary" one is intentional:
they are siblings, not parent-and-child.

**The Text-Link Rule.** A borderless, text-only tertiary action ("Skip",
"Copy", "Add custom mint URL") always goes through
`.textLinkButton()` — `.subheadline.weight(.medium)`, `.secondary`. Never
hand-roll the font/color on a `.buttonStyle(.plain)` text link; that is how
"Skip for now" drifted to `.footnote` while its twins stayed `.subheadline`.
This is a *typography* standard, not a surface — it does not contradict the
Singular-Button Rule, because a text link has no surface. Raw
`.buttonStyle(.plain)` is now reserved for **icon-only** utilities (see the
Plain-Button Rule). A leading SF Symbol on a text link (the "+" on "Add custom
mint URL") is allowed — it lives in the call-site label, not the style.

**The Iconless-CTA Rule.** Primary `glassButton()` CTAs at the bottom of a
sheet are **text-only**. No leading SF Symbol, no `Label(_:systemImage:)`,
no `HStack { Image + Text }`. The verb already lives in the label
("Copy Invoice", "New Request", "Send", "Pay"), so an icon next to it is
visual noise that reduces the typographic weight of the action. Copy controls
do not morph or relabel after activation; the shared top-center confirmation
toast is the only in-app success feedback. Context-menu entries are the exception: they
use `Label(_:systemImage:)` because iOS context menus expect an icon column
and look wrong without one. Small inline copy chips (Settings rows, the
truncated Lightning-address chip on the main wallet) also keep their icons
— there, the SF Symbol *is* the affordance because there is no text label.

**The Iconless-Row Rule.** Two-column detail rows — the metadata list on a
transaction receipt, the confirm-screen facts on a pay/receive flow, and the
preserved payment facts on `PaymentStatusView` (processing → success → failure)
— are **label + value only**. No leading SF Symbol, no `Label(_:systemImage:)`.
The label already names the field, so a glyph beside it is decoration that
competes with the value it is meant to introduce, and a column of unrelated
symbols reads as a toolbar rather than a receipt. Trailing affordances stay:
the `pencil` on an editable row, `arrow.up.right` on an outbound link, the
seal/caution glyph that qualifies a *value* (a locked-ecash key), and the
chevron on a switchable mint. Method/action rows (the Send and Receive entry
sheets, Settings navigation rows) are a different vocabulary and keep their
leading icons — there the glyph identifies a destination, not a field.

Transaction receipts group the status hero and amount with a 16pt/dp gap,
then separate that group from the detail rows by 24pt/dp. Detail rows use
12pt/dp vertical padding and retain native minimum touch heights (44pt on iOS,
48dp on Android). A 12pt/dp gap after the rows combines with the last row's
bottom padding to leave 24pt/dp before the actions. Stacked actions use a
12pt/dp gap, and the content ends with 16pt/dp padding above the native bottom
inset. The QR's size and white border stay unchanged.

**The Confirmation Toast Rule.** Completed utility actions such as Copy use a
single top-center capsule with a short semantic message (for example, “Copied
Bitcoin address”). It enters with a restrained upward spring/slide and opacity,
exits with opacity only, never stacks, contains no status icon, and auto-dismisses
after roughly 2.2 seconds. Reduced Motion collapses the spatial transition to a
fade. One pass-through global overlay owns the toast for the entire app; screens
and native sheets must not mount competing hosts. The overlay stays at the
physical top center above sheets, their scrims, and any presenting-canvas blur.

**The Mint Card Exception (retired 2026-05-22).** The home screen no longer
carries a horizontal mint-card switcher. Mint browsing, active-mint selection,
and adding mints all live in the Mints tab; the home canvas now renders only
balance + actions + recent activity. With the carve-out gone, the
Flat-By-Default Rule applies uniformly across the app — no card stack is
permitted on any in-app surface. The only home-screen mint-related affordance
that remains is whatever the Mints tab itself surfaces. The home screen's
fixed top section (BTC chip, balance, fiat line, Receive/Send) is pinned via
`.safeAreaInset(edge: .top)` while the recent-activity list scrolls beneath
it, with a `LinearGradient` opacity mask fading rows to clear before they
reach the buttons. See `MainWalletView.swift` for the current implementation.

*Carve-out (Multi-unit balance pager, 2026-07-06).* When the wallet holds a
balance in more than one **unit** (sat + eur/usd/custom — mints can advertise
multiple units, NUT-04/05), the balance hero becomes a horizontal **pager**:
one unit's balance per page, swipeable, with system page dots
(`TabView`/`.tabViewStyle(.page)` in `MainWalletView.unitBalanceHero`). This is a
**deliberate, user-chosen** re-introduction of a horizontal swiper on the home
balance — surfaced against this retired-mint-card precedent with two flat
alternatives (a unit-chip menu, a supplementary sub-line) before the swipe idiom
was picked. It does **not** revive the mint-card switcher: it browses *units of
the same wallet*, not accounts; there is exactly **one hero number visible at a
time** (the Only-Hero-Number rule holds — no stat panel, no card stack); the
canvas underneath stays bare; and the pager appears **only** when the **active
(default) mint** advertises multiple units **and** a non-sat balance is held
(`HomeBalance.showsUnitPager`, 2026-07-06 refinement). A sat-only default mint
renders the single hero verbatim — no pager, no dots — even if a non-sat balance
is held at another mint (that balance still shows on Send + Mint Detail); switching
the default mint chip re-evaluates the gate live. Each page keeps the Tabular
Figure Rule (`.monospacedDigit()` +
`.contentTransition(.numericText())`); the sat page keeps its ₿/sat tap-toggle
and fiat sub-line, non-sat pages show the amount in its own currency (no fiat
conversion — eur is already fiat).

**The Bar-Band Rule (2026-08-05).** Onboarding draws no navigation bar, but every
step reserves the same 44 pt band below the status bar, with two positions:
**leading = back** (`OnboardingBackButton`) and **trailing = help**
(`OnboardingInfoButton`, `?`, opening the ecash concept sheet). Neither position
is ever repurposed for anything but one circular glyph, and a step may leave
either empty. Welcome is the only step with the help glyph today.

This is why "What is ecash?" is **not** a chassis text link: as a tertiary it made
Welcome the only three-slot step, so the button stack visibly changed height the
moment you left it. In the bar band the chassis holds a steady two buttons, and
the title lands on the same line on every step either way
(`barTopInset + barHeight + titleGap` == `titleTopInset`). On iOS both
affordances are built from the same private `OnboardingBarButton` so they land on
identical geometry.

**Bar-band icons must set their content color explicitly.** The onboarding canvas
is painted with a background modifier, not a `Surface` — and only a `Surface`
provides an ambient content color. An icon that inherits the ambient value gets
the framework default (**black**) and disappears on the dark canvas. On Android
pass `IconButtonDefaults.iconButtonColors(contentColor = colorScheme.onSurface)`;
on iOS `.foregroundStyle(.primary)` already resolves per appearance. The Android
screenshot frame deliberately mirrors production here (background modifier, no
`Surface`) — wrapping previews in a `Surface` made them render correct while the
real app was black-on-black, which is exactly how this shipped unnoticed.

**The Seed Card Exception (2026-08-05).** The onboarding seed step
(`showMnemonic`) renders its 12 words inside a single container: Liquid Glass on
iOS 26+ / `.quaternary` below (`.liquidGlass(in: RoundedRectangle(cornerRadius:
14))`), `surfaceContainerHigh` at `RoundedCornerShape(14.dp)` on Android. This is
the **only** screen permitted a content container, and the carve-out is narrow on
purpose:

- The phrase is **one object the user must act on**, not screen content. Bare
  words on the canvas read as output; a container reads as a thing to handle.
- The card is **load-bearing for the gesture**. Tap-to-reveal previously targeted
  an invisible rectangle with no edges. The container is what tells you where to
  tap, so it is an affordance, not decoration — exactly the case the
  Glass-As-Surface Rule permits.

The canvas around it stays bare. The Flat-By-Default Rule and the No-Shadow
Absolute still apply to it in full: no shadow, no border, no per-word chrome
inside it. The `Copy` link and the "never share" caution sit **outside** the
card on the bare canvas.

*Amended 2026-08-08 — the entry card.* The exception now covers a second
surface: the word-by-word **seed entry** card on `restoreInput` (and its
Settings twin), which holds one word at a time behind up to two **empty ghost
cards** standing for the words still to come. This is the single place in the
app permitted anything resembling a card stack, and the carve-out is narrower
than it looks:

- The ghosts hold **nothing**. They are the *shape of what is left*, not
  containers for content — the No-Nested-Containers rule is about content
  inside content, and there is none here.
- They earn their place by answering "how much more of this is there?", which
  the rail alone answers abstractly and the deck answers physically.
- **Alpha and scale only, never blur.** Skia renders blur one level differently
  across hosts, so a statically-blurred ghost could never pass Compose golden
  validation on Linux CI — and iOS has to draw the identical thing.
- Everything else holds: no shadow, no border beyond the input hairline, no
  per-word chrome, bare canvas around the block.

Reference: Family's recovery flow. Do not generalise this to any other screen —
if a second surface wants a stack, that is a new argument, not this one.

Reference: Family's Manual Backup screen. Implemented in
`OnboardingView.showMnemonicStage` and `OnboardingScreen.SeedPhraseReveal` — on
Android the surface is drawn *inside* `SeedPhraseReveal` (clip + background
before the clickable, inner padding after) so the whole card is the tap target
and the screenshot previews cannot drift from production.

**The Share-At-Top Rule.** Any sheet that displays a shareable QR artifact —
Lightning Invoice (`ReceiveLightningView`), Cashu Request
(`CashuRequestDetailView`), generated ecash token (`SendView`), historical
transaction (`TransactionDetailView`) — places its Share affordance at
toolbar `.topBarTrailing`. The Share is either a bare `ShareLink(item:)`
(when the artifact ships as a plain string, e.g. a Lightning invoice or a
Cashu Request) or a `Button { showShareSheet = true }` that routes through a
custom share sheet (when the artifact needs URL-scheme formatting, e.g. an
ecash token gets the `cashu:` prefix via `CashuTokenShareSheet`). The QR
additionally carries a `.contextMenu { Copy + Share }` so long-pressers find
the same affordance — the doubled discovery is intentional, not a redundancy.
The bottom row is reserved for primary CTAs (Copy, Continue, New Request,
Send) and **never** carries Share. Aligning Share to one corner across every
artifact-display sheet makes it a learnable habit, not a per-screen guess.

## 6. Motion Vocabulary

Seven named animations carry the entire system. New custom motion must justify
why none of these fit before it earns its own name. All seven honor
`accessibilityReduceMotion` (existing code is not yet uniformly compliant; new
code must be).

1. **Row stagger** — *retired 2026-07-06.* History rows now appear in place with
   no entrance animation. The stagger (`.smooth(0.32).delay(index * 0.035s)`,
   gated on `hasAppearedOnce`) was meant to play once, but the History tab
   remounts on every visit (the `Color.clear` fast-boot swap in
   `MainTabView.tabContent`), so it replayed as a swoop-in on every visit and was
   removed. Left here as one of the seven slots for the record; the entrance
   vocabulary is now "appear in place." See §5 History Rows → Entrance.
2. **Badge symbol-replace** — `.contentTransition(.symbolEffect(.replace.downUp))`
   on the history-row directional badge, `.snappy(0.28)` keyed on
   `transaction.status` and `transaction.type`. Morphs `clock.circle.fill` →
   `arrow.down.circle.fill` / `arrow.up.circle.fill` when a transaction clears.
3. **Chooser cascade** — Receive/Send action sheet options reveal with
   `.smooth(duration: 0.32).delay(index * 0.07s)` on `value: revealed`. Each
   option fades in and slides 12pt from the leading edge. The cascade is the
   *only* place an in-app element animates from a *direction* rather than
   from a *scale or opacity*.
4. **Press feedback** — `PressableButtonStyle` scales to 0.97 on press
   (`.snappy(0.09)`), springs back to 1.0 on release (`.snappy(0.18)`).
   Color/opacity unchanged. Apply only where the glass surface doesn't
   already carry feedback; `glassButton()` ships its own pressed opacity drop.
   *Amended 2026-08-06:* the asymmetry is the point — feedback belongs on
   touch-**down** and must feel immediate, while the release is the system
   responding and can settle. `FullWidthCapsuleButtonStyle` and
   `TextLinkButtonStyle` had been shipping a symmetric `.snappy(0.18)` and now
   share the same 0.09-down / 0.18-up pair. Android states the identical ratio
   in its own measure (`fastSpatialSpec` down / `defaultSpatialSpec` up for
   scale; the effects pair for text-link opacity, which must not carry
   overshoot).
5. **Sheet cross-fade** — in-sheet flow swap, e.g. the home sheet's
   `.sheet(item:)` content morphing between `WalletSheet` cases (Send → Send
   Ecash, Receive → Bitcoin) or a flow flipping between two faces of one task.
   Each branch ships `.transition(.opacity)` and the container animates on the
   discriminator. Use this whenever a sheet has two faces of the same task;
   the alternative (push navigation, modal stacking) breaks the "the sheet is
   the unit of intent" principle in docs/product/PRODUCT.md.
6. **Payment-received celebration** — `paymentJustReceived` lights up the
   Cashu Request status badge for 2.5s with `.spring(response: 0.5,
   dampingFraction: 0.7)`. The checkmark uses `.symbolEffect(.bounce, value:)`
   and the entire badge transitions in via `.scale(scale: 0.9).combined(with: .opacity)`
   — a gentle grow-in, not a scale-from-zero pop (the `.symbolEffect(.bounce)` is the
   single delight beat; the badge scale-in stays subtle so it doesn't compound).
   Same pattern is mirrored in `ReceiveLightningView` for `isPaid`. *Amended
   2026-07-05:* on the **home screen** the celebration is quieter — the hero
   balance rolls up (`.contentTransition(.numericText())`) and a **monochrome**
   `+amount` beat (`MainWalletView.receivedDeltaBeat`, no green, no checkmark)
   takes over the fiat slot; the green `✓` was retired here as corny. The badge
   instances share the *singular* allowed celebration vocabulary — never confetti,
   never a haptic stronger than `.success`, never a sustained-color flash. **Resolution is
   context-dependent:** in a receive flow (Lightning invoice, or a fresh Cashu
   Request being watched) the badge dwells ~1.2s then the sheet slides down and
   dismisses; when *inspecting* an existing Cashu Request it instead holds 2.5s
   then steps back to the persistent line (N-payments-received). The home-balance
   delta beat steps back to the fiat sub-amount. *Amended 2026-08-30:* a payment
   terminal **mounted directly at success** (a payment landing while a waiting
   face was up — receive invoice, token claim, ecash claimed) plays the same
   recipe as a **staged entrance**, because transitions and phase-keyed effects
   never fire on a fresh subtree's initial content and the celebration was
   silent there: beat 1 at ~100ms — the check materializes (blur 4→0, scale
   0.92→1 on the celebration spring) with the single bounce and the success
   haptic; beat 2 at ~220ms — title + message, opacity + an 8pt settle-rise on
   `.smooth(0.3)`; beat 3 at ~300ms — detail rows (6pt settle-rise, **no blur —
   money**) and the CTA (opacity only; hit-testable from frame 1 — the stage is
   decorative). The waiting face exits fast (`.easeInOut(0.2)` opacity). Failure
   and settlement-pending mounts stay deliberately still; morph-mounted
   instances never re-stage; Reduce Motion collapses the stage to today's
   single flat fade. The ≤8pt settle-rise is a *settle*, not a directional
   slide — it does not extend the chooser cascade's direction monopoly (#3).
7. **Waiting-pulse** — `.symbolEffect(.pulse, options: .repeating)` on a
   single SF Symbol while a system is waiting on external state: the empty-
   state History bolt, the Cashu Request "Waiting for payment…" clock, the
   ActivityOrb's rotating dotted-circle. Quiet, infinite, no scale change.

**Allowed easings.** `.smooth(duration:)` for entrances and reflows.
`.snappy(duration:)` for state flips and presses (.09 / .18 / .25 / .28 / .35
are the canonical durations). `.easeInOut(duration: 0.2–0.3)` for
cross-fades and value-driven container animations.
`.spring(response: 0.5, dampingFraction: 0.7)` for the celebration only.
`.linear(duration: 2).repeatForever()` for the ActivityOrb rotation only.
No bounce, no elastic, no custom cubic-bezier, no `.interactiveSpring`.

**Carve-outs** *(added 2026-07-06 — motion audit, design-motion-principles /
Jakub-Krehel production-polish lens; both refine the seven, neither adds a new
curve or a delight beat):*

- **Subtler exits.** Exits are quieter than entrances. An element that *enters*
  with move/scale + opacity *leaves* with opacity alone (or a ≤50% move). This
  applies to transient surfaces — the error banner
  (`.asymmetric(insertion: .move(edge:.bottom)+opacity, removal: .opacity)`),
  the celebration / received badges, and the home received-delta beat. The seven
  named animations keep their **entrance** recipes verbatim; only the removal
  edge changes. Honors `accessibilityReduceMotion` (reduce-motion is a plain
  `.opacity` both ways).
- **Blur-to-sharp materialize.** A blur radius `4 → 0` is an allowed *entrance*
  modifier on **confirmation glyphs only** — the payment-received celebration and
  `PaymentStatusView`'s success check — so the glyph comes *into focus* as it
  scales in, riding the existing `.smooth(0.3)` / celebration curve (no new
  timing). Never on a money value (Numbers Are Sacred), never ambient, always
  dropped under `accessibilityReduceMotion`. Bounce stays reserved for the one
  celebration beat: a failure or historical-review glyph never bounces.
  (`AnyTransition.materializeBlur` lives in `LiquidGlassModifiers.swift`; the
  onboarding exemption below additionally rides it on stage and headline
  entrances — pre-wallet only.)
- **Blur as a cross-fade *mask*** *(added 2026-08-06 — onboarding button-morph
  pass; **onboarding exemption only**, see below).* Distinct from the entrance
  modifier above: a 1.5–4 pt blur may ride **both halves** of a button's content
  or slot cross-fade (label↔label, label↔spinner, slot↔slot). The rationale is
  perceptual, not decorative — in an unmasked cross-fade the eye resolves the
  outgoing and incoming states as two distinct objects overlapping, so the
  change reads as a *replacement*. Blurred, they blend and it reads as one
  object *transforming*, which is what a morph is supposed to be. Because it is
  a mask, the usual "exits subtler than entrances" rule does not strip the blur
  from the outgoing half — a mask on one half only does nothing; the exit is
  instead made subtler by being *shorter* (~160 ms vs ~260 ms) and carrying no
  scale. Radii stay small: this must never be legible as an effect. Primitives:
  `AnyTransition.materializeBlur(radius:)` (iOS, already existed) and
  `AnimatedVisibilityScope.morphBlur(radius:)` (Android, `Materialize.kt` — the
  entrance-only `Modifier.materializeBlur()` cannot blur a child on its way out).
  Both no-op under reduce motion; Android additionally no-ops below API 31.

  **Reach differs by platform, and the asymmetry is deliberate rather than an
  oversight.** On iOS the morph lives entirely in `OnboardingChassis.swift`, so
  it is genuinely pre-wallet-only and stays barred inside the wallet proper
  until deliberately propagated. On Android it lives in the shared
  `PrimaryButton` / `GhostButton` (`ui/components/Buttons.kt`) and therefore
  reaches every CTA in the app. That is the correct call: the thing being fixed
  there is a **label→spinner hard cut**, which is a defect wherever it appears,
  and gating a component's own internal correctness behind a call-site flag
  would be worse than the inconsistency it avoids. Android's wallet-proper CTAs
  consequently gain the blur mask early; iOS's do not until the propagation
  pass, and until then the two platforms' non-onboarding CTAs are knowingly a
  half-step apart.

**Onboarding exemption** *(added 2026-08-05 — onboarding restyle,
docs/product/onboarding-restyle-brief.md, user-directed):* pre-wallet
onboarding surfaces — `OnboardingView`, `OnboardingChassis`, i.e. everything
before `completeOnboarding()` /
`completeRestore()` hands off to the wallet — are **exempt from the
seven-named-animation budget**. Nothing defined under this exemption may be
reused inside the wallet proper. The exemption's terminal beat is the **ASCII
handoff** (`OnboardingHandoff.swift` / `OnboardingHandoff.kt`): a full-screen
terrain curtain that sweeps down over the last onboarding screen, flips the
root gate at full cover, blooms once at center, then **erodes**: the opaque
scrim clears early so the wallet stands behind a terrain that is still there,
and the glyphs then dissolve level by level (`AsciiFieldTerrain.erosionAlpha`,
mirrored and pinned by `AsciiFieldErosionTests`) — the faint dotted plain
thins first, the contour ridgelines hold, and the ₿ peaks are the last things
over the balance. Nothing translates and no edge travels: a moving plane reads
as a slide and a moving edge reads as a wipe, and the last beat of onboarding
is neither. The only motion is the field's own drift and the bloom's release
swirl
— onboarding-owned, mounted at the app root only so it survives the teardown
it conceals, played exactly once, never referenced by wallet code. The wallet
composes beneath it with no entrance animation of its own. Two rules survive the exemption unchanged:
**Numbers Are Sacred** (the restored balance and the recovered-sats total keep
`.monospacedDigit()` + `.contentTransition(.numericText())`; no count-up, no
odometer, no roll) and **Reduce Motion** (every onboarding animation honors
`accessibilityReduceMotion` / `rememberReducedMotion()`; reduced-motion paths
are opacity-or-nothing). The shared cross-platform spec — Android expresses
the same intent with M3 Expressive motion-scheme springs per
docs/android/DESIGN-ANDROID.md rather than copying the tween values:

| Element | Out | In |
| --- | --- | --- |
| Stage swap | blur 0→6, opacity 1→0, ~180 ms ease-out | scale 0.96→1, blur 6→0, opacity 0→1, ~280 ms `.smooth`; overlaps the tail of *out* by ~80 ms |
| Element cascade inside a stage | — | 70 ms stride, reusing `stagger` (iOS) / `Modifier.riseIn` (Android) |
| Chassis container | never animates | never animates |
| CTA content change (label ⇄ label ⇄ spinner) | blur 0→2, opacity 1→0, ~160 ms ease-out | blur 2→0, opacity 0→1, ~260 ms `.smooth` (Android also scales 0.96→1) |
| CTA slot occupancy / style | opacity alone | scale 0.96→1, blur 4→0, opacity 0→1, on the step's own `.easeInOut(0.28)` (Android: M3 `defaultSpatialSpec` height spring, blur 3) |
| Press feedback | existing 0.97 scale, `.snappy(0.09)` down / `.snappy(0.18)` up | — |
| ASCII field vault morph (welcome ⇄ restoreMethod) | terrain deforms into the vault door riding the step's own `.easeInOut(0.28)` (Android: `defaultSpatialSpec`) — per-cell brightness lerp, never a crossfade; the mask's opaque ramp shortens to end at the door's top edge in the same scalar | vault dissolves back into terrain on retreat, same transaction; Reduce Motion snaps — the end states differ (terrain vs vault), so the swap stays legible without motion |

Three notes on that table, all added by the 2026-08-06 button-morph pass:

- **"Chassis container never animates" means the container.** Its padding,
  background, and position are fixed. The *slots inside it* do animate their
  height — that is how the stack grows upward from its fixed bottom edge as a
  step's action set changes, and Android has always done it
  (`SizeTransform` in `OnboardingChassis.kt`). iOS previously had no slot
  transition at all and snapped; it now matches.
- **"CTA content change" is one transition, not two.** Label→label and
  label→spinner are the same morph: iOS keys a `CapsuleContent` enum, Android
  uses a nullable label (`null` == loading) as the `AnimatedContent` target.
  Branching the spinner *outside* the animation — which is what Android shipped
  until now — produces a hard cut, and it was the single most visible snap in
  the flow.
- **The CTA never resizes mid-morph.** iOS reserves the footprint with an
  invisible spacer glyph (the device `PaymentStatusView` already uses for its
  CTA); Android's 64 dp `heightIn` covers both label and spinner already.

The welcome stage carries **no figurative ambient piece**: the note ↔ token
morph that shipped with the restyle was cut on 2026-08-05 (user-directed) — an
idle loop earning nothing after the first launch. What it carries instead is
the **ASCII terrain field** as texture — on welcome it runs tall: clear
behind the header, a long fade to opaque, filling the stage's slack. Since
2026-08-09 (second pass, same day as the extent settle it supersedes) the
pair's screen-change cue is the field's **material**: on restoreMethod the
terrain morphs into a **vault door** (`AsciiFieldVault` — rings, spokes, ₿
bolts, and a ₿ monogram as a procedural brightness field through the same
glyph ramp, its ink modulated by the live terrain field itself so the
ridgelines keep crawling through the door's structure; the brief §4 amendment
is the sanctioned exception that permits it). The drawn layer is full-window on **both** steps and never
moves (glyph positions are a function of layer size — a resizing layer would
make the texture swim and re-hash); one 0…1 morph scalar riding the step
transaction lerps every cell's brightness terrain → vault and shortens the
mask's opaque ramp to end at the door's top edge — the clear line behind the
header never moves. Band mode (the old restoreMethod bottom band) survives in
`AsciiFieldLayout` as pure math and tests; no step rests on it. The vault is
authored at fixed size (outer ring r146, reach 157 grid units), centered in
the free region between header clearance and chassis, and does not scale with
the window. `AsciiFieldLayout` / `AsciiFieldVault` on each platform are the
single statements of that geometry and material, pinned by
`AsciiFieldLayoutTests` / `AsciiFieldLayoutTest`, the vault parity vectors
(`AsciiFieldVaultTests` / `AsciiFieldVaultTest` — generated from the design
mock's Python), and the compose layout-invariant test.

Exits stay subtler than entrances throughout (the carve-out above). The
layout grammar (revised by design review 2026-08-05): **every** step, welcome
included, titles itself at the top (`OnboardingStepHeader`, riding the stage
swap) with its actions anchored to the bottom edge and a circular Liquid Glass
back button
(`OnboardingBackButton`, `.quaternary` pre-26) wherever a retreat exists.
Every step's title lands on the same line whether or not it has a retreat:
the back button fills a bar band below the safe area, and a step without one
(the terminal restore screens) **reserves that band** instead of riding up
against the status bar — the title has to stay put across the stage swap.
`OnboardingMetrics` (`OnboardingChassis.swift`) is the only place that
geometry is stated; no step hand-rolls its own top spacing, and no stage
re-applies the header's gutter. Android states the same rule in its own
measure — see UX_SPEC.md §2.
The indicator slot is resolved as "no indicator" (the flow branches into
paths of different lengths, so page dots would imply a linear path that does
not exist).

"Anchored to the bottom edge" means the bottom of the **available content
area**, which the software keyboard shrinks. `restoreInput` deliberately raises
a keyboard on arrival (see below), and the chassis rides up with it — iOS via
`.safeAreaInset(edge: .bottom)`, Android via `imePadding()`. The UI tests
measure against that edge, not the window, or the invariant would read as
broken on exactly the step that exercises it hardest.

`restoreInput` is the one step that **focuses on arrival**. Word-by-word seed
entry is keyboard-driven from the first frame, so the "land calm — don't pop
the keyboard on arrival" rule that `restoreMints` keeps is suspended here, and
only here. On iOS that also means all smart-substitution traits and
`inlinePredictionType` are off — not for tidiness, but because the predictive
bar changes the keyboard's height, which would move the CTA mid-step. Android
cannot suppress Gboard's strip; `imePadding()` absorbs the difference.

The step's progress rail carries one gesture beyond tap-to-jump: press-and-hold
then drag scrubs through the words, the focused word updating live with one
selection tick per word change, releasing wherever the finger is. The
long-press gate is the whole design — quick taps never satisfy it and plain
drags still scroll, so it adds nothing to either path's cost.

## 7. Do's and Don'ts

### Do

- **Do** reach for system semantic colors first: `Color.primary`,
  `Color.secondary`, `Color.accentColor`, `Color(.systemBackground)`,
  `Color(.separator)`. The only acceptable state colors are `.green`,
  `.orange`, `.red`, and they appear at full opacity for foreground or at the
  stated tints (10% for pending, 18% for error).
- **Do** apply `.monospacedDigit()` and `.contentTransition(.numericText())`
  to every value that represents money, every time. Balance, amount, fee.
- **Do** use `Capsule()` for full-width primary and secondary buttons, and
  `RoundedRectangle(cornerRadius: 12)` for inline chips and notifications.
  Stick to the spacing scale (4, 6, 8, 12, 16, 20, 24, 28).
- **Do** branch with `if #available(iOS 26.0, *)` for Liquid Glass and provide
  a quiet `.thinMaterial` or `.quaternary` fallback. Never ship a Liquid Glass
  surface that breaks on iOS 18.
- **Do** use `CanvasDivider()` when a single-canvas detail needs explicit row
  separation. Home and History transaction activity intentionally omit it.
- **Do** name iOS text styles (`.body`, `.largeTitle`, `.caption`) so Dynamic
  Type scales for free. Pair balance/amount text with `.minimumScaleFactor(0.5)`
  and `.lineLimit(1)` so AX5 doesn't truncate a money value.
- **Don't** add an entrance stagger (or any offset/fade swoop-in) to a list that
  lives on a tab. The History tab remounts on every visit (`Color.clear` fast-boot
  swap), so a "play once" entrance replays as an unwanted swoop every time. Rows
  appear in place; reserve motion for reflows (`.snappy(0.25)` scroll-reset) and
  explicit user actions (the chooser cascade), never for arriving at a tab.
- **Do** swap in-sheet faces with a 0.25s opacity cross-fade
  (`.transition(.opacity)` + `.animation(.easeInOut(duration: 0.25), value:)`)
  rather than pushing a sub-view through a `NavigationLink`. Sheets are units
  of intent; cross-fade keeps the unit intact. Push navigation is for
  content-detail relationships.
- **Do** open small attribute editors (mint, amount on a Cashu Request) as
  nested sheets at `.presentationDetents([.medium])` and dismiss on selection.
  The parent's context never leaves the screen.
- **Do** promote the parent sheet's detent programmatically when its content
  outgrows the current size (e.g. flipping from a paste-token form at
  `.medium` to a freshly-built Cashu Request at `.large`). The detent serves
  the content, not the other way around.
- **Do** honor `accessibilityReduceMotion` on every custom animation. (The
  current named animations are not yet uniformly compliant; new code must be.)

### Don't

- **Don't** define a custom `extension Color`. There is no `Color.cashuOrange`,
  no `Color.brandInk`. If you reach for one, the design has drifted.
- **Don't** use `.black` or `.white` outside the scanner overlay and QR code
  contexts. Use `Color.primary` and `Color(.systemBackground)` instead.
- **Don't** color a pending row green, an outgoing badge green, a chevron
  green, or anything other than a completed-row amount or a confirmed
  *incoming* directional badge. **The One Green Rule.**
- **Don't** ship a loud "PENDING" pill or any full-saturation orange chip. The
  quiet-pending principle is encoded in `clock.circle.fill` over secondary
  text and `.opacity(0.1)` orange backgrounds.
- **Don't** drop a `.shadow(...)` modifier on a card, a button, or a row, ever.
  **The Flat-By-Default Rule** is absolute — there are zero shadows in the app
  (see the No-Shadow Absolute). Depth is materials and hairlines.
- **Don't** ship the **hero-metric SaaS panel**: big number on tinted card,
  small label below, supporting stats around it. The balance is the only
  hero number the wallet gets, and it lives on the bare canvas. *Mint
  cards (see The Mint Card Exception in §5) are not stats — they are
  first-class account surfaces, and they earn the carve-out for that
  reason. No other "supporting tile" pattern qualifies.*
- **Don't** wrap a screen's content in nested cards or in a single full-bleed
  container with `cornerRadius: 16`. Use the bare canvas + `CanvasDivider`.
  *The mint card row on home is a horizontally-scrolling row of Liquid Glass
  tiles, not a container wrapping content — the canvas underneath is still
  bare, and the transactions list below sits on it directly.*
  *The onboarding seed phrase is the one screen with a content container — see
  The Seed Card Exception in §5. It earns it because the card is the
  tap-to-reveal affordance, not decoration. Do not generalize it.*
- **Don't** introduce a display font, a serif pairing, or a custom-loaded
  `.otf` **on iOS**. SF system styles only — see §3 for why this is an
  iOS-specific rule and why Android's Geist carve-out (2026-08-03,
  user-directed) does not contradict it.
- **Don't** write a bare `.system(size: N)`, a literal `.tracking()`, or a
  reserved height as a constant. Roles carry all three; `TypographyGuardTest`
  fails the build on the Android side and the same rule holds on iOS.
- **Don't** hand a pre-joined amount string to a hero. Pass `AmountParts` so the
  unit can be subordinated.
- **Don't** reach for `.fullScreenCover` for a confirmation, a settings flow,
  or any modal that is not the camera. Use a sheet with the right detent.
- **Don't** add bounce, elastic, or new `.spring` parameters outside the
  named seven (see § Motion Vocabulary). The single allowed spring is the
  payment-received celebration at `(0.5, 0.7)`; everything else lives in
  `.smooth(0.32)`, `.snappy(0.09–0.35)`, or `.easeInOut(0.2–0.3)`.
- **Don't** push a sub-view inside a sheet when the inner state is just
  another face of the same task. Use the 0.25s opacity cross-fade. Push
  navigation inside a sheet is reserved for content-detail relationships
  (a history row opening its transaction detail).
- **Don't** spawn a new sheet, full-screen cover, or alert for an attribute
  edit that fits in three rows. The right pattern is a `.medium`-detent
  sub-sheet that closes itself on selection.
- **Don't** echo the anti-references from docs/product/PRODUCT.md: no gamified crypto-app
  confetti, no neon-on-black "crypto default" palette, no mascots, no
  signature gradients, no holographic borders, no glowing rings. Money is not
  a game and the wallet should not fight iOS for attention.
