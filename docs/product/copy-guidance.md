# Copy guidance

Shared product copy contracts for the iOS and Android apps. Each section is
self-contained; platform-native wording may differ where a section allows it,
but equivalent contexts must communicate the same meaning.

## Zero-fee wording by meaning

"Free", "No fee", and "0 sat" are not interchangeable. Which one is correct
depends on what the row means, not on which screen renders it. Three meanings
exist; each has exactly one wording class per platform.

### 1. Prospective user charge — "you will be charged nothing"

Context: a fee estimate or preview shown *before* the user commits (send/pay
confirmation, scanned-invoice preview, receive-token review). The row tells
the user what they will be charged; zero means "no charge applies".

Wording: a charge-absence phrase — **"No fee"** on both platforms. Never a
bare numeric zero: "0 sat" reads as an accounting figure, not as a statement
about the user's charge.

- iOS: `SendView` and `ScannerWrapperView` fee rows (`FeeState.free` →
  "No fee"); `ReceiveTokenDetailView` confirm fee row ("No fee" when the
  previewed fee is zero).
- Android: `CashuRequestFeeEstimate.NoFee` → "No fee";
  `SendPaymentDetailRows` fee-detail rows with amount 0 → "No fee";
  `TokenInspectorRows` fee preview → "No fee" when the previewed fee is zero.

### 2. Accounting value — the fee actually paid was zero

Context: a settled receipt, success screen, or history detail describing what
happened. The row records a fact about the completed transaction.

Wording: when the recorded fee is greater than zero, show the recorded amount
("N sat" or the fiat-formatted equivalent). When the recorded fee is zero,
**omit the fee row entirely** — a receipt records what happened, and a
zero-fee line is noise. Never "0 sat", "Free", or "No fee" as a receipt
value.

- iOS: `TransactionDetailView` (fee row only when `fee > 0`), `SendView`
  generated-token and claimed rows (only when `tokenFee > 0`),
  `ReceiveTokenDetailView` success rows (fee row omitted when the paid/preview
  fee is zero).
- Android: `ReceiveTokenReview` claimed receipt (fee row only when
  `claimed.fee > 0`), `formatSendEcashFee` (returns null for zero so the row
  is omitted).

### 3. Numeric reserve / upper bound — labeled estimate, not a zero-fee statement

Context: a Lightning quote reserve ("Max fee", "Network fee" shown with an
"Up to …" value). The label carries the estimate meaning, so the value stays
numeric ("N sat" / "Up to N sat") even when the reserve is zero. This class
is not a zero-fee statement and does not use the classes above.

## Success language by context

The words shown when money moves depend on the surface, not on the payment rail.
Three contexts, three meanings:

### 1. Terminal success screen (celebratory)

The full-screen end state of an in-flight receive flow — Lightning receive
(one-shot invoice, reusable offer, or on-chain deposit), ecash token claim,
Cashu Request payment, and NFC receive (Android-only surface).

- **Meaning:** a celebration that funds just landed in the wallet. The user was
  waiting for this exact payment and watched the flow complete.
- **Contract:** both platforms say **"Payment Received!"** (celebratory
  exclamation). The rail is irrelevant — the detail rows (Amount, Mint) already
  carry the specifics.
- **Reference:** iOS `PaymentStatusView` call sites in `ReceiveLightningView`,
  `ReceiveTokenDetailView`, and `CashuRequestDetailView` all pass
  `successTitle: "Payment Received!"`; Android `PaymentStatusScreen` terminals in
  `ReceiveLightningScreen`, `ReceiveTokenReview`, `CashuRequestDetailScreen`,
  and `NfcReceiveUi` use the same title.

### 2. History row / transaction detail title (factual record)

The permanent ledger entry after settlement, seen long after the moment of
receipt.

- **Meaning:** a neutral, factual record of what happened — kind first, verb
  second, no exclamation. This is bookkeeping, not celebration.
- **Contract:** kind-first titles identical on both platforms — "Ecash
  received", "Lightning received", "Bitcoin received" (and the outgoing
  counterparts). Single source of truth per platform (iOS
  `WalletTransaction.displayTitle`, Android `TransactionDisplay.title`) so a
  row and the detail it opens read identically.

### 3. Transient live confirmation (brief signal)

Short-lived inline feedback while a flow is still on screen or a receipt
arrives passively: the paid badge under a QR, a scanner toast, the NFC
indicator line, a home balance delta, a "N payments received" counter.

- **Meaning:** "a payment just arrived" — enough to confirm the event at a
  glance; the terminal screen or History row is the durable record.
- **Contract:** must name the receipt (e.g. "Payment Received!", "Received
  21 sat", "Payment received — paying request…"). Celebration vs. neutral tone,
  capitalization, and punctuation are platform-native and may vary by surface.

## Empty states that are the only way forward

When a screen's list starts empty and the action that fills it is a button the
user has to find, the empty-state line is not a description — it is the
navigation. Restore's "Add your mints" step is the case that set this contract.

The step used to look up the user's published mint list automatically on
arrival. That read as the wallet contradicting itself: the subhead says the seed
phrase doesn't record which mints you used, and then a dozen of the user's mints
appeared from nowhere. In a wallet whose whole promise is that nothing leaves
the device unasked, an unexplained list of your own mints is the worst possible
thing to show. The lookup is now user-triggered, which puts the entire burden of
getting people through the step onto copy.

Three states, and each has a distinct job:

1. **Landing** (nothing searched yet) — the state everyone arrives in. Names the
   button literally and capitalized exactly as it appears, plus the manual
   escape hatch: "Tap Find my mints to look for a backup of your mint list, or
   add them above."
2. **Working** — says the wallet is looking, in the user's terms rather than the
   transport's: "Checking for a backup of your mint list…"
3. **Came back empty** — says so and names the way out: "No backup found. Add
   the mints you used before, then restore."

Rules this generalizes to:

- **Name the control, don't describe the situation.** "Add the mints you used
  before" was true and useless; it never mentioned the button that does it.
- **Quote the label verbatim.** Voice Control matches spoken words against a
  control's accessibility label, so the label must equal the visible text and
  the empty state must quote it exactly. Overriding a button's
  `accessibilityLabel` with a longer explanation breaks this; put the
  explanation in the hint instead.
- **Don't say the same thing twice.** A notice and an empty-state line can both
  fire on "nothing found". Gate the notice on the list being non-empty, so
  whichever surface is actually on screen carries the message alone.
- **Reset "already searched" on retreat.** Backing out and returning must land
  on the landing line, not on "No backup found" — otherwise the user comes back
  to a dead screen with no pointer.

Both platforms hold these strings in one place (`RestoreMints*` constants in
`RestoreWalletFlow.kt`; `emptyMintListNotice` in `OnboardingView.swift`).

## Seed entry, word by word

`restoreInput` (and its Settings twin) asks for one word at a time, so a single
line under the card carries three different jobs. Only one can ever be on
screen, and the precedence is fixed: **host notice → per-word rejection →
completion.** While entering, the line is empty — the keyboard's Next key (and
the space bar) already teaches the commit, so a standing instruction would be
furniture. The line only speaks when it has news.

| State | String |
| --- | --- |
| Subhead | "Enter your 12 words, one at a time." |
| Entering | *(nothing)* |
| All twelve in | "All 12 words verified." |
| Word refused | "Not a seed word. Check the spelling." |
| Checksum failed | "That's not a valid seed phrase." / "One of the words is probably mistyped. Tap any word below to fix it." |
| Pasted fewer than 12 | "Pasted N words. Enter the rest." |
| Pasted 12, one bad | "Pasted 12 words, but word N isn't in the list." |
| Clipboard unusable | "Nothing in the clipboard looked like a seed phrase." |

Rules this generalizes to:

- **Tell them what to do, not what the field is.** The checksum recovery line
  is "Tap any word below to fix it", not "Seed word 3 of 12" — the ordinal is
  already on the card and the rail already shows the position. Copy earns its
  place by saying something the layout cannot; the old "Press space after each
  word" helper was cut on exactly this rule once the keyboard's Next key made
  it redundant.
- **An error that can't be localised must still point somewhere.** A BIP-39
  checksum failure proves one of the twelve is wrong but never which. "That
  seed phrase doesn't look right" (the old string) left the user with no move.
  The replacement names the recovery — "Tap any word below to fix it" — and the
  UI puts all twelve within reach to make that true.
- **Say what landed, then what's left.** Paste outcomes report the count that
  went in *and* the next action, because a partial paste looks identical to a
  successful one until you count.
- **Distinguish "not a word" from "wrong phrase".** The first is per-word,
  instant, and cheap to fix; the second is about the whole phrase and needs a
  different surface. Sharing one error string for both would tell the user the
  wrong thing half the time.

Both platforms hold these strings in one place (`SeedEntryCopy` in
`SeedWordEntry.kt` and `SeedWordEntry.swift`).
