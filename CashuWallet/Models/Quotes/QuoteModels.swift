import Foundation

struct MintQuoteInfo: Identifiable {
    let id: String
    let request: String  // Payment request (BOLT11 invoice, BOLT12 offer, or on-chain address)
    let amount: UInt64?
    let paymentMethod: PaymentMethodKind
    var state: MintQuoteState
    let expiry: UInt64?
    
    var isExpired: Bool {
        guard let expiry = expiry, expiry > 0 else { return false }
        return Date().timeIntervalSince1970 > Double(expiry)
    }
}

/// Melt quote information
struct MeltQuoteInfo: Identifiable {

    let id: String
    let mintUrl: String
    let amount: UInt64
    let feeReserve: UInt64
    let paymentMethod: PaymentMethodKind
    var state: MeltQuoteState
    let expiry: UInt64?
    
    var totalAmount: UInt64 {
        amount + feeReserve
    }
    
    var isExpired: Bool {
        guard let expiry = expiry, expiry > 0 else { return false }
        return Date().timeIntervalSince1970 > Double(expiry)
    }
}

/// Final result for a completed melt payment.
struct MeltPaymentResult {
    let preimage: String?
    let amount: UInt64
    let feePaid: UInt64
    let mintUrl: String
}

/// Wallet transaction
