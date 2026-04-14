import Foundation
import CashuDevKit

enum PaymentMethodKind: String, CaseIterable, Codable, Hashable {
    case bolt11
    case bolt12
    case onchain

    static func from(_ cdkMethod: CashuDevKit.PaymentMethod) -> PaymentMethodKind? {
        switch cdkMethod {
        case .bolt11:
            return .bolt11
        case .bolt12:
            return .bolt12
        case .custom(let method):
            return method.lowercased() == PaymentMethodKind.onchain.rawValue ? .onchain : nil
        }
    }

    var cdkMethod: CashuDevKit.PaymentMethod {
        switch self {
        case .bolt11:
            return .bolt11
        case .bolt12:
            return .bolt12
        case .onchain:
            return .custom(method: rawValue)
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

    var requiresMeltAmount: Bool {
        switch self {
        case .onchain:
            return true
        case .bolt11, .bolt12:
            return false
        }
    }
}

enum PaymentRequestParser {
    static func normalizeLightningRequest(_ request: String) -> String {
        let trimmedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let lightningPrefix = "lightning:"

        if trimmedRequest.lowercased().hasPrefix(lightningPrefix) {
            return String(trimmedRequest.dropFirst(lightningPrefix.count))
        }

        return trimmedRequest
    }

    static func normalizeBitcoinRequest(_ request: String) -> String {
        let trimmedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "bitcoin:"

        let withoutScheme: String
        if trimmedRequest.lowercased().hasPrefix(prefix) {
            withoutScheme = String(trimmedRequest.dropFirst(prefix.count))
        } else {
            withoutScheme = trimmedRequest
        }

        return withoutScheme.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? withoutScheme
    }

    static func isBitcoinAddress(_ request: String) -> Bool {
        let normalizedRequest = normalizeBitcoinRequest(request).lowercased()
        return normalizedRequest.hasPrefix("bc1")
            || normalizedRequest.hasPrefix("tb1")
            || normalizedRequest.hasPrefix("bcrt1")
            || normalizedRequest.hasPrefix("1")
            || normalizedRequest.hasPrefix("3")
            || normalizedRequest.hasPrefix("2")
            || normalizedRequest.hasPrefix("m")
            || normalizedRequest.hasPrefix("n")
    }

    static func isHumanReadableLightningAddress(_ request: String) -> Bool {
        let trimmedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmedRequest.firstIndex(of: "@") else { return false }
        let user = trimmedRequest[trimmedRequest.startIndex..<atIndex]
        let domain = trimmedRequest[trimmedRequest.index(after: atIndex)...]
        return !user.isEmpty && domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    static func paymentMethod(for request: String) -> PaymentMethodKind? {
        if isBitcoinAddress(request) {
            return .onchain
        }

        let normalizedRequest = normalizeLightningRequest(request)
        guard !normalizedRequest.isEmpty else { return nil }
        guard let decodedRequest = try? decodeInvoice(invoiceStr: normalizedRequest) else {
            return nil
        }

        switch decodedRequest.paymentType {
        case .bolt11:
            return .bolt11
        case .bolt12:
            return .bolt12
        }
    }
}

/// Mint information
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
extension Notification.Name {
    static let cashuTokenReceived = Notification.Name("cashuTokenReceived")
    static let cashuTokenClaimed = Notification.Name("cashuTokenClaimed")
    static let cashuTransactionsUpdated = Notification.Name("cashuTransactionsUpdated")
}

/// Mint quote information
struct MintQuoteInfo: Identifiable {
    let id: String
    let request: String  // Payment request (BOLT11 invoice, BOLT12 offer, or on-chain address)
    let amount: UInt64?
    let paymentMethod: PaymentMethodKind
    var state: MintQuoteState
    let expiry: UInt64?
    
    var isExpired: Bool {
        guard let expiry = expiry else { return false }
        return Date().timeIntervalSince1970 > Double(expiry)
    }
}

/// Melt quote information
struct MeltQuoteInfo: Identifiable {

    let id: String
    let amount: UInt64
    let feeReserve: UInt64
    let paymentMethod: PaymentMethodKind
    var state: MeltQuoteState
    let expiry: UInt64?
    
    var totalAmount: UInt64 {
        amount + feeReserve
    }
    
    var isExpired: Bool {
        guard let expiry = expiry else { return false }
        return Date().timeIntervalSince1970 > Double(expiry)
    }
}

/// Wallet transaction
struct WalletTransaction: Identifiable {
    let id: String
    let amount: UInt64
    let type: TransactionType
    let kind: TransactionKind
    let date: Date
    let memo: String?
    var status: TransactionStatus
    
    /// Associated mint URL
    var mintUrl: String?
    
    /// Payment proof (preimage for Lightning, txid for on-chain when exposed)
    var preimage: String?
    
    /// Ecash token string (for outgoing pending transactions)
    var token: String?
    
    /// Payment request string (BOLT11 invoice, BOLT12 offer, or on-chain address)
    var invoice: String?
    
    /// Fee paid for the transaction (in sats)
    var fee: UInt64 = 0
    
    /// Whether this is from pending storage vs. completed transactions
    var isPendingToken: Bool = false
    
    enum TransactionType {
        case incoming   // Mint or receive
        case outgoing   // Send or melt
        
        var icon: String {
            switch self {
            case .incoming: return "arrow.down.circle.fill"
            case .outgoing: return "arrow.up.circle.fill"
            }
        }
    }
    
    /// Kind of transaction - distinguishes between Ecash and Lightning
    enum TransactionKind {
        case ecash      // Ecash token send/receive
        case lightning  // Lightning invoice mint/melt
        case onchain    // On-chain address mint/melt
        
        var displayName: String {
            switch self {
            case .ecash: return "Ecash"
            case .lightning: return "Lightning"
            case .onchain: return "On-chain"
            }
        }
    }
    
    enum TransactionStatus {
        case pending
        case completed
        case failed
        
        var displayText: String {
            switch self {
            case .pending: return "Pending"
            case .completed: return "Completed"
            case .failed: return "Failed"
            }
        }
    }
}

/// Result of a send tokens operation - includes token string and fee paid
struct SendTokenResult {
    let token: String
    let fee: UInt64
}

/// Pending token entry - stored when user sends ecash
struct PendingToken: Codable, Identifiable {
    var id: String { tokenId }
    let tokenId: String
    let token: String
    let amount: UInt64
    let fee: UInt64
    let date: Date
    let mintUrl: String
    let memo: String?
}

/// Pending receive token entry - stored when user chooses "Receive Later"
struct PendingReceiveToken: Codable, Identifiable {
    var id: String { tokenId }
    let tokenId: String
    let token: String
    let amount: UInt64
    let date: Date
    let mintUrl: String
}

/// Claimed token entry - stored when a sent token is claimed by recipient
struct ClaimedToken: Codable, Identifiable {
    var id: String { tokenId }
    let tokenId: String
    let token: String
    let amount: UInt64
    let fee: UInt64
    let date: Date
    let mintUrl: String
    let memo: String?
    let claimedDate: Date
}

/// Result of restoring proofs from a single mint via NUT-09
struct RestoreMintResult: Identifiable {
    var id: String { mintUrl }
    let mintUrl: String
    let mintName: String
    let spent: UInt64
    let unspent: UInt64
    let pending: UInt64

    var totalRecovered: UInt64 { unspent + pending }
}

/// Token parsed information
struct TokenInfo {
    let amount: UInt64
    let mint: String
    let unit: String
    let memo: String?
    let proofCount: Int
    
    /// Parse a cashu token string
    static func parse(_ tokenString: String) -> TokenInfo? {
        // Basic parsing - cdk-swift handles the actual token parsing
        // This is for display purposes
        
        guard tokenString.hasPrefix("cashu") else { return nil }
        
        // For now, return placeholder - actual parsing done by cdk-swift
        return TokenInfo(
            amount: 0,
            mint: "",
            unit: "sat",
            memo: nil,
            proofCount: 0
        )
    }
}

// MARK: - Data Extensions

import CryptoKit

extension Data {
    /// SHA256 hash of the data
    func sha256() -> Data {
        let hash = SHA256.hash(data: self)
        return Data(hash)
    }
}
