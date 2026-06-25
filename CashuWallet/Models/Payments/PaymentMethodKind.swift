import Cdk

enum PaymentMethodKind: String, CaseIterable, Codable, Hashable {
    case bolt11
    case bolt12
    case onchain

    static func from(_ cdkMethod: Cdk.PaymentMethod) -> PaymentMethodKind? {
        switch cdkMethod {
        case .bolt11:
            return .bolt11
        case .bolt12:
            return .bolt12
        case .onchain:
            return .onchain
        case .custom(let method):
            return method.lowercased() == PaymentMethodKind.onchain.rawValue ? .onchain : nil
        }
    }

    var cdkMethod: Cdk.PaymentMethod {
        switch self {
        case .bolt11:
            return .bolt11
        case .bolt12:
            return .bolt12
        case .onchain:
            return .onchain
        }
    }

    var displayName: String {
        switch self {
        case .bolt11:
            return "BOLT11"
        case .bolt12:
            return "BOLT12"
        case .onchain:
            return "On-chain"
        }
    }

    var symbol: String {
        switch self {
        case .bolt11:
            return "\u{26A1}"
        case .bolt12:
            return "\u{1F517}"
        case .onchain:
            return "\u{20BF}"
        }
    }

    var requestDisplayName: String {
        switch self {
        case .bolt11:
            return "Invoice"
        case .bolt12:
            return "Offer"
        case .onchain:
            return "Address"
        }
    }

    /// Plain-language title for the receive method picker, in place of the
    /// protocol jargon (`displayName`). Used by the method chip + picker sheet.
    var friendlyTitle: String {
        switch self {
        case .bolt11:
            return "Lightning invoice"
        case .bolt12:
            return "Reusable offer"
        case .onchain:
            return "On-chain address"
        }
    }

    /// One-line descriptor shown beneath `friendlyTitle` in the picker sheet.
    var friendlyDescriptor: String {
        switch self {
        case .bolt11:
            return "One-time, instant"
        case .bolt12:
            return "Share once, paid many times"
        case .onchain:
            return "Slower, for larger amounts"
        }
    }

    /// Verb-phrase for the create CTA, matching `friendlyTitle`'s language.
    var createActionTitle: String {
        switch self {
        case .bolt11:
            return "Create invoice"
        case .bolt12:
            return "Create offer"
        case .onchain:
            return "Create address"
        }
    }

    var sortOrder: Int {
        switch self {
        case .bolt11:
            return 0
        case .bolt12:
            return 1
        case .onchain:
            return 2
        }
    }

    var requiresMintAmount: Bool {
        self != .bolt12
    }

    var supportsOptionalMintAmount: Bool {
        self == .bolt12
    }

}
