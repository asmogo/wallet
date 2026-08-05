# DESIGN-ANDROID.md — the Android design charter

**Charter (2026-07-08): Android-first, Material 3 Expressive, no iOS constraints.**

The iOS app's `DESIGN.md` governs **what** the product does — screens, flows,
copy intent, feature semantics. It never governs how Android looks, moves, or
feels. Android is a first-class native app: if a choice would make the app feel
like a port, make the Android-native choice instead.

---

## 1. Foundations

### Color — monochrome inverted ink
- **Custom zero-chroma scheme** (`LightInkColorScheme` / `DarkInkColorScheme`
  in `ui/theme/Color.kt`, applied in `ui/theme/CashuTheme.kt`): white canvas +
  black ink in light mode, black canvas + white ink in dark mode — the brand
  identity shared with iOS ("inverted ink"). All neutrals are pure grays.
- **No Material You dynamic color** (locked decision, 2026-07-09): the palette
  must never shift with the wallpaper. Brand > Monet.
- Full M3 color roles are still used as designed: filled primary CTAs (black on
  light / white on dark), tonal secondaries, `secondaryContainer` nav
  indicator, tonal surface-container tiers (gray ramp). Components stay stock
  Material — only the palette is branded.
- **Semantic state hues stay fixed** (received green / pending orange / error
  red via `CashuColors` + the `error` role) — chromatic color is reserved
  exclusively for payment state.

### Type & shape — stock M3
- `Typography()` and `Shapes()` defaults (`ui/theme/Type.kt`, `Shape.kt`).
  Roles used as designed; no custom ramps.
- Money always chains `withMonoDigits()` (tabular figures) — amounts roll,
  never reflow. `asOverline()` for section headers. `CapsuleShape` available.
- **Weight carve-outs (2026-07-10, cross-platform brand parity, user-directed):**
  two deliberate deviations from stock W400. (1) The tab titles render **Bold**
  via the shared `ui/components/TabTopBar.kt` — the one wrapper every top-level
  tab (History/Mints/Settings) routes through, so their big collapsing titles are
  identical by construction. (2) Every live amount-entry hero renders **SemiBold**
  with the unit baked *inline* (`₿1,234` / `1,234 sat`, no separate caption) via
  the shared `ui/components/AmountEntryHero.kt` + `AmountFormatter.entryDisplay`,
  mirroring iOS `CurrencyAmountDisplay`. Kept at the `displayMedium` (45sp) size so
  long amounts stay on one line. Native collapse-on-scroll is unchanged.

### Motion — M3 Expressive springs
- `MaterialExpressiveTheme` + `MotionScheme.expressive()`: spring physics drive
  component motion. New motion should use `spring(...)` specs (or motion-scheme
  tokens), not hand-tuned tweens. Choreography constants that are literal iOS
  copies (70ms stagger step, 1100ms waiting-pulse, 900ms spinner period) live
  in `ui/theme/Motion.kt` (`CashuMotion`).
- **Shared motion primitives** (`ui/components/`): `SpinnerRing` (Canvas port
  of the iOS trimmed-arc payment spinner; reduce-motion falls back to
  `CircularProgressIndicator`), `IconSwap` (glyph replacement ≙ iOS
  `.symbolEffect(.replace)`), `rememberBounceScale` (one-shot bounce ≙
  `.symbolEffect(.bounce)`), `Modifier.materializeBlur()` (blur-to-sharp
  success materialize, API 31+ only), `SkeletonValue` (redacted-style
  fill-in for pending quote values, no shimmer). Reuse these instead of
  re-deriving per screen.
- **Navigation**: shared-axis X (slide + fade) for push/pop; fade-through for
  tab switches (`CashuNavHost.kt`). Predictive back is enabled
  (`android:enableOnBackInvokedCallback`).
- **No hard cuts**: full-screen overlays (scanner, contactless) slide over the
  shell (`CashuApp.kt`); the bottom bar animates away on push
  (`WalletScaffold.kt`); the payment terminal fades/settles in
  (`PaymentStatusScreen.kt`). The success check carries the one celebration
  beat (bounce + materialize); failures stay deliberately still. **Every**
  completion routes through the shared `PaymentStatusScreen` — including Receive
  Lightning (paid invoice) and a fresh Cashu Request's first payment, which
  cross-fade the whole sheet body to the terminal and auto-dismiss after ~1.8s
  with no Done button (Android carve-out; iOS keeps Done). A Cashu Request opened
  from *history* stays inline/persistent — it's reusable and multi-payment.
- **Touch responds physically**: CTAs and number-pad keys spring-scale on press
  (`Buttons.kt`, `NumberPad.kt`); text buttons dim to 0.6 while pressed
  (iOS `TextLinkButtonStyle`).
- Lists animate placement (`Modifier.animateItem()` — History, Home recent,
  Mint discovery), reveals expand/shrink, page dots stretch into pills.
- **Numbers are quiet**: `AmountText` cross-fades the whole string on change
  (`Spring.StiffnessMedium`, no per-digit slide) — the same restrained
  transition every other amount swap uses (`AmountFlipDisplay`, `BalanceDisplay`).
  The earlier per-digit odometer roll read as too much and was retired
  (2026-07-10). Home's received-delta beat still swaps into the fiat slot for
  2.5s with the sanctioned celebration spring (`BalanceDisplay`).
- **Reduce-motion**: decorative loops (waiting pulses, spinner ring, bounces,
  cascades) render their resting state when system animations are off.
  `rememberReducedMotion()` is reactive — it observes
  `ANIMATOR_DURATION_SCALE` and updates mid-session.
- **Onboarding exemption (2026-08-05, onboarding restyle, user-directed):**
  pre-wallet onboarding surfaces (`ui/onboarding/` — the chassis, stages, and
  welcome piece, everything before `completeOnboarding()`/`completeRestore()`)
  carry their own motion spec, shared with iOS via the table in
  `docs/product/DESIGN.md` §6 and expressed here as motion-scheme springs
  (`motionScheme.defaultEffectsSpec/defaultSpatialSpec/fastEffectsSpec`), the
  gated `Modifier.materializeBlur()`, and `Modifier.riseIn` (70 ms
  `CashuMotion.StaggerStepMs` stride). **Nothing defined under this exemption
  may be reused inside the wallet proper.** Numbers stay quiet (the
  recovered-sats total keeps mono digits, no roll) and every onboarding
  animation is `rememberReducedMotion()`-gated to opacity-or-nothing.
- **Onboarding system back (2026-08-05):** `OnboardingScreen` registers a
  `BackHandler` mirroring the on-screen Back affordances exactly (method
  chooser → welcome, seed entry → welcome, mint staging → seed entry with the
  staged list cleared). Steps with no Back affordance keep the platform
  default. Closes the gap where system back exited the app from every
  onboarding step.

### Components — expressive first
- Loaders are the expressive `LoadingIndicator` / `LinearWavyProgressIndicator`
  — never the classic circular/linear spinners. One carve-out: the payment
  terminal uses the custom `SpinnerRing` (cross-platform brand parity with the
  iOS pay-flow spinner).
- Tab screens use `LargeFlexibleTopAppBar` (big collapsing titles).
- Settings rows are M3 `ListItem`.
- Button hierarchy: filled `Button` (primary action) → `FilledTonalButton`
  (secondary) → `TextButton` (inline). See `PrimaryButton` / `SecondaryButton`
  / `GhostButton` / `DestructiveTextButton` in `Buttons.kt`.
- Bottom sheets (`ModalBottomSheet`) for choosers/pickers/inspectors; pushed
  destinations for flows. `NavigationBar` for tabs. `AlertDialog` for
  confirmation, destructive action tinted `error`.

### Layout invariants (kept from the structural pass)
- Measure, never assume, overlay heights (Home pinned header is pre-measured
  via `SubcomposeLayout`, so the first frame lays out with the correct list
  inset and fade mask — no hide-first-frame hacks).
- Consume the shell scaffold's window insets exactly once
  (`.consumeWindowInsets(contentPadding)` on every tab).
- Bottom inset spacers use `windowInsetsBottomHeight(WindowInsets.navigationBars)`.
- Dimension parameters are `Dp`, never raw `Int`.

### Haptics
`LocalHapticFeedback`: selection-class ticks on taps/toggles, `Confirm`/`Reject`
on payment terminal outcomes, `LongPress` where a long-press acts. Never
double-buzz one gesture.

---

## 2. Feature parity map (iOS = feature reference)

Screens and flows mirror iOS **functionally**: Home (balance, mint chip,
Receive/Send, recent activity), History (search/filter/pull-to-refresh),
Mints (+detail/discovery), Settings (+Backup, Lightning, Locked Ecash hub,
Nostr, Privacy), unified Send, Receive (ecash/lightning/requests), scanner,
contactless, onboarding. See git history for the parity passes.

## 3. Ranked gap backlog (features, not design)

1. **App Lock** — BiometricPrompt gate + `FLAG_SECURE` privacy scrim + Settings
   toggle. Also unlocks auth-gating for the nsec reveal sheets.
2. **Cloud seed backup** — Auto Backup / Blockstore / Drive decision pending.
3. **Cashu Request editing UI** — ✅ Mint / Amount / Unit inspector sub-sheets
   shipped; quote-backed receive artifacts remain correctly read-only.
4. **NFC tap-to-pay parity check** — verify `ContactlessPayView` against iOS
   coordinator flow and restyle to the new charter.
5. **Restore-over-units hardening** — loop restore across `mint.units` (do with
   iOS together).
6. **Home received-delta beat** — ✅ visual beat shipped (`BalanceDisplay`
   `receivedDelta`, driven by a balance-rise watch in `HomeScreen`). Still
   open: the success haptic for background receives, which needs a real
   receive-event signal from WalletManager to avoid double-buzzing in-flow
   receives.
7. **Non-sat History** — ✅ transaction loading now enumerates every tracked
   mint/unit wallet and preserves native-unit formatting in rows and details.
8. **Shared-element transitions** — transaction row → detail, QR card flows
   (`SharedTransitionLayout`), once nav-level motion has settled.
9. **Expressive `ButtonGroup` / shape-morph press states** — evaluate for the
   Receive/Send pair and number pad when the APIs stabilize.

## 4. Protected areas

- QR pipeline internals (`Views/Components/QRCodeView.kt`,
  `Core/AnimatedUrDecoder.kt`) are off-limits; style around them.
- The Nostr/P2PK seed is `sha256(mnemonic utf8)` on both platforms — never
  change unilaterally.
