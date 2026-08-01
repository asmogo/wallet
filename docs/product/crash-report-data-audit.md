# Crash-report data audit

Last audited: 2026-08-01

Crash reporting is opt-in and off by default on both platforms. Enabling it starts Sentry;
disabling it closes the SDK. Both SDK configurations disable default PII collection,
screenshots, and view-hierarchy attachments, and enable session tracking and 10% performance
trace sampling.

## iOS inventory

- Explicit captures: wallet load/creation failure, wallet deletion failure, and Nostr-NPC
  quote failure. These errors now cross `CrashReportSanitizer`, which keeps the error type and
  code but discards arbitrary `NSError.userInfo` and redacts the description.
- Explicit breadcrumbs: token sent/received; mint added/restored/removed; wallet
  loaded/created/restored/deleted; Lightning mint, send, and asynchronous settlement states;
  and Nostr-NPC quote minting. These are static action labels without amounts, token material,
  quote IDs, mint URLs, or addresses. The Sentry boundary still sanitizes every explicit
  breadcrumb message.
- SDK diagnostics: unhandled crash diagnostics, automatic SDK breadcrumbs, session state, and
  sampled performance traces may be collected while reporting is enabled. They are not covered
  by a promise of anonymity or of containing no personal data.

## Android inventory

- Explicit captures and wallet breadcrumbs: none currently emitted by production call sites.
  `SentryService.capture` and `breadcrumb` remain sanitized and tested boundaries for future
  call sites.
- SDK diagnostics: unhandled crash diagnostics, automatic Android/Sentry breadcrumbs, session
  state, and sampled performance traces may be collected while reporting is enabled. They are
  not covered by a promise of anonymity or of containing no personal data.

## Redaction contract

The shared platform policy redacts known high-risk values from explicit wallet captures and
breadcrumbs: Nostr private keys, Nostr Wallet Connect URIs, Cashu tokens and requests,
Lightning payment payloads, Bitcoin URIs and addresses, email/Lightning addresses, HTTP(S)
URLs, local filesystem paths, and values labeled as mnemonic, seed phrase, private key, or
secret. Tests on both platforms cover the crash-report boundary and these payload classes.

The Settings text deliberately promises only enforced SDK configuration: reporting is opt-in,
screenshots and view hierarchy are not attached, and reports can include technical error details
and recent wallet actions.
