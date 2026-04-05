# Button Consistency Audit — cashu.me-swift

## Background

The app currently has inconsistent button styling across screens. We have a good foundation with `.glassButton()` and `.liquidGlass()` modifiers in `LiquidGlassModifiers.swift`, but they are not applied uniformly. The goal is a deep audit and fix of every button in the app to enforce one coherent system.

## The Reference Standard

The **"Receive Ecash" bottom sheet** (ReceiveTokenDetailView) has the correct button pattern:
- **Full-width primary buttons** spanning the available layout width
- Clean, readable label text
- Proper use of liquid glass on iOS 26+ via the existing `.glassButton()` modifier

Every primary action button in the app should match this pattern.

## Observed Inconsistencies (from screenshots)

| Screen | Button | Problem |
|--------|--------|---------|
| Pay Lightning (MeltView) | "Get Quote" | Pill-shaped, centered, not full-width |
| Send Ecash (SendView) | "Send" | Pill-shaped, centered, not full-width |
| Receive Ecash amount screen | "Receive" | Pill-shaped, centered, not full-width |
| Receive Ecash amount screen | "Receive Later" | Plain text, inconsistent secondary style |
| Lightning request success screen | Bottom buttons | Two buttons appear as circles/pills with no visible label |

## What I Need You To Do

### 1. Deep Audit
Read every view file under `CashuWallet/Views/`. For each button, document:
- What style it currently uses (`.glassButton()`, `.buttonStyle(.plain)`, `.liquidGlass()`, custom, etc.)
- Whether it is full-width or constrained
- Whether it is a primary action, secondary action, or utility/navigation button

### 2. Define the Hierarchy

Apply the following button hierarchy consistently:

**Primary action buttons** (e.g. Send, Receive, Get Quote, Continue, Pay):
- Use `.glassButton(prominent: true)` on iOS 26+, fall back gracefully
- Full-width: `.frame(maxWidth: .infinity)` inside a padded `VStack`
- `.controlSize(.large)`
- Pinned to the bottom of the screen/sheet

**Secondary action buttons** (e.g. "Receive Later", "Cancel", "Paste from Clipboard"):
- Use `.glassButton()` (non-prominent) or a clearly legible `.buttonStyle(.bordered)` fallback
- Full-width if it appears in the same bottom area as a primary button
- Never use raw `.buttonStyle(.plain)` for secondary actions that are meaningful CTAs

**Utility/navigation buttons** (e.g. close X, toolbar icons, number pad keys, mint selector):
- Keep `.buttonStyle(.plain)` or `.liquidGlass(interactive: true)` as appropriate
- These do NOT need to be full-width

### 3. Liquid Glass Rules (follow Apple's HIG for iOS 26)
- Use liquid glass (`.glassButton()` → `.buttonStyle(.glass)`) for **primary and secondary action buttons** in sheets and modal contexts
- Use `.liquidGlass(interactive: true)` for **interactive container areas** like the quick-action capsules on the home screen
- Do NOT apply glass to toolbar/navigation buttons — keep those `.plain`
- Do NOT apply glass to number pad keys

### 4. Color Constraint
- Keep the existing **black and white** accent color scheme — do not introduce color
- Do not change any color values; only fix button styles, sizing, and layout

### 5. Width Constraint
- All primary and secondary CTA buttons must be **full-width** with standard horizontal padding (`padding(.horizontal)` or `padding(.horizontal, 20)` — match whatever the existing standard is in `ReceiveTokenDetailView`)
- No centered pill buttons for primary actions

## Files Most Likely Needing Changes

- `CashuWallet/Views/Send/SendView.swift`
- `CashuWallet/Views/Melt/MeltView.swift` (Pay Lightning)
- `CashuWallet/Views/Receive/ReceiveLightningView.swift`
- `CashuWallet/Views/Receive/ReceiveTokenDetailView.swift` ← this is the reference, touch only if needed
- `CashuWallet/Views/Settings/SettingsView.swift`
- Any other view with a primary CTA button

## Existing Utilities to Reuse

- `LiquidGlassModifiers.swift` — `.glassButton()`, `.glassButton(prominent: true)`, `.liquidGlass()`
- Do not create new button styles; use what exists

## Verification

After changes, confirm:
1. Every primary action button is full-width and uses `.glassButton(prominent: true)`
2. Every secondary action button is full-width (when co-located with a primary) and uses `.glassButton()`
3. No primary/secondary CTA uses raw `.buttonStyle(.plain)` or a narrow fixed width
4. Liquid glass is applied on iOS 26+ via the existing modifier (no new APIs)
5. Colors remain black and white
6. Build succeeds with no warnings introduced
