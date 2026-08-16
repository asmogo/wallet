import Foundation

struct SendTokenResult {
    let token: String
    let fee: UInt64
    /// CDK transaction id (saga-derived) recorded for this send, when known.
    /// The token string is stored under this id so History can re-display it
    /// and claim checks can resolve the operation via `TransactionId.fromSagaId`.
    var transactionId: String? = nil
}

/// Pending receive token entry — stored when the user chooses "Receive Later",
/// or when a NUT-18 payment is held for approval (auto-claim off / unknown
/// mint). Surfaced in History as a claimable pending row.
struct PendingReceiveToken: Codable, Identifiable, Equatable {
    var id: String { tokenId }
    let tokenId: String
    let token: String
    let amount: UInt64
    /// Mint account unit for `amount` ("sat", "usd", "eur", or custom).
    let unit: String
    let date: Date
    let mintUrl: String
    /// NUT-18 Cashu Request id when this payment arrived over Nostr; claiming
    /// routes through the request-attribution path so History links it to the
    /// originating request. Nil for manually parked tokens.
    let cashuRequestId: String?
    let memo: String?

    init(
        tokenId: String,
        token: String,
        amount: UInt64,
        unit: String = "sat",
        date: Date,
        mintUrl: String,
        cashuRequestId: String? = nil,
        memo: String? = nil
    ) {
        self.tokenId = tokenId
        self.token = token
        self.amount = amount
        self.unit = unit
        self.date = date
        self.mintUrl = mintUrl
        self.cashuRequestId = cashuRequestId
        self.memo = memo
    }

    private enum CodingKeys: String, CodingKey {
        case tokenId
        case token
        case amount
        case unit
        case date
        case mintUrl
        case cashuRequestId
        case memo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tokenId = try container.decode(String.self, forKey: .tokenId)
        token = try container.decode(String.self, forKey: .token)
        amount = try container.decode(UInt64.self, forKey: .amount)
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? "sat"
        date = try container.decode(Date.self, forKey: .date)
        mintUrl = try container.decode(String.self, forKey: .mintUrl)
        cashuRequestId = try container.decodeIfPresent(String.self, forKey: .cashuRequestId)
        memo = try container.decodeIfPresent(String.self, forKey: .memo)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tokenId, forKey: .tokenId)
        try container.encode(token, forKey: .token)
        try container.encode(amount, forKey: .amount)
        try container.encode(unit, forKey: .unit)
        try container.encode(date, forKey: .date)
        try container.encode(mintUrl, forKey: .mintUrl)
        try container.encodeIfPresent(cashuRequestId, forKey: .cashuRequestId)
        try container.encodeIfPresent(memo, forKey: .memo)
    }
}

/// Result of restoring proofs from a single mint via NUT-09
