# iOS wallet correctness review

Date: 2026-09-05

This pass concentrates on payment correctness, asynchronous UI state, mint identity,
stored currency accounts, and wallet replacement. It keeps the existing native
SwiftUI interface and service architecture. It is not an exhaustive security audit
or a claim that every function and hardware flow has been verified.

## Changes

| Area | Problem | Result |
| --- | --- | --- |
| Mint recovery | Retrying a reserved quote could delete CDK's recovery operation and clear its reservation. | CDK recovery runs first. An unresolved reservation or failed reload blocks another mint attempt. Recovered amounts are returned without another issuance attempt. |
| Quote persistence | A stale quote could overwrite its reservation; the fallback deleted the stored row before attempting another insert. | Stale versions and reservation mismatches are rejected. Persistence never removes a quote to force an update. |
| Receive confirmation | A paid Lightning invoice produced a success receipt before ecash issuance completed. | The receipt waits for issuance. Unknown receive fees remain unavailable with a retry action, and cannot be silently presented as free. |
| Fee arithmetic | Mint-supplied fee totals and NWC limit conversion could overflow. | Checked arithmetic rejects invalid totals. Receive fees are summed across inputs and rounded once, with one lookup per keyset. |
| Mint selection | URL normalization collapsed path boundaries and ignored schemes; onchain receive could use the mutable active mint. | Shared URL identity preserves scheme and path boundaries. Onchain requests and address reuse honor the requested mint. Selecting a removed mint is rejected. |
| Async presentation | Old quote requests could replace newer choices; truncated payload IDs could reuse the wrong SwiftUI state. | Quote tasks are cancelled when superseded, and stale results are ignored. Payment presentation IDs hash the complete payload. Confirmed payments retain their own lifetime. |
| Stored accounts | Advertised mint units determined which balances, history, and pending operations were read. | Existing repository accounts determine the work, including currencies no longer advertised by the mint. Failed balance reads preserve the last complete unit total. Startup recovery covers those accounts too. |
| Wallet boundaries | Create, restore, and delete could overlap queued work holding the previous repository. | Listener and NWC work are drained before the boundary operation; queued operations are cancelled while replacement holds the repository lease. Quote polling is reset and restarted after onboarding. |
| NWC lifecycle | Reentrant start/stop calls could install stale services or discard configuration changes. | Lifecycle calls are serialized, with revision checks after suspension points. Late startup failures do not overwrite a newer disabled state. |
| SQLite teardown | The integration test exposed a crash when CDK's native writer released the final SQLite callback reference. | A small database subclass retains the native runtime through superclass destruction and releases the final owner on a Dispatch worker outside Tokio. Both repository construction paths use it. |
| Cleanup | Two unused protocol files described interfaces that no longer matched the app; URL and migration logic was duplicated. | Dead protocols and their Xcode entries were removed. Shared identity and transactional file-migration helpers replace the copies. |

The database lifetime adapter is specific to CDK 0.18.0-rc.3. Its
[SQLite FFI object](https://github.com/cashubtc/cdk/blob/v0.18.0-rc.3/crates/cdk-ffi/src/sqlite.rs)
owns a [RuntimeGuard](https://github.com/cashubtc/cdk/blob/v0.18.0-rc.3/crates/cdk-ffi/src/runtime.rs).
Revisit the adapter when upgrading to a version that supports destroying an owned
runtime from an asynchronous native callback. The fix preserves the iOS 18.0 target.

## Validation

- Final complete unit-test run: **564 passed, 1 skipped, 0 failed**.
- Selected UI coverage: **10 passed**, covering main tabs, receive entry points,
  settings, restore-mint staging, and both onboarding completion paths. The two
  onboarding integration tests were rerun after the database lifetime change.
- Added **14 regression tests**, including a real Lightning receive against the
  local Nutshell mint after switching the active mint, database reservation
  preservation, teardown, NWC cancellation, fee errors, and queued-operation cancellation.
- Tests used an isolated iOS 26.5 simulator, ad-hoc signing for Keychain access,
  and the repository's local CDK and Nutshell test servers.
- `git diff --check` passed.

The existing skipped case is
`ScanRouterTests.testCashuRequestBolt11FallbackRoutesToMeltWithExplanation`.

## Remaining review areas

- Seed-only NUT-09 restore still reconstructs sat accounts. Restoring other
  currencies needs corresponding restore results and onboarding presentation;
  this pass improves recovery of accounts already stored locally.
- Biometric locking over presented sheets and app-switcher snapshots needs
  explicit device validation. The current root-overlay implementation was not
  replaced in this pass.
- Native long-lived payment watchers, deletion failure rollback, real NWC relays,
  NFC hardware, and iCloud account/device recovery still need dedicated fault
  and device testing.
- Android was not changed. Equivalent payment, recovery, fee, and URL-identity
  behavior should be checked there before claiming cross-platform parity.
