import Foundation

struct MintQuoteInfo: Identifiable {
    let id: String
    let request: String  // Payment request (BOLT11 invoice, BOLT12 offer, or on-chain address)
    let amount: UInt64?
    /// Whether the quote was created without an amount. This cannot be derived
    /// from `amount`: NUT-25 reports the cumulative paid amount after the first
    /// payment, but the underlying BOLT12 offer remains amountless and reusable.
    let isAmountless: Bool
    let paymentMethod: PaymentMethodKind
    var state: MintQuoteState
    let expiry: UInt64?
    /// First-seen timestamp for the offer. Set only for reusable (amountless
    /// BOLT12) offers, which carry no creation field in the CDK quote — see
    /// `MintQuoteCreatedAtStore`. nil for every other rail.
    let createdAt: Date?

    /// The unit the quote mints into ("sat", "eur", …). `amount` is denominated
    /// in this unit's base units. Defaults to "sat" for older/sat quotes.
    var unit: String = "sat"

    /// Mint wallet that owns the quote. Quote follow-up work must use this
    /// instead of mutable active-mint state.
    var mintURL: String? = nil

    /// NUT-25's durable settlement ledger. A reusable offer is fully caught up
    /// when these values are equal; their difference is the only amount the
    /// wallet is allowed to mint.
    var amountPaid: UInt64 = 0
    var amountIssued: UInt64 = 0

    var mintableAmount: UInt64 {
        amountPaid > amountIssued ? amountPaid - amountIssued : 0
    }

    var hasSettledPayment: Bool {
        amountPaid > 0 && amountIssued >= amountPaid
    }

    var isExpired: Bool {
        guard let expiry = expiry, expiry > 0 else { return false }
        return Date().timeIntervalSince1970 > Double(expiry)
    }
}

/// Counter-verified result of reconciling one persisted mint quote. A
/// successful mint response is combined with a follow-up quote check so an
/// ambiguous network failure cannot lose a payment or mint it twice.
struct MintQuoteReconciliationResult {
    let quote: MintQuoteInfo
    let newlyIssued: UInt64
    let hadOutstandingPayment: Bool

    var remainingAmount: UInt64 { quote.mintableAmount }
    var hasSettledPayment: Bool { quote.hasSettledPayment }

    init(
        observed: MintQuoteInfo,
        mintedAmount: UInt64 = 0,
        verified: MintQuoteInfo? = nil
    ) {
        var reconciled = verified ?? observed
        reconciled.amountPaid = max(reconciled.amountPaid, observed.amountPaid)

        let inferredIssued: UInt64
        let (sum, overflow) = observed.amountIssued.addingReportingOverflow(mintedAmount)
        inferredIssued = overflow ? UInt64.max : sum
        reconciled.amountIssued = max(reconciled.amountIssued, inferredIssued)

        if reconciled.amountPaid > 0,
           reconciled.amountIssued >= reconciled.amountPaid {
            reconciled.state = .issued
        } else if reconciled.amountPaid > reconciled.amountIssued {
            reconciled.state = .paid
        }

        let verifiedAdvance = reconciled.amountIssued > observed.amountIssued
            ? reconciled.amountIssued - observed.amountIssued
            : 0
        quote = reconciled
        newlyIssued = max(mintedAmount, verifiedAdvance)
        hadOutstandingPayment = observed.amountPaid > observed.amountIssued
    }
}

/// Remembers when each reusable (amountless BOLT12) offer was first materialized.
/// The CDK `MintQuote` has no creation timestamp, and the same offer is reused
/// across opens via `LightningService.existingAmountlessOffer(mintURL:unit:)`.
/// Without a stable record, the "Created" row would drift to "now" on every
/// visit. Keyed by quote id; stamped once, read back forever after.
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
        let total = amount.addingReportingOverflow(feeReserve)
        return total.overflow ? UInt64.max : total.partialValue
    }
    
    var isExpired: Bool {
        guard let expiry = expiry, expiry > 0 else { return false }
        return Date().timeIntervalSince1970 > Double(expiry)
    }
}

/// Final result for a completed melt payment.
struct MeltPaymentResult {
    /// How the mint answered the melt confirmation. `.settled` is final (fee and
    /// preimage are real). `.pending` means the mint accepted the payment for
    /// asynchronous NUT-05 processing — common for on-chain melts — so `preimage`
    /// is nil and `feePaid` is still the quote's fee reserve, not the actual fee.
    enum Settlement {
        case settled
        case pending
    }

    let preimage: String?
    let amount: UInt64
    let feePaid: UInt64
    let mintUrl: String
    var settlement: Settlement = .settled
}

/// Wallet transaction
