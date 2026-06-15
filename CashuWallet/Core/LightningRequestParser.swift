import Foundation
import Cdk

enum LightningRequestParser {
    struct ParsedRequest {
        let request: String
        let method: PaymentMethod
    }

    static func normalize(_ request: String) -> String {
        let trimmedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let lightningPrefixes = ["lightning://", "lightning:"]

        for prefix in lightningPrefixes where trimmedRequest.lowercased().hasPrefix(prefix) {
            return String(trimmedRequest.dropFirst(prefix.count))
        }

        return trimmedRequest
    }

    static func parse(_ request: String) throws -> ParsedRequest {
        let normalizedRequest = normalize(request)
        let decodedRequest = try decodeInvoice(invoiceStr: normalizedRequest)

        let method: PaymentMethod
        switch decodedRequest.paymentType {
        case .bolt11:
            method = .bolt11
        case .bolt12:
            method = .bolt12
        }

        return ParsedRequest(request: normalizedRequest, method: method)
    }
}
