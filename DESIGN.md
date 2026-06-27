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
  balance:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "34px"
    fontWeight: 700
    lineHeight: 1.06
    fontFeature: "tnum"
  title:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "28px"
    fontWeight: 600
    lineHeight: 1.14
  title3:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "20px"
    fontWeight: 500
    lineHeight: 1.2
  body:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.29
  body-emphasis:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: 1.29
  callout:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.3
  caption:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.33
  caption-emphasis:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 600
    lineHeight: 1.33
    letterSpacing: "0.06em"
  mono-caption:
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
    note: "Leading 36x36 history-row glyph (TransactionIcon). Pure directional arrow, always muted; direction is the arrow's orientation, never colour. The amount carries settled/pending state via .primary / .secondary — never green (One Green Rule). Carve-out: supersedes the prior kind-glyph + corner directional badge model."
  row-inspector-editable:
    backgroundColor: "transparent"
    textColor: "{colors.primary-text}"
    secondaryTextColor: "{colors.secondary-text}"
    padding: "12px 8px"
    typography: "{typography.body}"
    trailingHintSymbol: "pencil"
    note: "Cashu Request detail. Tap opens a medium-detent sub-sheet."
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

What this system explicitly rejects, pulled verbatim from PRODUCT.md:

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
- Hairline `CanvasDivider` (0.5pt at `Color(.separator)`) as the single-canvas
  separator. No card stacks, no nested containers.
- Motion is exponential ease-out, in the 180–350ms range. Seven named animations
  carry the full vocabulary: row stagger, badge symbol-replace, chooser cascade,
  press feedback, sheet cross-fade (in-sheet flow swap), payment-received
  celebration, and waiting-pulse. Nothing decorative beyond that.
- One inspector pattern for editable detail rows (Cashu Request → Mint, Amount):
  leading SF Symbol + secondary label + trailing value (medium weight, middle-
  truncated) + trailing `pencil` hint glyph. Tap opens a `.medium`-detent
  sub-sheet rather than pushing a screen.

## 2. Colors: The Inverted-Ink Palette

A semantic-only palette built on iOS system colors plus three state hues. The
single committed brand choice is the inverted `AccentColor`: black on light, white
on dark.

### Primary

- **System Ink** (light `#000000` / dark `#FFFFFF`): the `AccentColor` defined in
  `CashuWallet/Resources/Assets.xcassets/AccentColor.colorset`. Used for tints and
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
  receiver's reward, but **no longer on a ledger amount** — *as of 2026-06-01
  in-row amount green is retired* (see the amended One Green Rule; transaction
  and Cashu Request row amounts are `.primary` when settled, `.secondary` when
  pending). Green now lives only in **off-row / detail-surface success states**:
  the transient home received-delta beat (`✓ +amount`), the default-mint
  indicator dot, the `checkmark.seal.fill` "N payments received" status and the
  `checkmark.circle.fill` payment-received toast inside `CashuRequestDetailView`,
  and the transaction detail-sheet completed checkmark. **Nothing on a list row
  is green.** The leading directional arrow is always `.secondary` regardless of
  direction or state — green belongs to receipt-confirmation surfaces, not the
  ledger line.
- **Pending Orange** (`Color.orange`, ≈ `#FF9500` / `#FF9F0A`): foreground for
  the detail-sheet "pending" status badge (`TransactionDetailView`) and for the
  "Waiting for payment…" clock on a Cashu Request. It does **not** appear on a
  transaction *row* — a pending row is the muted `.secondary` amount alone
  (amended 2026-06-01). When used as a background it lives at `.opacity(0.1)` —
  the quiet-pending principle made visual.
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

**The Semantic-Only Rule.** No file in `CashuWallet/` defines a custom
`extension Color`. If a new color is needed, it is either a system semantic
(`Color.primary`, `Color.secondary`, `Color.accentColor`, `Color(.systemBackground)`,
`Color(.separator)`) or one of three state hues at a stated opacity. There is no
fourth case.

**The One Green Rule.** *Amended 2026-06-01: in-row amount green is retired —
amounts are never green.* A transaction row's amount is now a **two-state
ledger signal**: `.secondary` while `transaction.status == .pending`, `.primary`
once settled (both directions, both kinds — incoming, outgoing, ecash,
Lightning, on-chain). A received Cashu Request renders `.primary` too. The
shared `TransactionAmountColumn` (`CashuWallet/Views/Components/`) is the
canonical implementation: `amountColor` is exactly
`transaction.status == .pending ? .secondary : .primary`; do not re-derive the
color elsewhere. *Rationale for the carve-out:* mixing green/white/gray amounts
at mixed weights read as noisy rather than calm; a single white-settles /
gray-pends language is more aligned with the "System Utility" North Star, and
direction is already carried by the leading arrow + the `+`/`−` prefix.
Green now survives in **two off-row places only**, neither of which is a
transaction-row amount:
1. The home-screen received-delta beat (the transient `✓ +amount` under the
   balance, `AnimatedBalanceView`), green-on-receipt — a momentary celebratory
   confirmation that carries **no directional arrow** and fades in ~1s.
2. The **default-mint indicator dot** — a small green dot on a mint's icon
   (Mints list `MintsListView`, mint profile `MintDetailView`) marking the
   user's selected default mint. A *selection* marker (same axis as "Set as
   Default"), carries no amount or arrow, never appears on a transaction row
   (added 2026-05-31).
The detail sheet (`TransactionDetailView`) keeps its own *status-badge* colour
vocabulary (orange pending / green completed checkmark) — that is a labelled
status pill, a different surface from the ledger amount, and is intentionally
left untouched. Its **hero** (shown when there is no QR to display, e.g. a
received ecash) is the same muted directional arrow the list uses
(`arrow.down`/`arrow.up`, `.secondary`, on a `Color(.secondarySystemFill)`
circle) scaled up to 72pt — *not* a per-kind glyph (the old `link.circle` /
`bolt.fill` set was retired 2026-06-01). The **Type** and **State** rows are
omitted: the nav title (`WalletTransaction.displayTitle`) names the
kind/direction and the status badge carries the state, so repeating them as rows
is redundant.

**The Quiet Pending Rule.** *Amended 2026-06-01.* On **any list row** —
transaction or Cashu Request — pending/waiting is conveyed by the muted
`.secondary` amount **alone**: no badge, no icon, no orange. (The
`arrow.triangle.2.circlepath` per-row refresh button *and* the waiting-request
leading `clock` were both removed; manual re-check lives on History
pull-to-refresh — `.refreshable { syncPendingMintQuotes(); checkAllPendingTokens() }`.)
The muted-orange pending language survives only off the list: the detail-sheet
status badge (`TransactionDetailView`) and the "Waiting for payment…" status
clock inside `CashuRequestDetailView`. Never a full-saturation pill, never a
loud "PENDING" wordmark.

*Amended 2026-06-27: the leading `+`/`−` sign is itself a settled-ledger
signal. A pending row — either direction — renders a **bare, unsigned** amount;
the sign appears only on settlement, together with the `.primary` colour. This
unifies the transaction column (`TransactionAmountColumn`, used by BOLT11 /
Lightning / ecash) with the waiting Cashu Request / Reusable Invoice
(`CashuRequestAmountColumn`), which already showed a bare amount until paid — so
a pending incoming BOLT11 invoice no longer shows `+21` while a waiting BOLT12
offer shows `21`.*

**The Fiat Sub-Amount Rule.** When
`settings.showFiatBalance && priceService.btcPriceUSD > 0`, any row that
renders a sats amount also renders the fiat equivalent directly below it in
`.caption / .secondary / .monospacedDigit()` — supplementary text, never a
peer. Cashu Request "any amount" rows (no fixed expected total) render no
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

**Body Font:** San Francisco (`SF Pro`), via the iOS system font stack. No
`Font.custom(...)`, no font files in `Resources/`.
**Mono Font:** San Francisco Mono (`.system(.caption2, design: .monospaced)` or
`.fontDesign(.monospaced)`), used for token IDs, mnemonic words, and any place a
hex/base58 string would otherwise blur.

**Character:** the silent typographic confidence of a native iOS app. Text styles
are quoted by name (`.largeTitle`, `.title`, `.body`, `.caption`), never by
hardcoded `.system(size:)` except for the few monospaced fragments. Dynamic Type
inherits automatically; balance and amount displays survive AX5 because
`.minimumScaleFactor(0.5)` is paired with `.lineLimit(1)` on the balance and
because every layout uses `.frame(maxWidth: .infinity)` rather than fixed widths.

### Hierarchy

- **Balance** (`.largeTitle.bold()` + `.monospacedDigit()` + `.contentTransition(.numericText())`):
  the wallet balance and the recovered-amount counter. Tabular figures, animated
  digit-by-digit on change. The single most important typographic moment in the
  app. `MainWalletView.swift:93`, `AnimatedBalanceView.swift`.
- **Title** (`.title.weight(.heavy)` / `.weight(.semibold)`): onboarding hero
  headings only. `OnboardingView.swift:128, 258`.
- **Title3** (`.title3.weight(.medium)`): in-flow section heads such as the
  send/receive transaction-type label, modal titles. `MainWalletView.swift:165`.
- **Body Emphasis** (`.body.weight(.semibold)`): primary button labels (inside
  `glassButton()` / `FullWidthCapsuleButtonStyle`), history row title.
- **Body** (`.body`): default for prose, settings rows, detail values.
- **Text Link** (`.subheadline.weight(.medium)`, `.secondary`): borderless
  tertiary actions — "Skip" / "Skip for now", "What is ecash?", "Copy" /
  "Copied", "Add custom mint URL". Always applied via `.textLinkButton()`
  (`TextLinkButtonStyle`), never hand-rolled per site.
- **Callout** (`.callout`): supporting descriptive text under hero headings,
  e.g. "An ecash wallet for Bitcoin and Lightning." `OnboardingView.swift:135`.
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

**The System-Style Rule.** Text uses named iOS text styles (`.body`,
`.largeTitle`, `.caption`) so Dynamic Type "just works" from xSmall through AX5.
`.system(size:)` is reserved for the handful of monospaced fragments and the
ActivityOrb glyph. No `.system(size: 14)` to "make it fit"; pick the right style
and let the layout breathe.

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
  `CashuWallet/Views/Components/LiquidGlassModifiers.swift`. Used everywhere a
  button needs a visible affordance: Create Wallet, Continue, Pay, Send,
  Receive, Copy, Restore, etc.
- **Text link — `.textLinkButton()`** (= `TextLinkButtonStyle`): the canonical
  borderless, text-only tertiary action. `.subheadline.weight(.medium)`,
  `.secondary`, press-dim to 0.6, disabled 0.4 — the same feedback family as
  `glassButton()`. The style owns font + color + feedback only; layout
  (full-width, padding, an optional leading SF Symbol like the "+" on "Add
  custom mint URL") stays at the call site, since text links range from inline
  ("Copy") to full-width ("Skip", "Add custom mint URL"). Used for "Skip" /
  "Skip for now", "What is ecash?", "Copy", and "Add custom mint URL". Defined
  in `CashuWallet/Views/Components/LiquidGlassModifiers.swift`.
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
- **Press feedback — `PressableButtonStyle`**: 0.97 scale on press down
  (`.snappy(0.09)`), spring back on release (`.snappy(0.18)`). Apply only
  where the glass style doesn't already carry feedback (the chooser
  cascade).

### History Rows

The canonical list pattern. Defined in
`CashuWallet/Views/History/HistoryView.swift`.

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
- **Timestamp**: `.caption`, `Color.secondary`, immediately under the title.
  Formatted with `RelativeDateTimeFormatter(.abbreviated)` ("2 hr ago", "3 d ago").
- **Trailing amount**: `.system(.body, design: .rounded).weight(.semibold)
  .monospacedDigit()`, `.contentTransition(.numericText(value:))`, prefixed
  with `+` or `−`. Two-state colour: pending → `Color.secondary`, everything
  settled → `.primary` (both directions, both kinds; never green — see the
  amended One Green Rule).
- **Pending indicator**: none on the row. Pending is the muted `.secondary`
  amount alone (the `arrow.triangle.2.circlepath` refresh button was removed
  2026-06-01). Manual re-check is History pull-to-refresh
  (`syncPendingMintQuotes()` + `checkAllPendingTokens()`).
- **Separator**: `CanvasDivider()` with the default 28pt leading inset.
- **Entrance**: row stagger via `.smooth(duration: 0.32).delay(index * 0.035s)`,
  capped at `maxStaggerIndex = 8`. The first eight rows cascade in; everything
  after enters immediately. Driven by `hasAppearedOnce` so only the first
  appearance staggers — subsequent re-renders (filter change, pagination) animate
  via `.snappy(0.25)` on `value: filter` / `value: currentPage`.

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
- **Trailing amount** (all `.semibold`, matching every other amount):
  - Fixed-amount + waiting: `amount` in `.secondary`, no indicator — the muted
    amount alone signals waiting (the target is visible while pending).
  - Fixed-amount + received: `+amount` in `.primary`, monospaced digit,
    `.contentTransition(.numericText(value:))`. Cumulative for multi-payment.
  - Any-amount + waiting: no trailing element at all.
  - Any-amount + received: `+\(totalReceived)` in `.primary`, cumulative.
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
- **TextField** (Settings, e.g. Nostr relay): `.textFieldStyle(.roundedBorder)`
  — the system rounded style. Settings is the one place this is appropriate.
- **Amount entry**: never a raw TextField. The dedicated
  `CashuWallet/Views/Components/AmountEntryView.swift` view owns this — a
  full-screen canvas with `CurrencyAmountDisplay`, fiat-primary toggle, mint
  selector, and inline number pad. Amount is a *moment*, not a form field.

### Sheets

Sheets are the dominant modal pattern. Full-screen covers are reserved for the
camera scanner only.

- **Default**: `.sheet(item:)` + `.presentationDetents([.large])` +
  `.presentationDragIndicator(.visible)`. Use for any flow that has its own
  internal navigation (Send, Receive, Mints).
- **Adaptive**: `.presentationDetents([.medium, .large])`. Use for inspection-
  style sheets (Settings → Backup, single-mint detail). `ReceiveEcashView`
  opens at `.medium` and lets the user pull to `.large`; when the inner state
  flips to a freshly-built Cashu Request, the parent programmatically promotes
  the detent to `.large` (`sheetDetent?.wrappedValue = .large`) so the QR has
  room to land — the *detent* moves to the *content*, not the other way around.
- **Fixed height**: `.presentationDetents([.height(340)])` for compact
  confirmation surfaces (`AuthorizingOverlay`). Pair with
  `.presentationBackgroundInteraction(.disabled)` to lock the underlying canvas.
  The Send/Receive chooser uses `.presentationDetents([.height(195)])`
  (or `245` when NFC is available) — fitted exactly to the option list, never
  taller. Variable-height chooser detents are intentional: an empty option
  costs the user vertical space and adds no information.
- **Sub-sheets on a sheet**: `CashuRequestDetailView` opens
  `CashuRequestMintPickerSheet` and `CashuRequestAmountPickerSheet` as nested
  sheets at `.presentationDetents([.medium])`. The parent stays put; the
  sub-sheet is a transient editor and dismisses on selection. This pattern is
  the right replacement for "Edit Cashu Request" being its own screen — the
  attribute is small, the edit is one tap, the surrounding context never leaves.
- **Confirmation dialogs**: `.confirmationDialog(...)` for destructive
  actions (remove mint, sign out). Never a custom alert sheet.

### Cashu Request Inspector

The signature surface of the NUT-18 receive flow.
`CashuWallet/Views/Receive/CashuRequestDetailView.swift`. The view runs in two
contexts: as the receive-flow face inside a `.medium`/`.large` sheet from
`ReceiveEcashView`, or — from History/Home — presented as its **own bottom
`.sheet`** (wrapped in a `NavigationStack` at the call site for its toolbar).
**Detail surfaces are always bottom sheets, never pushed** — tapping any
history/recent item (transaction *or* Cashu Request) slides up the same way, so
the two never diverge into a push vs. sheet split. The same content scales to
both contexts.

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
    `.scale.combined(with: .opacity)` under `.spring(0.5, 0.7)`. Gated to the
    on-screen request (the `.cashuTokenReceived` notification carries the
    `requestId`). In the **receive flow** (watching a fresh request, `onClose`
    set) it dwells ~1.2s then the sheet auto-dismisses — mirroring the Lightning
    invoice. When **inspecting** an existing request from History/Home it holds
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
- **Actions**: two siblings via `glassButton()` — "Copy" (flips to "Copied"
  for 2s after tap, no other state change) and "New Request" (regenerates,
  rotating the QR). Order matters: the existing request lives on the left
  because it is the thing you'd usually share; the destructive-ish rotate
  lives on the right.

### Notifications

- **Received delta beat** (home screen): when `cashuTokenReceived` fires, the
  hero balance rolls upward via `.contentTransition(.numericText())` and a
  transient green `✓ +amount` (grouped through `AmountFormatter`, no unit, no
  directional arrow) takes over the fiat sub-amount slot beneath the balance,
  scaling in, holding 2.5s, then fading as the fiat line returns. Reuses the
  payment-received celebration vocabulary (Motion §6): `checkmark.circle.fill`
  with `.symbolEffect(.bounce)`, `.scale.combined(with: .opacity)`,
  `.spring(response: 0.5, dampingFraction: 0.7)`; reduce-motion collapses it to
  an opacity cross-fade. Defined in `MainWalletView` (`balanceStatusLine` /
  `receivedDeltaBeat`). This replaced the retired floating toast — the receive
  confirmation now lives on the balance, in the canvas, with no shadow and no
  floating surface.
- **`ErrorBannerView`**: inline red banner for in-context errors.

### Signature: ActivityOrb

`CashuWallet/Views/Components/ActivityOrbView.swift` — a pulsing `circle.dotted`
SF Symbol that fades in (`.easeIn(0.3)`), rotates linearly forever
(`.linear(2).repeatForever()`), and fades out (`.easeOut(0.5)`) when work
finishes. Used as a quiet "something is happening in the background" indicator
that doesn't block interaction. The closest thing this system has to a logo
moment — and it is still a system glyph at a system color.

### Named Rules

**The CanvasDivider Rule.** Single-canvas screens (History, Settings,
Lightning Invoice detail) use `CanvasDivider` between rows. Raw `Divider()` is
legacy. There are no card stacks; rows sit directly on the canvas, separated
only by the hairline.

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
"What is ecash?", "Copy", "Add custom mint URL") always goes through
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
visual noise that reduces the typographic weight of the action. The "Copied"
post-tap confirmation is also text-only — the label flips ("Copy" →
"Copied"), no checkmark icon. Context-menu entries are the exception: they
use `Label(_:systemImage:)` because iOS context menus expect an icon column
and look wrong without one. Small inline copy chips (Settings rows, the
truncated Lightning-address chip on the main wallet) also keep their icons
— there, the SF Symbol *is* the affordance because there is no text label.

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

1. **Row stagger** — `.smooth(duration: 0.32).delay(index * 0.035s)` on
   `value: hasAppearedOnce`, capped at index 8. Drives the History list's
   first appearance: 6pt y-offset + opacity → final position. Only first
   appearance staggers; filter/page changes re-render under `.snappy(0.25)`.
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
5. **Sheet cross-fade** — in-sheet flow swap, e.g. `ReceiveEcashView`
   flipping between the paste-token form and the `CashuRequestDetailView`.
   Each branch ships `.transition(.opacity)` and the container animates
   `.easeInOut(duration: 0.25)` on the discriminator (`value: currentRequest?.id`).
   Use this whenever a sheet has two faces of the same task; the alternative
   (push navigation, modal stacking) breaks the "the sheet is the unit of
   intent" principle in PRODUCT.md.
6. **Payment-received celebration** — `paymentJustReceived` lights up the
   Cashu Request status badge for 2.5s with `.spring(response: 0.5,
   dampingFraction: 0.7)`. The checkmark uses `.symbolEffect(.bounce, value:)`
   and the entire badge transitions in via `.scale.combined(with: .opacity)`.
   Same pattern is mirrored in `ReceiveLightningView` for `isPaid`, and on the
   home screen as the **received-delta beat** (`MainWalletView.receivedDeltaBeat`)
   — the green `✓ +amount` that takes over the balance's fiat slot on receipt.
   All three are instances of this one named animation, not new motions. The
   *singular* allowed celebration vocabulary — never confetti, never a haptic
   stronger than `.success`, never a sustained-color flash. **Resolution is
   context-dependent:** in a receive flow (Lightning invoice, or a fresh Cashu
   Request being watched) the badge dwells ~1.2s then the sheet slides down and
   dismisses; when *inspecting* an existing Cashu Request it instead holds 2.5s
   then steps back to the persistent line (N-payments-received). The home-balance
   delta beat steps back to the fiat sub-amount.
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
- **Do** use `CanvasDivider()` between rows on single-canvas screens. The
  default 28pt leading inset already aligns to the icon column.
- **Do** name iOS text styles (`.body`, `.largeTitle`, `.caption`) so Dynamic
  Type scales for free. Pair balance/amount text with `.minimumScaleFactor(0.5)`
  and `.lineLimit(1)` so AX5 doesn't truncate a money value.
- **Do** stagger the first eight history rows on entrance and morph the
  directional badge with `.contentTransition(.symbolEffect(.replace.downUp))`.
  Those are part of the seven named animations; new screens should reuse
  them, not invent more.
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
- **Don't** introduce a display font, a serif pairing, a custom-loaded `.otf`,
  or a `Font.system(size: N)` for body text. SF system styles only.
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
- **Don't** echo the anti-references from PRODUCT.md: no gamified crypto-app
  confetti, no neon-on-black "crypto default" palette, no mascots, no
  signature gradients, no holographic borders, no glowing rings. Money is not
  a game and the wallet should not fight iOS for attention.
