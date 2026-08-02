# Google Drive Recovery

How the Android wallet backs itself up to Google Drive (+ Block Store) and
restores from it. This is the Android twin of iOS iCloud recovery
(`docs/ios/ICLOUD_RECOVERY.md`); the payload semantics and restore engine are
identical, the storage trust model is not.

## TL;DR

- **The seed is the backup.** Drive recovery stores only your mnemonic plus the
  list of mint URLs. It does **not** store your ecash, balance, history, or the
  app's local database.
- On restore, the wallet re-derives its tokens from the seed and asks each mint
  to return them (NUT-09). Your balance is **rebuilt from the mints**, not
  copied out of a backup.
- The backup lives in **two places at once**: a plaintext JSON file in Google
  Drive's hidden `appDataFolder` (encrypted at rest by Google, **NOT
  end-to-end** — Google could technically read it), and a **Block Store** entry
  that is end-to-end encrypted when the device has a screen lock but is only
  reachable through Android's device-setup restore/transfer flow.
- One user-facing toggle ("Back up to Google Drive") drives both legs.

## Why two storage legs

Google offers no equivalent of iCloud Keychain (E2E + account-synced +
fetchable on demand):

| Property | iCloud Keychain | Block Store | Drive appDataFolder |
|---|---|---|---|
| E2E encrypted (provider can't read) | ✅ | ✅ (with screen lock) | ❌ |
| On-demand restore after a fresh setup | ✅ | ❌ setup-restore only | ✅ |

So Drive is the dependable leg (works in the lost-phone case, after sign-in +
consent) and Block Store is the zero-friction E2E leg (kicks in silently when
the user migrates phones through Android's setup flow). Restore checks Block
Store first — if the payload is already on the device, no Google sign-in
happens at all.

## What is and isn't backed up

| Data | Backed up? | Where |
|---|---|---|
| Seed / mnemonic | ✅ Yes | Drive `appDataFolder` + Block Store |
| Mint URL list | ✅ Yes | same payload |
| Backup timestamp | ✅ Yes | same payload (`updatedAt`) |
| Ecash proofs / token secrets | ❌ No | Local DB only (`cashu-kotlin/wallet.db`) |
| Balance | ❌ No | Derived from proofs |
| Transaction history | ❌ No | Local only |
| App settings / preferences | ❌ No | Local DataStore |
| Nostr private key | ❌ No | Local Keystore-wrapped storage |

The payload (`DriveBackupPayload`, `Core/GoogleDriveBackupService.kt`):

```json
{ "version": 1, "mnemonic": "…12 words…", "mintUrls": ["https://…"], "updatedAt": 1722… }
```

- File `cashu_wallet_backup.json` in the Drive `appDataFolder` (visible only to
  this app; the user can purge it via Drive → Settings → Manage apps →
  "Delete hidden app data"). It **persists across app uninstall**.
- Block Store entry key `com.cashu.me.wallet_backup`, ≤ 4 KB (trailing mint
  URLs are dropped if a pathological mint list exceeds the limit — a seed-only
  backup is still a valid backup).
- Readers ignore unknown fields and never reject newer `version`s: the seed is
  the product. A payload is valid when its mnemonic parses; the mint list may
  be empty ("Seed backup — add mints after").

## Storage / auth mechanisms

| Concern | Implementation |
|---|---|
| OAuth | Play services Identity `AuthorizationClient`, scope `drive.appdata` only (`Core/Platform/PlayServicesDriveAuth.kt`). After the first consent, tokens are issued silently — that's what lets background triggers run without UI. |
| Drive REST | Plain OkHttp against Drive v3 (`Core/Platform/GoogleDriveAppDataApi.kt`) — find/create/update/download/delete in `spaces=appDataFolder`, plus `about` for the "Connected as" caption. One silent re-auth retry on 401. No Google Java SDK. |
| Block Store | `Core/Platform/PlayServicesBlockStore.kt`; `setShouldBackupToCloud(true)` only when `isEndToEndEncryptionAvailable()` (Android 9+, screen lock set). The local entry still transfers during cable/D2D setup either way. |
| Availability | `GoogleApiAvailability`; on GMS-less devices (GrapheneOS etc.) the feature shows as unavailable and seed-phrase restore remains the universal path. |

No OAuth client ID is embedded in code — Google matches the caller by package
name + signing certificate (see Console setup below).

## When a backup happens

`performBackup()` runs (mirroring iOS `performICloudBackup()`):

- **Automatically** on wallet install (create/restore), when a mint is added or
  removed, on restore completion, and the moment the toggle is switched on.
- **Manually** via "Back Up Now" in Settings → Backup & Restore → Google Drive
  Backup.

Background triggers cannot show the consent sheet; if the token needs one they
record a `NeedsConsent` outcome, which the settings screen surfaces ("tap Back
Up Now to grant it"). The enabled flag (`settings.driveBackupEnabled`) is
**device-local** and defaults to off.

Turning the toggle **off** deletes the Drive file and the Block Store entry.
**Deleting the wallet does not** — like iOS, the remote backup deliberately
survives wallet deletion. Consequence (also like iOS): with backup enabled,
creating a new wallet overwrites the old backup with the new seed.

## Restore

Onboarding → Restore Wallet → **Restore from Google Drive**
(`ui/restore/DriveRestoreStep.kt`), mirroring the iOS `.iCloudRestore` phases:
detect → preview (found: timestamp + mint count / not found / unavailable) →
restore → success (recovered balance + "Open Wallet").

The engine is `WalletManager.restoreFromDriveBackup(payload)` — the
line-for-line twin of iOS `restoreFromICloudBackup()`:

1. Set the **incomplete-restore marker** (`local.driveRestoreIncomplete`). While
   set, `performBackup()` returns `Deferred` — the write barrier that stops a
   half-restored mint list from clobbering the good remote backup — and
   `DriveRestorePolicy.needsOnboarding` forces the app back into onboarding on
   next launch so the restore resumes at this step.
2. `initializeRestoredWallet(mnemonic)` — wipes local wallet state and installs
   the backed-up seed (transactional, with rollback).
3. Per mint URL: `restoreFromMint(url)` — NUT-09 deterministic re-derivation.
4. **All-or-nothing**: any mint failure aborts with the marker still set and the
   remote backup preserved ("Could not restore X of N mints…").
5. On success: clear the marker, re-enable backup (which re-uploads).

Completing onboarding by any other path (e.g. abandoning the Drive restore and
creating a new wallet) also clears the marker in
`WalletManager.completeOnboarding()`.

## Google Cloud Console setup (one-time, per project)

> Full background — what this registration is, why Google requires it, and how
> it relates (and doesn't) to the Play Store — in
> `GOOGLE_DRIVE_CONSOLE_SETUP.md`.

1. Enable the **Google Drive API**.
2. OAuth consent screen: add scope `https://www.googleapis.com/auth/drive.appdata`
   (documented as non-sensitive; verify current classification). While the
   screen is in "Testing", only listed test users can grant access.
3. Create **Android OAuth client IDs** — one per (package, SHA-1):
   - `com.cashu.me` + release keystore SHA-1 (and the Play App Signing SHA-1 if
     Play re-signs);
   - `com.cashu.me.debug` + each developer's debug keystore SHA-1
     (`keytool -list -v -keystore ~/.android/debug.keystore`, password
     `android`). **Missing this is the classic "works in release, fails in
     debug" trap** — `authorize()` fails with a developer error.
4. Block Store needs no Console setup.

## Testing

Three tiers (see `GoogleDriveBackupServiceTest.kt` for tier 1):

1. **JVM unit tests, no Google** — the service depends on narrow seams
   (`GoogleDriveBackupService.Host`, `DriveAuthClient`, `DriveAppDataApi`,
   `BlockStoreFacade`), all faked: policy truth tables, guard order, 401
   retry, duplicate-file cleanup, Block-Store-first detection, forward-compat
   payloads, all-or-nothing marker semantics.
2. **Emulator with a Google Play system image + throwaway account** — the full
   Drive loop works on AVDs: enable → Back Up Now → wipe app data → onboarding
   restore. Set a screen-lock PIN to exercise Block Store E2E. Requires the
   `com.cashu.me.debug` OAuth client for the machine's debug keystore.
3. **Manual, two physical devices** — the Block Store silent path via a real
   device-setup migration; account-switch (backup in account A, signed into B →
   not-found + "Connected as" caption); access revocation at
   myaccount.google.com/permissions → NeedsConsent recovery; airplane-mode
   failure copy; GrapheneOS graceful-unavailable; a minified release build.

## Copy rules

Never describe the Drive leg as end-to-end encrypted. The only E2E claim
allowed is Block Store's, and only conditioned on a screen lock. The enable
dialog says plainly that anyone who can read the backup can spend the funds.
