# Payment coverage and remaining risks

This pack adds real native-wallet and simulator payment tests to the existing
Nutshell/CDK pipeline. It focuses first on loss or duplication of funds, then on
transport delivery and real UI wiring. It does **not** claim every payment feature
is end-to-end covered.

## What the review found

The existing native matrix already covers basic minting, token round trips,
insufficient ecash, duplicate redemption, counter restoration, reusable BOLT12
offer issuance deltas, and on-chain quotes/payments. Android also has dedicated BOLT12 restart and foreign-NFC recovery
regressions. Most Android UI journeys use `FakeWalletGateway`; the iOS live smoke
suite primarily covers onboarding and adding a mint. Those are useful tests, but
they cannot establish payment conservation across a lost HTTP response, a durable
saga, and a second independent wallet.

The previous Swift quote-transition test paid/minted a *different* quote through
`mintSats`. It now checks and issues the original quote, then verifies that a second
unissued-quote sweep credits nothing. Sat keyset checks now allow a mint to advertise
other units, so both platforms can use the sat+USD CDK fixture profile.

## Added required coverage

`coverage.json` lists individual executable tests, not feature labels. Both
platforms require 14 cases on PRs (12 native + 2 UI) and 19 on full/nightly runs.
`check_coverage.py` reads JUnit XML or Xcode test-result trees and fails for any
missing, skipped, or unsuccessful required case. The existing suites still run.

| Boundary | Assertions | Tier |
|---|---|---|
| Unpaid invoice | Zero balance until explicit payment; reject early issuance; issue once | PR |
| Internal Nutshell and external CDK BOLT11 | Paid state, amount + actual fee + change conservation, one outgoing receipt; internal recipient redeems | PR |
| Lost melt response after mint commit | Recovery, durable reopen, paid quote, one receipt, no second debit | PR |
| Lost mint response after issuance | Recover the same paid quote after reopen; one receipt and no second credit | PR |
| Failed Lightning backend | Balance restored and all funds spendable by another wallet | PR |
| Insufficient funds / unavailable quote endpoint | Rejection without debit; remaining proofs spendable | PR |
| Paid but unissued invoice | Reopen SQLite, sweep once, second sweep zero | PR |
| Ecash claim after sender reopen | Pending operation persists; claimed token cannot be revoked or redeemed twice | PR |
| Ecash revoke | Original token becomes unspendable; recovered funds transfer successfully | PR |
| Nonzero input fees | Send-max at 1000 ppk, real redemption fee and net balances | PR |
| P2PK on both mint implementations | Wrong key cannot credit; correct key subsequently succeeds | PR |
| Concurrent redemption | Two separate receivers race; exactly one succeeds and total credit equals token value | PR |
| Real native UI on both mints | Receive 100, pay 21, history survives relaunch (iOS) / activity recreation (Android) | PR |
| Cashu Request HTTP | Fixed and amountless request, matching request ID, actual recipient redemption, exact sender debit on the zero-fee mint | Full |
| Cashu Request delivery failure | Failed HTTP delivery leaves a reclaimable operation; revoke restores balance | Full |
| Proof reservation release | Swift competing preparation/cancel; Android repeated real fee-preview/cancel; full balance remains spendable | Full |
| Currency isolation | Sat and USD share one repository/database per wallet owner; USD payments preserve both sender and recipient sat balances | Full |
| NWC over local signed Nostr relay | Balance, payment limit, duplicated request event, one payment and conserved funds | Full |

Repository reopen tests use the same mnemonic and SQLite file; they are not
OS-process-death tests. iOS UI explicitly terminates and relaunches the app.
Android UI recreation retains its application container, so it proves activity
restoration only. FakeWallet settlement is not evidence of routing on a real
Lightning network or confirmation by a Bitcoin node.

## Fixture design

Start the ordinary mints first, then `CI/start-payment-fixtures.sh`. All listeners
bind to loopback; Android reaches the host using its emulator alias.

- `3341`: per-test proxy, invoice/request generator, HTTP receiver, Nostr relay.
- `3342`: real Nutshell ledger with manually paid FakeWallet invoices, zero input fee.
- `3343`: the same controlled mint at 1000 input-fee ppk.

Every scenario gets a distinct URL namespace, fault list, delivery store and relay
subscriptions. Wallet seeds and databases are separate. The proxy never fabricates
proofs or balances. A reject fault does not forward the request; a lost-response
fault waits for the actual upstream response and then truncates the response body.
Tests verify that the latter was forwarded. Request records omit proof bodies.

The relay validates canonical event IDs and Schnorr signatures, filters and replays
subscriptions, and carries actual NIP-47 encrypted requests/responses. It is a small
local test relay, not a general-purpose Nostr implementation. Fixture behavior and
the coverage gate have their own Python tests.

The proxy currently forwards mint HTTP endpoints, not NUT-17 mint WebSockets;
SDK subscriptions therefore fall back to HTTP polling. These tests do not cover
mint push delivery, reconnect, or missed-update recovery.

The UI live-payment mode enables real payment maintenance while preserving test
animation settings and disabling unrelated external services. iOS relay traffic is
redirected to the local session relay. Android's native NWC test uses the relay
directly; its UI fixture leaves external listeners disabled.

## Run locally

From the repository root, with the platform toolchains installed:

```sh
./CI/setup-nutshell.sh
./CI/setup-cdk.sh 3339 android
./CI/start-nutshell.sh
./CI/start-cdk.sh
./CI/start-payment-fixtures.sh
CI/.nutshell-venv/bin/python -m unittest discover -s CI/payment-tests -v

PAYMENT_FIXTURE_URL=http://127.0.0.1:3341 PAYMENT_TEST_TIER=full \
  swift test --package-path CI/IntegrationTests \
  --filter 'Payment(Safety|Extended)IntegrationTests'
```

For Xcode, use the scheme's regular build/test commands with
`TEST_RUNNER_PAYMENT_FIXTURE_URL=http://127.0.0.1:3341` and
`TEST_RUNNER_PAYMENT_TEST_TIER=full`. The `TEST_RUNNER_` prefix passes variables into
the simulator test runner. Select `PaymentSafetyIntegrationTests`,
`PaymentExtendedIntegrationTests`, `LiveCdkPaymentUITests` and
`LiveNutshellPaymentUITests` for only this pack.

For a running Android emulator:

```sh
cd android
./gradlew :app:connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class=com.cashu.me.liveintegration.PaymentSafetyLocalMintTest,com.cashu.me.liveintegration.PaymentExtendedLocalMintTest,com.cashu.me.ui.journeys.LivePaymentJourneyTest \
  -Pandroid.testInstrumentationRunnerArguments.cashu.paymentFixtures=true \
  -Pandroid.testInstrumentationRunnerArguments.cashu.paymentFixtureUrl=http://10.0.2.2:3341
cd ..
python3 CI/payment-tests/check_coverage.py --platform android --tier full \
  android/app/build/outputs/androidTest-results/connected
```

Stop with `CI/stop-payment-fixtures.sh`, `CI/stop-nutshell.sh`, and
`CI/stop-cdk.sh`. Fixture state lives under ignored `CI/.payment-workdir/`.
The scripts manage only their recorded processes. Never expose these unauthenticated
fake-payment services to a public interface.

## Known regressions and next tests

1. **Cashu Request receiver fees — highest priority.** With CDK 0.18, a funded
   100-sat wallet paying a 21-sat request at 1000 ppk produces a token redeeming for
   19 sats. It has been observed with fixed and amountless requests; proof selection can
   affect the exact shortfall. The test retains the
   intended `received == 21` assertion; it is excluded from the required manifest
   and skipped unless explicitly enabled. Reproduce with
   `PAYMENT_KNOWN_REGRESSIONS=1 PAYMENT_TEST_TIER=full` in Swift, or
   `-Pandroid.testInstrumentationRunnerArguments.cashu.paymentKnownRegressions=true`
   on Android, selecting the `ReceiverFeeRegression` case. Fix the SDK fee/proof
   selection and make this case required when the binding is upgraded. A green CI
   run currently does **not** mean fee-bearing request underpayment is fixed.
2. **Actual process death while pending.** Add two-phase drivers that stop the app
   after proof reservation, mint acceptance, or HTTP delivery and restart it while
   preserving all stores. Include pending-to-paid, pending-to-failed, prolonged
   unknown state, repeated recovery, and history/notification deduplication.
3. **Requests beyond HTTP.** Nostr gift-wrap delivery, listener reconnect/replay,
   expired/invalid requests, P2PK request locks, multi-mint top-up, underpayment,
   overpayment, repeated and partial payment. NWC needs unauthorized clients,
   revoke/restore, concurrent distinct payments, and limit persistence tests.
4. **Address resolution and remote services.** LNURL callbacks and amount/comment
   bounds, bad callback invoices, BIP353/DNSSEC resolution, and NPC quote recovery
   need controlled resolver/service endpoints and native coordinator tests.
5. **Broader payment-method state transitions.** Extend the existing BOLT12 and
   on-chain matrix with BOLT12 invoice-request failures, invalid amounts,
   duplicate/late settlement, expiry, restart between successive offer credits,
   on-chain fee-option changes and restart during pending settlement.
6. **Device entry points.** Deep links, clipboard, QR/camera, and NFC cancellation,
   disconnect/retry and replay need UI/device tests layered on the native payment
   invariants. Physical NFC and camera behavior need real-device validation.

Nutshell 0.20.1 has a fixture timing limitation: it can return async `PENDING`
before its background task persists the new state, and stock FakeWallet reports
external payments settled even before they execute. The fast internal-payment
scenario and the iOS external-payment UI journey delay their first status GET by
one second through the session proxy. This pacing does not establish correctness of
the mint's immediate-status race. The standalone Swift package can also emit
nonfatal native Tokio runtime-drop warnings from CDK 0.18 during teardown.
