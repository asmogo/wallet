import Cdk
import Foundation

enum NFCReceiveError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

struct NFCReceivePayment {
    let pending: PendingReceiveToken
    let needsReview: Bool
    let validationMessage: String?

    static func canPresent(_ request: CashuRequest, now: Date = Date()) -> Bool {
        (request.amount ?? 0) > 0 &&
            (request.rail == .ecash || request.receivedPayments.isEmpty) &&
            (request.expiry.map { $0 > now } ?? true)
    }

    static func validationMessage(request: CashuRequest, amount: UInt64, unit: String, mint: String) -> String? {
        if !canPresent(request) { return "This request is no longer accepting contactless payments." }
        guard amount > 0 else { return "The received token has no value." }
        guard unit.caseInsensitiveCompare(request.unit) == .orderedSame else {
            return "The received token uses a different currency from this request."
        }
        if let required = request.amount, amount < required {
            return "The received token is less than the requested amount."
        }
        if !request.mints.isEmpty,
           !request.mints.contains(where: { MintURLIdentity.normalized($0) == MintURLIdentity.normalized(mint) }) {
            return "The received token is from a different mint than this request accepts."
        }
        return nil
    }

    static func decode(_ payload: NFCNdefPayload) throws -> Token {
        switch payload {
        case .cashuBinary(let data): return try Token.fromRawBytes(bytes: data)
        case .text(let text):
            // Also accept Cashu token links written by Numo-compatible payers.
            guard let range = text.range(of: "cashuA") ?? text.range(of: "cashuB") else {
                throw NFCReceiveError.message("No Cashu token was received. Try again.")
            }
            let encoded = text[range.lowerBound...].prefix {
                $0.isASCII && ($0.isLetter || $0.isNumber || "-_=+/".contains($0))
            }
            return try Token.decode(encodedToken: String(encoded))
        }
    }
}

extension WalletManager {
    /// Save before acknowledging the final APDU. Even a disconnect, cancellation,
    /// unknown mint, or failed redeem must leave the bearer token claimable.
    func stageNFCReceive(_ payload: NFCNdefPayload, request: CashuRequest) throws -> NFCReceivePayment {
        let token = try NFCReceivePayment.decode(payload)
        let encoded = token.encode()
        let amount = try token.value().value
        let mint = try token.mintUrl().url
        let unit = PaymentRequestDecoder.unitDescription(token.unit() ?? .sat)
        let message = NFCReceivePayment.validationMessage(request: request, amount: amount, unit: unit, mint: mint)
        let known = mints.contains { MintURLIdentity.normalized($0.url) == MintURLIdentity.normalized(mint) }
        let pending = pendingReceiveTokens.first { $0.token == encoded } ?? PendingReceiveToken(
            tokenId: UUID().uuidString, token: encoded, amount: amount, unit: unit,
            date: Date(), mintUrl: mint,
            // Mismatched payments stay claimable without fulfilling this request.
            cashuRequestId: message == nil ? request.id : nil, memo: token.memo()
        )
        savePendingReceiveToken(pending)
        guard walletStore.loadPendingReceiveTokens().contains(where: { $0.token == encoded }) else {
            throw NFCReceiveError.message("Couldn't save the payment. Try again.")
        }
        return NFCReceivePayment(pending: pending, needsReview: !known || message != nil, validationMessage: message)
    }
}
