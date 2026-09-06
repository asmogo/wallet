import Foundation

struct WalletTransaction: Identifiable {
    let id: String
    let amount: UInt64
    let type: TransactionType
    let kind: TransactionKind
    let date: Date
    var memo: String?

    var displayDescription: String? {
        if let memo, !memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return memo }
        return PaymentRequestDecoder.description(from: invoice)
    }

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

    /// Mint account unit for `amount` ("sat", "usd", "eur", or custom).
    var unit: String = "sat"

    /// CDK wallet-saga (operation) id backing this transaction, when the row
    /// came from CDK. Pending sent tokens use it for `checkSendStatus` /
    /// `revokeSend`; nil for app-synthesized rows (quotes, held receives).
    var sagaId: String? = nil

    /// Incoming ecash the user hasn't claimed yet (a "Receive Later" token or
    /// a NUT-18 payment held for approval). Rows with this flag open the
    /// claim flow instead of a plain receipt.
    var isPendingReceiveToken: Bool = false

    /// Source Cashu Request id when this incoming ecash transaction was
    /// auto-claimed via NUT-18. History uses this to suppress the duplicate
    /// row in favor of the request row.
    var cashuRequestId: String? = nil

    /// Mint-quote id for Lightning / on-chain mints and melts. The join key
    /// used to attach this transaction to the receive-intent backing its quote
    /// (a reusable BOLT12 offer, a BOLT11 invoice, an on-chain address).
    var quoteId: String? = nil

    /// BOLT11 mint quote still awaiting payment — titles the row
    /// "Lightning invoice" until the invoice settles.
    var isUnpaidInvoice: Bool = false

    /// The Quiet Pending treatment (bare, muted amount) covers expired too:
    /// an expired invoice never credited the balance.
    var isUnsettled: Bool {
        status == .pending || status == .expired
    }

    /// Mint-quote id to re-check when opening this row's detail, if any.
    /// Only unsettled incoming Lightning / on-chain mint quotes (not ecash,
    /// not melts). Expired unpaid invoices are included so a late-paid NUT-04
    /// quote can still mint after the invoice timer.
    var mintQuoteIdForStatusRefresh: String? {
        guard type == .incoming else { return nil }
        guard kind == .lightning || kind == .onchain else { return nil }
        guard !isPendingReceiveToken else { return nil }
        guard invoice != nil else { return nil }
        guard status == .pending || status == .expired else { return nil }
        return quoteId ?? id
    }

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
        if isPendingReceiveToken { return "Ecash to claim" }
        // Nothing has been received while the invoice awaits payment.
        if isUnpaidInvoice { return "Lightning invoice" }
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
        case expired

        var displayText: String {
            switch self {
            case .pending: return "Pending"
            case .completed: return "Completed"
            case .failed: return "Failed"
            case .expired: return "Expired"
            }
        }
    }
}

extension Array where Element == WalletTransaction {
    /// Resolve the live row for a detail screen opened with `openId` (and the
    /// open-time `openQuoteId`). Pending quote rows use `id == quoteId`; once
    /// minting starts CDK replaces them with a saga-derived transaction id that
    /// still carries `quoteId`, so fall back to the quoteId to keep following
    /// the row as it flips Pending → Completed in place. Rows are newest-first,
    /// so a reusable offer resolves to its latest payment.
    func liveDetail(openId: String, openQuoteId: String? = nil) -> WalletTransaction? {
        first(where: { $0.id == openId })
            ?? first(where: { $0.quoteId != nil && $0.quoteId == openQuoteId })
    }
}

/// Home is a compact settled-ledger view, not an operational queue. Generated
/// receive artifacts and every non-completed state remain available in History.
enum HomeActivity {
    static func recentTransactions(
        from transactions: [WalletTransaction],
        limit: Int
    ) -> [WalletTransaction] {
        transactions
            .filter { $0.status == .completed }
            .sorted { $0.date > $1.date }
            .prefix(max(0, limit))
            .map { $0 }
    }
}

/// CDK derives the transaction id of a saga-managed operation from the
/// operation (UUID) id: the id's dash-free ASCII form becomes the 32 id bytes,
/// which the FFI then hex-encodes. Reproduced locally because the FFI helper
/// (`TransactionId.from_saga_id`) is not exported to the bindings.
enum SagaTransactionId {
    /// Operation (saga) UUID string → CDK transaction id hex.
    static func transactionIdHex(operationId: String) -> String? {
        let simple = operationId.lowercased().replacingOccurrences(of: "-", with: "")
        guard simple.count == 32, simple.allSatisfy({ $0.isHexDigit }) else { return nil }
        return Data(simple.utf8).map { String(format: "%02x", $0) }.joined()
    }

    /// CDK transaction id hex → operation (saga) UUID string, as accepted by
    /// `checkSendStatus` / `revokeSend` (UUID parsing tolerates the simple form).
    static func operationId(fromTransactionIdHex txId: String) -> String? {
        var bytes = [UInt8]()
        bytes.reserveCapacity(txId.count / 2)
        var index = txId.startIndex
        while index < txId.endIndex {
            let next = txId.index(index, offsetBy: 2, limitedBy: txId.endIndex) ?? txId.endIndex
            guard let byte = UInt8(txId[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        guard bytes.count == 32 else { return nil }
        let simple = String(decoding: bytes, as: UTF8.self)
        guard simple.count == 32, simple.allSatisfy({ $0.isHexDigit }) else { return nil }
        return simple
    }
}


extension WalletTransaction {
    /// CDK may omit a mint transaction's memo and request after settlement.
    func restoringDescription(from requests: [CashuRequest]) -> WalletTransaction {
        let request = requests.first { request in
            type == .incoming && unit.lowercased() == request.unit.lowercased() &&
                (request.receivedPayments.contains { $0.transactionId == id } || cashuRequestId == request.id ||
                    (quoteId != nil && quoteId == request.quoteId &&
                        request.mints.contains { MintURLIdentity.normalized($0) == mintUrl.map(MintURLIdentity.normalized) }))
        }
        var transaction = self
        transaction.memo = displayDescription ?? request?.displayDescription
        return transaction
    }
}
