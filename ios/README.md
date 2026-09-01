# Cashu Wallet iOS

A privacy-first iOS wallet for Cashu ecash and the Lightning Network, with on-chain Bitcoin support and NFC contactless payments.

Built with SwiftUI, targets iOS 18+, and uses [cdk-swift](https://github.com/asmogo/cdk-swift) (the Cashu Dev Kit) under the hood.

## Features

- **Ecash** — mint, send, and redeem Cashu tokens across multiple mints
- **Lightning** — pay and receive BOLT11 invoices, with Lightning Address support
- **On-chain** — send to and receive from regular Bitcoin addresses
- **Contactless (NFC)** — tap-to-pay using NDEF tags
- **Nostr** — NWC (Nostr Wallet Connect), payment requests, and NPC integration
- **P2PK** locking, multi-mint discovery, and deterministic recovery from seed
- Backup & restore from BIP-39 seed phrase

## Screenshots

| Launch | Onboarding | Wallet |
| :---: | :---: | :---: |
| ![Launch](../docs/screenshots/01-launch.png) | ![Welcome](../docs/screenshots/02-welcome.png) | ![Wallet](../docs/screenshots/03-main-wallet.png) |

| Send options | Settings |
| :---: | :---: |
| ![Send](../docs/screenshots/04-send-options.png) | ![Settings](../docs/screenshots/05-settings.png) |

| Receive on-chain | Send on-chain |
| :---: | :---: |
| ![Receive on-chain](../docs/screenshots/06-receive-onchain.png) | ![Send on-chain](../docs/screenshots/07-send-onchain.png) |

## Building

Open `ios/CashuWallet.xcodeproj` from the repository root, or open
`CashuWallet.xcodeproj` from this folder, in Xcode 16+ and run on an iOS 18
simulator or device. Swift Package Manager resolves `cdk-swift` automatically.

For a CLI build to the simulator from this folder:

```sh
xcodebuild -project CashuWallet.xcodeproj \
  -scheme CashuWallet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

> **Known issue on Xcode 26.1.** The command above fails to link with ~20
> undefined `_secp256k1_*` symbols. swift-secp256k1 0.23.2 gates its C modules
> behind SwiftPM package *traits*, and Xcode 26.1 does not apply that package's
> default traits. Append this to work around it — only command-line settings
> reach package targets, so it cannot be fixed in the project file:
>
> ```sh
>   'GCC_PREPROCESSOR_DEFINITIONS=$(inherited) ENABLE_MODULE_ECDH=1 \
>     ENABLE_MODULE_RECOVERY=1 ENABLE_MODULE_SCHNORRSIG=1 ENABLE_MODULE_MUSIG=1'
> ```

## macOS menu bar app

The same target also builds a Mac app that lives in the menu bar. It is an
`LSUIElement` accessory: no Dock icon, no window at launch — click the bitcoin
glyph in the menu bar to open the wallet in a panel under it.

```sh
./Scripts/build-macos.sh run
```

The script signs ad-hoc, so it needs no Apple Developer setup. That has one
consequence worth knowing: an ad-hoc signature has no team identifier, so the
build is **not sandboxed** (see `CashuWallet/CashuWalletMacLocal.entitlements`)
and the seed lands in the legacy Keychain rather than the data-protection one.
Build with `DEV_TEAM=<team-id> ./Scripts/build-macos.sh` to get the real
sandboxed entitlements — that is what release builds must use.

Platform differences, all deliberate:

- **No NFC.** Macs have no NFC radio, so tap-to-pay is compiled out and the Tap
  button does not appear.
- **No iCloud seed backup** on ad-hoc builds — the entitlement needs a
  provisioning profile. Backup falls back to local only.
- **QR scanning uses the webcam**, via a native AppKit capture view.
- Haptics are no-ops, and sheets replace iOS full-screen covers.

Shared code stays platform-free by way of `CashuWallet/Core/Platform/`, which
reproduces the iOS API surface (pasteboard, fonts, navigation-bar modifiers) on
macOS. Prefer adding a shim there over branching inside a view.

## Project layout

- `CashuWallet/App` — app entry point, root view, and the macOS menu bar host
- `CashuWallet/Core` — services (wallet, mints, NFC, Nostr, keychain), navigation, settings
- `CashuWallet/Core/Platform` — macOS compatibility shims for iOS-only API
- `CashuWallet/Views` — SwiftUI views grouped by flow (Send, Receive, Mints, History, Settings)
- `CashuWallet/Models` — data types and protocols
