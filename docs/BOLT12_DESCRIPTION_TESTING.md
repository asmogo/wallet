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


## Descriptions in paid history

History and recent activity keep their compact rows without description previews.
Opening a request or payment keeps its description in a fixed bottom section,
below the payment facts and above the action buttons. This section remains visible
while the details above it scroll. Short descriptions display in full; longer ones
show up to three lines with a native Read more view for the full selectable text.
Short windows and larger accessibility text use a one-line preview.
Saved memos take precedence; older records can recover descriptions from their encoded BOLT11,
BOLT12, or Cashu payment request. Incoming receipts missing CDK metadata also
recover the description from their persisted receive request, matched by payment
ID or by quote, mint, and currency. This is independent of payment status and
works again after restarting the app.

`HistoryDescriptionTest` (Android) and `HistoryDescriptionTests` (iOS) cover
reloading paid reusable requests, multiple receipts, outgoing invoice recovery,
Cashu request payments, blank descriptions, and mint/currency isolation.
`HistoryDescriptionJourneyTest` drives the real Android History and detail
screens with simulated settlement and a long Unicode description. It checks that
the footer is visible without scrolling, stays fixed while metadata scrolls, and
opens the complete text via Read more. Run it using
the instrumentation command above, replacing the class argument with
`com.cashu.me.ui.journeys.HistoryDescriptionJourneyTest`; no live-mint arguments
are needed. These tests never spend funds.
