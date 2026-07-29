# Android Testing

The Android test stack drives the production `MainActivity` and production
Compose navigation. It combines deterministic in-process wallet fixtures for
user journeys with a narrow real-CDK boundary against local test mints. Tests
must never contact public mints, relays, telemetry, or real financial
infrastructure.

## Test layers

- `src/test`: JVM unit and integration tests.
- `src/androidTest`: component, accessibility, navigation, and production-app
  emulator journeys.
- `src/screenshotTest`: ten deterministic Compose Preview screenshot baselines.
- `macrobenchmark`: release-validation performance coverage; it is separate
  from behavioral correctness.

The required journey suite mirrors the iOS smoke flows and adds mint lifecycle,
send/receive ecash, Lightning receive and invoice-payment transitions, history,
settings persistence, deep links, validation, failure, retry, camera-permission
UX, and destructive-action confirmation.
`LiveLocalMintMainActivityJourneyTest` adds a real-CDK UI boundary against
Nutshell. Tests annotated `FullOnly` run only in nightly and release tiers;
tests annotated `Compatibility` form the small cross-device behavior pack.

## Deterministic app runtime

`CashuUiTestRunner` launches the debug-only `UiTestApplication`. The application
does not create an app container until `AppTestFixture` installs one, so no
activity or production service can race fixture setup.

`UiRuntimePolicy.DeterministicTest` disables telemetry, public relay listeners,
startup maintenance, NWC startup, foreground quote polling, and automatic
clipboard reads. Explicit UI actions still call either `FakeWalletGateway` or
the real CDK gateway connected to a local mint. Cleartext HTTP is accepted only
in this policy and only for emulator/host loopback addresses; production still
requires HTTPS. The same policy drives the production scanner UI through a
deterministic denied/allow/ready permission contract while replacing only the
OS grant dialog and physical camera preview.

Available fixture modes are:

- `EmptyWallet`
- `SeededWithoutMint`
- `SeededWithMint`
- `FundedWithHistory`
- `LiveSeededWithoutMint`
- `LiveLocalMint`

The fake has fixed test-only seed, token, invoice, balance, quote, and
transaction data. Tests explicitly advance quote states such as invoice-paid;
there are no timer-based transitions. Android Test Orchestrator clears package
data and creates a fresh instrumentation process for every test.

## Local commands

Use JDK 17 or newer and an installed Android SDK. Commands below start in the
repository root unless the snippet changes directory.

Compile the app and instrumentation suite:

```sh
cd android
./gradlew --no-daemon \
  :app:compileDebugKotlin \
  :app:compileDebugAndroidTestKotlin
```

Run JVM checks:

```sh
cd android
./gradlew --no-daemon :app:testDebugUnitTest :app:lintDebug
```

Run the required PR emulator suite. The local Nutshell URL is the Android
emulator's host-loopback address:

```sh
./CI/setup-nutshell.sh
./CI/start-nutshell.sh 3338
cd android
./gradlew --no-daemon :app:pixel2Api35DebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.notAnnotation=com.cashu.me.test.FullOnly \
  -Pandroid.testInstrumentationRunnerArguments.cashu.liveUiLocalMintEnabled=true \
  -Pandroid.testInstrumentationRunnerArguments.cashu.nutshellMintUrl=http://10.0.2.2:3338
cd ..
./CI/stop-nutshell.sh
```

Run one deterministic journey class without a mint:

```sh
cd android
./gradlew --no-daemon :app:pixel2Api35DebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class=com.cashu.me.ui.journeys.MainActivityJourneyTest
```

Run the full local-mint tier:

```sh
./CI/setup-nutshell.sh
./CI/setup-cdk.sh 3339 android
./CI/start-nutshell.sh 3338
./CI/start-cdk.sh
cd android
./gradlew --no-daemon :app:modernApi36DebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.cashu.liveUiLocalMintEnabled=true \
  -Pandroid.testInstrumentationRunnerArguments.cashu.nativeWalletLocalMintIntegration=true \
  -Pandroid.testInstrumentationRunnerArguments.cashu.nutshellMintUrl=http://10.0.2.2:3338 \
  -Pandroid.testInstrumentationRunnerArguments.cashu.cdkMintUrl=http://10.0.2.2:3339
cd ..
./CI/stop-nutshell.sh
./CI/stop-cdk.sh
```

Run either compatibility device:

```sh
cd android
./gradlew --no-daemon :app:compactApi26DebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.annotation=com.cashu.me.test.Compatibility
./gradlew --no-daemon :app:tabletApi35DebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.annotation=com.cashu.me.test.Compatibility
```

## Screenshot baselines

Pixel comparison is limited to the deterministic host-side preview suite.
Full-app emulator screenshots are failure diagnostics, not golden images.

Validate committed references:

```sh
cd android
./gradlew --no-daemon :app:validateDebugScreenshotTest
```

Update references only after visually reviewing the intended UI change:

```sh
cd android
./gradlew --no-daemon :app:updateDebugScreenshotTest
```

References live in `app/src/screenshotTestDebug/reference`. CI validates them
but never updates or commits them.

## Authoring rules

- Launch production screens through `AppTestFixture`; do not substitute fake
  screen implementations.
- Prefer visible text and accessibility semantics. Use `UiTestTags` only for
  screen roots or controls whose semantics are otherwise ambiguous.
- Use `WalletJourneyRobot` condition waits. Never use fixed sleeps.
- Keep tests independent, English-locale, portrait-first, and deterministic.
- Use only fixed test data. Never paste a developer or user seed, token,
  invoice, URL, screenshot, or log into a fixture.
- Exercise deterministic camera, NFC, and biometric permission/unavailable
  contracts on the emulator; reserve Permission Controller integration and
  physical hardware behavior for release-device validation.
- Run automated accessibility checks on critical screens and preserve
  meaningful content descriptions and 48dp interaction targets.

On failure, `UiFailureArtifactsRule` stores a screenshot plus merged and
unmerged Compose semantics trees through AndroidX Test Storage. Managed-device
results also retain JUnit, HTML, logcat, and additional device output. CI
uploads these artifacts together with sanitized local-mint logs.

## CI tiers

`.github/workflows/android-ui-tests.yml` is reusable by release automation and
also runs directly:

- PR/push: Pixel 2, API 35 AOSP; required journeys excluding `FullOnly`, plus
  screenshot validation.
- Nightly at 03:00 UTC and release: full API 36 suite with local Nutshell and
  CDK mints.
- Nightly/release compatibility: API 26 compact phone and API 35 tablet ATD,
  filtered to `Compatibility`.

The release APK job depends on the reusable full UI workflow, so a failed
critical UI journey prevents Android artifact publication.
