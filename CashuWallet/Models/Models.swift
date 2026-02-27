import Foundation

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
    
    /// Last updated timestamp
    var lastUpdated: Date = Date()
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
    let request: String  // Lightning invoice (bolt11)
    let amount: UInt64
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
    
    /// Lightning payment preimage (for melt transactions)
    var preimage: String?
    
    /// Ecash token string (for outgoing pending transactions)
    var token: String?
    
    /// Lightning invoice (bolt11) for Lightning transactions
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
        
        var displayName: String {
            switch self {
            case .ecash: return "Ecash"
            case .lightning: return "Lightning"
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
