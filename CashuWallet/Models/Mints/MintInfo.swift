import Foundation

struct MintInfo: Identifiable, Equatable, Codable {
    var id: String { url }
    let url: String
    var name: String
    var description: String?
    var isActive: Bool
    var balance: UInt64
    
    /// Icon URL (if available from mint info)
    var iconUrl: String?
    
    /// Supported units
    var units: [String] = ["sat"]

    /// Supported NUT-04 payment methods for receiving
    var supportedMintMethods: [PaymentMethodKind] = [.bolt11]

    /// Supported NUT-05 payment methods for sending
    var supportedMeltMethods: [PaymentMethodKind] = [.bolt11]

    /// Required on-chain confirmations for minting, if advertised by the mint
    var onchainMintConfirmations: Int? = nil
    
    /// Last updated timestamp
    var lastUpdated: Date = Date()
}

extension MintInfo {
    private enum CodingKeys: String, CodingKey {
        case url
        case name
        case description
        case isActive
        case balance
        case iconUrl
        case units
        case supportedMintMethods
        case supportedMeltMethods
        case onchainMintConfirmations
        case lastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Mint"
        description = try container.decodeIfPresent(String.self, forKey: .description)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        balance = try container.decodeIfPresent(UInt64.self, forKey: .balance) ?? 0
        iconUrl = try container.decodeIfPresent(String.self, forKey: .iconUrl)
        units = try container.decodeIfPresent([String].self, forKey: .units) ?? ["sat"]
        supportedMintMethods = try container.decodeIfPresent([PaymentMethodKind].self, forKey: .supportedMintMethods) ?? [.bolt11]
        supportedMeltMethods = try container.decodeIfPresent([PaymentMethodKind].self, forKey: .supportedMeltMethods) ?? [.bolt11]
        onchainMintConfirmations = try container.decodeIfPresent(Int.self, forKey: .onchainMintConfirmations)
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(balance, forKey: .balance)
        try container.encodeIfPresent(iconUrl, forKey: .iconUrl)
        try container.encode(units, forKey: .units)
        try container.encode(supportedMintMethods, forKey: .supportedMintMethods)
        try container.encode(supportedMeltMethods, forKey: .supportedMeltMethods)
        try container.encodeIfPresent(onchainMintConfirmations, forKey: .onchainMintConfirmations)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }
}

// Extension for notifications
