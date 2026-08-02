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
