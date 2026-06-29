import Foundation

struct WalletTransaction: Identifiable {
    let id: String
    let amount: UInt64
    let type: TransactionType
    let kind: TransactionKind
    let date: Date
    let memo: String?
    var status: TransactionStatus
    var statusNote: String? = nil
    
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

    /// Source Cashu Request id when this incoming ecash transaction was
    /// auto-claimed via NUT-18. History uses this to suppress the duplicate
    /// row in favor of the request row.
    var cashuRequestId: String? = nil

    /// Mint-quote id for Lightning / on-chain mints and melts. The join key
    /// used to attach this transaction to the receive-intent backing its quote
    /// (a reusable BOLT12 offer, a BOLT11 invoice, an on-chain address).
    var quoteId: String? = nil

    var displayStatusText: String {
        if status == .pending {
            return statusNote ?? status.displayText
        }

        return status.displayText
    }

    /// Canonical row/detail title — kind-first, capitalized kind, lowercase
    /// verb, parallel across all kinds (e.g. "Ecash received", "Lightning
    /// paid"). Single source of truth for the History/Home rows and the
    /// transaction detail nav title.
    var displayTitle: String {
        switch (kind, type) {
        case (.ecash,     .incoming): return "Ecash received"
        case (.ecash,     .outgoing): return "Ecash sent"
        case (.lightning, .incoming): return "Lightning received"
        case (.lightning, .outgoing): return "Lightning paid"
        case (.onchain,   .incoming): return "Bitcoin received"
        case (.onchain,   .outgoing): return "Bitcoin sent"
        }
    }

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
