import Foundation

struct CashuRequestPayment: Codable, Hashable {
    let transactionId: String
    let amount: UInt64
    let receivedAt: Date
}

struct CashuRequest: Codable, Identifiable, Hashable {
    let id: String
    let encoded: String
    let amount: UInt64?
    let unit: String
    let mints: [String]
    let memo: String?
    let createdAt: Date
    var receivedPayments: [CashuRequestPayment]

    init(
        id: String = Self.newId(),
        encoded: String,
        amount: UInt64? = nil,
        unit: String = "sat",
        mints: [String] = [],
        memo: String? = nil,
        createdAt: Date = Date(),
        receivedPayments: [CashuRequestPayment] = []
    ) {
        self.id = id
        self.encoded = encoded
        self.amount = amount
        self.unit = unit
        self.mints = mints
        self.memo = memo
        self.createdAt = createdAt
        self.receivedPayments = receivedPayments
    }

    static func newId() -> String {
        UUID().uuidString.split(separator: "-").first.map(String.init) ?? UUID().uuidString
    }

    var totalReceived: UInt64 {
        receivedPayments.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Codable with legacy fallback

    private enum CodingKeys: String, CodingKey {
        case id, encoded, amount, unit, mints, memo, createdAt
        case receivedPayments
        case receivedPaymentIds  // legacy: stored as [String], no amounts
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
    }
}
