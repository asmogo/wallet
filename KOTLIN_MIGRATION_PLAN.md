# Swift iOS to Kotlin/CDK Migration Plan

Source audit date: 2026-05-20  
Source of truth: current working tree in this repository  
Goal: feature-complete Kotlin/Android reimplementation using `org.cashudevkit:cdk-kotlin` in place of `cdk-swift`

## Audit Notes

- [x] Audited all tracked Swift application/source-input paths from `git ls-files`.
- [x] Audited the visible workspace paths from `rg --files`.
- [x] Included binary assets and screenshot resources in the migration inventory.
- [x] Included prompts and design documents as reference-only files.
- [x] Excluded non-runtime assistant tooling from the migration matrix; it is not application scope.
- [x] Confirmed the repository has existing uncommitted Swift changes; the migration plan must not overwrite or revert them.
- [x] Re-audited current working-tree behavior on 2026-05-20, including uncommitted Swift changes in wallet setup, payment decoding, quote handling, NFC, scanner, send/pay, P2PK, and settings-secret storage.
- [x] CDK Kotlin package target selected: `org.cashudevkit:cdk-kotlin:0.17.0-rc-onchain`. Before implementation, run a Gradle dependency-resolution spike to confirm generated API names, Android ABI behavior, and min SDK requirements for this exact artifact.

References:

- CDK Kotlin artifact: https://central.sonatype.com/artifact/org.cashudevkit/cdk-kotlin
- CDK Kotlin package index mirror: https://mvnrepository.com/artifact/org.cashudevkit/cdk-kotlin
- CDK core repository: https://github.com/cashubtc/cdk

## Section Progress Tracker

Use this table as the top-level tracker. A section is `Implemented` only when all rows/checklists inside that section have Kotlin code. A section is `Verified` only when tests or manual parity checks pass.

| Section | Planned | Implemented | Verified | Notes |
| --- | --- | --- | --- | --- |
| Audit Notes | [x] | [ ] | [ ] | Source inventory captured for app, docs, config, resources, and screenshots. |
| File Coverage Audit | [x] | [ ] | [x] | Verified 98 of 98 in-scope Swift/source-input files are represented in the per-file matrix. |
| Feature Completeness Addendum | [x] | [ ] | [ ] | Captures behavior found in the current Swift implementation that needs explicit Kotlin parity. |
| Migration Targets | [x] | [ ] | [ ] | Defines platform, CDK, parity, and release targets. |
| Boundaries | [x] | [ ] | [ ] | Defines what must not be built or changed during planning/porting. |
| Structure Compatibility Plan | [x] | [ ] | [ ] | Keeps Kotlin source layout compatible with the Swift project shape. |
| Proposed Kotlin Architecture | [x] | [ ] | [ ] | Defines mirrored folders plus internal boundaries. |
| CDK Swift to CDK Kotlin Gateway Plan | [x] | [ ] | [ ] | Must be confirmed against real CDK Kotlin APIs. |
| Storage and Secret Targets | [x] | [ ] | [ ] | Covers DataStore, secure storage, CDK DB, and reset boundaries. |
| Feature Parity: Wallet Lifecycle | [x] | [ ] | [ ] | Create, restore, initialize, delete, recover, refresh wallet, onboarding seed display/confirmation, first-mint setup, and two-phase restore mint recovery are partially implemented; full lifecycle parity remains pending. |
| Feature Parity: Mint Management | [x] | [ ] | [ ] | Add/remove/restore/refresh mints, active mint indication, method chips, remove confirmation, mint URL paste/copy/share affordances, and Nostr discovery implemented; broader parity still pending. |
| Feature Parity: Receive | [x] | [ ] | [ ] | Ecash receive token preview/fee/spendability/P2PK guard, clipboard auto-paste/suggestion, pending receive save/claim/remove, BOLT11/BOLT12/on-chain quote display/copy/share/QR, animated QR for long ecash payloads, quote expiry countdown, manual quote status refresh, BOLT12/on-chain quote subscriptions, polling fallback, paid-quote mint action, and incoming Cashu request payments are partially implemented; outgoing Cashu request generation/detail history remains pending. |
| Feature Parity: Send and Pay | [x] | [ ] | [ ] | Ecash send from selected mint, token display/copy/share/QR, P2PK send locking UI, pending sent-token status/reclaim, clipboard payment suggestion, recent recipients, BOLT11/BOLT12 melt quotes, Lightning address melt quotes, first-option on-chain melt quotes, melt preimage/fee persistence, and Cashu request pay with compatible mint selection are partially implemented; full send/pay parity remains pending. |
| Feature Parity: Contactless and Scanner | [x] | [ ] | [ ] | NFC NDEF text/URI/external/media/raw UTF-8 decoding, CReq token preparation, NDEF token record creation, ReaderMode Contactless flow, static CameraX/MLKit QR scanning, and animated UR scanner reassembly are implemented; hardware verification still pending. |
| Feature Parity: History | [x] | [ ] | [ ] | Transaction aggregation, explicit pending/claimed token fallback rows, pending mint quote fallback rows with timestamp pruning, stored melt quote fallback rows, date-sectioned filtered/paginated list rows, expandable transaction detail, QR, copy/share, preimage, fee fields, on-chain explorer links and observation status, pull-to-refresh, pending sent-token status refresh, pending mint quote refresh/minting, BOLT12 duplicate suppression, and transaction update signals are partially implemented; live explorer/device validation and full parity remain pending. |
| Feature Parity: Settings and Integrations | [x] | [ ] | [ ] | Nostr key/NIP-98 foundations, Nostr key/relay settings UI, backup seed access, restore entry, theme/amount display controls, privacy toggles, Payment Request storage keys/listener support, price settings, P2PK settings, NWC settings, legacy NWC/P2PK secret migration, NPC/Lightning address settings and locked-quote minting, advanced delete-wallet controls, P2PK receive preview/signing, and P2PK send locking UI are implemented; NWC runtime processing, P2PK live-token validation, Payment Request settings-UI parity, and full settings parity remain pending. |
| Feature Parity: Platform and Release | [x] | [ ] | [ ] | Android permissions, `cashu:` deep-link routing, copy/share actions, send/receive/mints clipboard suggestions, connectivity observation, shared haptic feedback mapping, scanner haptics, and release build are implemented; broader clipboard parity/device runs remain pending. |
| Milestone: Phase 0 API and Dependency Spike | [x] | [ ] | [ ] | CDK artifact resolves and generated API/native ABI inspection started; live wallet operations still need verification. |
| Milestone: Phase 1 Android Foundation | [x] | [x] | [x] | Android subproject scaffolded under `android/`; `assembleDebug` and `testDebugUnitTest` pass. |
| Milestone: Phase 2 Core Domain and CDK Gateway | [x] | [ ] | [ ] | Direct CDK gateway and CDK-backed parser/token decoding are in place; broader parity still pending. |
| Milestone: Phase 3 Wallet, Mint, Transaction Services | [x] | [ ] | [ ] | Ports service layer and integration behavior. |
| Milestone: Phase 4 Compose Features | [x] | [ ] | [ ] | Ports all views/screens under the mirrored `Views` tree. |
| Milestone: Phase 5 Hardening and Parity Verification | [x] | [ ] | [ ] | Manual and automated parity checks. |
| Per-File Matrix: Root, Product, Design, and Build Files | [x] | [ ] | [ ] | Non-runtime docs/config/build plan. |
| Per-File Matrix: Xcode, iOS Config, and Resources | [x] | [ ] | [ ] | Android manifest/theme/resource equivalents. |
| Per-File Matrix: App Entry and Navigation | [x] | [ ] | [ ] | Entry points and route model. |
| Per-File Matrix: Models and Core Utilities | [x] | [ ] | [ ] | Domain models, parsers, utilities, logging. |
| Per-File Matrix: Protocols, Stores, and Secrets | [x] | [ ] | [ ] | Storage, secure storage, settings, wallet interfaces. |
| Per-File Matrix: Wallet Domain Services | [x] | [ ] | [ ] | Wallet, mint, lightning, token, transaction, NFC services. |
| Per-File Matrix: Shared Compose Components | [x] | [ ] | [ ] | Reusable UI primitives. |
| Per-File Matrix: Main, Onboarding, History, and Mints UI | [x] | [ ] | [ ] | Primary app screens. |
| Per-File Matrix: Receive UI | [x] | [ ] | [ ] | Receive screens. |
| Per-File Matrix: Send and Pay UI | [x] | [ ] | [ ] | Send/pay/contactless screens. |
| Per-File Matrix: Settings UI | [x] | [ ] | [ ] | Settings screens and sheets. |
| Test Plan | [x] | [ ] | [ ] | Unit, integration, screenshot, device, release tests. |
| Risks and Open Questions | [x] | [ ] | [ ] | Resolve before declaring full parity. |
| Definition of Done | [x] | [ ] | [ ] | Final acceptance gate. |

## File Coverage Audit

Coverage check performed against the current tracked Swift/source-input inventory. Android implementation files under `android/` are migration output and are excluded from this source-input coverage count.

- [x] Total tracked repository files: 289.
- [x] In migration source-input scope: 98 files.
- [x] In-scope coverage: 98 of 98 files are represented in the per-file migration matrix.
- [x] Intentionally excluded from migration scope: 42 non-runtime assistant/tooling files under `.agents/`, `skills/`, and `skills-lock.json`.
- [x] Existing tracked Android implementation files under `android/` are excluded from source-input coverage because they are Kotlin migration output, not Swift application inputs.
- [x] The generated plan file itself, `KOTLIN_MIGRATION_PLAN.md`, is not counted as Swift application input.

In-scope means Swift app source, Xcode/iOS configuration, app resources, product/design/build docs, prompts that affect app UI decisions, and screenshots used for parity review. Excluded tooling is not part of the shipping application and should not shape the Android runtime.

Re-run this before implementation begins and whenever files change:

```sh
git ls-files CashuWallet docs README.md PRODUCT.md DESIGN.md DESIGN.json Package.swift Package.resolved button-audit-prompt.md button-fixes-prompt.md | while IFS= read -r f; do
  rg -F -q "\`$f\`" KOTLIN_MIGRATION_PLAN.md || printf 'MISSING %s\n' "$f"
done
```

No output means the per-file matrix covers every in-scope tracked file.

## Feature Completeness Addendum

This addendum is the behavioral gap list from the current Swift working tree. Treat these as required parity details even where the per-file matrix has a broader line item.

- [x] Wallet creation and restore are transactional. Kotlin must snapshot wallet-scoped app storage, move the CDK database and SQLite sidecars to temporary backup names, initialize the new repository, save the mnemonic only after repository creation succeeds, and roll back the previous mnemonic, app storage, and database files if the replacement fails.
- [x] Kotlin must preserve legacy wallet database migration behavior: move `cashu_wallet.db` plus `-wal`, `-shm`, and `-journal` sidecars from the legacy location into the current private wallet database directory before opening the repository.
- [x] Payment input decoding must support raw BOLT11/BOLT12, `lightning:` and `lightning://`, `bitcoin:` URIs with `lightning`, `lightninginvoice`, or `creq` query parameters, raw `creqa`/`creqb1` Cashu requests, `cashu:`/`cashu://` wrapped Cashu requests/tokens, human-readable Lightning addresses, and plain Bitcoin addresses.
- [x] Receive-side Cashu request generation must preserve Swift behavior: `creqA` NUT-18 builder, NIP-19 nprofile transport with relays, generated request persistence, current request ID, editable mint/amount, received-payment attachment, copy/share/static QR detail, and legacy payment-ID fallback.
- [x] Bitcoin address validation must match Swift behavior for Base58Check and Bech32/Bech32m mainnet, testnet, and regtest address families, and must not classify `user@domain` Lightning addresses as Bitcoin addresses.
- [x] BOLT12 quote handling must preserve the local never-expires sentinel, avoid reminting reusable BOLT12 quotes already surfaced by CDK transactions, and avoid duplicate history rows caused by CDK `getUnissuedMintQuotes()` returning reusable BOLT12 offers.
- [x] On-chain receive must preserve local amount fallback, `extra: "{}"` mint-quote creation, quote status refresh via CDK, amount-paid/amount-issued checks, split-target minting, mempool/mutinynet/signet explorer observation, cache-busted explorer requests, confirmation text, and block-explorer links.
- [x] Mint quote persistence must preserve local metadata when CDK responses omit it, clear orphaned `usedByOperation` quote reservations when no saga exists, and release/delete saga reservations before minting a stored quote.
- [x] P2PK parity includes send-time public-key normalization, x-only-to-compressed key expansion, receive-time detection of token P2PK pubkeys, refusal to receive without a matching local signing key, signing with all local P2PK private keys, and `used`/`usedCount` updates for matching keys.
- [x] NWC and P2PK settings must migrate legacy serialized secret fields into encrypted storage on read and encode persisted settings without private keys/secrets afterward.
- [x] Nostr parity includes seed-derived keys, custom nsec import/generation, reset-to-seed behavior, Bech32 npub/nsec encoding and decoding, and NIP-98 signing with the same JSON field ordering and slash-escaping behavior as Swift.
- [x] NPubCash parity includes seed-derived npub.cash keys, Lightning address display, mint selection, polling preferences, automatic versus manual claim behavior, processed quote ID storage, locked quote minting with P2PK spending conditions, and duplicate/in-flight quote guards.
- [x] Nostr mint discovery must be gated by `settings.useWebsockets`, query configured/default relays for kind `38172`, honor the current short discovery window, parse `u` tags and content metadata, deduplicate by URL, and close WebSocket sessions.
- [x] NFC parity is limited to current Swift behavior: read NDEF text records, URI records, external/media payload text, and raw UTF-8 payload fallback; decode CReq/Cashu payment requests and BOLT11 requests from plain/cashu/lightning/bitcoin inputs; write the prepared Cashu token back as an NDEF text record. Pure on-chain NFC payment routing is not a separate Swift feature unless it is represented by a Cashu payment request.
- [ ] Scanner parity includes animated UR fragment reassembly, callback-only mode for inline scanner use, default routing for ecash receive, Cashu request pay, Lightning/BOLT12/on-chain melt, human-readable Lightning address melt, mint-URL copy fallback, success/error haptics, and camera failure handling. Callback/default routing, animated UR reassembly, mint URL scan fallback, success haptics, and camera failure fallback are implemented; physical-device validation remains open.
- [x] Send/pay mint selection must preserve active-mint preference, compatibility filtering by payment method, minimum-amount affordability sorting, selected-mint reset when incompatible, and recent-recipient derivation from the latest outgoing Lightning/on-chain transactions.
- [x] Payment request runtime processing now follows the Swift listener shape in Kotlin: seed/custom Nostr keys, NIP-17 gift-wrap unwrap, NIP-44 v2 decryption, NUT-18 payload conversion, relay subscription, and duplicate request tracking are implemented. Settings-only toggles that are not fully wired to runtime processors in Swift must remain settings-only in Kotlin; this still includes `checkPendingOnStartup` and NWC runtime processing.
- [x] Root/build/reference parity closed on 2026-05-22: repo-level Android ignore patterns, current Android build/run documentation, Gradle dependency replacement for SwiftPM, manifest/resource replacements for Xcode metadata, Compose design tokens, and button hierarchy guidance are represented in the Android project and this plan.

## Migration Targets

- [ ] Build a native Android application in Kotlin.
- [ ] Use Jetpack Compose for all UI.
- [ ] Use `org.cashudevkit:cdk-kotlin:0.17.0-rc-onchain` for wallet protocol operations, storage-backed wallet repository, token parsing/encoding, mint/melt quotes, on-chain mint/melt flows, payment requests, subscriptions, P2PK, and npub.cash helpers where exposed.
- [ ] Preserve every user-facing feature from the Swift app.
- [ ] Preserve the current product tone from `PRODUCT.md`, `DESIGN.md`, and `DESIGN.json`: quiet, native, minimal, high-trust, black/white primary palette with semantic green/orange/red.
- [ ] Preserve wallet data boundaries: CDK wallet database, app settings, wallet-scoped settings, and secure secrets must remain separated.
- [ ] Preserve all reset/delete wallet safety behavior.
- [ ] Preserve all advanced features, even if some are settings-only in Swift today.
- [ ] Target a modern Android baseline: proposed `minSdk 26`, target/compile the current stable Android SDK available during implementation, and raise `minSdk` only if CDK Kotlin or security libraries require it.
- [ ] Keep the first implementation Android-only unless a later decision explicitly chooses Kotlin Multiplatform.

## Boundaries

- [ ] Do not create the full Kotlin project in this planning step.
- [ ] Do not remove or modify Swift source files during planning.
- [x] Do not invent features that are absent from Swift. Payment Requests now have Swift/Kotlin runtime listener support; settings-only advanced states that remain without Swift runtime processors, currently `checkPendingOnStartup` and NWC runtime processing, must keep stored state and explicit TODO boundaries rather than invented processors.
- [ ] Do not attempt a pixel-perfect clone of iOS Liquid Glass. Recreate the design intent with Material 3/Compose surfaces, restrained elevation, semantic states, and accessible contrast.
- [ ] Do not share CDK binding types directly with Compose screens. Create a Kotlin CDK gateway that maps CDK Kotlin types into stable app domain models.
- [ ] Do not store mnemonic, Nostr private key, P2PK private keys, or NWC secrets in plain DataStore/SharedPreferences.
- [x] Do not rely on polling-only quote updates where CDK Kotlin exposes working WebSocket subscriptions.
- [ ] Do not hand-roll Cashu protocol logic that CDK Kotlin exposes.

## Structure Compatibility Plan

The Kotlin project should preserve the Swift project's section layout so both projects can evolve together. Use Android/Gradle conventions at the outer shell, but keep app source packages and folders aligned with the Swift tree.

- [ ] Keep the Swift project as the section map for Kotlin: `App`, `Core`, `Core/Protocols`, `Core/Services`, `Core/Navigation`, `Models`, `Resources`, and `Views`.
- [ ] Prefer one Kotlin file per Swift file with the same base name when practical, for example `WalletManager.swift` to `WalletManager.kt`.
- [ ] When a Swift file is too large and needs a Kotlin split, keep a compatibility anchor file with the same base name and list the split files in its KDoc and in this plan.
- [ ] Preserve domain model names where possible: `MintInfo`, `MintQuoteInfo`, `MeltQuoteInfo`, `WalletTransaction`, `PendingToken`, `PendingReceiveToken`, `ClaimedToken`, `RestoreMintResult`, and `TokenInfo`.
- [ ] Preserve storage key names and JSON field semantics so Swift and Kotlin app-state snapshots remain comparable.
- [ ] Preserve route/screen names where practical so screenshots, issue reports, and QA checklists can be compared one-to-one.
- [ ] Keep platform-only Android adapters behind small files under the matching Swift section instead of moving feature behavior into unrelated packages.
- [ ] Update this migration plan whenever a Swift source file is added, removed, renamed, or materially changes behavior.

Mirrored source layout target:

| Swift section | Kotlin/Android section target | Compatibility rule |
| --- | --- | --- |
| `CashuWallet/App` | `android/app/src/main/java/org/cashu/wallet/App` | Android entry files may add `MainActivity`, but app lifecycle and root state stay here. |
| `CashuWallet/Core` | `android/app/src/main/java/org/cashu/wallet/Core` | Wallet managers, stores, parsers, utilities, network services, and platform facades stay here. |
| `CashuWallet/Core/Protocols` | `android/app/src/main/java/org/cashu/wallet/Core/Protocols` | Kotlin interfaces replace Swift protocols with matching responsibilities. |
| `CashuWallet/Core/Services` | `android/app/src/main/java/org/cashu/wallet/Core/Services` | CDK-backed services and NFC/NDEF services stay parallel to Swift. |
| `CashuWallet/Core/Navigation` | `android/app/src/main/java/org/cashu/wallet/Core/Navigation` | Navigation Compose route definitions mirror Swift navigation concepts. |
| `CashuWallet/Models` | `android/app/src/main/java/org/cashu/wallet/Models` | Kotlin data classes mirror Swift models and serialized field behavior. |
| `CashuWallet/Resources` | `android/app/src/main/res` plus `android/app/src/main/java/org/cashu/wallet/Resources` when typed tokens are needed | Android resources replace asset catalogs while preserving app icon/accent/design-token intent. |
| `CashuWallet/Views` | `android/app/src/main/java/org/cashu/wallet/Views` | Compose screens mirror SwiftUI view folders: `Components`, `Main`, `History`, `Mints`, `Receive`, `Send`, `Settings`. |
| Root docs/config | root Android docs/config equivalents | Keep product/design/build docs next to both projects for shared ownership. |

## Proposed Kotlin Architecture

Start with one Android app module and preserve the mirrored source tree above. Add Gradle modules later only if they keep the same public section names and do not hide Swift-to-Kotlin parity.

- [ ] `App`: Android entry point, manifest bridge, dependency graph, lifecycle startup, root Compose host.
- [ ] `Core`: app orchestration, wallet manager, storage managers, formatting, logging, parsing, price, Nostr, NPC, mint discovery, and CDK gateway wrappers.
- [ ] `Core/Protocols`: Kotlin interfaces for wallet service, storage, secure storage, currency display, and payment method support.
- [ ] `Core/Services`: CDK-backed wallet services, transaction service, NFC/NDEF services, Lightning/token/mint operations.
- [ ] `Core/Navigation`: route definitions, deep-link parsing, modal/sheet routing, scanner route handoff.
- [ ] `Models`: Kotlin data classes/enums equivalent to Swift app models.
- [ ] `Resources`: Android resources plus optional typed design-token constants generated from `DESIGN.json`.
- [ ] `Views`: Compose screens/components organized by the same folders as SwiftUI.
- [ ] Internal-only package `Core/CDK` may be added for generated CDK type adapters if it keeps CDK imports out of `Views`.
- [ ] Internal-only package `Core/Platform` may be added for Android-only camera, clipboard, haptics, connectivity, share, and secure-storage adapters.

State model:

- [ ] Convert `ObservableObject`/`@Published` to `ViewModel` plus `StateFlow`.
- [ ] Convert `async/await` to coroutines with structured scopes.
- [ ] Keep long-running wallet operations off the main thread.
- [ ] Emit one-way UI events for copy/share/haptic/toast/navigation.
- [ ] Keep all CDK calls behind suspend functions returning domain results or typed domain errors.

## CDK Swift to CDK Kotlin Gateway Plan

Create a `CdkWalletGateway` and map each Swift CDK use into a Kotlin gateway method. Exact generated Kotlin names must be verified during the dependency spike.

| Swift CDK usage | Kotlin gateway target | Notes |
| --- | --- | --- |
| `CashuDevKit.initLogging(level:)` | `initializeLogging(level)` | Run once from application start; map app log level. |
| `generateMnemonic()` | `generateMnemonic()` | Used by onboarding; keep BIP39 validation behavior. |
| `mnemonicToEntropy(mnemonic:)` | `mnemonicToEntropy(mnemonic)` | Used for seed/Nostr/NPC derivations. |
| `WalletSqliteDatabase(filePath:)` | `openWalletDatabase(path)` | Android path under app files, not external storage. |
| `WalletRepository(mnemonic:store:)` | `createWalletRepository(mnemonic, store)` | Central repository lifetime managed by wallet manager. |
| `customWalletStore(db:)` | `createCustomWalletStore(db)` | Preserve SQLite-backed CDK store. |
| `createWallet(mintUrl, unit, targetProofCount)` | `ensureWallet(mintUrl, unit, targetProofCount)` | Idempotent behavior expected by current services. |
| `getWallet(mintUrl, unit)` | `walletForMint(mintUrl, unit)` | Gateway should normalize URLs first. |
| `removeWallet(mintUrl,currencyUnit)` | `removeMintWallet(mintUrl, unit)` | Used by mint removal. |
| `fetchMintInfo` | `fetchMintInfo(mintUrl)` | Also keep raw `/v1/info` fallback for on-chain confirmations. |
| `restore` | `restoreMint(mintUrl)` | Used during recovery/onboarding. |
| `totalBalance` | `totalBalance(mintUrl)` | Aggregate in wallet manager. |
| `mintQuote` | `createMintQuote` | Supports BOLT11, BOLT12, and on-chain where exposed. |
| `checkMintQuote` / `checkMintQuoteStatus` | `checkMintQuote` | Preserve quote-state mapping. |
| `WalletSqliteDatabase.getMintQuote`, `getUnissuedMintQuotes`, `addMintQuote`, `removeMintQuote`, `releaseMintQuote`, `getSaga`, `deleteSaga` | `StoredQuoteGateway` methods | Required for BOLT12/on-chain quote metadata preservation, duplicate prevention, and stale reservation cleanup. |
| `WalletSqliteDatabase.getMeltQuote`, `getMeltQuotes` | `StoredMeltQuoteGateway` methods | Required for history fallback rows, mint URL resolution, fee display, and payment proof/preimage lookup. |
| `mintUnified` | `mintTokens` | Preserve split target and quote metadata handling. |
| `meltQuote` | `createBolt11MeltQuote` | Include amount, unit, mint preference. |
| `meltHumanReadable` | `createHumanReadableMeltQuote` | Used for Lightning addresses/BIP-353 style inputs. |
| `quoteOnchainMeltOptions` / `selectOnchainMeltQuote` | `createOnchainMeltQuote` | Preserve quote selection and fee display. |
| `prepareMelt` | `payMeltQuote` | Store preimage and fee paid. |
| `prepareSend` | `sendEcashToken` | Supports amount, memo, P2PK lock, include fees. |
| `receive` | `receiveEcashToken` | Supports fee preview and pending receive. |
| `calculateFee` | `calculateReceiveFee` | Used before receiving token. |
| `getKeysetFeesById` | `keysetFeesById` | Used to estimate P2PK/receive fees. |
| `checkProofsSpent` | `checkTokenSpendable` | Used for pending sent token claim detection. |
| `subscribe` | `subscribeToMintQuote` | Preserve Swift's BOLT12/on-chain subscription monitoring and polling fallback. |
| `listTransactions` | `listWalletTransactions` | Merge with pending/local metadata. |
| `payRequest` | `payCashuPaymentRequest` | Support NUT-18/NUT-26 payment request flows. |
| `Token.decode` / `Token.encode` | `decodeToken` / `encodeToken` | Preserve token validation, mint URL, memo, P2PK extraction. |
| `Token.value`, `Token.p2pkPubkeys`, `token.proofsSimple` | `tokenValue`, `tokenP2PKPubkeys`, `tokenProofs` | Preserve receive preview, P2PK lock warnings/signing, and fee/spendability checks. |
| `decodeInvoice` | `decodeInvoice` | Used by input parser/scanner. |
| `decodePaymentRequest` | `decodePaymentRequest` | Used by Cashu request parser. |
| `PaymentRequest.amount`, `unit`, `description`, `mints` | `CashuPaymentRequestSummary` mapping | Required for scanner/clipboard preview, custom amount rules, non-sat rejection, and compatible mint selection. |
| `NpubCashClient` and helpers | `NpubCashGateway` | Preserve npub.cash setup, mint selection, quote polling/claim. |
| `SecretKey` / `SpendingConditions` / `SendOptions` | typed gateway input models | Keep CDK types inside gateway. |
| `FfiError` | `WalletDomainError` | Port detailed error-code and raw-message mapping. |

## Storage and Secret Targets

- [x] Use Android Keystore-backed encrypted storage for `wallet_mnemonic`, `nostr_private_key`, NWC wallet private keys, NWC connection secrets, and P2PK private keys.
- [ ] Use device-bound encrypted storage semantics equivalent to iOS `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` where possible. Android now uses an app-private AndroidKeyStore AES key and ciphertext storage; exact when-unlocked accessibility parity still needs security review.
- [x] Use DataStore with Kotlin serialization for simple settings and JSON-like arrays.
- [ ] Consider Room only for app-side history metadata if DataStore blobs become hard to maintain; CDK's own wallet SQLite database remains separate.
- [x] Preserve key names from `StorageKeys` where useful for traceability: `wallet.*`, `settings.*`, `npc.*`, `price.*`.
- [x] Implement wallet-boundary deletion equivalent to `walletBoundaryKeys`, including all wallet data keys, wallet-scoped settings, and prefix keys.
- [ ] Store CDK wallet database under app-private storage, for example `filesDir/cashu-kotlin/wallet.db`.
- [x] Preserve corrupted-database backup/recovery behavior from `WalletManager`.
- [x] Preserve create/restore rollback boundaries: app storage snapshot, CDK database and sidecar backups, previous mnemonic fallback, and cleanup of temporary replacement backups.
- [x] Preserve legacy serialized-secret migration for NWC/P2PK: load legacy private values once, save them to encrypted storage, then persist public metadata without private fields.
- [ ] Preserve legacy-key migration logic inside Kotlin storage adapters, even though Android has no prior Swift install. This keeps tests aligned and documents model evolution.

Storage keys to port:

- [ ] Wallet: `wallet.mints`, `wallet.activeMintUrl`, `wallet.pendingTokens`, `wallet.pendingReceiveTokens`, `wallet.claimedTokens`, `wallet.transactions`, `wallet.savedTokens`, `wallet.paymentPreimages`, `wallet.meltQuoteFees`, `wallet.mintQuoteTimestamps`, `wallet.processedNPCQuotes`.
- [ ] Settings: `settings.useBitcoinSymbol`, `settings.showFiatBalance`, `settings.bitcoinPriceCurrency`, `settings.checkPendingOnStartup`, `settings.checkSentTokens`, `settings.autoPasteEcashReceive`, `settings.useWebsockets`, `settings.enablePaymentRequests`, `settings.receivePaymentRequestsAutomatically`, `settings.enableNWC`, `settings.nwcConnections`, `settings.showP2PKButtonInDrawer`, `settings.p2pkKeys`, `settings.checkIncomingInvoices`, `settings.periodicallyCheckIncomingInvoices`, `settings.nostrRelays`, `settings.nostrSignerType`, `settings.amountDisplayPrimary`.
- [ ] NPC: `npc.enabled`, `npc.automaticClaim`, `npc.selectedMint`, `npc.lastCheck`.
- [ ] Price: `price.enabled`, `price.currencyCode`, `price.cachedBTC`, `price.cachedBTCDate`, plus currency-specific cache keys.
- [ ] Secure: `wallet_mnemonic`, `nostr_private_key`, generated NWC secret keys, generated P2PK secret keys.

## Feature Parity Checklist

### Wallet Lifecycle

- [x] App startup initializes logging, wallet manager, settings manager, Nostr service, NPC service, price service, and connectivity observation.
- [ ] Startup must mirror current Swift lifecycle: initialize logging and wallet repository from secure mnemonic, load cached mints/transactions immediately, derive Nostr/NPC keys from the wallet seed, and let settings-controlled services start only where Swift currently starts them.
- [x] Detects existing mnemonic from secure storage.
- [x] Creates new wallet with generated mnemonic.
- [x] Restores wallet from typed mnemonic.
- [x] Validates mnemonic length and BIP39 words.
- [x] Shows and verifies seed phrase during onboarding.
- [x] Initializes CDK wallet repository and SQLite store.
- [x] Migrates/creates wallet database path.
- [x] Migrates legacy database filename and SQLite sidecars before opening the current database path.
- [x] Handles database corruption recovery with backup and clean reinitialization.
- [x] Handles failed create/restore by restoring the previous wallet mnemonic, app storage, and CDK database files.
- [ ] Loads cached mints, pending tokens, pending receive tokens, claimed tokens, processed NPC quote IDs, and transactions.
- [ ] Refreshes balances across tracked mints.
- [x] Deletes wallet safely: secure secrets, CDK DB, wallet-scoped settings, cached data, and runtime state.

### Mint Management

- [ ] Add mint by URL with normalization and validation.
- [ ] Enforce the current HTTPS mint URL rule and trim trailing slashes.
- [ ] Create/retrieve CDK wallet for each mint.
- [ ] Fetch CDK mint info and raw `/v1/info` details.
- [ ] Persist mint list, active mint, balances, units, NUT-supported methods, icons, descriptions, and update timestamps.
- [ ] Set active mint and reflect it across send/receive flows.
- [ ] Remove mint and its CDK wallet.
- [ ] Restore mint state via CDK restore.
- [ ] Discover mints from Nostr relays using kind `38172`.
- [ ] Gate Nostr relay mint discovery behind the WebSocket setting, use configured/default relays, parse `u` tags plus JSON content name/description, deduplicate by URL, and close sessions after the discovery window.
- [ ] Surface payment method support: BOLT11, BOLT12, on-chain.
- [ ] Surface on-chain mint confirmation requirements when available.

### Receive

- [x] Receive ecash token by paste, clipboard auto-paste, scanner, or deep link.
- [x] Parse raw token and `cashu:` URI forms.
- [x] Show token amount, mint, memo, P2PK lock warning, fee estimate, and spendability state.
- [x] Block receiving P2PK-locked tokens when no local matching key exists; sign receive attempts with local P2PK keys and mark matched keys used.
- [x] Receive immediately into matching mint wallet.
- [x] Save token as pending receive and claim later.
- [x] Create BOLT11 mint quote.
- [x] Create BOLT12 offer/invoice flow including amountless/fixed amount behavior.
- [x] Create on-chain mint quote/address.
- [x] Render QR and animated QR where needed. Static QR rendering, Swift-style `ur:bytes` animated frames for long non-static payloads, speed/size controls, and static-only Lightning/on-chain quote rendering are implemented.
- [x] Copy/share invoice, offer, address, or token. Ecash token copy uses the raw token while share uses a `cashu:` URL, matching Swift.
- [x] Track quote expiry and status. Expiry countdown, manual CDK status refresh, BOLT12/on-chain subscription updates, and polling fallback are implemented.
- [x] Use quote subscriptions where Swift currently uses them for BOLT12/on-chain quote monitoring, and keep polling fallback. Preserve the WebSocket setting for Nostr mint discovery; do not newly gate quote subscriptions on that setting unless Swift does first.
- [x] Fall back to polling when quote subscriptions are unavailable or fail.
- [x] Detect on-chain payments through CDK state and explorer observation where the Swift app does.
- [x] Preserve on-chain explorer network selection, cache busting, confirmation count/status text, and address/transaction explorer links.
- [x] Mint tokens after paid quote and refresh balance/history.

### Send and Pay

- [x] Send ecash token from selected mint.
- [x] Support amount keypad, use-max behavior, fee-aware exact sends, memo, mint selector, and P2PK locking.
- [x] Normalize P2PK public keys exactly as Swift does: accept 64-character x-only hex by adding `02`, accept 66-character compressed `02`/`03` hex, and reject all other values.
- [x] Encode generated token and present copy/share/QR.
- [x] Store pending sent token and check whether proofs were claimed.
- [x] Reclaim pending tokens when still spendable.
- [x] Pay BOLT11 invoice.
- [x] Pay BOLT12 request.
- [x] Pay Lightning address/human-readable input.
- [x] Pay on-chain Bitcoin address with first available quote option and fee display, matching current Swift behavior.
- [x] Parse clipboard suggestions and recent recipients.
- [x] Decode clipboard/scanner/recent-recipient inputs through the shared decoder, including `bitcoin:` query parameters for `lightning`, `lightninginvoice`, and `creq`.
- [x] Scan invoices/payment requests.
- [x] Present quote confirmation and send/payment authorizing overlay.
- [x] Store payment preimage and melt fee paid.
- [x] Refresh balance/history after melt.
- [x] Pay Cashu payment requests from raw request, `cashu:` URI, `bitcoin:` URI, or scanner result.
- [x] Select compatible mint for payment request.
- [x] Support custom amount where allowed by request.
- [x] Reject non-sat Cashu payment requests, require a custom amount only when the request is amountless, and prefer selected/active compatible mints before falling back by balance.

### Contactless and Scanner

- [x] Android NFC ReaderMode reads NDEF text, URI, external type, and media payloads equivalent to Swift NFC parsing. Record decoding is unit-tested; physical ReaderMode tag-session validation remains open in hardening.
- [x] Android NFC writer returns Cashu token to compatible tags for contactless payment. NDEF text token records, CReq token preparation, and Contactless write flow are implemented; physical tag write validation remains open in hardening.
- [ ] Decode contactless request (`CReq`) payloads and BOLT11 inputs from plain strings plus `cashu:`, `lightning:`, and `bitcoin:` URI forms. CReq/Cashu request extraction, bitcoin URI Lightning fallback, single-colon/double-slash Lightning schemes, and BOLT12-style Lightning routing are implemented and unit-tested. Pure Bitcoin address routing over NFC is outside current Swift parity unless embedded in a Cashu payment request.
- [x] Preserve pending/authorizing NFC UI state.
- [ ] Camera scanner recognizes QR codes.
- [x] Scanner reassembles animated UR fragments.
- [x] Scanner routes Cashu tokens, Lightning invoices, Bitcoin URIs, Cashu payment requests, and human-readable Lightning addresses.
- [x] Scanner supports inline callback mode for send/pay input fields and default routed mode for full-screen scanning.
- [x] Scanner handles camera permission denial and simulator/no-camera fallback.

### History

- [ ] Load CDK wallet transactions per tracked mint.
- [x] Merge pending sent tokens, pending receive tokens, claimed tokens, mint quotes, melt quotes, preimages, and fee metadata.
- [x] Preserve BOLT12 duplicate suppression when CDK returns reusable offers as unissued quotes and the completed transaction already exists.
- [x] Preserve transaction direction/type/status labels.
- [x] Preserve pagination/filtering/refresh behavior. Filtering, pagination, date sections, pull-to-refresh, and History-triggered pending sent-token plus pending mint quote refresh are implemented.
- [x] Preserve transaction detail view with copy/share/QR/explorer behavior.
- [x] Refresh pending mint quotes and pending token claim status.
- [x] Preserve quote timestamp storage/pruning for pending quote fallback transactions.
- [x] Notify UI on transaction updates.

### Settings and Integrations

- [x] Theme/amount display settings.
- [x] Backup seed display and copy flow.
- [x] Privacy settings: auto-paste, pending checks, WebSocket toggle.
- [x] Price settings: enable/disable, fiat currency selection, cached BTC spot price, refresh interval.
- [x] Payment request settings toggles.
- [x] NWC settings: generate connection, allowance, relay, connection URI, QR, copy, remove, secure secret storage.
- [x] Nostr settings: seed-derived key, custom key import/generate, reset, npub/nsec display, relay list management.
- [x] P2PK settings: show drawer button, generate/import nsec, public key display, copy/delete, secure private storage.
- [x] npub.cash/NPC settings: enable, automatic claim, selected mint, Lightning address display, connect/disconnect, mint update, quote claim/polling.
- [x] Nostr/NPC cryptographic behavior: P256K/Schnorr-compatible key derivation, Bech32 npub/nsec handling, NIP-98 authorization header generation, and npub.cash locked-quote P2PK spending conditions.
- [x] Advanced settings: delete wallet, logs/debug controls where present.

### Platform and Release

- [x] Android manifest includes `INTERNET`, `ACCESS_NETWORK_STATE`, `CAMERA`, and `NFC`.
- [x] Intent filters handle `cashu:` deep links. Add `bitcoin:` or `lightning:` OS-level filters only if product explicitly chooses Android behavior beyond current Swift, which only declares the `cashu` URL scheme.
- [x] MainActivity forwards initial and single-task `cashu:` VIEW intents into Compose navigation; tokens route to Receive and Cashu payment requests route to Send.
- [ ] Clipboard integration mirrors Swift paste/copy behavior. Send payment-request suggestions, Receive Cashu-token auto-paste/suggestions, onboarding and Mints mint-URL paste affordances, and Mints mint URL copy/share actions are implemented; history and remaining paste affordances still need parity.
- [x] Share integration uses Android `ACTION_SEND`.
- [x] Haptics map to Compose/Android haptic feedback.
- [x] Connectivity observation maps `NWPathMonitor` to `ConnectivityManager`.
- [x] App icon and accent resources are converted for Android density buckets/adaptive icon.
- [x] R8/Proguard keep rules preserve CDK Kotlin/UniFFI/native symbols as required.
- [ ] Release build signs and runs on device.

## Milestone Checklist

### Phase 0: API and Dependency Spike

- [ ] Create a throwaway local Gradle spike outside this repo's committed plan scope.
- [x] Resolve `org.cashudevkit:cdk-kotlin:0.17.0-rc-onchain`.
- [x] Record package names, generated Kotlin APIs, native ABI requirements, and min SDK requirements for `0.17.0-rc-onchain`.
- [ ] Verify wallet creation, SQLite database open, mint info fetch, token decode, quote creation, and error handling.
- [ ] Verify NpubCash and payment-request APIs are exposed.
- [x] Verify CDK Kotlin exposes or can replace quote DB operations used by Swift: unissued mint quotes, melt quotes, quote insert/remove, quote reservation release, saga lookup/delete, and on-chain mint-quote status checks.
- [x] Verify CDK Kotlin exposes Token value/P2PK helpers and PaymentRequest amount/unit/description/mints helpers, or define gateway adapters for equivalent generated bindings.
- [x] Decide QR/static scanner, secp256k1/Schnorr, Bech32, Nostr relay, camera, NFC, and animated QR/UR libraries used by implemented slices.
- [x] Inspected the current CDK Kotlin classes for npub.cash support; no `NpubCashClient`/helper classes are exposed in `0.17.0-rc-onchain`, so Android NPC work uses a direct HTTP/NIP-98 adapter plus local CDK mint-quote construction for paid quote claims.

Phase 0 implementation note, 2026-05-20:

- [x] Gradle resolved `org.cashudevkit:cdk-kotlin:0.17.0-rc-onchain` in `debugRuntimeClasspath`.
- [x] Resolved CDK package namespace is `org.cashudevkit`; generated top-level functions live in `Cdk_ffiKt`.
- [x] Inspected generated APIs with `javap`: `WalletRepository`, `Wallet`, `WalletSqliteDatabase`, `WalletStore`, `MintQuote`, `MeltQuote`, `Token`, `PaymentRequest`, `Transaction`, quote DB methods, and payment request/token helper methods are present.
- [x] Android debug build packaged CDK native libraries for `armeabi-v7a`, `arm64-v8a`, and `x86_64`.
- [x] Added `CdkWalletGatewayImpl` using direct generated CDK APIs for repository open, mint add/remove/info/restore, balance, mint quotes, minting, melt quotes, melt finalization, ecash send/receive, receive fees, token spent checks, transaction listing, payment requests, and domain mapping.
- [ ] Run live wallet operations against test mints to prove runtime behavior, quote state transitions, on-chain flows, subscriptions, and error mapping.

### Phase 1: Android Foundation

- [x] Create Android Kotlin project skeleton.
- [x] Add Compose, Navigation, serialization, storage, secure storage, networking, QR, camera, NFC, and CDK dependencies.
- [x] Add manifest permissions and deep-link filters.
- [x] Add app icon/accent resources.
- [x] Add design system and app shell.
- [x] Add test scaffolding.

Phase 1 implementation note, 2026-05-20:

- [x] Created new Android subfolder at `android/` with Gradle Kotlin DSL project files, app module, manifest, resources, Proguard rules, Android-specific `.gitignore`, and README.
- [x] Added mirrored Kotlin package sections for `App`, `Core`, `Core/Protocols`, `Core/Services`, `Core/Navigation`, `Models`, `Resources`, and `Views`.
- [x] Added Compose shell for onboarding, wallet, receive, send, mints, history, settings, QR rendering, and contactless/NFC status surfaces.
- [x] Added core domain models, parser utilities, wallet/settings stores, Android Keystore-backed encrypted storage, wallet database path/rollback helpers, price service, Nostr/NPC boundaries, NDEF parsing, and CDK gateway interface.
- [x] Declared the planned CDK dependency `org.cashudevkit:cdk-kotlin:0.17.0-rc-onchain` behind `CdkWalletGateway`.
- [x] Verify dependency resolution and generated CDK API names.
- [x] Replace the temporary reflection/placeholder CDK gateway methods with concrete generated CDK Kotlin API calls after Phase 0 can run in a JDK/Gradle environment.
- [x] Run `gradle :app:assembleDebug` and unit tests.
- [x] Run Android lint.
- [x] Run release build with R8 enabled.
- [x] Add and verify Gradle wrapper.
- [ ] Run instrumented/device tests and runtime checks.

### Phase 2: Core Domain and CDK Gateway

- [ ] Port all models from `Models.swift`.
- [ ] Port `AmountFormatter`, parser utilities, and error mapping.
- [ ] Implement CDK gateway with domain-type mapping.
- [x] Implement wallet database path manager and recovery helpers.
- [ ] Implement transactional wallet replacement helpers with rollback tests for app storage, encrypted storage, CDK DB, and SQLite sidecars. App-storage snapshot helpers and replacement ordering are implemented and unit-tested; full encrypted-storage and sidecar failure tests remain open.
- [ ] Implement secure storage and app storage.
- [ ] Add unit tests for models, formatters, parsers, and storage reset boundaries.

Implementation notes:

- [x] Added transactional wallet replacement ordering: wallet/settings preference snapshots are taken before replacement, CDK database files are moved to backups, wallet-scoped metadata is cleared without deleting old secrets, the new repository is opened before saving the new mnemonic, and rollback restores the previous mnemonic, preference snapshots, and database backups.
- [x] Delayed deletion of old Nostr/NWC/P2PK secure secrets until replacement succeeds; failed replacement restores settings metadata and reopens the previous repository when a previous mnemonic exists.
- [x] Added `PreferenceSnapshot` unit coverage for restoring present values and removing keys that were absent in the captured wallet-boundary snapshot.
- [x] Verification after transactional wallet replacement changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Wired corrupted database recovery into repository open: SQLite/database/corruption-shaped open failures move the current database and sidecars to `.corrupt.<timestamp>` backups through `WalletDatabasePathManager` and retry once against the clean path.
- [x] Added focused unit tests for legacy database sidecar migration, no-overwrite behavior when the current database already exists, corrupted database sidecar backup, and the recovery error classifier.
- [x] Verification after database recovery wiring: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Verification after legacy database migration test coverage: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.

- [x] Implemented `CdkWalletGatewayImpl` against the generated `org.cashudevkit` bindings and wired `AppContainer` to use it instead of the reflection spike.
- [x] Replaced heuristic Lightning/Cashu payment request decoding with CDK-backed `decodeInvoice` and `decodePaymentRequest` mapping for amount, unit, description, type, and mints.
- [x] Replaced heuristic Cashu token previews with CDK-backed `Token.decode`, value, mint URL, unit, memo, and proof-count extraction.
- [x] Added JVM-safe Bitcoin URI query extraction for `lightning`, `lightninginvoice`, and `creq`; verified with focused unit tests.
- [x] Added focused input-decoder parity tests for raw BOLT11/BOLT12 prefixes, `lightning:`/`lightning://`, `bitcoin:` query fallbacks, raw and wrapped CReq, wrapped Cashu tokens, human-readable Lightning addresses, and plain Bitcoin addresses.
- [x] Verification after parser/token changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-20.
- [x] Verification after payment input parity coverage: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.

### Phase 3: Wallet, Mint, Transaction Services

- [ ] Port `WalletManager` as domain orchestrator plus ViewModel facade.
- [ ] Port `MintService`.
- [ ] Port `LightningService`.
- [ ] Port `TokenService`.
- [ ] Port `TransactionService`.
- [ ] Port `PriceService`, `NostrService`, `NPCService`, and mint discovery.
- [ ] Port quote metadata preservation, BOLT12 reusable-offer guards, on-chain explorer observation, P2PK signing/usage, and NPC locked-quote minting.
- [ ] Add integration tests against test mints where safe.

Implementation notes:

- [x] Implemented Nostr mint discovery gated by `settings.useWebsockets`, using configured/default relays, kind `38172`, `u` tags, content `name`/`description`, URL deduplication, a short discovery window, and explicit WebSocket cleanup.
- [x] Wired discovered mints into the Android Mints screen with add-from-discovery actions.
- [x] Added unit tests for Nostr mint event parsing and verified with `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` plus `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` on 2026-05-20.
- [x] Replaced the placeholder Nostr key service with seed/custom key management, Bech32 `npub`/`nsec` encode/decode, secp256k1 x-only public key derivation, BIP-340 Schnorr signing/verification, and NIP-98 auth header generation.
- [x] Wallet initialization/create/restore now derives Nostr key state from CDK mnemonic entropy, while custom Nostr private keys remain in encrypted storage.
- [x] Added unit tests for Bech32 nsec round-trip, secp256k1 generator public key derivation, and Schnorr signature verification.
- [x] Verification after Nostr crypto changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-20.
- [x] Added exact NIP-98 event commitment and signed-event JSON tests for Swift-compatible compact field ordering and unescaped URL slashes, and matched Swift's WebSocket-disabled mint discovery message in the Android Mints screen.
- [x] Verification after NIP-98 serialization and mint discovery UI parity changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [ ] Live NIP-98 service consumers remain open.

### Phase 4: Compose Features

- [ ] Onboarding.
- [ ] Main wallet.
- [ ] Receive ecash/Lightning/BOLT12/on-chain.
- [ ] Send ecash/melt/payment request.
- [ ] Contactless NFC.
- [ ] History and detail.
- [ ] Mints list/detail.
- [ ] Settings sections.
- [ ] Scanner and QR flows.

Implementation notes:

- [x] Implemented a CameraX/MLKit static QR scanner surface with runtime camera permission handling, close action, haptic feedback on scan, and CameraX lifecycle cleanup.
- [x] Wired scanner entry points from Wallet, Receive, and Send. Auto-routing sends Cashu tokens to Receive, payment requests/invoices/Bitcoin addresses to Send, and likely mint URLs to the Mints URL field.
- [x] Verification after scanner changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-20.
- [x] Added field-specific scanner callback coverage for the Mints URL input and broadened default scanner fallback so scanned HTTPS mint URLs route to the Mints tab field; Receive and Send already use callback targets for token/payment-request input fields.
- [x] Verification after scanner callback/fallback routing changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Wired `cashu:` deep links from Android intents through `NavigationManager` into Receive/Send tab state, with unit coverage for `cashu:`, `cashu://`, percent-decoded token links, Cashu payment request links, and invalid payloads.
- [x] Verification after deep-link routing changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-20.
- [x] Receive screen now retains generated BOLT11/on-chain mint quotes, renders QR, exposes copy/share actions, and can mint the paid quote.
- [x] Send screen now retains generated ecash tokens with QR/copy/share, displays melt quote totals with a pay action, and exposes a Cashu payment request pay action for decoded requests.
- [x] Added reusable Android copy/share controls backed by `ClipboardManager` and `ACTION_SEND` for generated payment payloads.
- [x] Verification after Receive/Send output changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-20.
- [x] Wired Nostr settings UI to `NostrService` and `SettingsManager`: signer selection, custom nsec import/generation, reset to wallet seed, npub/nsec copy/reveal, relay add/remove/copy, and default relay reset.
- [x] Verification after Nostr settings UI changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-20.
- [x] Added Swift-parity privacy/default settings for incoming invoice checks, startup pending checks, periodic invoice checks, sent-token checks, WebSocket gating, and automatic ecash paste.
- [x] Added Coinbase BTC price state with cached per-currency values, enabled/currency settings, manual refresh, 60-second auto-refresh while enabled, and Settings UI for fiat currency selection and status/error display.
- [x] Verification after privacy/display/price settings changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-20.
- [x] Added amount display parity: normalized `settings.amountDisplayPrimary`, Swift-style `₿` sat-count formatting, reusable Compose fiat/sats two-line display with primary flip, wallet balance integration, and Display settings for fiat enablement, currency, price refresh, and primary amount selection.
- [x] Verification after amount display settings changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added Swift-parity Advanced settings delete-wallet control with destructive styling, confirmation, async error surfacing, and wallet-boundary deletion through `WalletManager.deleteWallet()`.
- [x] Verification after Advanced settings changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added backup settings controls for seed phrase reveal/copy and restore-flow entry, plus a reversible onboarding restore mode for existing wallets.
- [x] Verification after backup settings changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-20.
- [x] Added P2PK settings backed by encrypted private-key storage: random key generation, nsec import, compressed `02 + xonly` public keys, duplicate detection, key list/copy/remove, quick-access toggle, and wallet-boundary secret cleanup.
- [x] Verification after P2PK settings changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-20.
- [x] Added NWC settings backed by encrypted wallet private keys and connection secrets: enable/ensure connection, secp256k1 public metadata, relay-based connection URI, copy/remove controls, allowance editing, and wallet-boundary secret cleanup. Runtime NWC request processing remains intentionally open because Swift treats it as settings-bounded.
- [x] Verification after NWC settings changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-20.
- [x] Audited settings-only runtime boundaries: `checkPendingOnStartup` and NWC enablement are persisted without starting invented background processors; code-level TODOs mark the future runtime boundary. Payment Request listener runtime now exists, while enable/auto-receive settings UI still needs reconciliation with the tracked Swift settings surface.
- [x] Added NWC/P2PK legacy-secret migration: parses old serialized `walletPrivateKey`, `connectionSecret`, and `privateKey` fields, saves missing values into encrypted secure storage without overwriting existing secure secrets, rewrites public metadata-only settings, and unit-tests Swift-shaped plus current metadata rows.
- [x] Verification after legacy-secret migration changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added NPC/Lightning Address support backed by `NPCService`: persisted enable/auto-claim/selected-mint/last-check state, seed-derived `npubx.cash` Lightning address display/copy, NIP-98-to-JWT authenticated npub.cash quote fetch and mint update calls, quote parsing, polling preference hooks, selected-mint UI, and manual check UI.
- [x] Added unit tests for npub.cash quote response parsing.
- [x] Added QR dialogs for NWC connection strings and P2PK public keys.
- [x] Verification after NPC settings and QR changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-20.
- [x] Added NPC automatic/manual claim parity: paid quotes are sorted and filtered against stored processed IDs, automatic claim stores a CDK mint quote and calls `mintUnified`, locked quotes pass seed-derived P2PK spending conditions, duplicate/in-flight quote IDs are suppressed, and already-issued quotes are marked processed.
- [x] Verification after NPC claim changes: focused NPC/Nostr tests, `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace`, and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Wired P2PK-locked token receive path to detect token P2PK pubkeys, require matching encrypted local P2PK private keys, pass CDK `SecretKey` signing keys into `ReceiveOptions`, and update local P2PK used counters after receive.
- [x] Verification after P2PK receive signing changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Wired P2PK send locking UI in Compose: lock toggle, recipient key input, stored-key picker, Swift-compatible normalization, CDK send options, local used-counter update for matching stored keys, and focused unit tests for normalization.
- [x] Verification after P2PK send locking changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added receive token preview details in Compose: token amount, receive fee estimate, mint, memo, proof count, P2PK lock status, and disabled receive action for P2PK tokens without a matching local key.
- [x] Aligned P2PK receive signing with Swift behavior: require any matching local P2PK key for locked tokens and pass available local encrypted P2PK private keys into CDK receive options.
- [x] Verification after P2PK receive preview/signing alignment: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added pending receive token flow: save parsed token for later, persist in wallet storage/state, list pending tokens in Receive, claim through the normal receive path, and remove saved entries.
- [x] Verification after pending receive flow changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added pending sent token flow: list saved pending sent tokens, manually check proof-spent status, move claimed tokens into claimed-token storage, reclaim unclaimed tokens through the receive path, and remove stale pending entries.
- [x] Verification after pending sent token flow changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added ecash send mint selector: defaults to the active mint, lists available mints with balances, blocks selected-mint overspend, provides basic use-max fill, and passes the selected mint URL into CDK send.
- [x] Verification after send mint selector changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added receive token spendability preview using CDK proof-spent checks: shows Checking/Spendable/Claimed/Unknown and blocks receive when proofs are reported spent.
- [x] Verification after receive spendability changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added shared Android clipboard suggestion chip and clipboard reader; Send now offers recognized BOLT11/BOLT12/Lightning address/on-chain/Cashu payment request suggestions, and Receive auto-pastes Cashu tokens when enabled or shows a token suggestion chip.
- [x] Verification after clipboard suggestion changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added Send recent recipients: loads current transactions, derives up to three distinct recent outgoing Lightning/on-chain invoices or addresses, shows compact selection actions while request input is empty, and reuses the shared decoder path after selection.
- [x] Verification after recent recipient changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21. First lint/release attempt hit a Kotlin incremental-cache EOF and passed on rerun.
- [x] Added send/pay mint selection parity: shared Android helpers now keep active-mint preference, reset incompatible payment selections, filter Lightning/BOLT12/on-chain payment quotes by supported melt methods, prefer affordable mints for known amounts, and sort mint menus by selected state, affordability, balance, then name.
- [x] Verification after send/pay mint selection changes: focused mint-selection tests, `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace`, and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Audited send amount-entry parity: Android includes digit keypad input, use-max, memo, selected mint, P2PK locking, and CDK `includeFee = false` exact-send behavior matching Swift.
- [x] Added BOLT12 reusable-quote protections: local never-expires sentinel normalization/display hiding, paid/issued state derivation from paid/issued amounts, mint-sync skip when already issued, and quote-backed history fallback suppression when CDK transactions already surfaced the quote.
- [x] Verification after BOLT12 quote handling changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added mint quote persistence safeguards in the CDK gateway: refreshed quotes preserve local request/amount/expiry/payment method/confirmation/secret/reservation metadata when CDK omits fields, orphaned `usedByOperation` reservations are cleared when no saga exists, and stored quote reservations are released with saga deletion before minting.
- [x] Verification after mint quote persistence changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added Bitcoin address validation coverage matching the Swift validator: Base58Check mainnet/testnet, Bech32 v0, Bech32m v1+, invalid checksum/HRP/mixed-case cases, Lightning-address exclusion, Bitcoin URI normalization, on-chain classification, and payment-method detection. Fixtures were aligned to BIP350 segwit address test vectors.
- [x] Verification after Bitcoin address validation tests: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added BOLT12 receive entry: active mints advertising BOLT12 can create amountless offers when amount is blank or fixed-amount offers when amount is entered; generated offers use the existing quote display/copy/share/QR card.
- [x] Verification after BOLT12 receive changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added manual receive quote status refresh through CDK `checkMintQuote`, and guarded minting so the paid-quote mint action only enables once the quote state is `Paid`.
- [x] Verification after quote refresh changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added BOLT12/on-chain receive quote subscriptions through CDK `subscribeMintQuoteState`, exposed as a gateway `Flow`, collected by Receive for immediate quote-state updates, and kept the existing polling loop as fallback without tying quote subscriptions to `settings.useWebsockets`.
- [x] Verification after quote subscription changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added payment quote gateway support for Lightning addresses and on-chain Bitcoin addresses: address payments require a typed amount, Lightning addresses use CDK `meltHumanReadable` with a mint-network heuristic, on-chain payments use CDK `quoteOnchainMeltOptions`/`selectOnchainMeltQuote` with the first available option, and Send passes the custom amount plus selected mint into quote creation.
- [x] Verification after payment quote gateway changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Audited on-chain melt quote options against Swift: the Swift app also selects the first CDK on-chain melt option and displays the returned fee reserve, so Android's first-option behavior is parity rather than a missing picker.
- [x] Added melt payment metadata persistence: successful melts store Lightning/on-chain payment proofs and actual paid fees by quote ID, cached/remote transactions are enriched from those stores, and quote-ID deduplication avoids duplicate cached payment rows after CDK refreshes.
- [x] Verification after melt metadata persistence changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added Cashu payment request mint selection and validation: raw/`cashu:`/`bitcoin:?creq=`/scanner payloads decode through the shared request path, non-sat requests are rejected, amountless requests require a positive custom amount, selected/active compatible mints are preferred, and fallback selection chooses the compatible mint with enough balance.
- [x] Verification after Cashu payment request mint-selection changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added Compose `AuthorizingOverlay` for Send payments: Cashu request pay and melt quote pay now show an authorizing state, success auto-dismiss, error state, haptic feedback, recipient caption, and amount display using current settings.
- [x] Verification after authorizing overlay changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added receive quote expiry countdown formatting and display on generated BOLT11/BOLT12/on-chain quote cards.
- [x] Verification after receive quote expiry countdown changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added receive quote polling fallback: open generated quotes are checked every 15 seconds without setting global loading state, and polling stops after terminal states, quote replacement, or expiry.
- [x] Verification after receive quote polling fallback changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added onboarding seed display and verification: Create Wallet now generates a mnemonic first, displays numbered words, requires typed confirmation before installing the wallet, and restore input is gated to supported BIP39 word counts before CDK validation.
- [x] Verification after onboarding seed display changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added Swift-style first-mint and restore-mints onboarding: create now installs the wallet, offers recommended/custom mint selection with URL normalization and paste support, adds selected mints before completing onboarding, and restore now opens the wallet first, restores NUT-09 proofs from user-supplied mints, displays per-mint progress/results plus recovered/pending totals, and only exits onboarding on Continue/Skip.
- [x] Added shared mint URL input helpers and unit tests for HTTPS normalization, quote/trailing-slash trimming, clipboard separator parsing, deduplication, and invalid URL rejection.
- [x] Verification after onboarding mint setup/restore changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added Compose `NumberPadAmountInput` parity for send amount entry: digit-only rows, delete, long-press clear, stable key sizing, and shared haptic feedback.
- [x] Aligned restore/create mnemonic validation with current Swift behavior: Android now accepts only 12- or 24-word seed phrases before CDK BIP39 word/checksum validation, uses the same UI wording, and enforces the length again inside `WalletManager`.
- [x] Verification after mnemonic validation alignment: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added expandable Android history transaction details: rows now expand to show amount, date, direction/type/status, fee, mint, request/address, payment proof or on-chain transaction ID, QR content, and copy/share actions.
- [x] Verification after history transaction detail changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added on-chain block-explorer links for history details using the Swift network mapping: mainnet mempool.space, signet/testnet mempool.space/signet, and CDK on-chain mint mutinynet links.
- [x] Verification after history explorer link changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added Android connectivity observation: app-level `ConnectivityManager` callback with `StateFlow`, wallet offline banner, Settings network status/refresh row, and `ACCESS_NETWORK_STATE` permission.
- [x] Verification after connectivity observation changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added Android haptic feedback mapping: centralized `WalletHaptic` helper over `View.performHapticFeedback`, selection feedback on shared action buttons, and success feedback when scanner QR detection completes.
- [x] Verification after haptic feedback mapping changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added History filters and pagination: Android history now supports All/Pending/Completed filtering and ten-row pages matching the Swift list structure.
- [x] Verification after History filter/pagination changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added History date sections matching Swift's buckets: Today, Yesterday, This Week, This Month, and Earlier.
- [x] Verification after History date-section changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added History pending sent-token status refresh: History can check all pending sent tokens, mark claimed tokens, reload transactions, and report the claimed count.
- [x] Verification after History pending status refresh changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added History pending mint quote refresh: Android now loads CDK unissued mint quotes as pending incoming rows, preserves/prunes local quote timestamps, suppresses reusable BOLT12 duplicates already surfaced by CDK transactions, refreshes pending quote state from History, and mints paid quotes.
- [x] Verification after History pending mint quote refresh changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added stored melt quote fallback rows: Android now loads CDK stored melt quotes into outgoing Lightning/on-chain history rows, maps pending/paid/failed states, applies stored preimages and actual fees, suppresses rows already surfaced by CDK transactions, and preserves/prunes quote timestamps for outgoing quote rows.
- [x] Verification after stored melt quote fallback changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added explicit token fallback rows in History: pending sent tokens, pending receive tokens saved for later, and claimed sent tokens now aggregate into incoming/outgoing ecash transaction rows, while cached pending-token rows are filtered to prevent stale removed entries from reappearing.
- [x] Verification after token fallback history changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added on-chain explorer observation for pending mint quote rows: Android now selects mempool/signet/mutinynet APIs, uses cache-busted no-cache requests, detects matching address outputs by amount, stores observed txids, and renders confirmation-aware status text and explorer links.
- [x] Verification after on-chain observation changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added on-chain mint finalization parity: Android now persists local on-chain quote amount fallbacks, refreshes stored on-chain mint quotes through CDK `checkMintQuoteStatus`, blocks mint attempts until `amount_paid` exceeds `amount_issued`, and passes a value `SplitTarget` into `mintUnified` for credited on-chain quotes.
- [x] Verification after on-chain mint finalization changes: focused quote tests, `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace`, and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added unit-tested NFC/NDEF parsing parity: Android now decodes NDEF text records, NFC Forum URI records, external/media UTF-8 payloads, and raw UTF-8 fallback payloads without relying on Android framework URI helpers; NFC payment input routing handles Cashu payment requests and bitcoin URI Lightning fallback, and CReq token preparation selects a compatible funded mint before creating the token record.
- [x] Verification after NFC/NDEF parsing changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Wired Android Contactless NFC flow: the screen enables reader mode, reads the first supported NDEF payload, prepares in-band Cashu payment-request tokens, writes the prepared token back as an NDEF text record, and routes Lightning NFC requests back into Send.
- [x] Verification after Contactless NFC flow changes: focused NFC tests, `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace`, and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added Contactless pending/authorizing completion state: Android now surfaces reading/preparing/writing progress, remembers the sent amount after writing the token, shows a sent state, and provides a pay-again reset.
- [x] Verification after Contactless UI state changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added transaction update signals: every `loadTransactions()` aggregation now increments a `WalletState.transactionUpdateVersion` counter so Compose screens and future services can observe transaction refreshes with Swift-style update semantics.
- [x] Verification after transaction update signal changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added camera scanner failure fallback: CameraX provider/bind failures now show a recoverable scanner error state with retry/close actions instead of leaving the user on a blank preview.
- [x] Verification after scanner camera-failure fallback: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added animated UR scanner reassembly with `bcur-kotlin`: CameraX scanning keeps analysis active for multipart `ur:` frames, shows progress, decodes Swift-style `ur:bytes` CBOR payloads, and only completes routing once content is reconstructed.
- [x] Verification after animated UR scanner changes: focused `AnimatedUrDecoderTest`, `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace`, and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added animated QR generation with `bcur-kotlin`: long non-static QR payloads render rotating `ur:bytes` frames, Swift-style speed/size controls are available where enabled, Send token QR hides production controls while still animating, and Lightning/on-chain receive quotes stay static.
- [x] Verification after animated QR generation changes: focused `QRCodeViewTest` and `AnimatedUrDecoderTest` passed on 2026-05-21 with `./gradlew --no-daemon :app:testDebugUnitTest --tests org.cashu.wallet.Views.Components.QRCodeViewTest --tests org.cashu.wallet.Core.AnimatedUrDecoderTest --stacktrace`, followed by full `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` gates.
- [x] Added Mints clipboard parity: Mints now normalizes scanned/pasted mint URLs with the shared helper, offers a paste-from-clipboard action and clipboard suggestion chip for valid mint URLs, and exposes copy/share actions for configured and discovered mint URLs.
- [x] Verification after Mints clipboard changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Added History pull-to-refresh parity: the transaction list now uses Material 3 pull-to-refresh to reload transactions and refresh pending mint quotes/sent tokens, matching Swift's `.refreshable` behavior while keeping the explicit pending-status action.
- [x] Verification after History pull-to-refresh changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Converted app icon and accent resources: Android now uses launcher PNGs generated from the iOS app icon for mdpi through xxxhdpi, adaptive icon XML references generated foreground mipmaps, and light/dark accent resources mirror the iOS black/white accent definitions.
- [x] Verification after icon/accent conversion: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` passed on 2026-05-21; initial `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` caught an API 27-only `windowLightNavigationBar` item, which was removed, and the retry passed on 2026-05-21.
- [x] Added shared Compose component equivalents for `ActivityOrbView`, `EcashIcon`, `ErrorBannerView`, `NotificationBadgeView`, and `PressableButtonStyle`; primary and secondary action buttons now use the shared press-scale interaction.
- [x] Verification after shared component changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Improved Mints list parity: the screen now scrolls, shows active mint state, renders BOLT12/on-chain method chips, supports remove confirmation for configured mints, and reuses normalized add behavior for discovered mint rows.
- [x] Verification after Mints list parity changes: forced `./gradlew --no-daemon :app:compileDebugKotlin :app:testDebugUnitTest --rerun-tasks --stacktrace`, normal `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace`, and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21. Lint initially surfaced a suspicious-indentation error in `ContactlessPayView.kt`; the NFC reader flag expression was parenthesized and the retry passed.
- [x] Added NFC payment input decoder coverage for `lightning:` single-colon BOLT11 input and BOLT12-style `lightning:lno...` payloads, confirming they route to Send as Lightning requests.
- [x] Verification after NFC decoder coverage changes: focused `NFCPaymentInputDecoderTest`, `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace`, and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Wired Mint detail parity: configured mint rows now open a detail dialog backed by `MintDetailView`, including URL copy/share, balance, units, receive/send methods, on-chain confirmations, and icon URL display where available.
- [x] Verification after Mint detail wiring: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Fixed copy/share payload parity: `CopyShareRow` now supports distinct copy and share payloads, generated ecash tokens and history ecash entries copy the raw token, and ecash share actions wrap the payload with `cashu:` exactly once.
- [x] Verification after copy/share payload changes: focused `PlatformActionsTest`, `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace`, and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-21.
- [x] Improved receive success parity: ecash receives, pending receive claims, and paid quote minting now use the shared success notification badge, auto-dismiss behavior, and success/error haptic feedback.
- [x] Verification after receive success parity changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-22.
- [x] Improved History loading/error parity: the History screen now uses the shared activity indicator, dismissible error banner, refresh status banner, loading empty state, and carded empty state.
- [x] Verification after History loading/error changes: `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace` and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-22.
- [x] Replaced Android wallet/settings SharedPreferences facades with DataStore-backed stores while preserving existing store names and keys through `SharedPreferencesMigration`; wallet/settings stores now support test-isolated store names, wallet-scoped clearing, migrated defaults, and processed Cashu request ID storage.
- [x] Added Android instrumentation coverage for wallet/settings DataStore migration, wallet-boundary clearing, and secure storage save/load/delete behavior.
- [x] Verification after DataStore storage migration: `./gradlew --no-daemon :app:compileDebugKotlin --stacktrace`, `./gradlew --no-daemon :app:compileDebugKotlin :app:compileDebugAndroidTestKotlin --stacktrace`, and `./gradlew --no-daemon :app:connectedDebugAndroidTest --stacktrace` passed on 2026-05-22 on device `SM-G991B - 15`.
- [x] Added a standalone History transaction detail dialog opened from expanded rows, reusing the same QR/copy/share, mint, quote, preimage, fee, explorer-link, and pending-refresh detail content.
- [x] Added runtime Cashu payment request listener support: Android starts/stops the listener from the app shell after wallet initialization, subscribes to Nostr kind `1059` gift wraps over configured relays, unwraps NIP-17/NIP-44 payloads, converts NUT-18 payloads to `cashuA` tokens, pays them through `WalletManager`, and suppresses duplicate request IDs.
- [x] Verification after Cashu request listener and standalone History detail changes: focused `NIP44AndNIP17Test`/`CashuRequestListenerTest`, `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace`, and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-22. A later `connectedDebugAndroidTest` retry was blocked because `adb devices` reported no connected devices after the earlier device run.
- [x] Added receive-side Cashu request generation: Android now builds deterministic Swift-compatible `creqA` NUT-18 requests with NIP-19 nprofile relay transport, persists generated request history/current ID in wallet storage, shows static QR/copy/share detail on Receive, supports any-mint or active-mint restriction with edit dialogs, preserves legacy received-payment IDs, provides regenerate/delete controls, fires success haptics when linked payments arrive, and attributes NIP-17 listener payments by event ID while linking them back to generated request IDs.
- [x] Verification after receive-side Cashu request generation: `./gradlew --no-daemon :app:compileDebugKotlin :app:compileDebugAndroidTestKotlin :app:compileDebugUnitTestKotlin --stacktrace`, focused `PaymentRequestBuilderTest`/`CashuRequestListenerTest`/`PaymentRequestDecoderTest`, `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace`, `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace`, and `./gradlew --no-daemon :app:connectedDebugAndroidTest --stacktrace` on device `SM-G991B - 15` passed on 2026-05-22.
- [x] Added dedicated receive-side Cashu request detail, amount picker, and mint picker sheets: Android now opens generated requests in a bottom-sheet detail view with static QR, share/copy, waiting/received status, payment-received success badge, editable amount/mint rows, fiat/sat amount display, any-amount behavior, any-mint/configured-mint choices, mint icons, selected checkmarks, regenerate, and delete actions.
- [x] Verification after receive-side Cashu request sheet parity: `./gradlew --no-daemon :app:compileDebugKotlin :app:compileDebugUnitTestKotlin --stacktrace`, `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace`, and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-22.
- [x] Closed amount/currency formatting parity: Kotlin now has sat/fiat amount formatting, BTC-symbol display support, primary/secondary fiat-sat display helpers, currency definitions for SAT/USD/EUR, `CurrencyAmount` formatting, and mint-unit currency lookup coverage.
- [x] Verification after amount/currency formatting parity: focused `AmountFormatterTest`/`CurrencyProtocolTest`, `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace`, and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-22.
- [x] Closed `AppLogger.swift` parity: Kotlin now has wallet/network/security/UI Logcat categories plus JVM-tested privacy-safe redaction for Nostr private keys and labeled seed/private-key/secret log messages.
- [x] Verification after logger parity: focused `AppLoggerTest`, `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace`, and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-22.
- [x] Closed `PaymentMethodProtocol.swift` parity: Kotlin now has payment rail, request/result/status value types, expiry/status helpers, and stable BOLT11/BOLT12/on-chain icon/capability labels.
- [x] Verification after payment method protocol parity: focused `PaymentMethodProtocolTest`, `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace`, and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-22.
- [x] Closed `TokenParser.swift` parity: Kotlin now covers Cashu token URI extraction/normalization, Swift-named normalized-token access, malformed-token messages, scanner/deep-link routing use, and Receive UI gating so malformed text is not submitted as an ecash token.
- [x] Verification after token parser parity: focused `TokenParserTest`/`PaymentRequestDecoderTest`, `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace`, and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-22.
- [x] Closed `KeychainService.swift` parity: Kotlin secure storage now has Swift-compatible mnemonic and Nostr key save/load/delete/has convenience helpers on top of the existing AndroidKeyStore AES/GCM backend and ciphertext preferences.
- [x] Verification after keychain/secure-storage parity: focused `SecureStorageProtocolTest`, `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace`, and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-22.
- [x] Closed `NavigationManager.swift` parity after audit: Android has a Compose route model, one-shot deep-link events, scanner/send/receive/mints routing, `cashu:` and `cashu://` token links, percent-decoded links, Cashu payment request routing, and invalid-payload rejection.
- [x] Verification after navigation parity audit: focused `NavigationManagerTest` passed on 2026-05-22.
- [x] Closed app-shell parity: Android now initializes dependencies through `CashuWalletApplication`/`AppContainer`, handles initial and new `cashu:` intents in `MainActivity`, switches Compose root state between loading/onboarding/authenticated shell, checks pending sent tokens on authenticated startup when settings allow, and starts/stops the Cashu request listener across authenticated state and Android foreground/background lifecycle.
- [x] Verification after app-shell parity: `./gradlew --no-daemon :app:compileDebugKotlin :app:compileDebugUnitTestKotlin --stacktrace`, `./gradlew --no-daemon :app:assembleDebug :app:testDebugUnitTest --stacktrace`, and `./gradlew --no-daemon :app:lintDebug :app:assembleRelease --stacktrace` passed on 2026-05-22. The build reports a non-blocking deprecation warning for Compose `LocalLifecycleOwner`.
- [x] Closed platform metadata parity after audit: AndroidManifest and resources now cover the iOS `cashu:` URL scheme, app label/application ID, camera/NFC permissions and optional hardware features, secure-storage/database backup exclusions, black/white accent resources, and adaptive launcher icons.
- [x] Closed `WalletServiceProtocol.swift` parity: Kotlin now has the root wallet protocol plus service-level `MintServiceProtocol`, `TokenServiceProtocol`, `TransactionServiceProtocol`, and `QuoteServiceProtocol` contracts using app-domain models and no CDK binding types at the UI-facing boundary.
- [x] Verification after wallet service protocol parity: focused `WalletServiceProtocolTest` passed on 2026-05-22.
- [x] Closed `Models.swift` parity: Kotlin now covers payment method values/symbols, payment input parser helpers, validated Bitcoin/on-chain helpers, on-chain explorer observations, mint/quote/melt/send result models, wallet transactions including Cashu request attribution, pending/claimed/restore/token models, token parse convenience, notification-style transaction update signals, and a shared SHA-256 data helper.
- [x] Verification after model parity: focused `ModelsParityTest` and `WalletServiceProtocolTest` passed on 2026-05-22.
- [x] Closed shared component anchors for `AmountEntryView.swift`, `AnimatedBalanceView.swift`, and `LiquidGlassModifiers.swift`: Compose now has shared amount entry, mint picker sheet, token display card, animated balance/amount display, balance card, pending badge, transaction amount view, canvas divider, capsule surface, and liquid-glass-style surface modifiers layered on the existing action buttons and press feedback.
- [x] Verification after shared component parity: `./gradlew --no-daemon :app:compileDebugKotlin :app:compileDebugUnitTestKotlin --stacktrace` passed on 2026-05-22.
- [ ] Camera scanner still requires physical-device validation.

### Phase 5: Hardening and Parity Verification

- [ ] Run feature-by-feature manual test matrix against Swift screenshots and behavior.
- [ ] Run accessibility pass with TalkBack, font scale, dark mode, and reduced motion.
- [ ] Run network failure, mint failure, malformed token, expired quote, and insufficient-balance tests.
- [ ] Verify wallet deletion and restore.
- [ ] Verify NFC on physical Android hardware.
- [ ] Verify camera scanner on physical Android hardware.
- [x] Verify release build with R8 enabled.
- [ ] Document any intentional platform differences.

## Per-File Migration Matrix

Migration type legend:

- `Port`: reimplement behavior in Kotlin/Android.
- `Translate`: convert configuration/resource into Android equivalent.
- `Reference`: keep as planning/design/testing context; do not port to runtime.
- `Asset`: reuse or convert media asset.

Progress column:

- `[ ]`: not implemented or not yet verified.
- `[x]`: Kotlin equivalent exists and has passed the relevant parity checks for that row.

### Root, Product, Design, and Build Files

| Source file | Migration type | Progress | Kotlin target and checklist |
| --- | --- | --- | --- |
| `.gitignore` | Translate | [x] | Android/Kotlin ignore patterns are present for Gradle state, Kotlin caches, Android Studio metadata, local SDK files, build outputs, keystores, heap dumps, and CDK/native intermediates. |
| `README.md` | Reference | [x] | Product setup context is preserved at the root, and `android/README.md` now carries Android build/run instructions, feature state, and CDK dependency notes. |
| `PRODUCT.md` | Reference | [x] | Product positioning and key flow guidance are carried into the Android README, Compose screen copy, feature scope, and quiet wallet-first UI structure. |
| `DESIGN.md` | Reference | [x] | Visual/interaction guidance is represented through `CashuTheme`, shared Compose components, semantic state colors, restrained surfaces, and full-width action hierarchy. |
| `DESIGN.json` | Reference | [x] | Token intent is mapped into Compose color, typography, shape, and button/amount-display components rather than a generated runtime JSON dependency. |
| `Package.swift` | Reference | [x] | SwiftPM dependencies are replaced by the Gradle version catalog, including the CDK Kotlin artifact and Android equivalents for Compose, CameraX, MLKit, ZXing, OkHttp, serialization, and crypto helpers. |
| `Package.resolved` | Reference | [x] | Swift resolved dependency versions were used as source context only; Android runtime dependency versions are owned by `android/gradle/libs.versions.toml`. |
| `button-audit-prompt.md` | Reference | [x] | Button hierarchy guidance is carried into `PrimaryActionButton`, `SecondaryActionButton`, press feedback, and feature screen CTA placement. |
| `button-fixes-prompt.md` | Reference | [x] | Full-width primary and readable secondary CTA states are implemented through shared Compose action button components. |

### Xcode, iOS Config, and Resources

| Source file | Migration type | Progress | Kotlin target and checklist |
| --- | --- | --- | --- |
| `CashuWallet.xcodeproj/project.pbxproj` | Reference | [x] | Bundle/app identity, source inventory, resources, entitlements, and dependencies are replaced by Android namespace/applicationId, manifest/resource declarations, mirrored Kotlin sources, and Gradle configuration. |
| `CashuWallet.xcodeproj/project.xcworkspace/contents.xcworkspacedata` | Reference | [x] | Xcode workspace metadata has no Android runtime port; Gradle settings define the Android workspace. |
| `CashuWallet.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | Reference | [x] | Swift resolved dependency versions remain reference-only; Android runtime dependencies are managed by Gradle. |
| `CashuWallet/Info.plist` | Translate | [x] | AndroidManifest app label/application ID, camera permission, NFC permission/feature, and `cashu:` deep-link intent filter are implemented. |
| `CashuWallet/CashuWallet.entitlements` | Translate | [x] | Android NFC permission/optional feature declarations are implemented, and secure wallet data is excluded from Android backup/device-transfer rules. |
| `CashuWallet/Resources/Assets.xcassets/Contents.json` | Translate | [x] | Android resource catalog equivalent exists through light/dark color resources, adaptive launcher icon XML, density launcher PNGs, and Compose theme tokens. |
| `CashuWallet/Resources/Assets.xcassets/AccentColor.colorset/Contents.json` | Translate | [x] | Compose color token and Android light/dark theme accent resources are mapped from the iOS black/white accent definitions. |
| `CashuWallet/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` | Asset | [x] | Converted into Android adaptive foreground mipmaps and launcher density PNG assets. |
| `CashuWallet/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` | Translate | [x] | Android mipmap/adaptive icon metadata equivalent is wired through `mipmap-anydpi-v26/ic_launcher*.xml`. |
| `docs/screenshots/01-launch.png` | Asset | [ ] | Reference screenshot for visual parity and Android README screenshots. |
| `docs/screenshots/02-welcome.png` | Asset | [ ] | Reference onboarding screenshot. |
| `docs/screenshots/03-main-wallet.png` | Asset | [ ] | Reference wallet-home screenshot. |
| `docs/screenshots/04-send-options.png` | Asset | [ ] | Reference send action-sheet screenshot. |
| `docs/screenshots/05-settings.png` | Asset | [ ] | Reference settings screenshot. |
| `docs/screenshots/06-receive-onchain.png` | Asset | [ ] | Reference on-chain receive screenshot. |
| `docs/screenshots/07-send-onchain.png` | Asset | [ ] | Reference on-chain send screenshot. |

### App Entry and Navigation

| Source file | Migration type | Progress | Kotlin target and checklist |
| --- | --- | --- | --- |
| `CashuWallet/App/CashuWalletApp.swift` | Port | [x] | `CashuWalletApplication`, `MainActivity`, dependency initialization, app-level logging, Cashu request listener startup, authenticated-startup pending sent-token checks, Android lifecycle foreground/background listener handling, and `cashu:` intent routing. |
| `CashuWallet/App/ContentView.swift` | Port | [x] | Compose root state switch between loading, onboarding, and authenticated wallet shell, plus one-shot deep-link routing into Receive/Send/Mints tabs and scanner/contactless modal routes. |
| `CashuWallet/Core/Navigation/NavigationManager.swift` | Port | [x] | Navigation Compose route model, scanner/send/receive/mints/contactless routes, `cashu:` deep-link routing, percent-decoding, Cashu token/payment-request routing, invalid-payload rejection, and one-shot navigation events. |

### Models and Core Utilities

| Source file | Migration type | Progress | Kotlin target and checklist |
| --- | --- | --- | --- |
| `CashuWallet/Models/Models.swift` | Port | [x] | Kotlin data classes/enums and helpers cover payment methods/symbols, parser helpers, Bitcoin address validation, on-chain observation/explorer, mint info, quote info, melt result, transactions including Cashu request attribution, pending/claimed tokens, restore result, token info/parse convenience, notifications/events, and shared SHA-256 data hashing. |
| `CashuWallet/Models/CashuRequest.swift` | Port | [x] | Persistent generated Cashu request model with request ID, encoded `creqA`, amount/unit/mints/memo, creation date, received-payment list, total received, and legacy bare-payment-ID fallback. |
| `CashuWallet/Core/AmountFormatter.swift` | Port | [x] | Kotlin amount/fiat formatting, BTC symbol toggle, sat/BTC display, localized number formatting, primary/secondary display helpers, and compact UI amount strings. |
| `CashuWallet/Core/AppLogger.swift` | Port | [x] | Kotlin logging facade over Logcat with wallet, network, security, and UI categories plus privacy-safe message redaction for secret-bearing messages. |
| `CashuWallet/Core/BIP39WordList.swift` | Port | [x] | Android delegates BIP39 word membership and checksum validation to CDK `mnemonicToEntropy`, matching Swift's final validation path; local Kotlin validation gates the current Swift-supported 12/24 word counts. |
| `CashuWallet/Core/HapticFeedback.swift` | Port | [x] | Compose/Android haptic mapping for selection, impact, success, warning, and error states via `View.performHapticFeedback`; shared buttons and scanner success are wired. |
| `CashuWallet/Core/LightningRequestParser.swift` | Port | [x] | Parser for BOLT11/BOLT12/Lightning address/human-readable payment inputs; strip lightning schemes and delegate invoice decode/payment type detection to CDK where possible. |
| `CashuWallet/Core/TokenParser.swift` | Port | [x] | Cashu token and URI extraction, normalization, malformed-token error messages, scanner/deep-link input handling, token preview metadata, and P2PK key extraction. |
| `CashuWallet/Core/PaymentRequestDecoder.swift` | Port | [x] | NUT-18/NUT-26 payment request decoder wrapper, summary domain model, raw/cashu/bitcoin URI support including `lightning`, `lightninginvoice`, and `creq` query extraction, amount-lock detection, type labels/icons, short representations, and Cashu-vs-Lightning precedence. |
| `CashuWallet/Core/PaymentRequestBuilder.swift` | Port | [x] | NUT-18 `creqA` request builder for receive-side Cashu request generation, including nprofile TLV encoding, deterministic minimal CBOR payloads, base64url encoding, amount/unit/single-use/mints/description fields, and builder errors. |
| `CashuWallet/Core/PriceService.swift` | Port | [x] | Coinbase BTC spot-price fetch, currency cache, refresh interval, enabled/currency settings, error handling. |
| `CashuWallet/Core/MintDiscoveryManager.swift` | Port | [x] | Nostr relay mint discovery, kind `38172` parsing, discovered mint model, duplicate filtering, loading state, WebSocket-disabled UI error, and explicit socket cleanup. |
| `CashuWallet/Core/NostrService.swift` | Port | [x] | Seed-derived/custom Nostr key management, Bech32 npub/nsec, exact NIP-98 auth header serialization/signing, relay settings, secure secret storage, reset-to-seed behavior. |
| `CashuWallet/Core/NostrInboxClient.swift` | Port | [x] | OkHttp WebSocket relay inbox client for kind `1059` subscriptions with `#p` pubkey filters, relay reconnect, close cleanup, and parsed event delivery. |
| `CashuWallet/Core/NIP44.swift` | Port | [x] | NIP-44 v2 encrypt/decrypt helpers using secp256k1 ECDH, HKDF/HMAC-SHA256, padding, and ChaCha20 payload encryption with unit-tested round trips. |
| `CashuWallet/Core/NIP17.swift` | Port | [x] | NIP-17 gift-wrap unwrap support, including outer gift-wrap decryption, seal decryption, rumor parsing, and recipient validation. |
| `CashuWallet/Core/CashuRequestListener.swift` | Port | [x] | Android foreground listener for Cashu payment requests: relay subscription, NIP-17/NIP-44 unwrap, NUT-18 payload-to-token conversion, duplicate request tracking, and `WalletManager` payment handoff. |
| `CashuWallet/Core/CashuRequestStore.swift` | Port | [x] | Receive-side generated Cashu request store with current request ID, persisted request list, create/delete lookup, received-payment attachment, legacy JSON compatibility, and wallet-boundary clearing. |
| `CashuWallet/Core/NPCService.swift` | Port | [x] | npub.cash client lifecycle, lightning address, selected mint, automatic/manual quote claim, polling preferences, locked quote P2PK spending conditions, processed quote handling, reset boundary. |

### Protocols, Stores, and Secrets

| Source file | Migration type | Progress | Kotlin target and checklist |
| --- | --- | --- | --- |
| `CashuWallet/Core/Protocols/CurrencyProtocol.swift` | Port | [x] | Kotlin interface/value helpers for amount display and fiat currency handling, including SAT/USD/EUR currency definitions, currency amount formatting, and mint-unit lookup. |
| `CashuWallet/Core/Protocols/PaymentMethodProtocol.swift` | Port | [x] | Kotlin payment rail interface, request/result/status value types, expiry/status helpers, and BOLT11/BOLT12/on-chain method capability/icon/label helpers. |
| `CashuWallet/Core/Protocols/StorageProtocol.swift` | Port | [x] | Kotlin storage interfaces, DataStore adapter, secure storage interface, `StorageKeys`, legacy key migration, prefix deletion, and `wallet.processedCashuRequests` tracking are implemented with instrumentation coverage for migration/clearing/secure storage. |
| `CashuWallet/Core/Protocols/WalletServiceProtocol.swift` | Port | [x] | Kotlin domain interfaces for root wallet operations, mint management, ecash token operations, transaction history, and quote/melt operations consumed by ViewModels/features, using app-domain models rather than CDK binding types. |
| `CashuWallet/Core/KeychainService.swift` | Port | [x] | Android secure storage exists through `AndroidSecureStorage` using AndroidKeyStore AES/GCM plus ciphertext preferences, with save/load/delete instrumentation coverage and Swift-compatible mnemonic/Nostr key convenience helpers. |
| `CashuWallet/Core/WalletStore.swift` | Port | [x] | Wallet-scoped DataStore repository for mints, pending tokens, saved tokens, preimages, fees, timestamps, processed NPC quote IDs, and processed Cashu request IDs; existing SharedPreferences data migrates through `SharedPreferencesMigration`. |
| `CashuWallet/Core/SettingsStore.swift` | Port | [x] | DataStore-backed settings repository with defaults, price cache migration, wallet-scoped clearing, NWC/P2PK legacy-secret parsing, metadata-only persistence, and test-isolated store-name support. |
| `CashuWallet/Core/SettingsManager.swift` | Port | [ ] | Settings ViewModel/domain manager: fiat currencies, relays, NWC connection generation, P2PK key generation/import/delete/used-count tracking, legacy secret migration into encrypted storage, metadata-only serialization, reset wallet-scoped data. Broader settings parity remains open around NPC live behavior and full runtime integration. |

### Wallet Domain Services

| Source file | Migration type | Progress | Kotlin target and checklist |
| --- | --- | --- | --- |
| `CashuWallet/Core/WalletManager.swift` | Port | [ ] | Main domain orchestrator. Must cover initialization, transactional create/restore/delete with rollback, DB path migration/recovery, Nostr/NPC setup, mint access, balance refresh, all quote/token/payment operations, pending sync, transaction loading, mnemonic validation, and error mapping. Android now includes onboarding-specific wallet initialization/completion and restore-from-mint tracking/refresh behavior; shared mint URL input helpers live in `Core/MintUrlInput.kt`. |
| `CashuWallet/Core/Services/MintService.swift` | Port | [ ] | Mint add/remove/load/active selection, mint info refresh, supported methods/units extraction, raw on-chain confirmation fetch, balance updates. |
| `CashuWallet/Core/Services/LightningService.swift` | Port | [ ] | Mint quote creation/check/mint, BOLT11/BOLT12/on-chain melt quotes, human-readable quote, quote subscription with polling fallback, quote persistence/metadata preservation, BOLT12 sentinel/duplicate guards, stale reservation cleanup, state mapping, on-chain network detection. BOLT11/BOLT12 melt, Lightning address melt, Swift-parity first-option on-chain melt, and BOLT12/on-chain receive quote subscriptions with polling fallback are implemented; broader live integration remains open. |
| `CashuWallet/Core/Services/TokenService.swift` | Port | [ ] | Ecash send/receive, token decode/value, receive-fee calculation, spendability check, P2PK pubkey normalization, missing-key errors, signing with local P2PK keys, key usage marking. |
| `CashuWallet/Core/Services/TransactionService.swift` | Port | [ ] | Transaction aggregation, pending and claimed token persistence, CDK transaction list merge, BOLT12 duplicate suppression, quote/preimage/fee/timestamp metadata, on-chain observations, update events. Pending/claimed token persistence, pending receive token history rows, CDK transaction merge, mint quote fallback rows, stored melt quote fallback rows, BOLT12 duplicate suppression, quote timestamp pruning, quote-ID melt preimage/fee persistence, on-chain explorer observations, transaction update signals, and transaction enrichment are implemented; live explorer/device validation remains open. |
| `CashuWallet/Core/Services/NDEFTextRecordCoder.swift` | Port | [x] | Android NDEF text record encoder/decoder with language-code/status-byte parity, NFC URI prefix decoding, external/media UTF-8 payloads, and raw UTF-8 fallback. |
| `CashuWallet/Core/Services/NFCPaymentService.swift` | Port | [x] | Contactless payment state machine: read request, prepare token, write token, route CReq/Cashu payment requests and BOLT11 requests from supported URI forms, preserve current non-sat/no-matching-mint/insufficient-balance errors. Physical session validation remains open in hardening. |
| `CashuWallet/Core/Services/NFCReaderDelegate.swift` | Port | [x] | Android NFC callback/session adapter using ReaderMode and NDEF tech APIs. NDEF message decoding plus Contactless ReaderMode lifecycle are implemented; physical tag-session validation remains open in hardening. |
| `CashuWallet/Core/Services/ContactlessPaymentCoordinator.swift` | Port | [x] | Android contactless orchestration is split across `ContactlessPayView`, `NFCPaymentService`, and `NFCReaderDelegate`: ReaderMode lifecycle, read/prepare/write status, Lightning routing, and success/error state are implemented. Physical tag-session validation remains open in hardening. |

### Shared Compose Components

| Source file | Migration type | Progress | Kotlin target and checklist |
| --- | --- | --- | --- |
| `CashuWallet/Views/Components/ActivityOrbView.swift` | Port | [x] | Compose `ActivityOrbView`, `LoadingSpinnerView`, and `MutexLockOverlay` equivalents with accessibility descriptions. |
| `CashuWallet/Views/Components/AmountEntryView.swift` | Port | [x] | Shared Compose amount entry, mint selector row, mint picker sheet, send/receive amount entry surface, and token display card components are implemented. |
| `CashuWallet/Views/Components/AnimatedBalanceView.swift` | Port | [x] | Animated balance, animated amount display, balance card, pending badge, and transaction amount components are implemented in Compose. |
| `CashuWallet/Views/Components/EcashIcon.swift` | Port | [x] | Compose Material icon components for ecash and lightning. |
| `CashuWallet/Views/Components/ErrorBannerView.swift` | Port | [x] | Compose error/warning/info banner component with optional dismiss action. |
| `CashuWallet/Views/Components/LiquidGlassModifiers.swift` | Port | [x] | Compose design-system modifiers/styles cover primary/secondary buttons, press feedback, liquid-glass-style surfaces, full-width capsule surface, canvas dividers, and quiet cards while preserving behavior rather than iOS-only APIs. |
| `CashuWallet/Views/Components/NotificationBadgeView.swift` | Port | [x] | Compose notification badge component with amount/fee formatting and dismiss action. |
| `CashuWallet/Views/Components/PressableButtonStyle.swift` | Port | [x] | Compose press interaction source and scale feedback; existing primary/secondary buttons are wired through it. |
| `CashuWallet/Views/Components/QRCodeView.swift` | Port | [x] | Static QR rendering, animated `ur:bytes` frames, speed/size controls, static-only mode, and fallback when UR encoding is unavailable. |
| `CashuWallet/Views/Components/ScannerWrapperView.swift` | Port | [ ] | Camera scanner screen, scanner ViewModel, QR routing, UR reassembly, inline callback mode, Cashu payment request pay screen, authorizing overlay handoff. Static QR routing to receive/send/mints is implemented, including Cashu payment requests, field-specific scanner callbacks, HTTPS mint URL fallback, and animated UR reassembly; dedicated payment-request pay screen and authorizing overlay handoff remain open. |

### Main, Onboarding, History, and Mints UI

| Source file | Migration type | Progress | Kotlin target and checklist |
| --- | --- | --- | --- |
| `CashuWallet/Views/Main/MainWalletView.swift` | Port | [ ] | Wallet shell, balance card, quick actions, bottom tabs, active mint display, pending indicators, refresh behavior. |
| `CashuWallet/Views/Main/OnboardingView.swift` | Port | [ ] | Welcome, create, seed display, word verification, restore phrase input, recommended/custom mints, restore progress and summary. Welcome, create mnemonic display, full-phrase confirmation, restore phrase input, restore word-count gating, recommended/custom first-mint setup, mint URL paste/normalization, two-phase restore, per-mint restore progress, and recovered/pending summary are implemented; visual parity and screenshot/device review remain open. |
| `CashuWallet/Views/History/HistoryView.swift` | Port | [ ] | Transaction list, filters/sections, pending refresh, empty/loading/error states. Transaction list, filters, date sections, pagination, empty/loading/error states, pull-to-refresh, pending refresh on entry, pending sent-token status checks, pending mint quote refresh, status/amount rows, and expandable details are implemented; screenshot/device polish remains open. |
| `CashuWallet/Views/History/TransactionDetailView.swift` | Port | [x] | Transaction detail, QR/copy/share, mint/quote/preimage/fee/explorer fields. Android now supports both expandable row details and a standalone full-detail dialog opened from History, with pending refresh, QR/copy/share, and explorer actions. Screenshot/device polish remains part of hardening. |
| `CashuWallet/Views/Mints/MintsListView.swift` | Port | [ ] | Mint list, add/discover/set-active/remove, balances, method chips, loading/error states. Android now includes shared mint URL normalization, scanner handoff normalization, paste-from-clipboard, clipboard suggestion, copy/share actions for configured and discovered mint URLs, active mint indication, method chips, scrolling, remove confirmation, and a mint detail dialog; richer loading/error polish remains open. |
| `CashuWallet/Views/Mints/MintDetailView.swift` | Port | [x] | Mint info detail dialog with URL copy/share, balance, units, supported receive/send methods, description, icon URL, and on-chain confirmations. |
| `CashuWallet/Views/Mints/MintDiscoverySheet.swift` | Port | [ ] | Discover mints sheet with WebSocket-required empty state, search, added/discovered sections, pull-to-refresh, per-session added animation, and clear-on-dismiss behavior. Android has inline Nostr discovery rows in `MintsListView`, but standalone searchable sheet parity remains open. |

### Receive UI

| Source file | Migration type | Progress | Kotlin target and checklist |
| --- | --- | --- | --- |
| `CashuWallet/Views/Receive/ReceiveView.swift` | Port | [ ] | Receive entry sheet, receive ecash flow, amount entry, method selection, scanner/paste actions. Cashu-token clipboard auto-paste/suggestion and receive-side Cashu request creation/detail card are implemented. |
| `CashuWallet/Views/Receive/ReceiveTokenDetailView.swift` | Port | [ ] | Token preview, fee estimate, P2PK warning, receive now/later, success state. Preview, fee estimate, spendability status, P2PK unknown-key guard, receive-later persistence, pending claim, remove actions, and receive success badge/haptics are implemented; standalone receive-token sheet polish remains open. |
| `CashuWallet/Views/Receive/ReceiveLightningView.swift` | Port | [ ] | BOLT11/BOLT12/on-chain receive, method picker, quote/address display, QR, copy/share, expiry countdown, status polling/subscription, mint success. BOLT11, BOLT12 amountless/fixed entry, on-chain quote entry, quote display/copy/share/QR, expiry countdown, manual status refresh, BOLT12/on-chain quote subscriptions, polling fallback, paid-quote mint action, and success badge/haptics after minting are implemented; broader richer mint-success parity remains open. |
| `CashuWallet/Views/Receive/CashuRequestDetailView.swift` | Port | [x] | Receive-side Cashu request QR/detail sheet with static QR, share/copy, waiting/received status, payment-received success badge/haptics, editable mint/amount rows, regenerate-new-request action, delete action, and payment attachment display. |
| `CashuWallet/Views/Receive/CashuRequestAmountPickerSheet.swift` | Port | [x] | Amount picker sheet for generated Cashu requests using the shared number pad and fiat/sat display, including nil/any-amount behavior. |
| `CashuWallet/Views/Receive/CashuRequestMintPickerSheet.swift` | Port | [x] | Mint picker sheet for generated Cashu requests, including any-mint option, configured mint list, balances, icons, and selected checkmark. |

### Send and Pay UI

| Source file | Migration type | Progress | Kotlin target and checklist |
| --- | --- | --- | --- |
| `CashuWallet/Views/Send/SendView.swift` | Port | [ ] | Send ecash, P2PK lock UI, pending claim polling/manual check, melt/pay flows, clipboard chip, recent recipients, payment request flows, compatible/affordable mint selector, quote confirmation, authorizing overlay, share sheets, invoice/address prefilled variants. Selected mint send, token QR/copy/share, digit-only amount keypad, basic use-max fill, P2PK lock input, stored-key picker, pending sent-token status checks, reclaim, removal, payment-request clipboard suggestion, recent recipients, Lightning address/on-chain amount-gated quote creation, Swift-parity first-option on-chain quote selection, Cashu request compatible-mint selection, and send/payment authorizing overlay are implemented; broader send parity remains open. |
| `CashuWallet/Views/Send/Components/AuthorizingOverlay.swift` | Port | [x] | Compose authorizing overlay with progress, success/error states, amount display, haptics, and auto-dismiss for send/payment actions. |
| `CashuWallet/Views/Send/Components/ClipboardPaymentChip.swift` | Port | [x] | Shared Compose clipboard suggestion chip with Android clipboard reads. |
| `CashuWallet/Views/Send/Components/CurrencyAmountDisplay.swift` | Port | [x] | Reusable Compose fiat/sat amount component with settings-driven primary display, fiat fallback, secondary flip control, and Swift-style sat `₿` formatting. Wallet balance uses it now; additional send/pay screen adoption remains part of broader send/pay parity. |
| `CashuWallet/Views/Send/Components/NumberPadAmountInput.swift` | Port | [x] | Compose numeric keypad with digit rows, delete, long-press clear, stable 56dp keys, and haptics. Decimal is intentionally absent because Swift's current component is digit-only for sats. |
| `CashuWallet/Views/Send/Components/RecentRecipientsList.swift` | Port | [x] | Recent recipient display and selection derived from outgoing Lightning/on-chain transactions; no additional persistence. |

### Settings UI

| Source file | Migration type | Progress | Kotlin target and checklist |
| --- | --- | --- | --- |
| `CashuWallet/Views/Settings/SettingsView.swift` | Port | [ ] | Settings root, sections, QR detail sheet, backup view, import P2PK/nsec sheets, and mint picker sheet. Android currently exposes payment request enable/auto-receive controls from stored keys, but the tracked Swift settings UI has no separate Payment Requests section, so that UI parity needs review. |
| `CashuWallet/Views/Settings/AdvancedSettingsSection.swift` | Port | [x] | Advanced delete-wallet control with destructive styling, confirmation dialog, local failure display, and `WalletManager.deleteWallet()` integration. No additional log/debug controls are present in the audited Swift section. |
| `CashuWallet/Views/Settings/BackupSettingsSection.swift` | Port | [x] | Seed backup access, warning states, secure copy behavior. |
| `CashuWallet/Views/Settings/LightningAddressSettingsSection.swift` | Port | [ ] | npub.cash Lightning address/NPC settings UI. |
| `CashuWallet/Views/Settings/NWCSettingsSection.swift` | Port | [x] | NWC enable/create/list/copy/QR/remove UI with allowance and relay fields. |
| `CashuWallet/Views/Settings/NostrSettingsSection.swift` | Port | [x] | Nostr keys and relay sections, nsec import/reset/copy, relay add/remove/default reset. |
| `CashuWallet/Views/Settings/P2PKSettingsSection.swift` | Port | [x] | P2PK drawer toggle, key generation/import/list/copy/delete. |
| `CashuWallet/Views/Settings/PrivacySettingsSection.swift` | Port | [x] | Clipboard, pending-check, incoming-invoice, WebSocket privacy toggles. |
| `CashuWallet/Views/Settings/ThemeSettingsSection.swift` | Port | [x] | Display settings include BTC symbol, fiat balance enablement, currency selector, price status/refresh, and fiat/sats primary amount selection. |

## Test Plan

- [ ] Unit tests for amount formatting, token parsing, payment request decoding including `bitcoin:` query params, Lightning/on-chain input parsing, Bitcoin address validation, BIP39 validation, Bech32, P2PK normalization/signing-key matching, and error mapping.
- [ ] Storage tests for every key, default, legacy-key migration, wallet-scoped clearing, and secure secret delete/load behavior. Android now has instrumentation coverage for representative wallet/settings SharedPreferences-to-DataStore migration, Cashu request persistence/current ID wallet-boundary clearing, and secure storage save/load/delete behavior; exhaustive every-key and rollback coverage remains open.
- [ ] Storage rollback tests for failed wallet create/restore and database sidecar backup/restore.
- [ ] CDK gateway tests for wallet create/restore, mint add, quote create/check/mint, quote DB operations, token send/receive/P2PK helpers, melt, payment request pay, list transactions, and subscription fallback.
- [ ] ViewModel tests for onboarding, receive, send, contactless, history, mint, settings, NPC, Nostr, NWC, and P2PK flows.
- [ ] Compose screenshot tests for launch, onboarding, wallet, send options, settings, receive on-chain, send on-chain, token receive, transaction detail, and scanner error.
- [ ] Device tests for camera scanner, NFC read/write, deep links, clipboard, share, haptics, dark mode, font scale, and offline/network-change behavior. DataStore/secure-storage instrumentation passed once on `SM-G991B - 15`; camera/NFC and the broader hardware matrix remain open, and the latest retry was blocked by no connected adb devices.
- [ ] Release tests with R8 enabled and all supported ABIs.

## Risks and Open Questions

- [ ] CDK Kotlin API names and availability may not match cdk-swift one-to-one. Resolve in Phase 0 and keep the gateway as the compatibility layer.
- [ ] CDK Kotlin newest indexed release may lag CDK core. Decide whether to pin stable, RC, or wait for a binding release matching the Swift feature set.
- [x] Animated QR/UR is not a CDK core feature; Android now uses `com.gorunjinian:bcur-kotlin` for Swift-compatible BC-UR encode/decode behavior.
- [ ] Android secp256k1/Schnorr key generation must exactly match P2PK/Nostr expectations. Verify library output against Swift fixtures.
- [ ] NFC behavior is hardware-dependent and must be verified on physical devices.
- [ ] Android clipboard privacy differs from iOS. Auto-paste should be permission-aware and minimally invasive.
- [x] `checkPendingOnStartup` and NWC include settings beyond currently visible runtime processing. Preserve Swift parity and document future service work separately. Payment Request listener runtime is now implemented; receive-side request generation and settings-UI parity remain tracked separately.
- [ ] iOS Liquid Glass has no Android equivalent. Compose should preserve hierarchy, contrast, motion, and spacing rather than mimicking implementation details.

## Definition of Done

- [ ] Every `Port` file in the matrix has a Kotlin/Android equivalent.
- [ ] Every `Translate` file has an Android config/resource equivalent.
- [ ] Every `Reference` file has either influenced implementation guidance or is explicitly marked not applicable.
- [ ] Every feature checklist item is complete or has a documented, approved platform difference.
- [ ] CDK Kotlin integration passes wallet create/restore/send/receive/mint/melt/payment-request test flows.
- [ ] Android app passes manual parity review against the Swift app's current screenshots and behavior.
- [ ] No secrets are stored outside encrypted storage.
- [ ] Release build runs with R8 enabled.
