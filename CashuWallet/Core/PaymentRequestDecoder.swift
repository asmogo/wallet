import Foundation
import CashuDevKit

/// Display-safe summary of a NUT-18/NUT-26 Cashu payment request.
struct CashuPaymentRequestSummary: Equatable {
    let encoded: String
    let amount: UInt64?
    let unit: String?
    let description: String?
    let mints: [String]

    var isSatUnit: Bool {
        guard let unit else { return true }
        return unit.lowercased() == "sat"
    }
}

/// Typed result of decoding a raw payment request string.
enum PaymentRequestDecodeResult: Equatable {
    case lightningAddress(String)
    case bolt11(amountSats: UInt64?, description: String?)
    case bolt12(amountSats: UInt64?, description: String?)
    case onchain(String)
    case cashuPaymentRequest(CashuPaymentRequestSummary)
    case unrecognized
}

/// Centralized payment-request decoder. Wraps `PaymentRequestParser` +
/// CashuDevKit's `decodeInvoice` so the chip preview, recents tap, scan
/// callback, and live decode feedback all share a single classification path.
enum PaymentRequestDecoder {
    static func decode(
        _ raw: String,
        includeCashuPaymentRequests: Bool = false,
        preferCashuPaymentRequests: Bool = false
    ) -> PaymentRequestDecodeResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unrecognized }

        if includeCashuPaymentRequests,
           preferCashuPaymentRequests,
           let summary = cashuPaymentRequestSummary(from: trimmed) {
            return .cashuPaymentRequest(summary)
        }

        if let decoded = decodedLightningRequest(from: trimmed) {
            return decoded
        }

        if PaymentRequestParser.isHumanReadableLightningAddress(trimmed) {
            return .lightningAddress(trimmed)
        }

        if PaymentRequestParser.isBitcoinAddress(trimmed) {
            return .onchain(PaymentRequestParser.normalizeBitcoinRequest(trimmed))
        }

        if includeCashuPaymentRequests,
           let summary = cashuPaymentRequestSummary(from: trimmed) {
            return .cashuPaymentRequest(summary)
        }

        return .unrecognized
    }

    static func encodedLightningRequest(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let bitcoinURI = bitcoinPaymentURI(from: trimmed),
           let lightning = bitcoinURI.lightning {
            return PaymentRequestParser.normalizeLightningRequest(lightning)
        }

        let normalized = PaymentRequestParser.normalizeLightningRequest(trimmed)
        guard (try? decodeInvoice(invoiceStr: normalized)) != nil else {
            return nil
        }

        return normalized
    }

    static func encodedCashuPaymentRequest(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let bitcoinURI = bitcoinPaymentURI(from: trimmed),
           let creq = bitcoinURI.creq {
            return creq
        }

        let withoutCashuScheme = stripSchemePrefixes(["cashu://", "cashu:"], from: trimmed)
        let lowercased = withoutCashuScheme.lowercased()
        guard lowercased.hasPrefix("creqa") || lowercased.hasPrefix("creqb1") else {
            return nil
        }

        return withoutCashuScheme
    }

    static func parseCashuPaymentRequest(_ raw: String) throws -> CashuDevKit.PaymentRequest {
        guard let encoded = encodedCashuPaymentRequest(from: raw) else {
            throw PaymentRequestDecodeError.noCashuPaymentRequest
        }

        return try decodePaymentRequest(encoded: encoded)
    }

    static func cashuPaymentRequestSummary(from raw: String) -> CashuPaymentRequestSummary? {
        guard let encoded = encodedCashuPaymentRequest(from: raw),
              let request = try? decodePaymentRequest(encoded: encoded) else {
            return nil
        }

        return CashuPaymentRequestSummary(
            encoded: encoded,
            amount: request.amount()?.value,
            unit: request.unit().map(unitDescription),
            description: request.description(),
            mints: request.mints()
        )
    }

    private static func decodedLightningRequest(from raw: String) -> PaymentRequestDecodeResult? {
        guard let normalized = encodedLightningRequest(from: raw),
              let decoded = try? decodeInvoice(invoiceStr: normalized) else {
            return nil
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
        case .lightningAddress, .onchain, .cashuPaymentRequest, .unrecognized:
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
        case .cashuPaymentRequest, .unrecognized:
            return nil
        }
    }

    /// SF Symbol for the result type. Used by chip + live feedback.
    static func iconName(_ result: PaymentRequestDecodeResult) -> String {
        switch result {
        case .lightningAddress: return "at"
        case .bolt11, .bolt12: return "bolt.fill"
        case .onchain: return "bitcoinsign.circle"
        case .cashuPaymentRequest: return "banknote"
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
        case .cashuPaymentRequest: return "Cashu request"
        case .unrecognized: return "Unrecognized"
        }
    }

    /// `prefix(6)…suffix(6)` short representation for invoices and addresses;
    /// human-readable addresses are returned in full.
    static func shortRepresentation(_ raw: String, result: PaymentRequestDecodeResult) -> String {
        switch result {
        case .lightningAddress(let address):
            return address
        case .cashuPaymentRequest(let summary):
            return summary.description ?? amountLabel(for: summary) ?? "Cashu payment request"
        case .bolt11, .bolt12, .onchain, .unrecognized:
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 16 else { return trimmed }
            return "\(trimmed.prefix(8))…\(trimmed.suffix(6))"
        }
    }

    static func amountLabel(for summary: CashuPaymentRequestSummary) -> String? {
        guard let amount = summary.amount else { return nil }
        return "\(amount) \(summary.unit ?? "sat")"
    }

    static func unitDescription(_ unit: CashuDevKit.CurrencyUnit) -> String {
        switch unit {
        case .sat:
            return "sat"
        case .msat:
            return "msat"
        case .usd:
            return "usd"
        case .eur:
            return "eur"
        case .auth:
            return "auth"
        case .custom(let unit):
            return unit
        }
    }

    private static func bitcoinPaymentURI(from raw: String) -> BitcoinPaymentURI? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "bitcoin" else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        let creq = queryValue(named: ["creq"], in: queryItems)
        let lightning = queryValue(named: ["lightning", "lightninginvoice"], in: queryItems)

        return BitcoinPaymentURI(creq: creq, lightning: lightning)
    }

    private static func queryValue(named names: Set<String>, in queryItems: [URLQueryItem]) -> String? {
        queryItems.first { names.contains($0.name.lowercased()) }?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripSchemePrefixes(_ prefixes: [String], from input: String) -> String {
        for prefix in prefixes where input.lowercased().hasPrefix(prefix) {
            return String(input.dropFirst(prefix.count))
        }
        return input
    }

    private struct BitcoinPaymentURI {
        let creq: String?
        let lightning: String?
    }

    private enum PaymentRequestDecodeError: Error {
        case noCashuPaymentRequest
    }
}
