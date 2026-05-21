# Cashu Wallet Android

This folder is the Kotlin/Android rewrite of the Swift Cashu Wallet app.

Current implementation state:

- Native Android project shell with Jetpack Compose.
- Mirrored source layout under `App`, `Core`, `Core/Protocols`, `Core/Services`, `Core/Navigation`, `Models`, `Resources`, and `Views`.
- Android manifest permissions for internet, camera, and NFC plus `cashu:` deep links.
- Core domain models, parser utilities, encrypted storage boundary, wallet database file helpers, and Compose feature shells.
- CDK is isolated behind `CdkWalletGateway`; the concrete binding adapter still needs dependency-resolution verification against the exact `org.cashudevkit:cdk-kotlin:0.17.0-rc-onchain` artifact.

The local migration environment did not have a JDK or Gradle installed when this scaffold was created, so dependency resolution and builds are intentionally still unchecked in `../KOTLIN_MIGRATION_PLAN.md`.

Build once a JDK 17 and Android SDK are available:

```sh
cd android
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
./gradlew :app:assembleDebug
```
