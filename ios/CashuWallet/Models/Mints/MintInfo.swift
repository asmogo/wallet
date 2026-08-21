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
    
    /// Supported units — the union of the mint's mintable and meltable units.
    var units: [String] = ["sat"]

    /// Units the mint can MINT (NUT-04), a subset of `units`. Drives the Receive
    /// unit selector so we never offer a melt-only unit for minting.
    var mintUnits: [String] = ["sat"]

    /// Supported NUT-04 payment methods for receiving
    var supportedMintMethods: [PaymentMethodKind] = [.bolt11]

    /// Supported NUT-05 payment methods for sending
    var supportedMeltMethods: [PaymentMethodKind] = [.bolt11]

    /// NUT-04 bolt12 `MintMethodSettings.description`. Default false so records
    /// persisted before this landed, and mints that omit the field, fail closed
    /// (the Description row stays hidden until a live fetch advertises true).
    var supportsBolt12MintDescription: Bool = false

    /// Required on-chain confirmations for minting, if advertised by the mint
    var onchainMintConfirmations: Int? = nil
    
    /// Last updated timestamp
    var lastUpdated: Date = Date()
}

/// Lightweight identity + capability preview fetched for discovery / staging
/// without adding the mint to the saved wallet list.
struct MintPreviewInfo {
    let name: String?
    let iconUrl: String?
    let methods: [PaymentMethodKind]
}

extension MintInfo {
    /// True when the mint advertises more than one unit, so a unit chooser is
    /// worth surfacing. Single-unit mints hide the selector entirely.
    var supportsMultipleUnits: Bool { units.count > 1 }

    /// Preferred unit for this mint: "sat" when supported, otherwise the first
    /// unit alphabetically, falling back to "sat" for a malformed empty list.
    var defaultUnit: String {
        units.contains("sat") ? "sat" : (units.sorted().first ?? "sat")
    }

    /// Returns `unit` when this mint supports it, otherwise `defaultUnit`. Used
    /// to reset a stale selection when the active mint changes.
    func resolvedUnit(_ unit: String?) -> String {
        guard let unit, units.contains(unit) else { return defaultUnit }
        return unit
    }

    // MARK: - Mintable units (NUT-04)

    /// True when the mint can mint more than one unit — gates the Receive selector.
    var supportsMultipleMintUnits: Bool { mintUnits.count > 1 }

    /// Preferred mintable unit: "sat" when mintable, else the first sorted unit.
    var defaultMintUnit: String {
        mintUnits.contains("sat") ? "sat" : (mintUnits.sorted().first ?? "sat")
    }

    /// Returns `unit` when the mint can mint it, otherwise `defaultMintUnit`.
    func resolvedMintUnit(_ unit: String?) -> String {
        guard let unit, mintUnits.contains(unit) else { return defaultMintUnit }
        return unit
    }
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
        case mintUnits
        case supportedMintMethods
        case supportedMeltMethods
        case supportsBolt12MintDescription
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
        // Older records predate mintUnits — fall back to the full unit set so a
        // multi-unit mint keeps offering units until its next refresh repopulates.
        mintUnits = try container.decodeIfPresent([String].self, forKey: .mintUnits) ?? units
        supportedMintMethods = try container.decodeIfPresent([PaymentMethodKind].self, forKey: .supportedMintMethods) ?? [.bolt11]
        supportedMeltMethods = try container.decodeIfPresent([PaymentMethodKind].self, forKey: .supportedMeltMethods) ?? [.bolt11]
        supportsBolt12MintDescription = try container.decodeIfPresent(Bool.self, forKey: .supportsBolt12MintDescription) ?? false
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
        try container.encode(mintUnits, forKey: .mintUnits)
        try container.encode(supportedMintMethods, forKey: .supportedMintMethods)
        try container.encode(supportedMeltMethods, forKey: .supportedMeltMethods)
        try container.encode(supportsBolt12MintDescription, forKey: .supportsBolt12MintDescription)
        try container.encodeIfPresent(onchainMintConfirmations, forKey: .onchainMintConfirmations)
        try container.encode(lastUpdated, forKey: .lastUpdated)
    }
}

// Extension for notifications
