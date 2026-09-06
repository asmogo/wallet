# Wallet UI parity review

Open [the screenshot comparison](index.html) for the complete visual evidence.

The baseline is commit `7d5ab9b5`; after captures show the local changes in this review. Screens were rendered on an iPhone 17 Pro simulator (iOS 26.5) and Pixel 8 emulator (API 36), in English and portrait orientation. Request fixtures use dummy encoded payloads and test-only payments. No live payment was required.

## Changes

- iOS Cashu requests and saved reusable invoices show **Total received**, formatted in the request currency, after Created. Legacy zero-amount payment records do not invent a received total.
- Request status icon and readable green ink agree across platforms; waiting text uses primary ink with an orange clock.
- Android request and receipt secondary actions use compact native buttons with matching neutral fill and label treatment. Cashu request actions use equal widths and a 12dp gap; both platforms stack them for large text.
- Android request amount metadata honors the Bitcoin-symbol preference and grouping. Unknown mint names fall back to the hostname. Read-only rows do not expose edit actions.
- Android Settings uses a compact native top bar. The empty Send sheet uses a prominent Receive action. Receive keeps Paste visible with an empty clipboard.

## Verification

- Android debug app and instrumentation suite compile; unit tests: **723 passed, 6 skipped, 0 failed**; lint passes.
- Six `ActivityDetailJourneyTest` journeys pass separately, covering request edits, request totals in sat and USD, currency preference changes, reusable invoice persistence, invoice settlement, failed receipts, and navigation through the main screens. The request footer also passes in dark mode at 1.6× text.
- iOS: five `CashuRequestPaymentObservationTests` and two `ActivityDetailUITests` pass. Both UI tests were rerun after the final status styling change. They verify visible totals, currency formatting, preserved receipt controls, and stacked accessible actions.
- PNG captures are retained in `screenshots/` with their pixel data unchanged. Embedded capture metadata is removed; simulator identifiers and local logs are excluded.

## Reproduce

Build with the platform README instructions. For iOS, run `ActivityDetailUITests` with simulator parallel testing disabled; `SHOW_COMPONENT_CATALOG=activity` and `CI_INTEGRATION_TEST=1` open the debug catalog for manual comparison. The activity catalog fixes the Bitcoin symbol preference for deterministic request captures.

For Android, run each `ActivityDetailJourneyTest` method through Android Test Orchestrator so it receives a fresh application process and cleared test data. `captureMainScreensAndReceiptStates` records the main screens and matching receipt fixtures; `requestTotalsAndEditableAmountRespectTheirCurrency` records paid requests; `cashuRequestKeepsInlineEditingAndNewRequest` records and checks the action footer. Screenshots are written through AndroidX Test Storage.

## Scope and remaining differences

This is a review of the listed main screens and activity states, not an exhaustive audit of every route. Native iOS glass, grouped lists, native Material navigation, typefaces, and some existing completed-receipt glyph styling remain different. The Android request also has a hardware-specific NFC availability indicator. These are visible in the gallery.

Wallet-overview fixtures have different mint names and saved currency-display settings. Receipt fixtures match optional token, memo, address and preimage fields so those differences are not mistaken for missing UI. Created timestamps vary with capture time. Fixed-amount fiat entry, onboarding, scanner/permission flows, and deeper settings remain candidates for a subsequent focused visual pass.
