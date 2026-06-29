import Foundation

struct CashuRequestPayment: Codable, Hashable {
    let transactionId: String
    let amount: UInt64
    let receivedAt: Date
}

/// A "receive intent" — anything the user holds out to get paid, across every
/// rail. Originally NUT-18 Cashu Requests only (hence the type name, kept until
/// the final rename pass); now also BOLT12 reusable offers, BOLT11 invoices, and
/// on-chain addresses, so every receive artifact behaves the same in history:
/// one persistent, re-openable, payment-aggregating timeline object.
struct CashuRequest: Codable, Identifiable, Hashable {

    /// The payment rail this intent was created on. `.ecash` is the original
    /// NUT-18 Cashu Request; the other three are the Lightning / on-chain
    /// receive artifacts that now persist as first-class intents too.
    enum Rail: String, Codable {
        case ecash, bolt11, bolt12, onchain
    }

    /// Coarse lifecycle, derived from rail + payments + expiry. Replaces the old
    /// "0 payments = pending / ≥1 = completed" binary, which mis-modelled
    /// reusable artifacts (a Cashu Request that took one payment is still
    /// actively collecting, not "completed").
    enum Lifecycle {
        case waiting     // created, nothing received yet
        case collecting  // reusable, ≥1 payment, still live
        case received    // one-shot, fulfilled
        case expired     // one-shot, past expiry, nothing received
    }

    let id: String
    let encoded: String
    let amount: UInt64?
    let unit: String
    let mints: [String]
    let memo: String?
    let createdAt: Date
    var receivedPayments: [CashuRequestPayment]

    /// Which rail this intent lives on. Defaults to `.ecash` so legacy stored
    /// Cashu Requests (which predate the field) decode unchanged.
    let rail: Rail

    /// Reusable artifacts (ecash request, BOLT12 offer) keep collecting and
    /// never auto-settle; one-shot artifacts (BOLT11 invoice, on-chain address)
    /// settle on first receipt.
    let reusable: Bool

    /// Mint-quote id for the non-ecash rails — the join key used to attach
    /// incoming CDK transactions to this intent and suppress their duplicate
    /// timeline rows. nil for ecash, which links via the NUT-18 transaction-id
    /// diff instead.
    let quoteId: String?

    /// One-shot expiry (BOLT11 invoices). nil for reusable / never-expiring rails.
    let expiry: Date?

    init(
        id: String = Self.newId(),
        encoded: String,
        amount: UInt64? = nil,
        unit: String = "sat",
        mints: [String] = [],
        memo: String? = nil,
        createdAt: Date = Date(),
        receivedPayments: [CashuRequestPayment] = [],
        rail: Rail = .ecash,
        reusable: Bool = true,
        quoteId: String? = nil,
        expiry: Date? = nil
    ) {
        self.id = id
        self.encoded = encoded
        self.amount = amount
        self.unit = unit
        self.mints = mints
        self.memo = memo
        self.createdAt = createdAt
        self.receivedPayments = receivedPayments
        self.rail = rail
        self.reusable = reusable
        self.quoteId = quoteId
        self.expiry = expiry
    }

    static func newId() -> String {
        UUID().uuidString.split(separator: "-").first.map(String.init) ?? UUID().uuidString
    }

    var totalReceived: UInt64 {
        receivedPayments.reduce(0) { $0 + $1.amount }
    }

    /// Derived lifecycle. For a reusable BOLT12 offer the cumulative total is
    /// authoritative from the mint quote's `amountIssued`; `receivedPayments`
    /// here is the per-receipt breakdown, used only to decide collecting vs
    /// waiting.
    var lifecycle: Lifecycle {
        if !receivedPayments.isEmpty {
            return reusable ? .collecting : .received
        }
        if let expiry, expiry < Date() {
            return .expired
        }
        return .waiting
    }

    /// Rail-driven row/detail title. Replaces the hardcoded "Cashu Request"
    /// string in the history rows so the artifact the user created surfaces
    /// under the name they created it under ("Reusable Invoice" for BOLT12).
    var displayTitle: String {
        switch rail {
        case .ecash:
            return "Cashu Request"
        case .bolt12:
            return "Reusable Invoice"
        case .bolt11:
            return receivedPayments.isEmpty ? "Lightning Invoice" : "Lightning received"
        case .onchain:
            return receivedPayments.isEmpty ? "Bitcoin Address" : "Bitcoin received"
        }
    }

    // MARK: - Codable with legacy fallback

    private enum CodingKeys: String, CodingKey {
        case id, encoded, amount, unit, mints, memo, createdAt
        case receivedPayments
        case receivedPaymentIds  // legacy: stored as [String], no amounts
        case rail, reusable, quoteId, expiry
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        encoded = try c.decode(String.self, forKey: .encoded)
        amount = try c.decodeIfPresent(UInt64.self, forKey: .amount)
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? "sat"
        mints = try c.decodeIfPresent([String].self, forKey: .mints) ?? []
        memo = try c.decodeIfPresent(String.self, forKey: .memo)
        createdAt = try c.decode(Date.self, forKey: .createdAt)

        // New rail metadata. Legacy entries predate these keys, so a missing
        // `rail` means the stored object is a NUT-18 Cashu Request (`.ecash`),
        // and `reusable` defaults from the rail (ecash + bolt12 are reusable).
        let decodedRail = try c.decodeIfPresent(Rail.self, forKey: .rail) ?? .ecash
        rail = decodedRail
        reusable = try c.decodeIfPresent(Bool.self, forKey: .reusable)
            ?? (decodedRail == .ecash || decodedRail == .bolt12)
        quoteId = try c.decodeIfPresent(String.self, forKey: .quoteId)
        expiry = try c.decodeIfPresent(Date.self, forKey: .expiry)

        if let payments = try c.decodeIfPresent([CashuRequestPayment].self, forKey: .receivedPayments) {
            receivedPayments = payments
        } else if let legacyIds = try c.decodeIfPresent([String].self, forKey: .receivedPaymentIds) {
            // Legacy entries never carried real amounts — they were bare UUIDs.
            // Surface them as zero-amount placeholders anchored to the request's
            // createdAt so the count is preserved (the row will still flip to
            // green) without inventing a fictitious sat value.
            let anchor = createdAt
            receivedPayments = legacyIds.map {
                CashuRequestPayment(transactionId: $0, amount: 0, receivedAt: anchor)
            }
        } else {
            receivedPayments = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(encoded, forKey: .encoded)
        try c.encodeIfPresent(amount, forKey: .amount)
        try c.encode(unit, forKey: .unit)
        try c.encode(mints, forKey: .mints)
        try c.encodeIfPresent(memo, forKey: .memo)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(receivedPayments, forKey: .receivedPayments)
        try c.encode(rail, forKey: .rail)
        try c.encode(reusable, forKey: .reusable)
        try c.encodeIfPresent(quoteId, forKey: .quoteId)
        try c.encodeIfPresent(expiry, forKey: .expiry)
    }
}
