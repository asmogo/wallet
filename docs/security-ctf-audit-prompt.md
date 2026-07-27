# Security CTF Audit — Cashu Wallet

## Background

Cashu Wallet is a native wallet for Cashu ecash, Lightning, on-chain Bitcoin,
Nostr payment requests, and NFC contactless payments, shipped on two platforms:

- `ios/` — SwiftUI app (Swift, CDK via UniFFI)
- `android/` — Jetpack Compose app (Kotlin, `com.cashu.me`)

Because ecash tokens are **bearer assets** and the wallet holds a BIP39 seed
plus Nostr keys, the security bar is high: any leak, parsing confusion, or
unauthorized spend path is a direct loss of user funds.

Your mission: treat this repository as a capture-the-flag arena. Each flag is a
class of vulnerability hidden in the codebase. Find as many flags as you can,
prove each one with concrete evidence (file, line, exploit path), and score
your run.

## Rules of Engagement

1. **Read-only audit.** Do not modify source files, do not exfiltrate data, do
   not contact live mints or relays with crafted payloads. All findings are
   demonstrated by code reading and, where useful, local-only repro snippets.
2. **In scope:** everything under `ios/`, `android/`, `CashuWallet/`, and the
   app's own integration scripts under `CI/` (secrets committed in scripts
   count). Third-party dependencies are in scope only for known-vulnerable
   pinned versions (`ios/Package.resolved`, Gradle lockfiles).
3. **Out of scope:** vulnerabilities inside the CDK library internals
   themselves; Apple/Google platform bugs; physical device access attacks.
4. A finding only counts as a captured flag if it includes: affected
   `file:line`, a concrete attack scenario, and impact. "This looks risky"
   without an exploit path is a lead, not a flag.

## The Flags

### Tier 1 — Direct loss of funds (Critical, 100 pts each)

**FLAG{seed_exposure}** — Find any path where the BIP39 mnemonic, derived
private keys, or the Nostr private key can escape secure storage.
Hunt targets:
- `ios/CashuWallet/Core/KeychainService.swift` — check `kSecAttrAccessible*`
  level, iCloud keychain sync attribute, error paths that return raw key data.
- Android equivalent secure storage under
  `android/app/src/main/java/com/cashu/me/Core/` — is it Keystore-backed, or
  plaintext in `DataStorePreferenceStore.kt` / SharedPreferences?
- Mnemonic display/input flows (`MnemonicInput.kt`, onboarding and backup
  views) — screenshots, app-switcher snapshots, accessibility exposure,
  `FLAG_SECURE` missing on Android screens showing the seed.
- The iCloud ubiquity key-value store entitlement
  (`ios/CashuWallet/CashuWallet.entitlements`) — verify no secret or
  secret-derived value is ever written to `NSUbiquitousKeyValueStore`.

**FLAG{secrets_in_logs}** — Find any log statement or telemetry event that can
contain a mnemonic, private key, full ecash token, NWC connection URI (it
embeds the client secret), invoice preimage, or payment secrets.
Hunt targets: `AppLogger.swift` / `AppLogger.kt`, `SentryService.swift` /
`SentryService.kt` (breadcrumbs, `extra` context, attachments), stray
`print()` / `NSLog` / `Log.d`, error descriptions that embed raw user input.

**FLAG{token_leak}** — Find any place an unspent ecash token (the money
itself) is persisted insecurely, logged, left on the clipboard past its use,
embedded in a notification, or recoverable after deletion.
Hunt targets: `TokenParser`, token storage under `Models/Tokens/` and the
CDK-backed stores, send flows in `Views/Send/`, Android clipboard handling,
pending/unclaimed token bookkeeping in `WalletManager+Tokens.swift`.

**FLAG{nwc_unauthorized_spend}** — Break the NWC (NIP-47) wallet service: a
connected client must never exceed its intended authority.
Hunt targets: `NWCManager.swift` / `NwcManager.kt` — is the per-payment
budget cap actually enforced before payment, can `pay_invoice` fire without
user confirmation, where is the connection URI stored and who can read it,
what happens when the URI leaks, can a relay or replayed request trigger
repeated payments?

### Tier 2 — Payment manipulation (High, 50 pts each)

**FLAG{invoice_confusion}** — Amount/unit/mint confusion in payment parsing
that makes the user pay or receive something different from what the UI shows.
Hunt targets: `PaymentRequestDecoder`, `LightningRequestParser`,
`PaymentRequestParser.swift` — sat vs msat mixups, integer overflow/truncation
on `UInt64` amounts, NUT-18/NUT-26 payment requests whose `mints` allowlist or
amount is tampered with, zero-amount requests, display strings injected into
descriptions/memos that misrepresent the payment.

**FLAG{deeplink_injection}** — Abuse the `cashu://` URL scheme or QR scanning
to make the wallet act without adequate confirmation.
Hunt targets: `ios/CashuWallet/Info.plist` (URL scheme registration),
`android/app/src/main/AndroidManifest.xml` (exported activities + intent
filters), the `onOpenURL` / intent handlers that consume those URLs, and
`ScannerWrapperView.swift` — can a crafted link auto-claim a token, auto-add a
mint, or prefill a send that a hurried user confirms?

**FLAG{nostr_crypto_flaw}** — Weaknesses in the Nostr message crypto or
payment-request authentication.
Hunt targets: the hand-rolled `NIP17.swift`/`NIP44.swift` and
`NIP17.kt`/`NIP44.kt` (compare against the official specs — version handling,
padding, nonce reuse, MAC verification), `CashuRequestListener` /
`CashuRequestStore` (can a stranger forge a payment request that renders as
trusted?), `NostrInboxClient` (relay authentication, unverified events),
key reuse between the Nostr identity key and the NWC signer key.

**FLAG{nostr_backup_metadata}** — Leakage through the encrypted mint backup.
Hunt targets: `NostrMintBackupService` / `NostrMintBackupService.kt` —
what can a relay or observer learn (wallet identity, mint list, timing,
correlation across publishes), is the backup key derived independently of
anything else, can a malicious relay serve a forged backup that restore
accepts (`WalletManager+Backup.swift`, restore flows)?

**FLAG{nfc_attack}** — Malicious NFC tag attacks.
Hunt targets: `NDEFTextRecordCoder.swift`, `NFCPaymentService.swift`,
`NFCReaderDelegate.swift`, `ContactlessPaymentCoordinator.swift`, Android
`Core/NfcReceive/` — crafted NDEF payloads, payment requests with attacker-
chosen amounts/mints, truncated or oversized records, tags that change
content between read and write.

### Tier 3 — Trust & robustness (Medium, 25 pts each)

**FLAG{malicious_mint}** — Paths where an attacker-controlled mint or
mint-discovery result harms the user.
Hunt targets: `AddMintSheet.swift` / mint URL input validation
(`MintUrlInput.kt` — are `http://` mints allowed? homograph domains?),
`MintDiscoveryManager` (Nostr-discovered mints are attacker-influenced — how
are they presented?), `MintService`, mint icon/logo fetching
(`MintLogoBitmapCache.kt` — tracking, SSRF-ish fetch of arbitrary URLs).

**FLAG{state_race}** — Concurrency bugs that duplicate or lose payments.
Hunt targets: `WalletManager+PendingMelts.swift`,
`WalletManager+MintQuoteSync.swift`, `MintQuotePollingPolicy.kt`, double-tap
on Send/Pay buttons, quote expiry races, re-entrancy across the `@MainActor`
/`CdkRuntime` boundary.

**FLAG{platform_misconfig}** — Platform-level hardening gaps.
Hunt targets: Android `AndroidManifest.xml` (`allowBackup`, `exported`
activities, network security config, cleartext traffic), Android
`AppLockManager.kt` / `AppLockPolicy.kt` (bypass via process death, deep link,
or rotation), iOS entitlements review, iCloud backup inclusion of sensitive
files (`docs/ios/ICLOUD_RECOVERY.md` — is that trade-off documented and
encrypted?).

**FLAG{dependency_vuln}** — Known-vulnerable pinned dependencies or unsafe
home-rolled primitives. Hunt targets: `ios/Package.resolved`, Gradle version
catalogs/lockfiles, `Bech32.kt`, `CryptoHash.kt`, `Data+Hashing.swift`.

### Bonus flags (25 pts each)

- **FLAG{ci_secret}** — secrets, tokens, or credentials committed under `CI/`
  or `.github/`.
- **FLAG{privacy_leak}** — third parties (Sentry, price feeds, explorers,
  relays) that can correlate a user's balance, addresses, or payment graph.
  Hunt targets: `PriceService`, `OnchainExplorer`, `SentryService`.
- **FLAG{ux_deception}** — UI flows where the displayed recipient, mint, or
  amount can differ from what is actually signed/sent, even without a code
  bug (e.g. truncation of long mint URLs, lookalike characters).

## Scoring

| Tier | Per flag | All-flags bonus |
|------|----------|-----------------|
| Critical (Tier 1) | 100 pts | +100 for sweeping all four |
| High (Tier 2) | 50 pts | +50 for sweeping all five |
| Medium (Tier 3) | 25 pts | — |
| Bonus | 25 pts | — |
| Duplicate flag across both platforms | +50% | e.g. same flaw in iOS **and** Android |

A flag found on both platforms counts once at full value plus 50%, provided
you show the evidence in both codebases. Maximum possible: 1000 pts.

## Report Format

For each captured flag:

```
## FLAG{flag_name} — [Critical|High|Medium] — Captured
- Platform(s): iOS / Android / both
- Location: path/to/file.swift:line (both platforms when applicable)
- Vulnerability: <what is wrong>
- Attack scenario: <step-by-step, from attacker's capability to impact>
- Impact: <what the user loses>
- Evidence: <code excerpt or repro>
- Suggested fix: <minimal, concrete>
- Points claimed: N
```

End the report with a scoreboard table and a prioritized top-3 fix list.

## Verification

Before claiming points, confirm:
1. Every flag has a real `file:line` citation in this repository — re-read the
   code and quote it; do not guess from memory.
2. Every attack scenario starts from a realistic attacker capability (malicious
   mint, malicious relay, malicious NFC tag, malicious deep link, leaked URI,
   co-installed app, network observer) — state which one.
3. No flag is a pure style issue ("could be more defensive") without a
   demonstrated exploit path.
4. Findings on both platforms were checked against both codebases — the
   Android port is not guaranteed to share iOS's flaws, and vice versa.
5. The report's scoreboard adds up, and the top-3 fixes would close the
   highest-severity flags first.
