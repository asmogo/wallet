import Foundation
import Cdk

/// Display-safe summary of a NUT-18/NUT-26 Cashu payment request.
struct CashuPaymentRequestSummary: Equatable, Sendable {
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

struct LightningRequestMetadata: Equatable, Sendable {
    let normalizedRequest: String
    let paymentMethod: PaymentMethodKind
    let amountSats: UInt64?
    let amountMsat: UInt64?
}

struct TokenPreview: Equatable, Sendable {
    let amount: UInt64
    let mintUrl: String
    let p2pkPubkeys: [String]
}

/// Non-main CDK boundary for synchronous FFI helpers.
///
/// CDK's wallet operations are mostly exposed as real async UniFFI futures, but
/// parsing helpers like `decodeInvoice`, `decodePaymentRequest`, and
/// `Token.decode` are synchronous. Keeping those behind this actor prevents
/// SwiftUI body recomputation and input handling from doing FFI work on the main
/// actor while still returning plain app values to views.
actor CdkRuntime {
    static let shared = CdkRuntime()

    private init() {}

    func decodePaymentRequest(
        _ raw: String,
        includeCashuPaymentRequests: Bool = false,
        preferCashuPaymentRequests: Bool = false
    ) -> PaymentRequestDecodeResult {
        PaymentRequestDecoder.decode(
            raw,
            includeCashuPaymentRequests: includeCashuPaymentRequests,
            preferCashuPaymentRequests: preferCashuPaymentRequests
        )
    }

    func normalizedLightningRequest(from raw: String) -> String? {
        PaymentRequestDecoder.encodedLightningRequest(from: raw)
    }

    func lightningMetadata(from raw: String) -> LightningRequestMetadata? {
        let normalized = PaymentRequestDecoder.encodedLightningRequest(from: raw)
            ?? PaymentRequestParser.normalizeLightningRequest(raw)

        guard !normalized.isEmpty else { return nil }

        if let decoded = try? decodeInvoice(invoiceStr: normalized) {
            let paymentMethod: PaymentMethodKind
            switch decoded.paymentType {
            case .bolt11:
                paymentMethod = .bolt11
            case .bolt12:
                paymentMethod = .bolt12
            }

            return LightningRequestMetadata(
                normalizedRequest: normalized,
                paymentMethod: paymentMethod,
                amountSats: decoded.amountMsat.map(PaymentRequestDecoder.satsCeiling(from:)),
                amountMsat: decoded.amountMsat
            )
        }

        guard let offer = PaymentRequestParser.bolt12OfferMetadata(from: normalized) else { return nil }

        return LightningRequestMetadata(
            normalizedRequest: offer.normalizedRequest,
            paymentMethod: .bolt12,
            amountSats: offer.amountMsat.map(PaymentRequestDecoder.satsCeiling(from:)),
            amountMsat: offer.amountMsat
        )
    }

    func tokenPreview(from tokenString: String) throws -> TokenPreview {
        let token = try Token.decode(encodedToken: tokenString)
        return TokenPreview(
            amount: try token.value().value,
            mintUrl: try token.mintUrl().url,
            p2pkPubkeys: token.p2pkPubkeys()
        )
    }
}

/// Typed result of decoding a raw payment request string.
enum PaymentRequestDecodeResult: Equatable, Sendable {
    case lightningAddress(String)
    case bolt11(amountSats: UInt64?, description: String?)
    case bolt12(amountSats: UInt64?, description: String?)
    case onchain(String)
    case cashuPaymentRequest(CashuPaymentRequestSummary)
    case unrecognized
}

extension PaymentRequestDecodeResult {
    /// Clean caution copy for amountless request types this wallet still cannot
    /// pay. BOLT12 offers are intentionally excluded: Send collects an amount
    /// and passes it through CDK's amountless melt option.
    var amountlessMeltCaution: String? {
        switch self {
        case .bolt11(let amountSats, _) where amountSats == nil:
            return "This invoice doesn't set an amount. Ask the sender for one with the amount set."
        default:
            return nil
        }
    }
}

enum PaymentRequestMode: String, Equatable, Sendable {
    case lightning
    case onchain
}

/// Centralized payment-request decoder. Wraps `PaymentRequestParser` +
/// CashuDevKit's `decodeInvoice`, with a BOLT12 envelope/TLV fallback for
/// valid amountless offers that CDK's stricter decoder rejects. The chip
/// preview, recents tap, scan callback, and live decode feedback all share this
/// single classification path.
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

        let normalized: String
        if let bitcoinURI = bitcoinPaymentURI(from: trimmed),
           let lightning = bitcoinURI.lightning {
            normalized = PaymentRequestParser.normalizeLightningRequest(lightning)
        } else {
            normalized = PaymentRequestParser.normalizeLightningRequest(trimmed)
        }

        if let offer = PaymentRequestParser.bolt12OfferMetadata(from: normalized) {
            return offer.normalizedRequest
        }

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

    static func parseCashuPaymentRequest(_ raw: String) throws -> Cdk.PaymentRequest {
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
        guard let normalized = encodedLightningRequest(from: raw) else { return nil }

        if let decoded = try? decodeInvoice(invoiceStr: normalized) {
            let amountSats: UInt64? = decoded.amountMsat.map(satsCeiling(from:))
            switch decoded.paymentType {
            case .bolt11:
                return .bolt11(amountSats: amountSats, description: decoded.description)
            case .bolt12:
                return .bolt12(amountSats: amountSats, description: decoded.description)
            }
        }

        guard let offer = PaymentRequestParser.bolt12OfferMetadata(from: normalized) else { return nil }
        return .bolt12(
            amountSats: offer.amountMsat.map(satsCeiling(from:)),
            description: offer.description
        )
    }

    fileprivate static func satsCeiling(from amountMsat: UInt64) -> UInt64 {
        amountMsat / 1000 + (amountMsat % 1000 == 0 ? 0 : 1)
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

    /// `prefix(8)…suffix(6)` middle-truncation for opaque destination blobs (invoices,
    /// on-chain addresses, encoded Cashu requests). Short strings are returned in full.
    static func middleTruncated(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 16 else { return trimmed }
        return "\(trimmed.prefix(8))…\(trimmed.suffix(6))"
    }

    /// Short representation for invoices and addresses; human-readable addresses are
    /// returned in full.
    static func shortRepresentation(_ raw: String, result: PaymentRequestDecodeResult) -> String {
        switch result {
        case .lightningAddress(let address):
            return address
        case .cashuPaymentRequest(let summary):
            return summary.description ?? amountLabel(for: summary) ?? "Cashu payment request"
        case .bolt11, .bolt12, .onchain, .unrecognized:
            return middleTruncated(raw)
        }
    }

    static func amountLabel(for summary: CashuPaymentRequestSummary) -> String? {
        guard let amount = summary.amount else { return nil }
        return "\(amount) \(summary.unit ?? "sat")"
    }

    static func suggestedMode(_ result: PaymentRequestDecodeResult) -> MeltView.MeltMode? {
        switch result {
        case .bolt11, .bolt12, .lightningAddress:
            return .lightning
        case .onchain:
            return .onchain
        case .cashuPaymentRequest, .unrecognized:
            return nil
        }
    }

    static func unitDescription(_ unit: Cdk.CurrencyUnit) -> String {
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

    /// Inverse of `unitDescription`: maps a mint's unit string to a CDK
    /// `CurrencyUnit`. Unknown strings pass through as `.custom(unit:)` so
    /// arbitrary mint units are supported, not just sat/usd/eur.
    static func currencyUnit(from unit: String) -> Cdk.CurrencyUnit {
        switch unit.lowercased() {
        case "sat":
            return .sat
        case "msat":
            return .msat
        case "usd":
            return .usd
        case "eur":
            return .eur
        case "auth":
            return .auth
        default:
            return .custom(unit: unit)
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
