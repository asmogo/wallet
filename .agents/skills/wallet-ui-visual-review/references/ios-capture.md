# iOS capture workflow

Use this reference only when iOS is routed.

## Preflight

Use Xcode without changing the global developer directory:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
xcrun simctl list runtimes -j
xcrun simctl list devices available -j
```

Verify the newest stable iOS simulator runtime available through the stable
Xcode toolchain. Exclude beta and RC runtimes by default. Compare both
revisions' `IPHONEOS_DEPLOYMENT_TARGET` and availability paths. If the required
runtime is absent, ask before downloading it or selecting an older runtime.

Use one exact simulator runtime and device type for both sides. Keep its UDID
local; publish only the device type and runtime/build.

## Build both revisions

Use separate Derived Data directories:

```sh
xcodebuild \
  -project "$BEFORE_WORKTREE/ios/CashuWallet.xcodeproj" \
  -scheme CashuWallet -configuration Debug \
  -destination "platform=iOS Simulator,id=$IOS_REVIEW_UDID" \
  -derivedDataPath "$SESSION_DIR/derived-data/ios-before" build

xcodebuild \
  -project "$AFTER_WORKTREE/ios/CashuWallet.xcodeproj" \
  -scheme CashuWallet -configuration Debug \
  -destination "platform=iOS Simulator,id=$IOS_REVIEW_UDID" \
  -derivedDataPath "$SESSION_DIR/derived-data/ios-after" build
```

Do not set `CODE_SIGNING_ALLOWED=NO`. The wallet touches Keychain; suppressing
normal simulator signing can cause `errSecMissingEntitlement` and invalidate
the state being reviewed.

If Xcode stops for interactive validation of the locked
`swift-secp256k1` build-tool plug-in, inspect the resolved package identity and
revision, then rerun non-interactively with `-skipPackagePluginValidation`.
Use that flag only for the checked-in dependency graph; do not use it to bypass
an unexpected or unreviewed plug-in.

Immediately before each build, record `git rev-parse HEAD`. Record
`CFBundleShortVersionString`, `CFBundleVersion`, and the SHA-256 of the built
app executable. Do not treat matching marketing versions as proof of matching
source revisions.

## Stabilize the simulator

Boot the selected simulator and make its visible environment deterministic:

```sh
xcrun simctl boot "$IOS_REVIEW_UDID"
xcrun simctl status_bar "$IOS_REVIEW_UDID" override \
  --time "9:41" --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularBars 4
xcrun simctl ui "$IOS_REVIEW_UDID" appearance light
```

Record:

- runtime version and build
- Xcode version and build
- device type
- screenshot pixel dimensions
- logical point dimensions and display scale
- appearance
- language/region
- preferred content-size category

Do not include the UDID, host paths, or local device-set paths in the manifest
or report.

## Install and create state

Uninstall/install each revision's `.app` and launch it with the same deterministic
environment. Prefix launch variables with `SIMCTL_CHILD_`:

```sh
SIMCTL_CHILD_CI_INTEGRATION_TEST=1 \
SIMCTL_CHILD_RESET_WALLET=1 \
SIMCTL_CHILD_UITEST_DISABLE_ANIMATIONS=1 \
xcrun simctl launch --terminate-running-process "$IOS_REVIEW_UDID" \
  com.cashu.me -AppleLanguages "(en)" -AppleLocale "en_US"
```

Use `SIMCTL_CHILD_UITEST_SEED_WALLET=1` for the existing deterministic seeded
wallet. Use `SIMCTL_CHILD_UITEST_SEED_MINT=1` only with the repository's local
test mint and disclose it. Replay the exact launch environment for both builds.

Prefer XCTest accessibility identifiers already used by
`CashuWalletUITests/UITestBase.swift`. If command-line navigation cannot use
them directly, use Simulator UI interaction and inspect every intermediate
screenshot. Coordinate clicks are a last resort; calibrate screen pixels to
window points and re-check focus before clicking.

## Capture

Use names that encode platform, side, surface, runtime, device, and appearance:

```text
ios-before-settings-ios26.5-iphone17pro-dark.png
ios-after-settings-ios26.5-iphone17pro-dark.png
```

Capture:

```sh
xcrun simctl io "$IOS_REVIEW_UDID" screenshot \
  "$ARTIFACT_DIR/ios/<runtime-id>/<filename>.png"
```

Inspect each screenshot immediately. Confirm the intended surface, fixture,
appearance, locale, content size, keyboard state, and animation completion.

Reset status-bar overrides and any simulator settings at the end:

```sh
xcrun simctl status_bar "$IOS_REVIEW_UDID" clear
```

## iOS-specific fixtures

Prefer the existing launch modes and helpers:

- `CI_INTEGRATION_TEST=1`
- `RESET_WALLET=1`
- `UITEST_DISABLE_ANIMATIONS=1`
- `UITEST_SEED_WALLET=1`
- `UITEST_SEED_MINT=1`

Read the implementations at both SHAs before relying on them. Follow
`fixture-recipes.md` for states they cannot express.
