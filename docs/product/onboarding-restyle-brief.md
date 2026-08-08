# Onboarding restyle — implementation brief

Restyle the onboarding flow in **both** the iOS and Android apps around a single layout
grammar: a **fixed bottom action chassis** and a **live stage above it**. Keep every existing
screen, branch, action, and guarantee. This is a presentation-layer redesign, not a flow
redesign.

## 0. Before you start

Install the motion skills (verified absent on this machine):

```bash
npx skills add emilkowalski/skill
```

Use them in this order:

- `emil-design-eng` — read **before** writing any motion code. Its restraint bias (sub-300 ms
  for anything on the critical path, transforms over layout, no `scale(0)` origins, transitions
  over keyframes) is the house style you are matching.
- `review-animations` — run against your own diff before you claim done.
- `improve-animations` — run on whatever `review-animations` flags.

Also read, in this order:

1. `AGENTS.md` — native components only, both platforms, no silent parity gaps.
2. `docs/product/PRODUCT.md` — principles and the anti-reference list.
3. `docs/product/DESIGN.md` — §2 color, §3 typography, §5 components, §6 motion.
4. `docs/android/DESIGN-ANDROID.md` — the Android charter. Android is **not** a port of iOS.
5. `~/.agents/skills/design-motion-principles/` (already installed) — three-designer audit
   rubric. It is React-oriented; take the principles, ignore the `.tsx` grep mechanics.
6. Repo skills: `.agents/skills/swiftui-expert-skill`, `.agents/skills/mobile-android-design`.

Do not start writing code until you have read the eight iOS steps in
`ios/CashuWallet/Views/Main/OnboardingView.swift` and their Android counterparts.

## 1. The reference

`~/Downloads/woKZ91yCWSftrTzl.mp4` — an 11.4 s concept reel for a fictional walking app.

**Ignore its content entirely.** It is a gamified fitness app with emoji, memoji, coins,
confetti, gradients and illustrated maps. Every one of those is on our anti-reference list.
The camera dolly/zoom in the video is video production, not app UI.

**Take only its structure and its timing.** Specifically:

| What the reference does | Take it? |
| --- | --- |
| Bottom block (indicator → headline → subhead → primary CTA → text link) is pinned and **never moves** between slides | **Yes — this is the whole point** |
| Top ~55–60 % is a per-slide "stage" that self-plays | **Yes** |
| Stage swaps via blur + scale crossfade; nothing slides laterally | **Yes** — matches our existing "no horizontal push" decision |
| Secondary elements cascade in after the primary element lands, ~70 ms apart | **Yes** |
| Headline reveals per-character, centre-out, each glyph blur→sharp | **Optional, gated** — see §5 |
| Numbers count up with a decelerating ease | **No** — violates *Numbers Are Sacred*. See §5 |
| Looping specular sweep across the primary CTA | **No** — we have no gradients and no ambient motion |
| Active page dot is an elongated pill | **Maybe** — see the open question in §3 |
| Blue gradient CTA, drop shadows, emoji, illustration | **No** |

The one-sentence version: *make every onboarding step feel like the reference's chassis, using
our ink-on-white palette and our existing motion primitives.*

## 2. What must not change

### Sitemap — preserve exactly

```
welcome ──► showMnemonic ──► firstMint ──► done
   │
   ├──► restoreMethod ──► iCloudRestore (preview → restoring → success) ──► done   [iOS only]
   │
   └──► restoreMethod ──► restoreInput ──► restoreMints ──► restoreProgress ──► done
```

Plus the `What is ecash?` concept sheet, opened from `welcome`'s bar-band `?`
button (it was a chassis text link until 2026-08-05 — see The Bar-Band Rule in
DESIGN.md §5).

Every CTA, secondary action, tertiary text link, back affordance, disabled-until-valid rule,
skip path, retry affordance, and error surface stays. Notably:

- `showMnemonic` primary stays disabled until the acknowledge checkbox is checked.
- `firstMint` primary stays disabled with no selection and empty custom input; `Skip for now`
  stays.
- `restoreInput` primary stays disabled below 12 valid words. *(2026-08-08: the code
  now actually enforces this. Both hosts previously gated on word **count** alone while
  only Settings checked validity; word-by-word entry makes per-word validity structural —
  a non-word cannot be committed — and the BIP-39 checksum gates the CTA on top of it.)*
- `restoreProgress` stays forward-only, primary disabled until every mint settles.
- `restoreInput`'s Back still returns to `welcome`, not `restoreMethod`.
- The `.onAppear` jump straight to `iCloudRestore` when `hasIncompleteICloudRestore` stays.

If you believe a step should be merged, reordered, or removed, **stop and ask**. Do not do it
as part of the restyle.

### Test contracts — these are load-bearing

iOS accessibility identifiers, all in `OnboardingView.swift`, driven by
`ios/CashuWalletUITests/UITestBase.swift`:

`onboarding-create-wallet`, `onboarding-ack-seed`, `onboarding-saved-seed`,
`onboarding-add-custom-mint`, `onboarding-continue`, `onboarding-skip-mint`,
`onboarding-custom-mint-field`, `onboarding-commit-custom-mint`

Android tags in `android/app/src/main/java/com/cashu/me/ui/testing/UiTestTags.kt:12–23`:
`cashu.onboarding`, `.create`, `.startup.retry`, `.seed.reveal`, `.seed.phrase`,
`.seed.hidden`, `.seed.acknowledge`, `.seed.saved`, `.mint.custom`, `.mint.url`,
`.mint.continue`, `.mint.skip`

Every one must survive on the same logical control. Moving an identifier to a different widget
is a break.

`SeedPhraseAccessibilityComposeTest` asserts the hidden seed phrase exposes **exactly one**
click action and one "Reveal seed phrase" content description. Any new control you add to the
masked seed stage breaks it — if that is deliberate, update the test in the same commit and say
why.

*Updated 2026-08-05:* the card is now a **toggle**, so the *revealed* state also carries exactly
one click action ("Hide seed phrase") where it previously carried none. The masked-state contract
above is unchanged. The revealed-state click action must stay **outside** `clearAndSetSemantics`
— masking that subtree would hide the 12 ordered words from TalkBack, defeating the point of
revealing them.

### Design system — non-negotiable

- **iOS: no custom `Color` extension.** Semantic colors only (`.primary`, `.secondary`,
  `.tertiary`, `Color(.systemBackground)`, `.thinMaterial`, `.quaternary`). AccentColor is
  inverted ink: `#000000` light / `#FFFFFF` dark.
- **Android: the zero-chroma ink scheme in `ui/theme/Color.kt`.** No Material You dynamic
  color (locked decision).
- **Zero shadows.** The Flat-By-Default Rule is absolute.
- **SF (iOS) / Roboto (Android) only.** No display face, no `Font.system(size:)` for body text.
- **Capsule for full-width buttons**, `cornerRadius: 12` for chips/notices, `14` for text
  containers. No other radii.
- **Liquid Glass only behind `if #available(iOS 26.0, *)`** with the `.quaternary` /
  `.thinMaterial` fallback. Deployment target is iOS 18.0 — never ship a glass surface that
  breaks on 18.
- **Android `minSdk = 26`**, so `Modifier.blur` / `RenderEffect` is API 31+. The seed screen
  already ships a `"••••••"` placeholder fallback for exactly this reason. Any new blur needs
  the same treatment.
- Reuse the existing button vocabulary — iOS `.glassButton()` /
  `FullWidthCapsuleButtonStyle` and `.textLinkButton()` in
  `ios/CashuWallet/Views/Components/LiquidGlassModifiers.swift:410,457`; Android
  `PrimaryButton` / `SecondaryButton` / `GhostButton` in `ui/components/Buttons.kt`. Do not
  invent a new button.

## 3. The architecture

Two of the eight steps already do this — `restoreMints` and `restoreProgress` use
`.safeAreaInset(edge: .bottom)` with a pinned footer over a scrolling body. **The redesign
generalizes that to all eight.** Read those two first; they are the working prototype.

Today the other six use `Spacer` → header → `Spacer` → inline CTA stack, so the CTAs sit at
different heights per screen and jump between steps. That jump is the thing to kill.

### Target frame — identical on every step

```
┌─────────────────────────────┐
│  STAGE                      │  flexible height, owns all vertical slack
│  animation OR functional    │  scrolls internally when its content overflows
│  content                    │
├─────────────────────────────┤
│  [progress indicator?]      │  ← open question, see below
│  Headline                   │  CHASSIS — pinned, fixed baseline
│  Subheadline                │  every step, every branch
│  ▸ Primary CTA              │  identical Y position across all 8 steps
│  ▸ Secondary CTA (optional) │
│  ▸ Tertiary text link (opt) │
└─────────────────────────────┘
```

Rules:

- The chassis is pinned — `.safeAreaInset(edge: .bottom)` on iOS, a bottom slot in the host
  `Column` on Android — and rides above the keyboard (`imePadding()` is already on the Android
  host).
- **The primary CTA's Y position is constant across all eight steps.** This is the single
  measurable success criterion. Screenshot every step and diff the button's frame; drift is a
  bug. Steps with fewer buttons keep the primary at the same baseline and let the stage take
  the slack — do not centre the stack.
- The chassis **never animates on step change**. Only its text content and button labels
  cross-fade in place. The container itself is motionless. This is what produces the "always
  the same place" feeling from the reference.
- The stage owns all layout change. When it scrolls, it scrolls under a fixed chassis.

### Stage payload per step

| Step | Stage holds |
| --- | --- |
| `welcome` | Its title + subhead at the top, like every other step, over open space. (Originally an abstract ink motion piece — see the note in §4.) |
| `showMnemonic` | The 12-word grid inside the seed card, then the `Copy` link. **No entrance animation on the grid** — this is deliberate and documented; it flickers. The "never share these words" caution is **not** in the stage: it rides the chassis accessory directly above the acknowledge row (2026-08-05), so it argues for the checkbox it sits over and can never push the CTA. The card itself is The Seed Card Exception (DESIGN.md §5) — it is the tap-to-reveal affordance, not decoration. |
| `firstMint` | The mint list + custom-URL field (functional, scrolls, keyboard). |
| `restoreMethod` | Header over open space (the quiet variant of the welcome piece went with it — see §4). Two buttons in the chassis. |
| `restoreInput` | *(rewritten 2026-08-08)* Word-by-word entry: a 12-tick progress rail, one card holding the current word behind up to two empty ghost cards, up to three BIP-39 completions, and a helper/notice line. Functional, and the **only step that focuses on arrival** — see DESIGN.md §6. Paste moved to a chassis tertiary link that retires once anything is entered. A checksum failure (which names no single word) swaps the card for a review grid of all twelve, each tappable back into the field. |
| `restoreMints` | The URL field, Add/Paste/Find-my-mints chips, staged rows (functional, keyboard). The only step besides `welcome` to use the bar band's trailing help slot, and the only one to fill both slots at once: the backup lookup is the way through for most people and nothing else on screen says what it does. The scroll fades at its bottom edge (`scrollEdgeFade`) so rows dissolve into the CTA rather than cutting against it. |
| `restoreProgress` | The live per-mint progress list — already a self-playing stage. |
| `iCloudRestore` | State-driven: symbol → spinner → success glyph + balance. Already the closest thing to the reference. |

Preserve the deliberate anti-patterns that are documented in code comments: the seed grid gets
no entrance animation, `stagger` animates no opacity (avoids double-fade against the
crossfade), and the seed uses `.redacted` **plus** blur, not blur alone (an animatable blur
ramps through a legible frame).

### Open question — the indicator slot

The reference uses page dots. Our flow branches: create is 3 steps, seed restore is 5, iCloud
restore is 3. Dots would imply a linear path that does not exist.

**Propose two or three options with a recommendation before building this.** Constraints: it
must not imply a false linear path; it must not add chrome that fights the flat aesthetic; if
it animates on branch selection, that animation must be honest about the new length. "No
indicator at all" is a legitimate answer — the stage can carry sense of place instead.

## 4. The `welcome` stage

> **Superseded 2026-08-05 (user-directed).** The piece this section asked for shipped as a
> note ↔ token morph and was then cut: an idle loop that earned nothing after the first
> launch. `welcome` now carries the same top title + subhead as every other step
> (`OnboardingStepHeader` at `OnboardingMetrics.titleTopInset` / `TitleTopInset`) over open
> space — consistency beat novelty. The rest of this section is kept for the record.

This is the only genuinely new visual element and the highest-risk part. It replaces empty
`Spacer` space with something that moves.

**Hard boundaries:** ink and system-semantic colors only. No gradient. No illustration. No
mascot. No emoji. No shadow. No brand mark that is not already in the app. It must read as
restrained after the tenth launch, not just the first.

**Available raw material in the app already:** `ActivityOrbView.swift` (with its documented
`.linear(2).repeatForever()` pulse), the monospaced-numeral treatment, the `MintAvatarView`
geometry, the capsule/pill language, `CanvasDivider` at 0.5 pt.

**Deliverable for this piece specifically:** propose 2–3 directions in prose plus a still frame
each before implementing. Do not pick one unilaterally. Directions worth considering — a
single slow-breathing ink form; type that composes itself; a minimal geometric construction of
"a note becoming cash". Whatever you pick must be *cheap* — this runs on first launch on cold
hardware and must not stutter.

Reduce Motion must yield a static, composed frame that still looks intentional — not an empty
box.

## 5. Motion

### Scoped exemption

Onboarding is **exempt** from the seven-named-animation budget in `DESIGN.md` §6. Record the
exemption explicitly in both `docs/product/DESIGN.md` §6 and
`docs/android/DESIGN-ANDROID.md`, scoped to pre-wallet onboarding surfaces only, with a
sentence stating that nothing here may be reused inside the wallet proper.

Two rules survive the exemption and are **not** negotiable:

- **Numbers Are Sacred.** No count-up, no odometer, no roll on any real value — the restored
  balance and the recovered-sats total keep `.monospacedDigit()` +
  `.contentTransition(.numericText())`. The reference's counting animation is exactly what this
  rule forbids.
- **Reduce Motion.** Every new animation honors `@Environment(\.accessibilityReduceMotion)`
  (iOS) and `rememberReducedMotion()` (Android), which already exist and are already used at
  every motion site in this flow. Reduced-motion paths are opacity-or-nothing.

### Shared spec — one table, both platforms implement natively

Commit this table into the follow-up PR as the single source of truth. Android expresses it
with `spring(...)` / motion-scheme tokens per its charter rather than copying the tween values;
the **intent** (duration feel, ordering, stagger stride) is what must match.

| Element | Out | In |
| --- | --- | --- |
| Stage swap | blur 0→6, opacity 1→0, ~180 ms ease-out | scale 0.96→1, blur 6→0, opacity 0→1, ~280 ms `.smooth`; overlap the tail of *out* by ~80 ms |
| Headline / subhead | opacity 1→0, ~140 ms | y +10→0, blur 3→0, ~260 ms `.smooth` |
| Element cascade inside a stage | — | 70 ms stride, reusing the existing `stagger` helper |
| Chassis container | never animates | never animates |
| CTA label change | `.contentTransition` in place | in place |
| Press feedback | existing 0.97 scale, `.snappy(0.09)` down / `.snappy(0.18)` up | — |

Exits stay subtler than entrances — that carve-out is already in `DESIGN.md` from the previous
motion audit. Keep it.

**Reuse, do not reinvent.** These already exist and already handle Reduce Motion:

- iOS: `stagger(appeared:index:)` at `OnboardingView.swift:183` — offset 12, blur 3, no
  opacity, `.smooth(0.4).delay(index * 0.07)`. `PressableButtonStyle`,
  `AnyTransition.materializeBlur`, `.contentTransition(.symbolEffect(.replace))`,
  `.contentTransition(.numericText(value:))`.
- Android: `Modifier.riseIn(appeared:index:)`, `rememberPressScale`, `rememberPressAlpha`,
  `IconSwap`, `rememberBounceScale`, `Modifier.materializeBlur()`, `CashuMotion.StaggerStepMs`
  (already 70).

Note the existing stride values already agree across platforms (70 ms / 0.07 s). Keep them
aligned.

### The per-character headline reveal

The reference reveals its headline glyph by glyph, centre-out, each glyph blur→sharp. It looks
excellent and it is genuinely expensive: splitting a `Text` into per-character views breaks
VoiceOver into fragments, fights Dynamic Type line breaking, and multiplies view count on the
first frame of a cold launch.

**Default position: do not do it.** Use the existing whole-line blur-rise instead.

If you want to argue for it, the bar is: the full headline remains a single accessibility
element with the complete string; it survives Dynamic Type AX5 and the three hardcoded `\n`
line breaks in the current headlines; it is disabled entirely under Reduce Motion; and it does
not regress cold-launch time to first frame. Show the measurement, then ask.

## 6. Platform parity

Build both in parallel from the shared spec table. `AGENTS.md` requires equal quality,
behavior, accessibility, tests, and docs on both.

Per `docs/android/DESIGN-ANDROID.md`, Android is **not** a port. Same structure, same timing
intent, Material 3 Expressive execution — `MotionScheme.expressive()` springs rather than
hand-tuned tweens, the expressive `LoadingIndicator` rather than a classic spinner.

Known asymmetries to preserve rather than "fix":

- iCloud restore is iOS-only. Android's `RestoreMethodStep` therefore presents a chooser with
  one real option. If the redesign makes that screen feel empty, propose a fix and ask — do not
  silently drop the step.
- Android registers **no `BackHandler`** for onboarding, so system back exits the app and does
  not retreat a step. This is a real gap. Fixing it is in scope if you want it; flag it either
  way.

## 7. Also fix while you are here

- `docs/android/UX_SPEC.md` §2 is stale. It describes a "Verify mnemonic" 3-word quiz step, a
  letter-spaced `CASHU` caption on Welcome, a 2-column seed grid, and "I have a seed phrase" as
  the secondary CTA. None of those exist in shipped code. Rewrite §2 to match what you ship.
- `docs/product/DESIGN.md` cites `OnboardingView.swift` line numbers that are already stale and
  will be more so. Update them.

## 8. Verification — all of it, before you claim done

1. **iOS UI tests** — `testOnboardingCreateWalletAndSkipMint` and `testOnboardingAddNutshellMint`
   in `ios/CashuWalletUITests/WalletIntegrationTests.swift`, green.
2. **Android instrumented tests** — `SeedPhraseAccessibilityComposeTest`,
   `WalletStartupFailureComposeTest`, `FunctionalWalletJourneyTest`, green.
3. **Compose screenshot references** — `:app:validateDebugScreenshotTest` runs in
   `.github/workflows/android-ui-tests.yml`. Regenerate the 11 existing references if they
   shift, **and add new onboarding baselines** — there are currently zero, so this redesign
   would otherwise land with no pixel regression coverage.
4. **CTA position diff** — screenshot all eight steps on both platforms and confirm the primary
   button's frame is identical across every one. This is the success criterion for the whole
   brief.
5. **Reduce Motion pass** — walk the entire flow with Reduce Motion on (iOS Settings →
   Accessibility → Motion; Android animator duration scale 0) on both platforms. Nothing may
   be missing, stuck, or invisible.
6. **Dynamic Type / font scale** — xSmall through AX5 on iOS, largest font scale on Android,
   on every step. No truncation of a money value.
7. **Light and dark** on both.
8. **Motion audit** — run `review-animations`, then `improve-animations` on what it flags.
9. **Visual evidence** — this is a UI PR, so `.agents/skills/wallet-ui-visual-review` applies.
   Committed target only, isolated before/after worktrees, matched capture matrix on both
   platforms under identical fixture/appearance/locale/text-scale, filled
   `capture-manifest.json`, and `validate_capture_manifest.py` passing. Synthetic wallet data
   only — never a real seed, key, token, or balance. Do not publish to GitHub without explicit
   authorization.
10. **Cold-launch check** — `welcome` is the first frame of a first launch. Confirm the stage
    animation does not delay or stutter it.

## 9. How to work

Land it in reviewable stages, not one commit:

1. Extract the chassis + stage frame; move all eight steps onto it with **zero** new motion.
   Prove the CTA position is constant and all tests still pass.
2. Apply the shared motion spec to step transitions.
3. Build the `welcome` stage (after proposing directions and getting a pick).
4. Resolve the indicator question (after proposing options and getting a pick).
5. Docs, screenshot baselines, visual review.

Stop and ask at the three decision points marked above: the indicator, the `welcome` stage
direction, and the per-character headline reveal if you want to argue for it.
