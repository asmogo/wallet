import Foundation

// MARK: - Payment Rail Protocol

/// Protocol defining the interface for different payment rails.
/// Implementations include Lightning (current), Bolt12 (future), and Onchain (future).
///
/// Note: Named "PaymentRail" to avoid conflict with CashuDevKit.PaymentMethod enum.
/// This abstraction allows the wallet to support multiple payment rails
/// while maintaining a consistent interface for the UI layer.
protocol PaymentRail {
    /// Unique identifier for this payment method (e.g., "lightning", "bolt12", "onchain")
    var identifier: String { get }
    
    /// Human-readable display name (e.g., "Lightning", "BOLT12", "On-chain")
    var displayName: String { get }
    
    /// Whether this payment method is currently available
    var isAvailable: Bool { get }
    
    /// Create a payment request (invoice) for receiving funds
    /// - Parameters:
    ///   - amount: The amount to request
    ///   - memo: Optional memo/description for the payment
    /// - Returns: A payment request that can be shared with the sender
    func createPaymentRequest(amount: CurrencyAmount, memo: String?) async throws -> PaymentRequest
    
    /// Pay an existing payment request
    /// - Parameter request: The payment request to pay
    /// - Returns: The result of the payment attempt
    func pay(request: PaymentRequest) async throws -> PaymentResult
    
    /// Check the status of a payment
    /// - Parameter paymentId: The unique identifier of the payment
    /// - Returns: The current status of the payment
    func checkPaymentStatus(paymentId: String) async throws -> PaymentStatus
}

// MARK: - Payment Request

/// A request for payment that can be shared with a sender
struct PaymentRequest {
    /// Unique identifier for this request
    let id: String
    
    /// The payment rail this request is for
    let paymentRail: String
    
    /// The requested amount
    let amount: CurrencyAmount
    
    /// Encoded request string (e.g., bolt11 invoice, bip21 URI)
    let encodedRequest: String
    
    /// Optional memo/description
    let memo: String?
    
    /// Expiration timestamp (nil if no expiration)
    let expiresAt: Date?
    
    /// Whether the request has expired
    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() > expiresAt
    }
}

// MARK: - Payment Result

/// Result of a payment attempt
struct PaymentResult {
    /// Whether the payment was successful
    let success: Bool
    
    /// Unique identifier for the payment
    let paymentId: String
    
    /// The amount that was actually paid
    let amount: CurrencyAmount
    
    /// Fee paid for the payment
    let fee: CurrencyAmount
    
    /// Payment preimage (for Lightning payments)
    let preimage: String?
    
    /// Error message if payment failed
    let errorMessage: String?
}

// MARK: - Payment Status

/// Status of a payment
enum PaymentStatus {
    case pending
    case completed(preimage: String?)
    case failed(reason: String)
    case expired
    
    var isPending: Bool {
        if case .pending = self { return true }
        return false
    }
    
    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
}
