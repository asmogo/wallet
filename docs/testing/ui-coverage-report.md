# Wallet UI coverage and bug report

The expansion adds **51 native UI tests**: 28 Android journeys and 23 iOS tests.
The [coverage matrix](wallet-ui-coverage.md) lists priorities, test owners, and
remaining device/service boundaries. All new UI cases have passed; detailed run boundaries are recorded below.

## Confirmed application defects

### UI-001 — iOS enables App Lock without available authentication

- Severity: high; iOS.
- Reproduction: open Settings → App Lock with no device-owner authentication
  available and enable the setting.
- Expected: enablement fails and the setting stays off.
- Actual: the shared runtime unlock fallback returned success when authentication
  was unavailable, allowing the setting to be enabled without a challenge.
- Fix: a separate enablement entry point requires authentication; runtime recovery
  retains its existing behavior when device authentication becomes unavailable.
- Regression: `SettingsUITests.testUnavailableAuthenticationCannotEnableAppLock`,
  alongside rejected and successful authentication journeys on both platforms.
- Validation: the unavailable, rejected, successful-enable/relaunch, rejected seed
  reveal, and reveal/dismiss/reopen iOS journeys passed. Android rejected enablement
  and successful retry/recreation also passed. The controlled response replaces
  OS authentication only; it does not validate biometric enrollment.

### UI-002 — Android replays a consumed payment link on activity recreation

- Severity: medium; Android.
- Reproduction: launch a token link, choose Receive later, recreate the activity,
  and attempt to open the pending token from History.
- Expected: the dismissed link remains dismissed and History stays navigable.
- Actual: `MainActivity.onCreate` routed the original intent again, interrupting
  navigation. The receive-later journey reproduced the replay before the fix.
- Fix: route launch intents only on initial creation; retain `onNewIntent` for
  new links delivered to the running activity.
- Regression: `PaymentRecoveryJourneyTest.receiveLaterCanBeClaimedFromHistoryExactlyOnce`.
- Validation: failed before the fix and passed after it, including one balance
  credit and the expected final transaction status.

### UI-003 — Android hides the multi-unit removal safety explanation

- Severity: medium; Android, with an explicit mapping regression on iOS too.
- Reproduction: connect a mint with wallets in more than one currency unit, then
  confirm removal from its detail screen.
- Expected: explain that multi-unit removal is not yet safe and retain the mint.
- Actual: the generic error classifier interpreted “Keep it connected” as a
  connection failure, telling the user to retry their network instead.
- Fix: classify the typed app-owned removal error before generic transport text
  matching. Preserve the same policy explanation explicitly on iOS.
- Regression: native multi-unit refusal journeys and `WalletErrorMessagesTest` /
  `WalletErrorMessageTests` check the explanation and retained wallet state.
- Validation: reproduced in the full Android UI suite; the focused post-fix mint-safety journey and JVM regression passed.

### UI-004 — reselecting the current non-sat currency disables Send

- Severity: medium; iOS and Android.
- Reproduction: fund a USD wallet, open Send Ecash, then choose USD again from
  the unit picker and enter a valid amount.
- Expected: the balance stays available and the payment can be sent.
- Actual: unit selection cleared the cached balance, while the balance-loading
  task did not restart because its mint/unit key had not changed. Send remained
  disabled. Selecting the same unit also discarded the entered amount.
- Fix: preserve the balance and amount when the effective unit is unchanged;
  still record the explicit selection and dismiss the picker.
- Regression: both USD journeys now reselect USD after entering $2.50 and verify
  that the resulting ecash amount remains 250 cents.
- Validation: reproduced in the live iOS UI suite; both final USD journeys passed after the fix.

## Test infrastructure defects

### TEST-001 — UI fixtures could use external service transports

Currency selection still used production exchange-rate fetching. Explicit NPC
and NWC enablement could also start public transport clients despite the quiet
startup policy. The app fixtures now inject fixed USD/EUR prices and local
transport doubles. Currency, Lightning Address settings, and Wallet Connect
limit/reset journeys passed with those boundaries controlled. Android's manual
Lightning Address check also verifies one credit across repeated checks.

### TEST-002 — camera fixtures prevented native key-shortcut coverage

The Android deterministic scanner returned a replacement permission screen after
camera authorization, omitting the real scanner controls and quick actions. The
iOS simulator could not expose these actions after physical-camera startup
failed. Both integration runtimes now substitute only camera capture and keep
the production scanner overlay, key shortcuts, and route handling. Release
camera behavior remains unchanged. Hardware decoding is not claimed as tested.

### TEST-003 — iOS source guards mishandled symlinked checkout paths

The typography guards compared a compiler source path with file-enumerator paths
without resolving aliases. That could include the excluded design-system folder
and report existing type definitions as new violations. Both paths are now
canonicalized before computing the relative source path. The focused typography
suite passed after this correction; no design-system allowlist was loosened.

## Validation results

- **All 51 new UI tests passed across the final targeted runs.** This means all
  28 new Android cases and all 23 new iOS cases have successful executed results;
  it does not describe a single combined 51-case run.
- **Android JVM:** 738 discovered, 732 passed, six configured skips, zero failures.
- **Android lint:** zero errors (62 warnings and six hints).
- **Android full required UI run:** 161 discovered, 155 passed, four configured
  skips, two failures. Those failures exposed the removal-message bug and the
  fake spend-state/visibility assertion issue. After corrections, the 28-case
  expansion run passed 27 cases; the remaining payment case and the changed USD
  case were included in the final eight-case payment/currency run, which passed
  all eight. Existing payment journeys were also rerun after the fixture change.
- **iOS full UI run:** 44 discovered, 40 passed, one configured skip, three
  failures. The final targeted rerun passed all three: Wallet Connect code
  persistence/reset, seed restore, and USD send. The first two needed reliable
  native sheet/word-entry actions; USD exposed UI-004.
- **iOS unit/integration:** 659 discovered, 657 passed, two configured skips,
  zero failures in the final full-target run. The typography/error-message
  suites passed after the source-path correction.
- Local-mint iOS journeys execute real CDK for receive, send, clipboard token
  redemption, and seed restoration. Android app fixtures explicitly control
  backend results; the full suite also exercises its local-mint UI boundary.
- Full-suite failures and follow-up runs are disclosed separately. No retry is
  presented as an initially green full-suite run. Four Android optional native/
  BOLT12 cases, six JVM cases, two iOS unit cases, and one iOS optional live BOLT12 UI case were skipped
  by their existing configuration gates.

## Deliberate scope boundaries

- Currency pickers have no search feature; tests cover selection, dismissal, off,
  persistence, conversion settings, and payment-unit behavior.
- History filters are All/Pending/Completed, not incoming/outgoing.
- Multi-unit mint removal is deliberately refused by the current product safety
  policy. Tests check the refusal and retained wallet state; this is not reported
  as an accidental deletion failure.
- Android fixture recreation retains the app container; it is not a cold process
  restart. iOS persistence checks terminate/relaunch without resetting the wallet.
- Physical camera/NFC, OS biometric enrollment, cloud accounts, and external
  signer/relay interoperability need their actual environments. The coverage
  matrix explicitly separates these from application behavior exercised by mocks.
