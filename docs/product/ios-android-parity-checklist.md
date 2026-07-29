# iOS and Android Wallet Parity Checklist

Code-audit baseline: 2026-07-29.

The iOS implementation is the default product reference. Items marked **Android → iOS** are cases where Android currently has the clearer or more complete behavior. **Converge** means neither implementation should be copied unchanged; both should adopt one shared product rule.

Only verified product gaps or explicitly labeled product decisions remain in this checklist. **Product decision** marks behavior that must be chosen and documented before implementation. Native capitalization and text-editing controls do not need to be identical across platforms.

Priorities:

- **P0** — security, payment correctness, or potential loss/confusion around funds
- **P1** — meaningful functional or UX inconsistency
- **P2** — visual, positional, copy, feedback, or accessibility inconsistency

Platform-specific differences are intentionally excluded, including iCloud backup, Android host-card-emulation for receiving over NFC, native biometric presentation, system back/swipe conventions, and platform-native sheet or navigation chrome.

## Onboarding, backup, and restore

- [x] **[P1 · iOS → Android] Surface wallet startup failures on the onboarding welcome screen.** iOS shows both the wallet manager’s startup error and errors raised by the current create action; Android’s wallet state contains `errorMessage`, but onboarding renders only its local create error. **Done when:** Android presents initialization failures in user-facing language with an appropriate retry or recovery action.

- [x] **[P1 · iOS → Android] Validate a custom first-mint URL before staging it.** iOS requires a parseable URL with a host and shows “That doesn't look like a mint URL”; Android’s onboarding normalizer accepts any non-empty value after adding a scheme and gives no feedback when normalization fails. **Done when:** Android applies the shared mint-URL validator, rejects malformed hosts, and keeps a visible inline explanation until the input changes.

- [x] **[P2 · iOS → Android] Collapse the hidden seed phrase into one accessibility action.** iOS removes the unrevealed word grid from the VoiceOver tree and exposes a single “Reveal seed phrase” action; Android leaves the numbered placeholder grid as descendants of the reveal target. **Done when:** TalkBack announces one reveal control while hidden and exposes the ordered words only after reveal.

- [x] **[P1 · iOS → Android] Translate per-mint restore failures into wallet-facing copy.** iOS puts `userFacingWalletMessage` in each failed restore row; Android renders the thrown exception message directly. **Done when:** Android uses the shared wallet error translator, preserves the Retry action, and never exposes CDK/FFI implementation text.

## App shell and Wallet home

- [ ] **[P1 · iOS → Android] Honor the preferred primary balance unit on Wallet home.** Android always constructs the home balance with sats as the primary value, even when the user selected fiat; iOS uses `amountDisplayPrimary`. Neither Home implementation currently offers an amount-flip control. **Done when:** Android opens with the saved sats/fiat preference and its visible and accessibility values consistently reflect that preference. A Home-specific flip interaction, if desired, is a separate product decision.

- [ ] **[P1 · iOS → Android] Gate payment actions on wallet runtime readiness.** iOS shows “Preparing wallet…” and disables Receive/Send until the runtime is ready; Android enables them based on mint presence alone. **Done when:** Android exposes a preparation state and cannot enter a money-moving flow before the runtime is ready.

- [ ] **[P1 · Android → iOS] Add the no-mint Wallet empty state and CTA.** Android explains that a mint is needed and provides “Add mint”; iOS shows the generic “No Activity Yet” state even when no mint exists. **Done when:** iOS distinguishes “no mint” from “no activity” and links directly to mint setup.

- [ ] **[P1 · iOS → Android] Keep Receive usable without an active mint.** iOS can create an any-mint Cashu Request without an active mint; Android disables Receive on Home and pins new requests to the active mint. **Done when:** Android allows the any-mint ecash receive path without a mint while clearly disabling or explaining receive methods that truly require one.

- [ ] **[P1 · iOS → Android] Drive the received-amount beat from an explicit receive event.** Android infers a receive from any balance increase, which can show a false `+amount` after a restore, mint operation, or unrelated balance refresh; iOS uses a receipt notification. **Done when:** Android only shows the beat for a confirmed incoming payment and only lets Home own the success haptic for background receipts that have no in-flow confirmation.

- [x] **[P2 · iOS → Android] Add an accessible loading label.** iOS shows “Loading Wallet…” with its progress indicator; Android shows an unlabeled indicator. **Done when:** Android visually or semantically identifies the startup operation as loading the wallet.

- [ ] **[P2 · Converge] Update Home action hints for the unified flows.** iOS accessibility hints still describe opening “options” for ecash and Lightning even though the buttons now open unified Send/Receive surfaces; Android exposes only the button names. **Done when:** both platforms describe the actual destination and supported inputs without referring to a retired chooser.

## Send — unified destination and payment flow

- [ ] **[P1 · iOS → Android] Support fiat-primary amount entry.** iOS converts keypad input according to the saved sats/fiat primary setting; Android’s unified Send amount step always interprets the input as sats. **Done when:** Android entry, “Send Max,” validation, and the amount hero all use the selected primary unit without changing the sat amount being paid.

- [ ] **[P1 · iOS → Android] Use a flippable amount on the confirmation screen.** iOS keeps the sats/fiat display available during payment confirmation; Android renders a fixed sat string. **Done when:** Android confirmation uses the same persisted primary display and flip affordance as its other amount-detail screens.

- [ ] **[P1 · iOS → Android] Show the Cashu Request fee estimate before payment.** iOS calculates the input fee and shows loading, “No fee,” an amount, or unavailable state; Android omits a fee row from Cashu Request confirmation. **Done when:** Android reserves and fills a fee row before the Pay action.

- [ ] **[P1 · iOS → Android] Preserve payment facts through processing, success, and failure.** iOS status screens retain Method, destination for on-chain, Amount, Network fee, Mint, and Cashu Request memo/fees as applicable; Android’s terminal screen generally keeps only Amount, optional fee, and Mint. **Done when:** Android uses a stable, rail-specific row set through all terminal phases.

- [ ] **[P1 · iOS → Android] Add a direct switch-mint recovery action for applicable failures.** iOS can surface a mint-switch CTA with an insufficient-balance or unavailable-mint failure; Android requires “Try again” and a second trip to the mint row. **Done when:** an Android failure that another mint can resolve offers that action directly and returns to confirmation without losing the quote context.

- [ ] **[P1 · Android → iOS] State rail-changing Cashu Request routes explicitly.** Android tells the user whether it will use the Lightning fallback, add a requested mint, or top up the target mint; iOS relies on the mint row and CTA wording. A normal compatible-mint payment is already identified by the mint row and does not need a duplicate route label. **Done when:** iOS explicitly names fallback and recovery routes that materially change how the request is paid, without adding redundant “Pay from” content for the ordinary route.

- [ ] **[P2 · Android → iOS] Include the amount in a directly payable Cashu Request CTA.** Android uses `Pay <amount>` while iOS uses the generic “Pay” for an already funded request. **Done when:** iOS repeats the amount at the commit point, while preserving the existing add/fund wording for recovery routes.

- [ ] **[P2 · Converge] Remove platform names from payment warnings.** Android says “supported on Android” and “Android can pay…” while iOS says “this wallet.” **Done when:** shared limitations and fallback messages use product language and the same terminology on both platforms.

## Send — ecash and locked ecash

- [ ] **[P1 · iOS → Android] Support fiat-primary entry when creating ecash.** iOS allows sat-denominated ecash to be entered in the preferred fiat unit; Android’s ecash keypad always uses sats even though the generated-token screen can show fiat. **Done when:** Android entry, validation, and Send Max follow the saved primary unit.

- [ ] **[P1 · iOS → Android] Add a scan action for a P2PK recipient key.** iOS can scan a public key and validate it before locking; Android only provides a manual text field and “Lock to my key.” **Done when:** Android can scan, paste, or type a recipient key through the same validation path.

- [ ] **[P2 · iOS → Android] Collapse a validated P2PK recipient into a compact chip.** iOS replaces entry chrome with “Locked to / Your key” or a shortened key plus Change/Remove actions; Android leaves the full technical input field in the amount layout. **Done when:** Android shows a compact confirmed-recipient state with obvious edit and remove actions.

- [ ] **[P2 · iOS → Android] Replace protocol jargon in lock accessibility copy.** Android announces “P2PK off” and “P2PK locked”; iOS uses “Lock ecash” and describes the outcome. **Done when:** Android’s visible and assistive copy explains the user effect first, with P2PK only as optional supporting terminology.

- [ ] **[P1 · iOS → Android] Provide manual claim-status checking when automatic checks are disabled.** iOS adds “Check Status” to the pending token actions; Android leaves the token at Pending with no equivalent action. **Done when:** Android users can run a one-off spent check without re-enabling background polling.

- [ ] **[P1 · iOS → Android] Include the send fee on the Claimed receipt.** iOS shows the fee when the token-generation swap charged one; Android’s pending view shows it but the full-screen Claimed terminal drops it. **Done when:** Android’s Claimed rows preserve Amount, applicable Fee, and Mint.

- [ ] **[P2 · iOS → Android] Keep the generated-token hero flippable.** iOS allows a sat token’s amount hero to switch between sats and fiat; Android shows a fixed primary amount and a separate Fiat detail row. **Done when:** Android uses the shared amount-flip presentation and avoids duplicating the same conversion below it.

## Receive — unified entry and Cashu tokens

- [ ] **[P0 · iOS → Android] Create new ecash requests as any-mint requests by default.** iOS creates a NUT-18 request with no mint restriction; Android silently inserts the active mint. This changes who can pay the request. **Done when:** Android leaves the mint list empty unless the user explicitly selects a mint.

- [ ] **[P1 · Converge] Use one Nostr-readiness rule and recovery message.** Android requires both a public key and relays and says “check your relays”; iOS checks initialized identity and points broadly to Settings → Nostr. **Done when:** both validate every prerequisite needed for a deliverable request and name the exact setting that needs attention.

- [ ] **[P0 · iOS → Android] Warn before receiving from an unknown mint.** iOS identifies that receiving will add a new mint and asks the user to continue only if they trust it; Android has no equivalent trust warning. **Done when:** Android displays the mint host, explains that it will be added, and blocks an accidental one-tap claim.

- [ ] **[P0 · iOS → Android] Show the actual P2PK lock target.** iOS displays “Locked to: Your key” or the unknown key with a caution; Android only adds a generic “P2PK / Requires your key” row when the key is not held and hides the row when it is held. **Done when:** Android always identifies a locked token’s recipient and clearly distinguishes claimable from unclaimable.

- [ ] **[P1 · Android → iOS] Show the token memo during review.** Android includes a Memo inspector row when present; iOS does not. **Done when:** iOS lets the recipient review the sender’s memo before claiming.

- [ ] **[P1 · iOS → Android] Preserve a memo when choosing Receive later.** iOS stores the decoded token memo in the pending receive; Android’s pending-token conversion drops it. **Done when:** the Android History row and later claim retain the original memo.

- [ ] **[P0 · iOS → Android] Report the actually paid receive fee.** iOS derives the final fee from gross token value minus the amount credited; Android carries the preview fee into success even if settlement differs. **Done when:** Android’s receipt reconciles against the credited amount.

## Receive — Lightning, reusable invoices, on-chain, and Cashu Requests

- [ ] **[P1 · iOS → Android] Support fiat-primary amount entry on Bitcoin receive rails.** iOS lets a sat Lightning invoice be entered in fiat; Android’s receive keypad uses fixed sat entry. **Done when:** Android converts entry and validation with the persisted primary display setting.

- [ ] **[P2 · iOS → Android] Keep generated invoice amounts flippable.** iOS retains the sats/fiat amount control under a BOLT11 or fixed BOLT12 QR; Android renders a fixed amount string. **Done when:** Android uses the shared amount-flip component for sat quotes.

- [ ] **[P1 · iOS → Android] Do not auto-dismiss a successful receive receipt.** iOS leaves the success screen in place until Done; Android closes it after about 1.8 seconds. **Done when:** Android waits for an explicit Done action so the receipt remains readable and accessible.

- [ ] **[P1 · iOS → Android] Replace “Waiting for payment” with “Expired.”** iOS changes the main status when a one-shot quote expires; Android can keep the waiting row while only the small expiry caption says Expired. **Done when:** the Android primary status cannot contradict the expiry state.

- [ ] **[P1 · Android → iOS] Add Total received to a reusable invoice.** Android shows a cumulative Total received row after BOLT12 payments; iOS only changes the status badge. **Done when:** iOS exposes the cumulative amount in the reusable-invoice details.

- [ ] **[P1 · Android → iOS] Correlate an open Cashu Request success to a new payment record.** Android watches the request’s received-payment IDs; iOS has a fallback that treats any balance increase while the receive sheet is open as payment for that request. **Done when:** iOS cannot show a false request success for an unrelated balance increase.

- [ ] **[P1 · Android → iOS] Show Total received in Cashu Request details.** Android adds the aggregate after one or more payments; iOS shows only the status count and original request amount. **Done when:** iOS includes a unit-correct aggregate row.

## History and transaction details

- [ ] **[P1 · Android → iOS] Search transaction and request memos.** Android includes memos in History search; iOS searches titles and numeric amounts only. **Done when:** iOS matches memo text case-insensitively for both item types.

- [ ] **[P1 · iOS → Android] Search a Cashu Request’s Total received amount.** iOS includes the aggregate received value in search; Android only searches the requested amount. **Done when:** Android matches both configured and received totals.

- [ ] **[P2 · iOS → Android] Include the query in the no-results state.** iOS says that no activity matches the entered query; Android only says “No matches.” **Done when:** Android repeats the query safely and provides equivalent context.

- [ ] **[P2 · Android → iOS] Use filter-specific empty-state titles.** Android distinguishes “No pending transactions” and “No completed transactions”; iOS uses the generic “Nothing Here.” **Done when:** iOS names the active filter in the empty state.

- [ ] **[P1 · iOS → Android] Explain all consequences of removing a Cashu Request row.** iOS says the QR and pending payment routing remain valid; Android only says received payments stay in the wallet. **Done when:** Android states before deletion that previously received funds remain, the QR and payment routing remain valid, and only the History row is removed.

- [ ] **[P1 · iOS → Android] Open an unclaimed incoming token directly in the claim flow.** iOS skips transaction detail for this row; Android opens detail and requires a second Receive tap. **Done when:** tapping the Android History row lands on token review, with detail still available through a secondary path if needed.

- [ ] **[P1 · iOS → Android] Add removal for an unclaimed incoming token.** iOS can delete the parked token with a warning that the ecash will be discarded and only the sender can reissue it; Android has no matching capability. **Done when:** Android provides a discoverable removal action and the same loss warning.

- [ ] **[P2 · iOS → Android] Respect the preferred primary amount in transaction details.** iOS lets sat Lightning/ecash amounts flip between sats and fiat; Android always displays sats. **Done when:** Android uses the saved primary setting while keeping on-chain and non-sat unit exceptions aligned with iOS.

- [ ] **[P2 · iOS → Android] Reduce the completed-history glyph from 96 to 64.** Android makes a historical success check much larger than both iOS and its own failure glyph. **Done when:** completed and failed historical glyphs use the same restrained 64-point/dp visual weight.

- [ ] **[P2 · iOS → Android] Announce the active History filter.** iOS exposes the selected filter as an accessibility value; Android’s filter control is announced only as “Filter.” **Done when:** TalkBack reports All, Pending only, or Completed only on the control.

## Mints list, add, and discovery

- [ ] **[P2 · Android → iOS] Shorten mint URLs in the Mints list.** Android removes the scheme/trailing slash for the compact row while retaining the full value in detail; iOS displays the full URL. **Done when:** iOS uses the normalized host/path in compact rows and never changes the value copied or opened.

- [ ] **[P1 · iOS → Android] Add pull-to-refresh to mint discovery.** iOS can explicitly restart discovery and reload missing previews; Android has no refresh gesture or retry action. **Done when:** Android users can restart discovery without closing and reopening the sheet, and both platforms’ empty states name the refresh action that is actually available.

- [ ] **[P2 · Converge] Unify the discovery-disabled recovery copy.** iOS says WebSockets are required and points to Settings; Android more usefully names Settings → Privacy. **Done when:** both explain why discovery is off and give the exact setting path.

- [ ] **[P2 · iOS → Android] Add contextual discovery no-result copy.** iOS distinguishes no mints found from no query matches and repeats the query; Android says “Listening on Nostr…” or “No matches” without a query-specific explanation. **Done when:** Android differentiates waiting, exhausted discovery, and filtered-zero states; terminal empty states repeat the query when applicable and point to the refresh action added above.

## Mint details

- [ ] **[P1 · iOS → Android] Add Share mint to the top actions.** iOS exposes the mint URL through the standard share sheet; Android only supports copying the URL chip. **Done when:** Android provides a clearly labeled share action using the full URL.

- [ ] **[P2 · iOS → Android] Show the fiat secondary balance when enabled.** iOS adds the fiat conversion beneath the sat balance; Android shows only sats plus native non-sat unit balances. **Done when:** Android mirrors the user’s global fiat-balance preference.

- [ ] **[P1 · iOS → Android] Expose metadata loading and failure states.** iOS shows “Loading mint info…” and an error banner when the live NUT-06 fetch fails; Android silently falls back to cached data and only marks Connection Offline. **Done when:** Android distinguishes cached content from a loading or failed live refresh and offers a retry where useful.

- [ ] **[P1 · iOS → Android] Add the Contact section.** iOS renders reported email, web, Nostr, Twitter/X, and Telegram contacts with appropriate actions; Android omits them. **Done when:** Android displays every reported contact and opens supported methods safely.

- [ ] **[P1 · iOS → Android] Add software version and Terms of Service.** iOS includes these live mint details; Android’s Details section contains only Units. **Done when:** Android shows software name/version and a safe external Terms link when reported.

- [ ] **[P2 · iOS → Android] Add the provenance footer.** iOS says “Information reported by the mint”; Android does not identify the source of remote descriptions, contacts, or terms. **Done when:** Android includes the same qualification near the metadata.

- [ ] **[P1 · iOS → Android] Preserve and hide absent payment methods.** iOS omits the section or an empty direction; Android’s domain mapping substitutes BOLT11 when a live NUT-04 or NUT-05 method list is empty, and the detail screen always renders both directions. **Done when:** Android preserves whether each direction was actually reported, uses any compatibility fallback only for records whose metadata is genuinely unknown, and hides a direction that the live mint reports as absent.

- [ ] **[P1 · iOS → Android] Surface Set as Default progress and errors.** iOS disables the action, shows a spinner, and renders an inline failure; Android launches the operation with no visible progress or error. **Done when:** Android cannot be double-submitted and clearly reports success/failure.

## Settings — information architecture, display, and destructive actions

- [ ] **[P1 · iOS → Android] Put App Lock in Backup & Security.** iOS gives App Lock its own destination at the top level; Android hides the toggle under Privacy. **Done when:** Android matches the Settings hierarchy and keeps privacy/background controls separate from device security.

- [ ] **[P0 · iOS → Android] Authenticate before enabling App Lock.** iOS verifies device-owner authentication and reverts with an error if enabling fails; Android directly persists the toggle. **Done when:** Android cannot enable a lock that has not been successfully tested.

- [ ] **[P0 · iOS → Android] Explain unavailable App Lock and preserve access.** iOS detects the absence of a device passcode, tells the user how to enable it, and explains that seed reveal always authenticates; Android exposes no equivalent setup guidance. **Done when:** Android shows capability state, setup recovery, and the seed-reveal guarantee without allowing an unusable lock.

- [ ] **[P1 · iOS → Android] Show wallet-deletion failures.** iOS catches deletion errors and displays a banner; Android starts deletion without dedicated error feedback. **Done when:** Android reports failure and leaves the existing wallet state intact and understandable.

- [ ] **[P1 · Android → iOS] Read the app version from build metadata.** Android uses `BuildConfig.VERSION_NAME`; iOS hard-codes `1.0.0`. **Done when:** iOS displays the shipped bundle version and, if desired, build number.

- [ ] **[P2 · Android → iOS] Add localized currency names.** Android shows the ISO code plus the localized currency name; iOS shows only the code. **Done when:** iOS rows are understandable without memorizing ISO-4217 codes.

- [ ] **[P2 · iOS → Android] Show when the BTC price was last updated.** iOS includes a relative timestamp beside the price; Android omits it. **Done when:** Android exposes recency and handles never-loaded/stale states.

- [ ] **[P2 · Product decision] Choose an accessible currency-row avatar system before converging.** iOS uses country/region flags even though a currency is not always tied to one country; Android uses symbols that can be ambiguous across currencies. A neutral currency-code or monogram avatar is the preferred direction. **Done when:** the visual rule is documented and both platforms implement it while retaining the ISO code and localized currency name in text.

## Settings — privacy and background behavior

- [ ] **[P1 · iOS → Android] Disable periodic invoice checks when incoming checks are off.** iOS disables the child control; Android leaves it interactive even though the runtime already requires incoming checks before periodic work runs. **Done when:** Android disables the child visually and semantically while preserving its saved preference for a later re-enable, and the effective runtime rule remains the logical combination of both settings.

- [ ] **[P1 · Android → iOS] Keep WebSockets independent of invoice/token polling.** Android correctly notes that WebSockets also power Nostr discovery; iOS disables the toggle when both incoming-invoice and sent-token checks are off. **Done when:** iOS users can enable discovery/live Nostr features independently.

- [ ] **[P1 · Product decision] Choose whether startup pending-token checks are independent.** Android exposes separate startup and ongoing sent-token preferences, but its startup runtime currently requires both to be enabled; iOS uses the sent-token setting for both behaviors. **Done when:** product documents either one combined rule or two genuinely independent rules, Android’s runtime matches that decision, and iOS exposes the same model.

- [ ] **[P2 · Converge] Align privacy setting names and helper text.** Examples include “Check sent ecash” versus “Check sent token claims,” “Check all invoices” versus “Periodic invoice checks,” and “Claim received ecash automatically” versus “Receive automatically.” **Done when:** both use the same plain-language labels and explain timing, network activity, and consequences.

- [ ] **[P1 · Converge] Audit crash-report data before publishing one privacy promise.** Both disable Sentry default PII, screenshots, and view hierarchy, but iOS captures raw errors and Android’s message redaction covers only selected secret and URL patterns. The current “no personal data, wallet addresses, or amounts are ever sent” claim is not established by the implementation. **Done when:** every capture and breadcrumb path is inventoried, sensitive wallet payloads are sanitized and tested on both platforms, and the displayed promise is limited to guarantees the implementation actually enforces.

## Settings — Lightning address

- [ ] **[P1 · iOS → Android] Replace “Enable Nostr-NPC bridge” with user-facing language.** iOS says “Enable Lightning Address”; Android exposes an internal protocol/component name and “NPC quote handler.” **Done when:** Android leads with the user outcome and moves implementation terminology to optional help text.

- [ ] **[P1 · iOS → Android] Gate Lightning settings by feature state.** iOS shows a simple disabled explanation, setup progress, initialization warning, or the live address/preferences/check controls as appropriate; Android always renders the empty address card, automatic claim, mint, and check controls. **Done when:** Android shows only actions meaningful in the current state.

- [ ] **[P1 · iOS → Android] Add initialization/setup feedback.** iOS distinguishes “Setting up Lightning address…” from “Wallet not fully initialized. Please restart”; Android collapses both into an empty address message. **Done when:** Android communicates progress versus a recoverable initialization problem.

- [ ] **[P2 · iOS → Android] Rename “Check for paid quotes now.”** iOS uses “Check for payments”; Android exposes quote jargon. **Done when:** both use payment language in the primary action.

- [ ] **[P2 · iOS → Android] Show the last check time.** iOS displays “Last checked …”; Android does not. **Done when:** Android shows a relative timestamp after manual or automatic checks.

- [ ] **[P1 · iOS → Android] Expose connection state to accessibility services.** iOS combines the address with Connected/Connecting/error text; Android encodes the state only in a colored dot. **Done when:** TalkBack announces the address and state, and color is never the only signal.

- [ ] **[P2 · Android → iOS] Add a visible Copy address action.** Android places a labeled Copy button under the address; iOS hides copy/share in a long-press context menu. **Done when:** iOS offers a discoverable copy affordance while keeping QR and Share available.

## Settings — Nostr identity and relays

- [ ] **[P2 · iOS → Android] Add the Nostr feature introduction.** iOS explains that Nostr powers the Lightning address, npub.cash requests, encrypted backups, and Wallet Connect; Android starts with signer controls. **Done when:** Android provides the same context before technical key management.

- [ ] **[P2 · Android → iOS] Expose the public key hex alongside npub.** Android makes both copyable; iOS only surfaces npub in the main key card. **Done when:** iOS provides the hex value in an advanced/detail affordance without cluttering the primary identity.

- [ ] **[P0 · iOS → Android] Do not silently fail signer changes or key generation/reset.** iOS catches and renders errors; Android wraps several operations in `runCatching` and discards failures. **Done when:** every Android identity mutation has progress where needed, visible failure feedback, and unchanged state on failure.

- [ ] **[P0 · iOS → Android] Require an explicit choice before switching to a missing custom key.** iOS prompts to generate or import when no custom private key exists; Android automatically generates a new identity when the user selects Custom Key without one. **Done when:** selecting Custom Key never creates or replaces an identity implicitly and instead asks the user to generate or import before the signer changes.

- [ ] **[P0 · iOS → Android] Warn next to private-key reveal.** iOS says the nsec controls the user’s Lightning address and must never be shared; Android shows masked/reveal/copy controls without nearby consequence text. **Done when:** Android presents a clear secret-handling warning before or with reveal.

- [ ] **[P1 · iOS → Android] Make nsec import explanatory and recoverable.** iOS explains that the key will be used for the Lightning address and provides a dedicated Paste action; Android shows a bare dialog field. iOS does not currently provide the claimed Clear control, and Android may retain its native text-editing menu. **Done when:** Android explains what the imported identity controls, validates the complete nsec with user-facing errors, and lets the user paste, replace, or clear input through native or explicit controls.

- [ ] **[P0 · Converge] Make every identity-replacement warning complete.** Current generate/reset warnings split the consequences between platforms, while import and signer-change paths do not consistently confirm replacement. **Done when:** generate, import, reset, and signer-change paths warn as applicable that the Lightning address changes, Nostr apps/messages use a different identity, and the old key is being replaced before a destructive confirmation.

- [ ] **[P2 · iOS → Android] Style Generate new key as identity replacement.** iOS uses a destructive confirmation role; Android’s Generate action is visually neutral. **Done when:** Android’s confirmation visually communicates the destructive replacement semantics.

- [ ] **[P2 · iOS → Android] Add Copy to relay rows.** iOS offers copy with confirmation and remove; Android offers remove only. **Done when:** Android can copy the full relay URL without text selection.

- [ ] **[P2 · iOS → Android] Add the relay-purpose footer.** iOS explains that relays synchronize npub.cash-compatible data and backups; Android lists relays without that explanation. **Done when:** Android explains why changing the list affects wallet features.

- [ ] **[P2 · iOS → Android] Expand the Wallet Connect subtitle.** iOS says a Nostr app can create invoices and pay Lightning invoices from this wallet; Android only says it can “use this wallet.” **Done when:** Android names the permissions/capabilities at the navigation row.

## Settings — Wallet Connect and locked-ecash keys

- [ ] **[P2 · Android → iOS] Add a visible Copy connection code action.** Android has a labeled copy icon/action next to the code; iOS relies on a QR/context menu. **Done when:** iOS makes copy discoverable without requiring long-press.

- [ ] **[P1 · iOS → Android] Use the complete reset-connection warning.** iOS explains that every paired app stops working until the new code is shared; Android’s confirmation is shorter. **Done when:** Android states the exact disruption before reset.

- [ ] **[P1 · Android → iOS] Save a device-key nickname when focus leaves the field.** Android persists each edit; iOS only saves on keyboard Submit, so navigating back can lose the rename. **Done when:** iOS saves on change, focus loss, or view disappearance without requiring Done.

- [ ] **[P2 · Converge] Use complete P2PK import consequence copy.** iOS explains that an imported key can claim locked ecash; Android explains that it is device-only and absent from the seed backup. **Done when:** both state both facts before import.

## Cross-cutting visual, copy, feedback, and accessibility

- [ ] **[P2 · Android → iOS] Mention invoices in the default scanner prompt.** Android says it can scan a Cashu token, payment request, invoice, or Bitcoin address; iOS omits invoice even though it accepts one. **Done when:** the prompts enumerate the same supported categories.

- [ ] **[P2 · Converge] Standardize ellipses in status copy.** The UI mixes three periods (`Checking...`, `Minting...`) and the ellipsis character (`Checking…`, `Creating…`). **Done when:** equivalent in-progress labels use one typography rule on both platforms.

- [ ] **[P2 · Converge] Standardize mint identity display without hiding the trust boundary.** Across list rows, selectors, confirmations, receive-success receipts, and details, the apps alternate among friendly name, full URL, host, and shortened URL. Friendly names are reported by the mint and can collide or be misleading. **Done when:** compact low-risk surfaces use friendly name with normalized-host fallback, payment confirmations and receipts show friendly name plus normalized host, and the full URL remains available for copy, share, and detail.

- [ ] **[P2 · Converge] Standardize zero-fee wording by meaning.** The apps alternate among “Free,” “No fee,” and “0 sat,” sometimes for different kinds of information. **Done when:** a shared copy table distinguishes a prospective user charge (“Free” or “No fee”) from an accounting value (`0 sat`), and equivalent contexts use the same term on both platforms.

- [ ] **[P2 · Converge] Standardize success titles by context.** The same completed receive/payment appears as “Payment Received!”, “Payment received,” “Payment Sent!”, and “Payment sent.” Live confirmation and historical status may intentionally use different tone. **Done when:** both platforms follow one copy table that defines live-success titles separately from compact historical labels, with consistent case and punctuation inside each context.

- [ ] **[P2 · Android → iOS] Advertise QR context actions to assistive technology.** Android’s shared QR card announces long-press Copy/Share options; iOS’s base QR view only says it contains payment data even where a context menu is attached. **Done when:** iOS adds accessibility actions or a hint for every actionable QR.

- [ ] **[P2 · Converge] Keep copy feedback semantically consistent within each platform.** Some actions change button text, some swap to a check, and some rely on the system clipboard confirmation. Native feedback patterns do not need identical visuals or reset timing across platforms. **Done when:** each platform consistently acknowledges comparable copy actions, exposes success to assistive technology, and avoids contradictory or missing feedback.
