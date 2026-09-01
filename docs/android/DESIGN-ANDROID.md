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

### Type — Geist on the M3 scale
*Rewritten 2026-08-03.*

- **Geist Sans and Geist Mono, bundled** (`res/font/geist.ttf`,
  `geist_mono.ttf`; SIL OFL 1.1, surfaced in Settings → Licenses). Android-first
  carve-out, user-directed: iOS keeps SF Pro because SF Symbols are metrically
  bound to it and system-presented surfaces cannot be restyled. Neither cost
  applies here — Compose renders its own text and every M3 component reads
  `MaterialTheme.typography`, so the swap is total.
- **Source the GitHub release build, never Google Fonts.** The Google Fonts
  build strips the full OpenType table; if it were substituted,
  `withMonoDigits()` would silently no-op and every amount column would start
  jittering with no error anywhere. `GeistFontTest` parses the shipped files and
  fails the build if `tnum`, `ss09`, the `wght`-only axis set, or the declared
  cap/ascent ratios are wrong.
- **Sizes, line heights and tracking are Material's own.** Geist's cap height
  (0.710) and x-height (0.530) are within a thousandth of Roboto's, so
  Material's Roboto-tuned reading tracking transfers unchanged rather than
  needing a Geist-specific table. Measured, not assumed.
- **`ui/theme/Type.kt` owns everything.** `CashuTheme.type.*` supplies twelve
  app roles on top of the Material scale. `TextStyle.atSize(size, leading,
  trackingEm)` is the only sanctioned way to change a size — a bare
  `copy(fontSize = …)` orphans the line height, which is how the entry hero came
  to set 64sp type in a 52sp box, a 0.81× ratio that crops the glyph.
  `TypographyGuardTest` enforces this with an empty allowlist.
- **The amount ladder is four rungs**: `amountHero` 52sp (balance *and* live
  entry — one component, `ui/components/AmountHero.kt`), `amountConfirm` 40sp,
  `amountCompact` 28sp, `amountRow` 16sp. Typed by role, never by point size.
  52 rather than 56 because Geist sets ~7% wider than Roboto.
- **The unit is subordinated, not set at parity.** Formatters return
  `AmountParts`; `AmountHero` composes value and unit as two runs of one string
  (one `Text`, so autosize scales both together) with a unit word at half size,
  one weight down, secondary ink, baseline-aligned.
- Money always chains `withMonoDigits()`. The mono roles add `withSlashedZero()`
  — via **`ss09`**, since Geist ships no standard `zero` feature.
- **Weight carve-out (2026-07-10, user-directed):** tab titles render **Bold**
  via the shared `ui/components/TabTopBar.kt`, so every top-level tab's
  collapsing title is identical by construction. Native collapse-on-scroll is
  unchanged.

### Shape — stock M3
- `Shapes()` defaults (`ui/theme/Shape.kt`); `CapsuleShape` available.

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
  success materialize, API 31+ only), `AnimatedVisibilityScope.morphBlur()`
  (cross-fade mask — see below), `SkeletonValue` (redacted-style
  fill-in for pending quote values, no shimmer). Reuse these instead of
  re-deriving per screen.
- **Cross-fade masking** (`morphBlur`, `Materialize.kt`, added 2026-08-06): a
  small blur riding **both** halves of an `AnimatedContent` swap, so the eye
  reads one object transforming instead of two overlapping. `materializeBlur`
  cannot do this — it is a one-shot `LaunchedEffect` and so can only blur the
  incoming child — hence the sibling. Used on `PrimaryButton` / `GhostButton`
  labels (2 / 1.5 dp) and the onboarding chassis slot (3 dp). API 31+ and
  reduce-motion gated; below either, the plain cross-fade still carries the
  change. Rationale in `docs/product/DESIGN.md` §6.
- **Navigation**: shared-axis X (slide + fade) for push/pop; fade-through for
  tab switches (`CashuNavHost.kt`). Predictive back is enabled
  (`android:enableOnBackInvokedCallback`).
- **No hard cuts**: full-screen overlays (scanner, contactless) slide over the
  shell (`CashuApp.kt`); the bottom bar animates away on push
  (`WalletScaffold.kt`). The payment terminal's entrance splits by mount:
  processing/failure mounts fade + settle in as one unit
  (`PaymentStatusScreen.kt`'s root layer), while a terminal **mounted directly
  at success** (payment landed while a waiting face was up) plays the staged
  celebration — check materializes at ~100ms (bounce + blur + 0.92 grow, with
  the success haptic), title band at ~220ms (opacity + 8dp settle-rise), rows
  + Done at ~300ms (6dp rise on rows only — never blur, they're money; Done is
  tappable from frame 1). The success check carries the one celebration beat;
  failures stay deliberately still; reduce-motion collapses the stage to a
  flat fade. **Every** completion routes through the shared
  `PaymentStatusScreen` — including Receive Lightning (paid invoice) and a
  fresh Cashu Request's first payment, which swap the sheet body to the
  terminal with the standard `fadeIn(200)/fadeOut(150)` pair and keep an
  explicit Done (both platforms; an older note claimed a ~1.8s auto-dismiss
  carve-out that never shipped). A Cashu Request opened from *history* stays
  inline/persistent — it's reusable and multi-payment.
- **Touch responds physically**: CTAs and number-pad keys spring-scale on press
  (`Buttons.kt`, `NumberPad.kt`); text buttons dim to 0.6 while pressed
  (iOS `TextLinkButtonStyle`). The response is **asymmetric** — a spring carries
  no direction, so the spec is selected on the press edge instead:
  `fastEffectsSpec` compressing, `defaultEffectsSpec` releasing. *Effects*, not
  spatial, even for scale: Expressive's spatial springs are under-damped
  (0.6–0.8) and a press must not overshoot — it is a state flip, not a reflow,
  and no gesture momentum preceded it.
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
  pre-wallet onboarding surfaces (`ui/onboarding/` — the chassis and stages,
  everything before `completeOnboarding()`/`completeRestore()`)
  carry their own motion spec, shared with iOS via the table in
  `docs/product/DESIGN.md` §6 and expressed here as motion-scheme springs
  (`motionScheme.defaultEffectsSpec/defaultSpatialSpec/fastEffectsSpec`), the
  gated `Modifier.materializeBlur()`, and `Modifier.riseIn` (70 ms
  `CashuMotion.StaggerStepMs` stride). **Nothing defined under this exemption
  may be reused inside the wallet proper.** Numbers stay quiet (the
  recovered-sats total keeps mono digits, no roll) and every onboarding
  animation is `rememberReducedMotion()`-gated to opacity-or-nothing. The
  exemption's terminal beat is the ASCII handoff (`OnboardingHandoff.kt`): a
  full-screen terrain curtain over the last onboarding screen that flips the
  app gate at full cover, then erodes: the scrim clears early so the wallet
  stands behind a terrain still substantially there, and the glyphs dissolve
  level by level (`AsciiFieldTerrain.erosionAlpha`, mirrored on iOS and pinned
  by `AsciiFieldErosionTest`) — faint plain first, ₿ peaks last. Nothing
  translates and no edge travels; the only motion is the field's own drift and
  the bloom's release swirl — onboarding-owned,
  hosted above the gate in `CashuApp` only so it survives the teardown it
  conceals, played once, never referenced by wallet code. The gate's own
  `transitionSpec` is untouched and plays unseen beneath it (plan 008 stays
  orthogonal); under Reduce Motion the curtain never mounts and the gate
  crossfade is the entire transition. The welcome ⇄ restoreMethod pair's
  screen-change cue is the ASCII backdrop's **vault morph**
  (`OnboardingAsciiBackdrop`, 2026-08-09, superseding that morning's extent
  settle): the full-window layer never moves; one 0…1 scalar on
  `motionScheme.defaultSpatialSpec` lerps every cell's brightness between
  welcome's tall terrain and restore's vault door (`AsciiFieldVault` — rings,
  spokes, ₿ bolts, ₿ monogram stencil; parity-pinned by
  `AsciiFieldVaultTest` against vectors from the design mock's Python) and
  shortens the mask's opaque ramp to end at the door's top edge; the clear
  line behind the header never moves, and the whole thing snaps under Reduce
  Motion — the iOS register is the step's own `.easeInOut(0.28)` transaction.
  Band mode survives in `AsciiFieldLayout` as math and tests only.
- **Onboarding system back (2026-08-05):** `OnboardingScreen` registers a
  `BackHandler` mirroring the on-screen back buttons exactly (seed reveal →
  welcome, method chooser → welcome, seed entry → welcome, mint staging →
  seed entry with the staged list cleared). Retreat-capable steps show an M3
  `ArrowBack` icon button (`OnboardingBackButton`) above their header; steps
  with no back affordance keep the platform default. Closes the gap where
  system back exited the app from every onboarding step.

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
- Text inputs go through `CashuTextField`. **One carve-out (2026-08-08):** the
  seed-entry card in `SeedWordEntry.kt` uses a bare `BasicTextField`, because
  `CashuTextField`'s job is to supply the container and here the *card is* the
  container — a second surface inside it would be a nested container.
- The seed-entry ghost cards use **alpha and scale, never `Modifier.blur`**.
  Skia renders blur one level differently across hosts, so a statically blurred
  element can never pass `validateDebugScreenshotTest` on Linux CI (the goldens
  are generated on macOS). Animated blur that settles to 0 is fine — previews
  are never captured mid-transition.
- **Accepted asymmetry:** iOS switches off inline predictions on the seed field
  so the keyboard's height stays constant for the whole step. Gboard's
  suggestion strip cannot be suppressed; `imePadding()` absorbs the difference
  instead.

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
