import Foundation

struct CashuRequest: Codable, Identifiable, Hashable {
    let id: String
    let encoded: String
    let amount: UInt64?
    let unit: String
    let mints: [String]
    let memo: String?
    let createdAt: Date
    var receivedPaymentIds: [String]

    init(
        id: String = Self.newId(),
        encoded: String,
        amount: UInt64? = nil,
        unit: String = "sat",
        mints: [String] = [],
        memo: String? = nil,
        createdAt: Date = Date(),
        receivedPaymentIds: [String] = []
    ) {
        self.id = id
        self.encoded = encoded
        self.amount = amount
        self.unit = unit
        self.mints = mints
        self.memo = memo
        self.createdAt = createdAt
        self.receivedPaymentIds = receivedPaymentIds
    }

    static func newId() -> String {
        UUID().uuidString.split(separator: "-").first.map(String.init) ?? UUID().uuidString
    }
}
