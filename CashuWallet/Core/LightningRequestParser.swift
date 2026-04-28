import Foundation
import CashuDevKit

enum LightningRequestParser {
    struct ParsedRequest {
        let request: String
        let method: PaymentMethod
    }

    static func normalize(_ request: String) -> String {
        let trimmedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let lightningPrefix = "lightning:"

        if trimmedRequest.lowercased().hasPrefix(lightningPrefix) {
            return String(trimmedRequest.dropFirst(lightningPrefix.count))
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
