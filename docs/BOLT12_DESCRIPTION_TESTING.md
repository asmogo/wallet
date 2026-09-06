# Live BOLT12 description checks

These opt-in tests create offers with a fresh, unfunded test wallet. They do
not pay invoices, issue ecash, or verify payment settlement. Ordinary CI skips
them, so CI never depends on a public mint's availability.

Use a mint advertising NUT-04 `bolt12` support with
`options.description: true`, such as `https://mint.hedwig.sh`.

## Android

With a dedicated emulator running and the Android SDK/JDK configured:

```sh
cd android
./gradlew :app:assembleDebug :app:assembleDebugAndroidTest
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell pm clear com.cashu.me.debug
adb shell am instrument -w -r \
  -e class com.cashu.me.ui.journeys.LiveBolt12DescriptionJourneyTest \
  -e cashu.liveBolt12Descriptions true \
  -e cashu.nutshellMintUrl https://mint.hedwig.sh \
  com.cashu.me.debug.test/com.cashu.me.test.CashuUiTestRunner
```

The mint URL argument uses the shared live-wallet fixture's existing name.
The journey adds the real mint through the UI, creates a reusable offer,
edits and clears its description, reopens it, and edits a fixed 21-sat offer.
It decodes the copied offers with CDK to assert their descriptions and amounts,
and compares encoded offers to verify reuse.

## iOS

Select a dedicated iOS simulator and run from the repository root:

```sh
TEST_RUNNER_BOLT12_DESCRIPTION_MINT_URL=https://mint.hedwig.sh \
  xcodebuild -project ios/CashuWallet.xcodeproj -scheme CashuWallet \
  -destination 'platform=iOS Simulator,name=YOUR_TEST_SIMULATOR' \
  -parallel-testing-enabled NO test \
  -only-testing:CashuWalletTests/LiveBolt12DescriptionTests \
  -only-testing:CashuWalletUITests/LiveBolt12DescriptionUITests
```

The native service test decodes amountless and 21-sat offers, including edited
descriptions, Unicode, the 640-character limit, and the mint's default
description. The UI test exercises onboarding, the actual editor, clearing,
reopening, and fixed-amount preservation. Screenshots are attached to its
XCTest result.

Descriptions normalize whitespace to spaces before minting: payer decoders
render embedded control characters such as newlines as replacement glyphs.
Clearing removes the custom description; the mint can embed its own default.
Offer creation dates and payment history stay intact when an older offer is
reused. The last presented offer is remembered per mint and currency.

Offline regression tests cover normalization, persisted selection after
clearing, mint/currency isolation, and preservation of payment history.
