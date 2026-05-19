# Product

## Register

product

## Users

Bitcoiners who are new to Cashu. They already understand self-custody, Lightning,
and seed phrases, but ecash is unfamiliar — they're not sure what's custodial,
what a "mint" is, or whether tokens can disappear. They pick up Cashu Wallet on
iPhone to try the privacy properties without breaking anything.

Job-to-be-done: receive, hold, and send sats privately across mints, with enough
guardrails that the first real transaction feels safe rather than scary.

Secondary users — experienced Cashu power users running multi-mint, P2PK, NWC,
NPC — get the same surfaces; expert features live one tap deeper instead of
crowding the default flow.

## Product Purpose

A privacy-first iOS wallet for Cashu ecash, Lightning, on-chain Bitcoin, and NFC
contactless payments. Success looks like: a newcomer can mint their first token,
send it, and redeem it back without consulting external docs, and an expert can
manage multiple mints, swap, and recover from seed without feeling that the app
is hiding things from them.

It exists because the existing wallets in the space are either web-first
(constrained UX, no NFC, no Keychain), or do not treat Cashu's privacy model
with native-iOS care.

## Brand Personality

**Quiet · Precise · Native.**

Voice: factual, brief, never breathless. Buttons say what they do. Errors say
what broke and what to try next. Numbers are numbers, not decorated with emoji
or marketing language.

Emotional goal: the calm of using a well-built Apple utility. The user should
feel that the app is competent and not trying to impress them, the same energy
as Wallet.app, Notes, Things 3, Bear. Sophistication shows through restraint,
not flourish.

Reference lane: tech-minimal, HIG-native. Liquid Glass on iOS 26+ where it
clarifies hierarchy; quiet fallbacks below. Monochrome with semantic color only
for state (green confirmed, red error, orange pending, and even pending is
muted to a clock badge, never a loud pill).

## Anti-references

What this should explicitly NOT look or feel like:

- **Gamified crypto consumer apps** — MetaMask, Coinbase Wallet, Trust Wallet.
  No animated logos, no achievement empty states, no "You earned X!" toasts, no
  NFT carousels, no swap-screen confetti. Money is not a game.
- **Hero-metric SaaS dashboards** — no big-number-with-tiny-label panels,
  no "transactions this month" vanity surfaces, no card grids of stats. This is
  a wallet, not analytics.
- **Neon-on-black "crypto default" aesthetic** — no glowing borders, no
  holographic gradients, no monospace numerals just to look technical, no neon
  green/cyan/magenta on black. Dark mode is a system theme, not a brand statement.
- **Heavy custom branding** — no mascots, no illustrated empty states, no
  signature gradients, no brand-stamped patterns. The app should not fight iOS
  for visual attention.

## Design Principles

1. **Native before novel.** When iOS has a pattern that fits (sheets, bottom
   action buttons, semantic separators, system materials) use it. Reach for a
   custom solution only when the native one demonstrably fails the task.
2. **Restraint scales further than flourish.** Monochrome surfaces with one
   accent role per state will read clearly in a year; gradients and decorative
   color will look dated in six months. Default to quiet.
3. **Teach the mental model, don't lecture.** Newcomers don't know what a mint
   is. The product reveals concepts through use (first send, first redeem,
   first multi-mint moment) never through a wall of explanatory copy.
4. **Numbers are sacred.** Balances, amounts, fees, and unit toggles get the
   typographic care of a stopwatch face: tabular figures, numeric content
   transitions, no animations that obscure what the value just changed to.
5. **Quiet pending, clear final.** Intermediate states (pending, signing,
   in-flight) are muted on purpose so confirmed states land with weight. A
   confirmed transaction is the only thing on the row that gets to be green.

## Accessibility & Inclusion

Commit: **full Apple HIG accessibility** as the floor, not the ceiling.

- **Dynamic Type** — every surface, including primary actions and balance
  readouts, must lay out from xSmall through AX5. No truncation of money values
  at any size.
- **VoiceOver** — every actionable control has a meaningful label and (where
  state isn't obvious from the label) a hint. Balance and status changes are
  announced.
- **Reduce Motion** — the four custom SwiftUI animations (row stagger, badge
  morph, chooser cascade, press feedback) honor `accessibilityReduceMotion`.
- **Contrast** — WCAG 2.2 AA contrast in both light and dark modes for all
  text and interactive surfaces, AAA for critical-numeric surfaces (balance,
  amount-being-sent) where reasonable.
- **Color blindness** — never encode state with color alone; pair every
  semantic color with shape, icon, or copy (e.g. checkmark + green, clock +
  muted).
