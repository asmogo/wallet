import Foundation
import CashuDevKit

/// Typed result of decoding a raw payment request string.
enum PaymentRequestDecodeResult: Equatable {
    case lightningAddress(String)
    case bolt11(amountSats: UInt64?, description: String?)
    case bolt12(amountSats: UInt64?, description: String?)
    case onchain(String)
    case unrecognized
}

/// Centralized payment-request decoder. Wraps `PaymentRequestParser` +
/// CashuDevKit's `decodeInvoice` so the chip preview, recents tap, scan
/// callback, and live decode feedback all share a single classification path.
enum PaymentRequestDecoder {
    static func decode(_ raw: String) -> PaymentRequestDecodeResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unrecognized }

        if PaymentRequestParser.isBitcoinAddress(trimmed) {
            return .onchain(PaymentRequestParser.normalizeBitcoinRequest(trimmed))
        }

        if PaymentRequestParser.isHumanReadableLightningAddress(trimmed) {
            return .lightningAddress(trimmed)
        }

        let normalized = PaymentRequestParser.normalizeLightningRequest(trimmed)
        guard let decoded = try? decodeInvoice(invoiceStr: normalized) else {
            return .unrecognized
        }

        let amountSats: UInt64? = decoded.amountMsat.map { $0 / 1000 }
        switch decoded.paymentType {
        case .bolt11:
            return .bolt11(amountSats: amountSats, description: decoded.description)
        case .bolt12:
            return .bolt12(amountSats: amountSats, description: decoded.description)
        }
    }

    /// True if the request carries an enforceable amount the user can't change
    /// (BOLT11 with amount, amountful BOLT12). Triggers auto-quote on tap.
    static func amountLocked(_ result: PaymentRequestDecodeResult) -> Bool {
        switch result {
        case .bolt11(let amount, _), .bolt12(let amount, _):
            return amount != nil
        case .lightningAddress, .onchain, .unrecognized:
            return false
        }
    }

    /// Which `MeltView.MeltMode` this result wants. Nil means caller's current
    /// mode is fine.
    static func suggestedMode(_ result: PaymentRequestDecodeResult) -> MeltView.MeltMode? {
        switch result {
        case .onchain:
            return .onchain
        case .bolt11, .bolt12, .lightningAddress:
            return .lightning
        case .unrecognized:
            return nil
        }
    }

    /// SF Symbol for the result type. Used by chip + live feedback.
    static func iconName(_ result: PaymentRequestDecodeResult) -> String {
        switch result {
        case .lightningAddress: return "at"
        case .bolt11, .bolt12: return "bolt.fill"
        case .onchain: return "bitcoinsign.circle"
        case .unrecognized: return "questionmark.circle"
        }
    }

    /// Short human label for the type.
    static func typeLabel(_ result: PaymentRequestDecodeResult) -> String {
        switch result {
        case .lightningAddress: return "Lightning address"
        case .bolt11: return "BOLT11 invoice"
        case .bolt12: return "BOLT12 offer"
        case .onchain: return "Bitcoin address"
        case .unrecognized: return "Unrecognized"
        }
    }

    /// `prefix(6)…suffix(6)` short representation for invoices and addresses;
    /// human-readable addresses are returned in full.
    static func shortRepresentation(_ raw: String, result: PaymentRequestDecodeResult) -> String {
        switch result {
        case .lightningAddress(let address):
            return address
        case .bolt11, .bolt12, .onchain, .unrecognized:
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 16 else { return trimmed }
            return "\(trimmed.prefix(8))…\(trimmed.suffix(6))"
        }
    }
}
