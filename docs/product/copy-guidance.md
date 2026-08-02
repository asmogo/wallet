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
