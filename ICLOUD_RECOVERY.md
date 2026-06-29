# iCloud Recovery

How the wallet backs itself up to iCloud and restores from it.

## TL;DR

- **The seed is the backup.** iCloud recovery stores only your mnemonic plus the
  list of mint URLs. It does **not** store your ecash, balance, history, or the
  app's local database.
- On restore, the wallet re-derives its tokens from the seed and asks each mint
  to return them (NUT-09). Your balance is **rebuilt from the mints**, not copied
  out of a backup.
- The seed is held in **iCloud Keychain** (Apple end-to-end encrypted). The mint
  list is held in **iCloud Key-Value Store**.

## What is and isn't backed up

| Data | Backed up to iCloud? | Where |
|---|---|---|
| Seed / mnemonic | ✅ Yes | iCloud Keychain (synchronizable item) |
| Mint URL list | ✅ Yes | `NSUbiquitousKeyValueStore` |
| Backup timestamp | ✅ Yes | `NSUbiquitousKeyValueStore` |
| Ecash proofs / token secrets | ❌ No | Local DB only (`cashu_wallet.db`) |
| Balance | ❌ No | Derived from proofs |
| Transaction history | ❌ No | Local only |
| App settings / preferences | ❌ No | Local `UserDefaults` |
| Nostr private key | ❌ No | Local Keychain (device-only) |

So: **secrets (proofs) are not backed up, and the app directory is not backed
up.** Only the seed + mint list are.

## Storage mechanisms

Two independent iCloud systems are used (`WalletManager+Backup.swift`,
`KeychainService.swift`):

| Item | API | Key / identifier | Encryption |
|---|---|---|---|
| Seed | iCloud Keychain via `kSecAttrSynchronizable` | service `com.cashu.wallet`, account `wallet_mnemonic_icloud` | Apple **end-to-end** (Apple cannot read it) |
| Mint URLs | `NSUbiquitousKeyValueStore` | `cashu.icloud.mintURLs` | Apple server-side |
| Timestamp | `NSUbiquitousKeyValueStore` | `cashu.icloud.backupTimestamp` | Apple server-side |

The seed exists as **two separate Keychain items**:

- **Local** — `...ThisDeviceOnly` accessibility, never synced.
- **iCloud** — synchronizable, `kSecAttrAccessibleAfterFirstUnlock`, synced via
  iCloud Keychain. This is the only copy that leaves the device.

`iCloudAvailable()` gates everything on `FileManager.default.ubiquityIdentityToken
!= nil` (user signed into iCloud with Keychain enabled).

## When a backup happens

`performICloudBackup()` runs:

- **Automatically** on wallet creation, when a mint is added or removed, and the
  moment the iCloud-backup toggle is switched on.
- **Manually** via "Back Up Now" in Settings.

The enabled flag itself (`cashu.local.icloudBackupEnabled`) lives in local
`UserDefaults` and is not synced. Turning the feature off calls
`clearICloudBackupData()`, which deletes the synchronizable seed and the
KV-store entries.

## How restore works

`restoreFromICloudBackup()` performs three steps:

1. **Read the backup.** Load the seed from iCloud Keychain
   (`loadSynchronizableMnemonic()`) and the mint URLs from the KV store. Detection
   (`detectICloudBackup()`) treats *seed present* as a valid backup — the mint
   list is optional.
2. **Re-initialize the wallet from the seed** (`initializeRestoredWallet`):
   validate the mnemonic and install a clean wallet.
3. **NUT-09 restore per mint** (`restoreFromMint` → `wallet.restore()`): for each
   mint URL, the wallet **deterministically re-derives its secrets from the seed**,
   then asks the mint to report their state and return signatures for any unspent
   tokens. Balance is reconstructed here.

The Onboarding "Restore from iCloud" flow and the manual Settings → Restore flow
share the same per-mint engine (`restoreFromMint` / `MintRestorePhase`). iCloud
restore just feeds it the mint URLs from the backup automatically instead of
having you type them.

The iCloud backup is fully independent of the local database, so deleting the
wallet on-device does not remove it — it can still be restored afterward.

## Why it's designed this way

Cashu ecash is bearer money but is **deterministic from the seed**
(NUT-13 derivation + NUT-09 restore). The seed is therefore the only thing that
*must* survive; proofs can always be regenerated from it. Backing up the proofs
directly would be redundant, larger, and a bigger exposure surface.

## Caveats

- **Mints must be reachable at restore time.** Balance comes back by querying each
  mint; an offline mint means its tokens can't be restored until it's reachable.
- **Non-deterministic local state can't be recovered.** A token received from a
  mint that has since disappeared permanently, or anything not derivable from the
  seed, is not in the backup.
- Restore requires the device to be signed into the **same iCloud account** that
  holds the synchronizable Keychain seed.

## Code map

| Concern | Location |
|---|---|
| Backup / restore / detection | `CashuWallet/Core/Wallet/WalletManager+Backup.swift` |
| Synchronizable Keychain seed | `CashuWallet/Core/KeychainService.swift` |
| Wallet init + NUT-09 per-mint restore | `CashuWallet/Core/Wallet/WalletManager+Lifecycle.swift` |
| `MintRestorePhase` model | `CashuWallet/Models/WalletSupport/RestoreMintResult.swift` |
| Onboarding iCloud restore UI | `CashuWallet/Views/Main/OnboardingView.swift` |
| Settings restore UI + "Back Up Now" | `CashuWallet/Views/.../SettingsView.swift` |
