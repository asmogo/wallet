# iOS and Android Wallet Parity Checklist

Code-audit baseline: 2026-07-29. Reworked and revalidated: 2026-07-30.

This checklist tracks verified differences in cross-platform product behavior. The iOS implementation is the default reference for what the product does; the [Android design charter](../android/DESIGN-ANDROID.md) remains authoritative for how Android looks, moves, and feels.

Parity means the same user outcome, safety guarantees, data correctness, capability, and accessible meaning. It does **not** require identical layouts, controls, gestures, animations, navigation chrome, copy capitalization, punctuation, or feedback timing.

Directions:

- **iOS → Android** — bring the verified iOS product behavior to Android using native Android patterns.
- **Android → iOS** — bring the verified Android product behavior to iOS using native iOS patterns.
- **Converge** — neither implementation is the complete rule; adopt one shared product contract.
- **Product decision** — choose and document the shared rule before implementation.

Priorities describe user impact, not the kind of work:

- **P0** — security, identity loss, wallet lockout, payment correctness, or potential loss/confusion around funds.
- **P1** — missing functionality, incorrect or materially misleading state, or an accessibility blocker in a core flow.
- **P2** — non-blocking context, copy, discoverability, feedback, or accessibility refinement.

An item is complete only when the behavior is verified on both platforms, including relevant loading, empty, error, and assistive-technology states. Add automated coverage where the rule can regress below the UI; otherwise record reproducible manual evidence.

Platform-specific capabilities remain intentionally outside parity, including iCloud backup, Android host-card-emulation for NFC receive, native biometric presentation, system back/swipe conventions, and platform-native sheet or navigation treatment.

## Required parity

### App shell and Wallet home


- [x] **[P1 · iOS → Android] Honor the preferred primary balance unit on Wallet home.** Android always constructs the home balance with sats as the primary value, even when the user selected fiat; iOS uses `amountDisplayPrimary`. Neither Home implementation currently offers an amount-flip control. **Done when:** Android opens with the saved sats/fiat preference and its visible and accessibility values consistently reflect that preference. A Home-specific flip interaction, if desired, is a separate product decision.

- [x] **[P1 · iOS → Android] Gate payment actions on wallet runtime readiness.** iOS shows “Preparing wallet…” and disables Receive/Send until the runtime is ready; Android enables them based on mint presence alone. **Done when:** Android exposes a preparation state and cannot enter a money-moving flow before the runtime is ready.

- [x] **[P1 · Android → iOS] Add the no-mint Wallet empty state and CTA.** Android explains that a mint is needed and provides “Add mint”; iOS shows the generic “No Activity Yet” state even when no mint exists. **Done when:** iOS distinguishes “no mint” from “no activity” and links directly to mint setup.

- [x] **[P1 · iOS → Android] Keep Receive usable without an active mint.** iOS can create an any-mint Cashu Request without an active mint; Android disables Receive on Home and pins new requests to the active mint. **Done when:** Android allows the any-mint ecash receive path without a mint while clearly disabling or explaining receive methods that truly require one.

- [x] **[P1 · iOS → Android] Drive the received-amount beat from an explicit receive event.** Android infers a receive from any balance increase, which can show a false `+amount` after a restore, mint operation, or unrelated balance refresh; iOS uses a receipt notification. **Done when:** Android only shows the beat for a confirmed incoming payment and only lets Home own the success haptic for background receipts that have no in-flow confirmation.

- [x] **[P2 · iOS → Android] Add an accessible loading label.** iOS shows “Loading Wallet…” with its progress indicator; Android shows an unlabeled indicator. **Done when:** Android visually or semantically identifies the startup operation as loading the wallet.

- [x] **[P2 · Converge] Update Home action hints for the unified flows.** iOS accessibility hints still describe opening “options” for ecash and Lightning even though the buttons now open unified Send/Receive surfaces; Android exposes only the button names. **Done when:** both platforms describe the actual destination and supported inputs without referring to a retired chooser.

### Send — unified destination and payment flow

- [ ] **[P1 · iOS → Android] Support fiat-primary amount entry.** iOS converts keypad input according to the saved sats/fiat primary setting; Android’s unified Send amount step always interprets the input as sats. **Done when:** Android entry, Send Max, validation, and amount presentation honor the selected primary unit without changing the sat amount being paid.

- [x] **[P1 · iOS → Android] Honor the preferred unit on payment confirmation.** Android confirmation renders a fixed sat string; iOS keeps the saved primary value and alternate conversion available. **Done when:** Android confirmation leads with the persisted primary unit and makes the alternate value available visually and to accessibility services through a native Android presentation. An identical iOS flip control is not required.

- [ ] **[P1 · iOS → Android] Show the Cashu Request fee estimate before payment.** iOS calculates the input fee and shows loading, no-fee, amount, or unavailable state; Android omits a fee row from Cashu Request confirmation. **Done when:** Android reserves and fills a fee row before the Pay action and does not present an unknown estimate as zero.

- [x] **[P1 · iOS → Android] Preserve relevant payment facts through terminal states.** Android’s processing, success, and failure screen can drop facts shown during confirmation. **Done when:** each rail has a documented stable row set across processing, success, and failure: amount and method; mint when applicable; destination for on-chain; network/input fees when applicable; and Cashu Request memo, route, or fee context when applicable.

- [ ] **[P1 · Android → iOS] Explain rail-changing fallback and recovery routes.** Android explicitly identifies Lightning fallback, adding a requested mint, or topping up the target mint; iOS can rely only on a mint row or CTA wording. **Done when:** iOS names a route whenever it materially changes how the request will be paid or what recovery will occur. The ordinary compatible-mint route does not need a duplicate “Pay from” label.

- [ ] **[P2 · Converge] Remove platform names from payment warnings.** Android says “supported on Android” and “Android can pay…” while iOS says “this wallet.” **Done when:** shared limitations and fallback messages use product language and equivalent terminology on both platforms.

### Send — ecash and locked ecash

- [ ] **[P1 · iOS → Android] Support fiat-primary entry when creating ecash.** iOS allows sat-denominated ecash to be entered in the preferred fiat unit; Android’s ecash keypad always uses sats. **Done when:** Android entry, validation, Send Max, and the generated amount honor the saved primary unit.

- [ ] **[P1 · iOS → Android] Add scanning for a P2PK recipient key.** iOS can scan a public key and validate it before locking; Android only provides manual entry and “Lock to my key.” **Done when:** Android can scan, paste, or type a recipient key through one validation path with equivalent error handling.

- [ ] **[P2 · iOS → Android] Show a clear confirmed P2PK recipient state.** Android leaves the full technical input field in the amount layout after validation; iOS replaces it with a compact confirmation. **Done when:** Android clearly identifies the validated recipient, distinguishes “your key” where applicable, and provides accessible edit and remove actions. The exact iOS chip treatment is not required.

- [ ] **[P2 · iOS → Android] Replace protocol jargon in lock accessibility copy.** Android announces “P2PK off” and “P2PK locked”; iOS describes the user outcome. **Done when:** Android’s visible and assistive copy leads with “Lock ecash” and the recipient effect, with P2PK only as optional supporting terminology.

- [ ] **[P1 · iOS → Android] Provide manual claim-status checking when automatic checks are disabled.** iOS adds “Check Status” to pending-token actions; Android leaves the token at Pending with no equivalent action. **Done when:** Android users can run a one-off spent check without re-enabling background polling.

- [ ] **[P1 · iOS → Android] Include the send fee on the Claimed receipt.** iOS shows the fee when the token-generation swap charged one; Android’s pending view shows it but the full-screen Claimed terminal drops it. **Done when:** Android’s Claimed details preserve Amount, applicable Fee, and Mint.

### Receive — unified entry and Cashu tokens

- [ ] **[P1 · iOS → Android] Create new ecash requests as any-mint requests by default.** iOS creates a NUT-18 request with no mint restriction; Android silently inserts the active mint, changing who can pay. **Done when:** Android leaves the mint list empty unless the user explicitly selects a mint, and tests cover request creation with and without a restriction.

- [ ] **[P1 · Converge] Use one Nostr-readiness rule and recovery message.** Android requires both a public key and relays and says “check your relays”; iOS checks initialized identity and points broadly to Settings → Nostr. **Done when:** both validate every prerequisite needed for a deliverable request and name the exact setting that needs attention.

- [ ] **[P0 · iOS → Android] Warn before receiving from an unknown mint.** iOS identifies that receiving will add a new mint and asks the user to continue only if they trust it; Android has no equivalent trust warning. **Done when:** Android displays the normalized mint host, explains that the mint will be added, and blocks an accidental one-tap claim.

- [ ] **[P1 · iOS → Android] Show the actual P2PK lock target.** Android uses a generic “Requires your key” row only when the key is not held and hides the row when it is held; iOS identifies the recipient. **Done when:** Android always identifies a locked token’s recipient and clearly distinguishes claimable from unclaimable before the user acts.

- [ ] **[P1 · Android → iOS] Show the token memo during review.** Android includes a Memo row when present; iOS does not. **Done when:** iOS lets the recipient review the sender’s memo before claiming.

- [ ] **[P1 · iOS → Android] Preserve a memo when choosing Receive later.** iOS stores the decoded token memo in the pending receive; Android’s pending-token conversion drops it. **Done when:** the Android History row and later claim retain the original memo.

- [ ] **[P0 · iOS → Android] Report the actually paid receive fee.** iOS derives the final fee from gross token value minus the amount credited; Android carries the preview fee into success even if settlement differs. **Done when:** Android’s receipt reconciles the displayed fee against the credited amount and tests cover a settlement that differs from the preview.

### Receive — Lightning, reusable invoices, on-chain, and Cashu Requests

- [ ] **[P1 · iOS → Android] Support fiat-primary amount entry on Bitcoin receive rails.** iOS lets a sat Lightning invoice be entered in fiat; Android’s receive keypad uses fixed sat entry. **Done when:** Android entry and validation honor the persisted primary display setting without changing the sat-denominated quote.

- [ ] **[P2 · iOS → Android] Honor the preferred unit on generated invoice details.** iOS keeps sats and fiat available under a BOLT11 or fixed BOLT12 QR; Android renders a fixed amount string. **Done when:** Android leads with the saved primary unit and exposes the alternate conversion visually and accessibly through a native presentation.

- [ ] **[P1 · iOS → Android] Make expiry the primary one-shot invoice status.** Android can keep “Waiting for payment” as the main status after expiry while only the small caption says Expired. **Done when:** the primary status, accessibility value, and available actions cannot contradict the expired state.

- [ ] **[P1 · Android → iOS] Add Total received to reusable-invoice details.** Android shows a cumulative total after BOLT12 payments; iOS only changes the status badge. **Done when:** iOS exposes the unit-correct cumulative amount.

- [ ] **[P1 · Android → iOS] Correlate an open Cashu Request success to a new payment record.** Android watches the request’s received-payment IDs; iOS has a fallback that treats any balance increase while the receive sheet is open as payment for that request. **Done when:** iOS cannot show request success for an unrelated balance increase, with regression coverage for concurrent balance changes.

- [ ] **[P2 · Android → iOS] Show Total received in Cashu Request details.** Android adds the aggregate after one or more payments; iOS shows only the status count and original request amount. **Done when:** iOS includes a unit-correct aggregate row without confusing it with the requested amount.

### History and transaction details

- [ ] **[P1 · Android → iOS] Search transaction and request memos.** Android includes memos in History search; iOS searches titles and numeric amounts only. **Done when:** iOS matches memo text case-insensitively for both item types.

- [ ] **[P2 · iOS → Android] Search a Cashu Request’s Total received amount.** iOS includes the aggregate received value in search; Android only searches the requested amount. **Done when:** Android matches both configured and received totals using the same normalized amount formats as other History search.

- [ ] **[P1 · iOS → Android] Explain all consequences of removing a Cashu Request row.** iOS says the QR and pending payment routing remain valid; Android only says received payments stay in the wallet. **Done when:** Android states before deletion that previously received funds remain, the QR and payment routing remain valid, and only the History row is removed.

- [ ] **[P1 · iOS → Android] Add removal for an ordinary parked incoming token.** Android already supports declining a held Cashu Request payment, but it has no equivalent removal for a normal unclaimed token. **Done when:** Android provides a discoverable removal action for ordinary parked tokens and warns that the ecash will be discarded and only the sender can reissue it.

- [ ] **[P2 · iOS → Android] Honor the preferred amount unit in transaction details.** iOS makes sats and fiat available for sat-denominated Lightning/ecash records; Android always displays sats. **Done when:** Android leads with the saved primary setting, exposes the alternate value accessibly, and preserves on-chain and non-sat-unit exceptions.

- [ ] **[P2 · iOS → Android] Announce the active History filter.** iOS exposes the selected filter as an accessibility value; Android’s filter control is announced only as “Filter.” **Done when:** TalkBack reports All, Pending only, or Completed only on the control.

### Mints list, add, and discovery

- [ ] **[P1 · iOS → Android] Add an explicit mint-discovery Retry or Refresh action.** iOS can restart discovery and reload missing previews; Android has no refresh gesture or retry action. **Done when:** Android users can restart discovery without closing the sheet, using a native button or gesture that is visible or accessibly discoverable.

- [ ] **[P2 · Converge] Unify discovery-disabled recovery copy.** iOS says WebSockets are required and points to Settings; Android more usefully names Settings → Privacy. **Done when:** both explain why discovery is off and give the exact setting path.

- [ ] **[P2 · iOS → Android] Make discovery empty states actionable and state-specific.** Android can show “Listening on Nostr…” or “No matches” without distinguishing active discovery, exhausted discovery, and a filtered-zero result. **Done when:** Android identifies the current state, safely repeats the query when applicable, and names the Retry or Refresh action that is actually available.

### Mint details

- [ ] **[P2 · iOS → Android] Show the fiat secondary balance when enabled.** iOS adds the fiat conversion beneath the sat balance; Android shows only sats plus native non-sat-unit balances. **Done when:** Android mirrors the user’s global fiat-balance preference without converting balances whose unit is not sat.

- [ ] **[P1 · iOS → Android] Distinguish cached mint metadata from live refresh state.** Android already shows Checking, Online, and Offline connection states, but it can silently display cached NUT-06 data after a live fetch fails. **Done when:** Android identifies loading or refresh, distinguishes cached/stale content from a successful live response, presents a user-facing failure explanation, and offers Retry where useful.

- [ ] **[P1 · iOS → Android] Add the Contact section.** iOS renders reported email, web, Nostr, Twitter/X, and Telegram contacts with appropriate actions; Android omits them. **Done when:** Android displays every reported contact, labels the remote source, and opens only safely parsed supported targets.

- [ ] **[P1 · iOS → Android] Show reported Terms of Service.** iOS includes the mint’s live Terms link; Android omits it. **Done when:** Android shows a safely parsed external link when reported, clearly identifies the destination, and handles an invalid or absent value without a dead row.

- [ ] **[P2 · iOS → Android] Show reported mint software and version.** iOS includes the live software name/version; Android omits it. **Done when:** Android displays the fields when reported and does not invent placeholders for absent values.

- [ ] **[P2 · iOS → Android] Add the metadata provenance footer.** iOS says “Information reported by the mint”; Android does not identify the source of remote descriptions, contacts, software, or terms. **Done when:** Android includes an equivalent qualification near the metadata.

- [ ] **[P1 · iOS → Android] Preserve and hide absent payment methods.** Android’s domain mapping substitutes BOLT11 when a live NUT-04 or NUT-05 method list is empty, and details always render both directions. **Done when:** Android preserves whether each direction was actually reported, uses compatibility fallback only when metadata is genuinely unknown, and hides a direction the live mint reports as absent.

- [ ] **[P1 · iOS → Android] Surface Set as Default progress and errors.** iOS disables the action, shows progress, and renders an inline failure; Android launches the operation with no visible progress or error. **Done when:** Android prevents duplicate submission and clearly reports success or failure without changing the apparent default on failure.

### Settings — information architecture, display, and destructive actions

- [ ] **[P2 · iOS → Android] Make App Lock discoverable in a security-oriented Settings location.** Android currently places the toggle under Privacy even though it controls local device access. **Done when:** App Lock is discoverable under a clear security or backup-and-security destination while privacy/background networking controls remain conceptually separate. The exact iOS hierarchy is not required.

- [ ] **[P0 · iOS → Android] Authenticate before enabling App Lock.** iOS verifies device-owner authentication and reverts with an error if enabling fails; Android directly persists the toggle. **Done when:** Android cannot enable App Lock until a device-owner challenge succeeds, and cancellation or failure leaves it disabled.

- [ ] **[P1 · iOS → Android] Explain unavailable App Lock and preserve access.** iOS detects the absence of a device passcode, gives setup guidance, and explains that seed reveal always authenticates; Android exposes no equivalent guidance. Android’s manager currently fails open, so this is not an established lockout bug. **Done when:** Android reports capability state, points to device security setup, states the seed-reveal guarantee, and never presents an unavailable lock as active.

- [ ] **[P1 · iOS → Android] Show wallet-deletion failures.** iOS catches deletion errors and displays a banner; Android starts deletion without dedicated error feedback. **Done when:** Android reports failure and leaves the existing wallet state intact and understandable.

- [ ] **[P1 · Android → iOS] Read the app version from build metadata.** Android uses `BuildConfig.VERSION_NAME`; iOS hard-codes `1.0.0`. **Done when:** iOS displays the shipped bundle version and, if included, its build number from metadata.

- [ ] **[P2 · Android → iOS] Add localized currency names.** Android shows the ISO code plus the localized currency name; iOS shows only the code. **Done when:** iOS rows are understandable without memorizing ISO-4217 codes.

- [ ] **[P2 · iOS → Android] Show when the BTC price was last updated.** iOS includes a relative timestamp beside the price; Android omits it. **Done when:** Android exposes recency and handles never-loaded and stale states.

### Settings — privacy and background behavior

- [ ] **[P1 · iOS → Android] Disable periodic invoice checks when incoming checks are off.** Android leaves the child control interactive even though the runtime requires incoming checks before periodic work runs. **Done when:** Android disables the child visually and semantically, preserves its saved preference for later re-enable, and keeps the effective runtime rule as the logical combination of both settings.

- [ ] **[P1 · Android → iOS] Keep WebSockets independent of invoice/token polling.** Android correctly notes that WebSockets also power Nostr discovery; iOS disables the toggle when both incoming-invoice and sent-token checks are off. **Done when:** iOS users can enable discovery and live Nostr features independently.

- [ ] **[P2 · Converge] Align privacy-setting concepts and consequences.** Labels differ for sent-ecash checks, periodic invoice checks, and automatic receive. **Done when:** both platforms use equivalent plain-language concepts and explain timing, network activity, and consequences. Native label length and sentence structure may differ.

### Settings — Lightning address

- [ ] **[P1 · iOS → Android] Replace “Enable Nostr-NPC bridge” with user-facing language.** iOS says “Enable Lightning Address”; Android exposes internal protocol/component names such as “NPC quote handler.” **Done when:** Android leads with the user outcome and moves implementation terminology to optional technical help.

- [ ] **[P1 · iOS → Android] Gate Lightning settings by feature state.** iOS shows disabled explanation, setup progress, initialization warning, or live controls as appropriate; Android always renders the empty address card and all preference/check controls. **Done when:** Android shows only actions meaningful in the current state.

- [ ] **[P1 · iOS → Android] Add initialization and setup feedback.** iOS distinguishes active setup from “Wallet not fully initialized”; Android collapses both into an empty address message. **Done when:** Android communicates progress separately from a recoverable initialization problem and gives an actionable recovery.

- [ ] **[P2 · iOS → Android] Rename “Check for paid quotes now.”** iOS uses “Check for payments”; Android exposes quote jargon. **Done when:** both use payment language in the primary action.

- [ ] **[P1 · iOS → Android] Expose Lightning-address connection state accessibly.** iOS combines the address with Connected, Connecting, or error text; Android encodes state only in a colored dot. **Done when:** TalkBack announces the address and current state, and color is never the only signal.

### Settings — Nostr identity and relays

- [ ] **[P2 · iOS → Android] Add the Nostr feature introduction.** iOS explains that Nostr powers the Lightning address, npub.cash requests, encrypted backups, and Wallet Connect; Android starts with signer controls. **Done when:** Android provides equivalent user context before technical key management.

- [ ] **[P0 · iOS → Android] Do not silently fail signer changes or key generation/reset.** iOS catches and renders errors; Android wraps several operations in `runCatching` and discards failures. **Done when:** every Android identity mutation has progress where needed, visible user-facing failure feedback, and unchanged state on failure.

- [ ] **[P0 · iOS → Android] Require an explicit choice before switching to a missing custom key.** Android automatically generates a new identity when the user selects Custom Key without one; iOS prompts to generate or import. **Done when:** selecting Custom Key never creates or replaces an identity implicitly and asks the user to generate or import before the signer changes.

- [ ] **[P1 · iOS → Android] Warn next to private-key reveal and copy.** Android already authenticates reveal/copy but shows masked/reveal/copy controls without nearby consequence text. **Done when:** Android explains that the nsec controls the user’s Nostr identity and Lightning address and must not be shared, before or alongside the authenticated actions.

- [ ] **[P1 · iOS → Android] Explain the consequences of nsec import.** Android already validates imports and reports errors; native text editing can provide paste, replace, and clear. The missing gap is product context. **Done when:** Android states that importing replaces the current custom identity and affects the Lightning address and Nostr apps/messages before confirmation, while keeping validation errors user-facing.

- [ ] **[P0 · Converge] Make every identity-replacement warning complete.** Current generate/reset warnings split consequences between platforms, while import and signer-change paths do not consistently confirm replacement. **Done when:** generate, import, reset, and signer-change paths warn as applicable that the Lightning address changes, Nostr apps/messages use a different identity, and the old key is replaced before destructive confirmation.

- [ ] **[P2 · iOS → Android] Give key generation native destructive semantics.** Android’s Generate action is visually neutral even though it replaces an identity; iOS uses a destructive confirmation role. **Done when:** Android uses the platform’s destructive semantic role and accessible announcement for the replacement action. It need not copy iOS styling.

- [ ] **[P2 · iOS → Android] Add the relay-purpose explanation.** iOS explains that relays synchronize npub.cash-compatible data and backups; Android lists relays without that context. **Done when:** Android explains why changing the relay list affects wallet features.

### Settings — Wallet Connect and locked-ecash keys

- [ ] **[P2 · iOS → Android] Complete the reset-connection recovery warning.** Android already says paired apps will stop working; iOS also explains that access remains broken until the new code is shared. **Done when:** Android states both the disruption and the recovery required before reset.

- [ ] **[P1 · Android → iOS] Save a device-key nickname without requiring keyboard Submit.** Android persists each edit; iOS can lose the rename when the user navigates back. **Done when:** iOS saves on change, focus loss, or view disappearance and does not require a hidden keyboard-specific action.

- [ ] **[P2 · Converge] Use complete P2PK import consequence copy.** iOS explains that an imported key can claim locked ecash; Android explains that it is device-only and absent from the seed backup. **Done when:** both state both facts before import.

### Cross-cutting copy, feedback, and accessibility

- [ ] **[P2 · Android → iOS] Describe every accepted input in the default scanner prompt.** iOS omits Lightning invoice even though it accepts one. **Done when:** each platform’s prompt accurately describes the categories accepted by that platform, including Cashu token/request, Lightning invoice, and Bitcoin address where supported. Exact enumeration and sentence structure may remain native.

- [ ] **[P1 · Converge] Standardize mint identity without hiding the trust boundary.** The apps alternate among friendly name, full URL, host, and shortened URL; friendly names are mint-reported and can collide. **Done when:** compact low-risk surfaces use friendly name with normalized-host fallback; payment confirmations and receipts show friendly name plus normalized host; compact lists may omit scheme/trailing slash; and copy, share, and detail always preserve the full URL.

- [ ] **[P2 · Converge] Standardize zero-fee wording by meaning.** The apps alternate among “Free,” “No fee,” and “0 sat” for different concepts. **Done when:** shared copy guidance distinguishes a prospective user charge from an accounting value, and equivalent contexts communicate the same meaning. Platform-native wording may differ.

- [ ] **[P2 · Converge] Standardize success language by context.** Live confirmations and compact historical statuses may intentionally use different tone. **Done when:** shared copy guidance defines the semantic distinction and both platforms use equivalent language within each context; exact capitalization and punctuation need not match.

- [ ] **[P2 · Android → iOS] Advertise QR context actions to assistive technology.** Android’s shared QR card announces long-press Copy/Share options; iOS’s base QR view can omit actionable context. **Done when:** every actionable iOS QR exposes native accessibility actions or an accurate hint; non-actionable QR views do not promise unavailable actions.

- [ ] **[P2 · Converge] Acknowledge copy success consistently and accessibly.** Some actions change text, some show a check, and some rely on system clipboard feedback. **Done when:** comparable copy actions receive an unambiguous acknowledgement within each platform, assistive technology is notified, and repeated actions cannot produce contradictory state. Visual form and reset timing remain platform-native.

## Product decision

- [ ] **[P1 · Product decision] Decide whether startup pending-token checks are independent.** Android exposes separate startup and ongoing sent-token preferences, but its startup runtime currently requires both; iOS uses the sent-token setting for both behaviors. **Decision is closed when:** product documents either one combined rule or two genuinely independent rules, Android’s runtime matches it, and iOS exposes the same model.

## Optional, non-blocking polish

These items may improve efficiency or discoverability but are not required for functional parity and should not block a parity release.

- [ ] **[Optional · iOS → Android] Offer direct switch-mint recovery for applicable failures.** The existing retry-then-mint-row path is functionally sufficient. **Done when:** a failure another mint can resolve offers a one-step switch that preserves quote context.

- [ ] **[Optional · iOS → Android] Include the History query in the no-results message.** **Done when:** the empty state safely repeats the active query without making the message noisy.

- [ ] **[Optional · Android → iOS] Use filter-specific History empty-state titles.** **Done when:** the empty state names Pending or Completed when that context is more helpful than the existing generic title.

- [ ] **[Optional · iOS → Android] Open an ordinary unclaimed token directly in claim review.** The current two-step route is functionally complete. **Done when:** tapping the row opens claim review and a secondary route preserves access to transaction details.

- [ ] **[Optional · iOS → Android] Add Share mint to top actions.** Copy already covers the required data-access outcome. **Done when:** a clearly labeled action sends the full URL to the native Android share sheet.

- [ ] **[Optional · iOS → Android] Show the Lightning-address last-check time.** **Done when:** a relative timestamp updates after manual or automatic checks and has an accessible full-date value where useful.

- [ ] **[Optional · Android → iOS] Add a persistent visible Copy Lightning address action.** iOS already provides QR, Share, and context-menu access. **Done when:** discoverability evidence supports another control and the added action copies the full address with accessible confirmation.

- [ ] **[Optional · Android → iOS] Expose the Nostr public-key hex in an advanced view.** **Done when:** the full value is copyable without displacing npub as the primary identity or cluttering the normal surface.

- [ ] **[Optional · iOS → Android] Add Copy to relay rows.** Native text selection or another existing route may already be sufficient. **Done when:** the action copies the full relay URL and acknowledges success accessibly.

## Related non-parity follow-ups

These are important, but they belong in dedicated security/privacy, design-system, or style/tooling backlogs rather than the release parity gate.

- [ ] **[P0 · Security/privacy] Audit crash-report data and narrow the displayed privacy promise.** **Done when:** captures and breadcrumbs are inventoried on both platforms, sensitive wallet payloads are sanitized, redaction is tested, and displayed promises are limited to guarantees the implementation enforces.

- [ ] **[P2 · Design system] Define an accessible currency-row avatar rule.** **Done when:** the design system documents a neutral currency code or monogram rule instead of country flags or ambiguous symbols, while retaining ISO code and localized currency name in text.

- [ ] **[P2 · Style/tooling] Define and lint one in-progress ellipsis rule per platform.** **Done when:** each platform’s copy/style system has a documented, automatically checked typography rule; cross-platform glyph identity is not required.

## Completed and verified in the baseline

- [x] **[P1 · iOS → Android] Surface wallet startup failures on onboarding.** Android presents initialization failures with user-facing recovery.

- [x] **[P1 · iOS → Android] Validate a custom first-mint URL before staging it.** Android uses the shared validator and keeps malformed-host feedback visible until input changes.

- [x] **[P2 · iOS → Android] Collapse the hidden seed phrase into one accessibility action.** TalkBack exposes one reveal control while hidden and the ordered words only after reveal.

- [x] **[P1 · iOS → Android] Translate per-mint restore failures into wallet-facing copy.** Android preserves Retry and does not expose CDK/FFI implementation text.
