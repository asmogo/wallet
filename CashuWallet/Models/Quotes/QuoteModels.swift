import Foundation

struct MintQuoteInfo: Identifiable {
    let id: String
    let request: String  // Payment request (BOLT11 invoice, BOLT12 offer, or on-chain address)
    let amount: UInt64?
    let paymentMethod: PaymentMethodKind
    var state: MintQuoteState
    let expiry: UInt64?
    /// First-seen timestamp for the offer. Set only for reusable (amountless
    /// BOLT12) offers, which carry no creation field in the CDK quote — see
    /// `MintQuoteCreatedAtStore`. nil for every other rail.
    let createdAt: Date?

    var isExpired: Bool {
        guard let expiry = expiry, expiry > 0 else { return false }
        return Date().timeIntervalSince1970 > Double(expiry)
    }
}

/// Remembers when each reusable (amountless BOLT12) offer was first materialized.
/// The CDK `MintQuote` has no creation timestamp, and the same offer is reused
/// across opens via `LightningService.existingAmountlessOffer()`, so without a
/// stable record the "Created" row would drift to "now" on every visit. Keyed by
/// quote id; stamped once, read back forever after.
enum MintQuoteCreatedAtStore {
    private static let storageKey = "mintQuoteCreatedAt.v1"

    /// Returns the stored date for `quoteId`, stamping `date` first if absent.
    @discardableResult
    static func recordIfAbsent(quoteId: String, date: Date) -> Date {
        var map = load()
        if let existing = map[quoteId] { return existing }
        map[quoteId] = date
        save(map)
        return date
    }

    static func date(for quoteId: String) -> Date? { load()[quoteId] }

    private static func load() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let map = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return map
    }

    private static func save(_ map: [String: Date]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

/// Melt quote information
struct MeltQuoteInfo: Identifiable {

    let id: String
    let mintUrl: String
    let amount: UInt64
    let feeReserve: UInt64
    let paymentMethod: PaymentMethodKind
    var state: MeltQuoteState
    let expiry: UInt64?
    
    var totalAmount: UInt64 {
        amount + feeReserve
    }
    
    var isExpired: Bool {
        guard let expiry = expiry, expiry > 0 else { return false }
        return Date().timeIntervalSince1970 > Double(expiry)
    }
}

/// Final result for a completed melt payment.
struct MeltPaymentResult {
    let preimage: String?
    let amount: UInt64
    let feePaid: UInt64
    let mintUrl: String
}

/// Wallet transaction
