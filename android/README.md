# Cashu Wallet Android

This folder is the Kotlin/Android rewrite of the Swift Cashu Wallet app.

## Implementation State

The Android app is a native Jetpack Compose implementation with the same broad source sections as the Swift app:
`App`, `Core`, `Core/Protocols`, `Core/Services`, `Core/Navigation`, `Models`, `Resources`, and `Views`.

Implemented runtime coverage includes:

- CDK-backed wallet creation, restore, delete, mint management, mint quotes, melts, token send/receive, transaction loading, and payment request handling.
- Android Keystore-backed secure storage, DataStore-backed app settings, wallet-scoped reset boundaries, and CDK database migration/recovery helpers.
- Compose flows for onboarding, wallet home, history, mints, receive, send/pay, scanner, contactless NFC, and settings.
- Android manifest permissions for internet, camera, NFC, vibration, optional hardware features, backup exclusions, and `cashu:` deep links.
- Product/design parity tokens from `PRODUCT.md`, `DESIGN.md`, `DESIGN.json`, and the button prompt files through `CashuTheme`, shared action buttons, quiet cards, semantic state colors, and amount display controls.

## Build

Use JDK 17 and a local Android SDK:

```sh
cd android
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
./gradlew --no-daemon :app:assembleDebug
```

Useful verification targets:

```sh
./gradlew --no-daemon :app:testDebugUnitTest
./gradlew --no-daemon :app:lintDebug
./gradlew --no-daemon :app:assembleRelease
```

The CDK dependency is managed by Gradle as `org.cashudevkit:cdk-kotlin` in `gradle/libs.versions.toml`.
