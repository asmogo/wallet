# Android capture workflow

Use this reference only when Android is routed.

## Preflight

Work from the session's detached worktrees. Verify the build settings at both
SHAs rather than relying on current-main values:

```sh
rg -n "minSdk|targetSdk|compileSdk|applicationId" \
  "$BEFORE_WORKTREE/android/app/build.gradle.kts" \
  "$AFTER_WORKTREE/android/app/build.gradle.kts"
```

Verify the newest stable Android release from official Android documentation,
then inventory installed images with `inspect_runtimes.py`. Do not use a beta,
preview, Canary, or QPR beta by default. If the exact stable image is missing,
ask before downloading it or using an older stable image.

Prefer an isolated emulator. Use a physical device only when the visible state
depends on hardware the emulator cannot reproduce, and ask before clearing or
changing that device.

## Build both revisions

Use JDK 17 and the local Android SDK. Build inside each worktree:

```sh
cd "$BEFORE_WORKTREE/android"
./gradlew --no-daemon :app:assembleDebug

cd "$AFTER_WORKTREE/android"
./gradlew --no-daemon :app:assembleDebug
```

Use task-specific environment variables rather than changing global shell
configuration. The debug application ID is normally `com.cashu.me.debug`, but
read the checked-out Gradle files and installed APK instead of assuming it.

Immediately before each build, record `git rev-parse HEAD`. Hash the produced
APK with `shasum -a 256` and record package version/build data from `aapt2 dump
badging` or `apkanalyzer manifest`. Associate the before build only with
`before_sha` and the after build only with `after_sha`.

## Stabilize the emulator

Select one explicit emulator serial and use `adb -s "$ANDROID_REVIEW_SERIAL"`
for every command. Record guest properties after boot:

```sh
adb -s "$ANDROID_REVIEW_SERIAL" shell getprop ro.build.version.release
adb -s "$ANDROID_REVIEW_SERIAL" shell getprop ro.build.version.sdk
adb -s "$ANDROID_REVIEW_SERIAL" shell getprop ro.build.version.incremental
adb -s "$ANDROID_REVIEW_SERIAL" shell getprop ro.build.version.security_patch
adb -s "$ANDROID_REVIEW_SERIAL" shell getprop ro.build.fingerprint
adb -s "$ANDROID_REVIEW_SERIAL" shell getprop ro.product.cpu.abi
adb -s "$ANDROID_REVIEW_SERIAL" shell wm size
adb -s "$ANDROID_REVIEW_SERIAL" shell wm density
adb -s "$ANDROID_REVIEW_SERIAL" shell settings get system font_scale
```

Disable window, transition, and animator scales for the capture session.
Configure light/dark mode, locale, font scale, resolution, and density
explicitly. Stabilize System UI demo values where the image includes the status
bar. Restore settings after capture.

Never place the serial, AVD path, host path, or build fingerprint containing a
machine-specific suffix into a public comment. The manifest records the guest
build fingerprint but not the device selector.

## Install and create state

For a fresh-state comparison:

1. Install the before APK.
2. Clear only the review app's data.
3. Launch it and create the recorded synthetic fixture.
4. Capture every Android matrix row.
5. Install the after APK.
6. Clear app data again and replay the exact fixture.
7. Capture the matching rows.

Use `-r` instead of clearing data only when preserved state is itself the
contract being tested. Explain that choice and verify the state is equivalent.

Prefer:

1. content descriptions and UI Automator selectors
2. visible text when it is stable and locale-appropriate
3. inspected coordinates only as a last resort

Dump semantics/UI hierarchy and inspect screenshots between navigation steps.
A successful tap command is not evidence that the intended surface opened.

## Capture

Use names that encode platform, side, surface, runtime, viewport, and
appearance:

```text
android-before-settings-api37-411dp-dark.png
android-after-settings-api37-411dp-dark.png
```

Capture directly to the artifact directory:

```sh
adb -s "$ANDROID_REVIEW_SERIAL" exec-out screencap -p \
  > "$ARTIFACT_DIR/android/<runtime-id>/<filename>.png"
```

Inspect each file immediately. The manifest validator later checks the complete
PNG payload, hashes, and paired dimensions.

For responsive checks, record both pixels and logical dp. If density is changed,
document:

```text
density_dpi = physical_width_px × 160 / desired_width_dp
```

Reset density, resolution, theme, locale, font scale, animations, and System UI
overrides at the end.

## Android-specific fixtures

The app currently has semantic content descriptions, Compose test harnesses,
and onboarding flows but no general-purpose production fixture receiver.
Prefer UI automation for simple states. For a complex state, follow
`fixture-recipes.md` and keep any fixture code under the isolated worktrees'
debug or androidTest source sets.
