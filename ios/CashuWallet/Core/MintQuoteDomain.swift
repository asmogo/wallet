import Foundation

/// Pure mint-quote domain rules (Android `MintQuoteDomain.kt` parity) —
/// extracted for unit testing.
enum MintQuoteDomain {
    /// Exact-match rule for reusable-offer reuse: an amountless BOLT12 quote
    /// at the active mint and requested unit whose locally stored memo equals
    /// the requested description (nil → only the plain, description-less
    /// offer). CDK never returns offer descriptions, so the memo stored locally
    /// by quote id is the only record — and exact matching keeps reuse
    /// unambiguous once several amountless offers exist (offers are immutable,
    /// so a changed description always mints a fresh one).
    static func isReusableAmountlessOffer(
        paymentMethod: PaymentMethodKind?,
        isAmountless: Bool,
        quoteMintUrl: String,
        quoteUnit: String,
        activeMintUrl: String,
        unit: String,
        storedMemo: String?,
        description: String?
    ) -> Bool {
        paymentMethod == .bolt12 &&
            isAmountless &&
            quoteMintUrl == activeMintUrl &&
            quoteUnit.lowercased() == unit.lowercased() &&
            storedMemo == description
    }
}
