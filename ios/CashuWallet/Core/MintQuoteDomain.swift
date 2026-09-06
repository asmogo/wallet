import Foundation

/// Pure mint-quote domain rules (Android `MintQuoteDomain.kt` parity) —
/// extracted for unit testing.
enum MintQuoteDomain {
    /// Payer decoders render control characters, including newlines, as replacement glyphs.
    static func normalizedOfferDescription(_ raw: String?) -> String? {
        let printable = (raw ?? "").unicodeScalars.compactMap { scalar -> String? in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { return " " }
            return scalar.properties.generalCategory == .control ? nil : String(scalar)
        }.joined()
        let normalized = String(printable.split(separator: " ").joined(separator: " ").prefix(640))
        return normalized.isEmpty ? nil : normalized
    }

    /// True when any NUT-04 bolt12 method advertises `description: true`.
    /// Null or false on every bolt12 method (or no bolt12 method) fails closed.
    static func reportsBolt12MintDescription(
        methods: [(method: PaymentMethodKind?, description: Bool?)]
    ) -> Bool {
        methods.contains { $0.method == .bolt12 && $0.description == true }
    }

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
