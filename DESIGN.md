---
name: Cashu Wallet
description: Privacy-first iOS wallet for Cashu ecash, Lightning, on-chain Bitcoin, and NFC.
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
- Motion is exponential ease-out, in the 200–350ms range. The four named animations
  (row stagger, badge symbol-replace, chooser cascade, press feedback) are the
  full motion vocabulary; nothing decorative.

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

- **Confirmed Green** (`Color.green`, ≈ `#34C759` / `#30D158`): the colour of a
  completed transaction. Foreground on the history row amount when status is
  `completed`, foreground on the badge checkmark. **Nothing else on the row is
  allowed to be green.**
- **Pending Orange** (`Color.orange`, ≈ `#FF9500` / `#FF9F0A`): muted clock badge
  on a pending history row, foreground for the "pending" status string. When used
  as a background it lives at `.opacity(0.1)` — the quiet-pending principle made
  visual.
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

**The One Green Rule.** A confirmed transaction is the only thing on its row that
gets to be green. Not the icon, not the chevron, not the amount in pending state.
Green is the reward the row earns by clearing.

**The Quiet Pending Rule.** Pending is `Color.orange` muted to `.opacity(0.1)`
as a background and the clock SF Symbol as a leading badge. Never a full-saturation
pill, never a loud "PENDING" wordmark. The recent commit "Quiet pending row state
in History — clock badge, drop orange pill" is the standing law.

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

There is no `box-shadow` or `.shadow(...)` modifier in the production view
tree. A single subtle press scale (0.97 via `PressableButtonStyle`, 0.09s down /
0.18s spring back) is the only "lift" the system ships.

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

**The Flat-By-Default Rule.** No drop shadows. No glow rings. Depth is conveyed
by translucent materials and hairline `CanvasDivider`s, not by elevation
geometry. If you reach for `.shadow(...)`, the layout is wrong.

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
- **Utility — `.buttonStyle(.plain)`** with an SF Symbol + label combo, often
  wrapped in `.liquidGlass(in: Capsule(), interactive: true)` when the symbol
  earns a glass surface. Used for the unit-symbol toggle on the main wallet,
  the truncated Lightning address copy chip, "Skip", "Back", "Got it" text
  links, and inline chevron actions.
- **Home action row — raw `.liquidGlass(in: Capsule(), interactive: true)`**:
  the Receive / Scan / Send triptych in `MainWalletView` uses inline glass
  rather than `glassButton()` because it needs `GlassEffectContainer` (iOS 26
  merged-glass effect) and three different shapes (Capsule + Circle + Capsule).
  Typography and padding match `FullWidthCapsuleButtonStyle` exactly
  (`.body.weight(.semibold)`, `.padding(.vertical, 18)`) so it reads as one
  family.
- **Press feedback — `PressableButtonStyle`**: 0.97 scale on press down
  (`.snappy(0.09)`), spring back on release (`.snappy(0.18)`). Apply only
  where the glass style doesn't already carry feedback (the chooser cascade,
  the EcashIcon tap target).

### History Rows

The canonical list pattern. Defined in
`CashuWallet/Views/History/HistoryView.swift`.

- **Leading**: stacked icon — transaction-kind glyph (EcashIcon, LightningIcon,
  or `bitcoinsign.circle.fill`) with a small badge overlay. The badge uses
  `.contentTransition(.symbolEffect(.replace.downUp))` so it morphs cleanly
  between `clock` (pending) and `checkmark.circle.fill` (confirmed).
- **Title**: left-aligned, `.body.weight(.medium)`, single line.
- **Timestamp**: `.caption`, `Color.secondary`, immediately under the title.
- **Trailing amount**: `.body.weight(.semibold).monospacedDigit()`,
  `.contentTransition(.numericText())`. Pending → `Color.secondary`. Confirmed →
  `Color.green`. Never colored in any other state.
- **Separator**: `CanvasDivider()` with the default 28pt leading inset.
- **Entrance**: row stagger via `.smooth(duration: 0.32).delay(index * 0.035s)`,
  capped at `maxStaggerIndex = 8`. The first eight rows cascade in; everything
  after enters immediately.

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
  style sheets (Settings → Backup, single-mint detail).
- **Fixed height**: `.presentationDetents([.height(340)])` for compact
  confirmation surfaces (`AuthorizingOverlay`). Pair with
  `.presentationBackgroundInteraction(.disabled)` to lock the underlying canvas.
- **Confirmation dialogs**: `.confirmationDialog(...)` for destructive
  actions (remove mint, sign out). Never a custom alert sheet.

### Notifications

- **`NotificationBadgeView`**: top-of-screen success toast. Checkmark icon +
  message + amount + close button.
  `.liquidGlassMaterial(in: RoundedRectangle(cornerRadius: 8))`. Slides in from
  the top edge (`.move(edge: .top).combined(with: .opacity)`), self-dismisses.
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

## 6. Do's and Don'ts

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
  pending/confirmed badge with `.contentTransition(.symbolEffect(.replace.downUp))`.
  Those are the existing motion vocabulary; new screens should reuse it, not
  invent more.
- **Do** honor `accessibilityReduceMotion` on every custom animation. (The
  current four custom animations do not yet check this; new code must.)

### Don't

- **Don't** define a custom `extension Color`. There is no `Color.cashuOrange`,
  no `Color.brandInk`. If you reach for one, the design has drifted.
- **Don't** use `.black` or `.white` outside the scanner overlay and QR code
  contexts. Use `Color.primary` and `Color(.systemBackground)` instead.
- **Don't** color a pending row green, an icon green, a chevron green, or
  anything other than the confirmed-amount text green. **The One Green Rule.**
- **Don't** ship a loud "PENDING" pill or any full-saturation orange chip. The
  quiet-pending principle is encoded in `.opacity(0.1)` and the clock SF Symbol.
- **Don't** drop a `.shadow(...)` modifier on a card, a button, or a row.
  **The Flat-By-Default Rule.** Depth is materials and hairlines.
- **Don't** ship the **hero-metric SaaS panel**: big number on tinted card,
  small label below, supporting stats around it. The balance is the only
  hero number the wallet gets, and it lives on the bare canvas.
- **Don't** wrap a screen's content in nested cards or in a single full-bleed
  container with `cornerRadius: 16`. Use the bare canvas + `CanvasDivider`.
- **Don't** introduce a display font, a serif pairing, a custom-loaded `.otf`,
  or a `Font.system(size: N)` for body text. SF system styles only.
- **Don't** reach for `.fullScreenCover` for a confirmation, a settings flow,
  or any modal that is not the camera. Use a sheet with the right detent.
- **Don't** add bounce, elastic, or `.spring(response:, dampingFraction:)`
  values outside the existing vocabulary (`.smooth(0.32)`, `.snappy(0.25–0.35)`,
  `.easeOut(0.2–0.3)`). Motion is exponential ease-out, in that range.
- **Don't** echo the anti-references from PRODUCT.md: no gamified crypto-app
  confetti, no neon-on-black "crypto default" palette, no mascots, no
  signature gradients, no holographic borders, no glowing rings. Money is not
  a game and the wallet should not fight iOS for attention.
