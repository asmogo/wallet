# Wallet UI interaction coverage

The highest-priority checks follow actions through to their effects: balances,
transaction status, selected mint, saved preferences, and state after returning
to the app. Merely opening a screen is not a payment test.

## Priority checklist and test owners

| Priority | Interaction and expected outcome | Android journeys | iOS journeys |
| --- | --- | --- | --- |
| P0 | Create wallet, acknowledge recovery phrase, skip/add first mint, reopen wallet | MainActivity | WalletIntegration, OnboardingChassis |
| P0 | Add mint; reject malformed and duplicate URLs; select default; remove/cancel removal; handle last-mint empty state | MintSafety, MultiCurrency, FunctionalWallet | Settings, WalletLifecycle |
| P0 | Enter, delete, clear, and cancel payment amount; refuse insufficient funds | PaymentRecovery, FunctionalWallet | WalletLifecycle |
| P0 | Send ecash, show pending receipt, debit once, preserve history | FunctionalWallet, PaymentRecovery | WalletLifecycle |
| P0 | Receive ecash via routed input; inspect unknown mint; receive later and claim from history | FunctionalWallet, PaymentRecovery | WalletLifecycle (clipboard round trip) |
| P0 | Receive Lightning payment and preserve balance/history across lifecycle transitions | FunctionalWallet, PaymentRecovery | WalletLifecycle |
| P0 | Restore seed/mints/funds; cancel before replacement; delete wallet confirmation/cancellation | Security, FunctionalWallet | WalletLifecycle, Settings |
| P0 | Require successful authentication to enable lock; reject denied seed reveal; reveal again only after authentication | Security | Settings |
| P1 | Select display currency, dismiss/off, persist preference; never change underlying funds | WalletPreferences | Settings |
| P1 | Select mint currency unit; keep cents distinct from sats; reject excess decimal digits | MultiCurrency, ActivityDetail | WalletLifecycle, MainTab |
| P1 | Combine history status filter and search; inspect receipt and return | PaymentRecovery, FunctionalWallet | WalletLifecycle |
| P1 | Check pending sent ecash manually; distinguish pending from claimed without another debit | PaymentRecovery | WalletLifecycle (pending check and live round trip) |
| P1 | Edit reusable request currency/mint/description, create a new request, retain prior receipts | ActivityDetail, ReusableReceive, HistoryDescription | MainTab, Receive |
| P1 | Enable quick lock, return from key scanner, preserve amount, remove lock | Security | WalletLifecycle |
| P1 | Toggle polling/listening dependencies independently and persist settings | WalletPreferences | Settings |
| P1 | Lightning Address enable/disable and auto-claim; manually check without duplicate credit | AdvancedSettings | Settings (connection/preferences) |
| P1 | Wallet Connect no-mint explanation, enable/disable, spending limit, reset/cancel | WalletPreferences, AdvancedSettings | Settings |
| P1 | Relay add/duplicate/remove or reset; cancel identity replacement | AdvancedSettings | Settings |
| P1 | Invoice payment, on-chain receive, reusable BOLT12 payments | FunctionalWallet, PaymentRecovery, ReusableReceive | Existing service/integration tests and Receive BOLT12 UI |
| P2 | Camera permission denial/retry, back navigation, empty clipboard, large text, accessibility | MainActivity, ActivityDetail and component suites | MainTab, OnboardingChassis and component suites |

Class names in the table omit `JourneyTest` / `UITests` suffixes where appropriate.
Both suites drive production native UI. Android fixtures replace wallet and
external-service boundaries; iOS live wallet journeys execute real CDK against
local FakeWallet mints. Android activity recreation is not a cold process restart;
iOS relaunch tests terminate the app and remove all reset/seed launch flags.

## Running and maintaining the checks

The normal Android PR instrumentation suite automatically discovers the new
journey classes. See [Android testing](../android/TESTING.md) for managed-device,
local-mint, and compatibility commands. For an already running emulator:

```sh
cd android
./gradlew :app:connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.notAnnotation=com.cashu.me.test.FullOnly
```

The iOS project registers `WalletLifecycleUITests` in the shared UI test target.
The iOS workflow runs all UI tests serially and provisions both local mints. Use
the CDK multi-unit profile for the USD case:

```sh
./CI/setup-cdk.sh 3339 android
./CI/start-cdk.sh
./CI/setup-nutshell.sh
./CI/start-nutshell.sh 3338
xcodebuild test -project ios/CashuWallet.xcodeproj -scheme CashuWallet \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO -only-testing:CashuWalletUITests
```

Settings tests use fixed exchange rates and no remote NPC/NWC transport.
Authentication outcomes are injected at the operating-system boundary. iOS
transport doubles and authentication overrides are compiled only in DEBUG and
activated only in the integration runtime. Production authentication and native
screen/navigation code still execute outside that boundary.

## Explicit limits and follow-up priorities

This is not a claim of exhaustive feature or protocol coverage. Remaining UI
parity work includes iOS receive-later/error/retry scenarios, manual NPC payment
claiming and claimed-token status transitions, on-chain receipt settlement, and full
locked-token/key-management operations. Android cold-process restoration also
needs a separate process-launch fixture. Existing lower-level tests cover parts
of these behaviors; they do not substitute for the missing UI journeys.

Physical camera/NFC interaction, actual OS biometric enrollment, real iCloud
accounts, and external signer/relay interoperability require their respective
device or service environments. Deterministic mocks do not validate those
systems. Currency search is absent from the current product; history filters are
All/Pending/Completed, not incoming/outgoing.

See [the bug report](ui-coverage-report.md) for defects found and executed results.
