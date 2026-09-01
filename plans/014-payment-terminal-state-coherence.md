# 014: Synchronize visible and spoken payment-state transitions

- **Status**: DONE
- **Implementation commits**: Android `38548cf7`, iOS `e44241a9`
- **Severity**: HIGH
- **Category**: state-transition clarity and accessibility
- **Estimated scope**: 5 files, medium

## Problem

The shared payment terminal changes glyph, title, motion, and haptic feedback,
but neither platform explicitly announces the new terminal state. Android's
contactless flow also implements a second bespoke success animation while NFC
reader mode remains enabled, instead of using the canonical terminal.

```swift
// ios/CashuWallet/Views/Send/Components/AuthorizingOverlay.swift:315, current
private func handlePhase(_ newPhase: Phase) {
```

```kotlin
// android/app/src/main/java/com/cashu/me/ui/components/PaymentStatusScreen.kt:90, current
LaunchedEffect(phase) {
```

```kotlin
// android/app/src/main/java/com/cashu/me/Views/Send/ContactlessPayView.kt:258, current
AnimatedVisibility(
    visible = paymentComplete,
```

## Target

- iOS posts exactly one VoiceOver announcement when the phase changes to
  success or failure, using the current visible title and failure detail when
  useful. Initial processing does not announce over the screen title.
- Android exposes the changing title/detail as one polite live region and
  retains the existing phase haptic. Decorative glyph descriptions do not
  cause a second announcement.
- Android contactless disables reader mode after Cashu success, ignores any
  callback once complete, and renders `PaymentStatusScreen` with the canonical
  success choreography and explicit Done action.
- No new curve, duration, bounce, or animation vocabulary is introduced.

## Repo conventions to follow

- Every Android completion uses `PaymentStatusScreen`; success is the only
  state allowed a celebratory bounce/materialize beat.
- iOS uses `AccessibilityNotification.Announcement(...).post()` elsewhere for
  transient state changes.
- Keep processing states interruptible and never queue delayed visual work
  after the phase has changed.

## Steps

1. Add one status announcement to `PaymentStatusView.handlePhase` in
   `AuthorizingOverlay.swift`, gated to real phase changes.
2. Add `LiveRegionMode.Polite` to one merged Android title/detail status node
   in `PaymentStatusScreen.kt`; hide decorative glyphs from semantics.
3. Replace `ContactlessPayContent`'s bespoke success block with
   `PaymentStatusScreen(Success, ...)` and add an `onDone` callback.
4. Gate Android reader mode on `!paymentComplete`, guard the callback against
   completion, and pass the sheet close action from `CashuApp.kt`.
5. Extend Compose tests to assert the Done action and live-region semantics.

## Boundaries

- Do NOT alter NFC payload parsing, token creation, tag-writing, protocol, or
  wallet accounting.
- Do NOT add failure bounce, per-digit amount motion, or a second success
  recipe.
- Do NOT modify protected QR animation internals.

## Verification

- **Mechanical**: run Android contactless/status Compose tests, Android unit
  tests and build, iOS focused tests and simulator build, then
  `git diff --check`.
- **Feel check**: move processing to success and failure. The visible glyph,
  title, haptic, and screen-reader announcement must describe the same state
  once. On Android contactless, a successful write must stop scanning and show
  the canonical terminal; tapping Done closes the sheet. Holding another tag
  nearby after success must not start a second payment.
- **Done when**: terminal changes are announced once, contactless cannot reread
  after success, and every successful Android contactless payment has the same
  completion motion and explicit exit as other pay flows.
