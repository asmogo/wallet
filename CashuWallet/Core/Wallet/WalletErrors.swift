import Foundation
import Cdk

// MARK: - Error Types

enum WalletErrorMessage {
    static func message(for error: Error) -> String {
        if let walletError = error as? WalletError {
            return message(for: walletError)
        }

        if let ffiError = error as? Cdk.FfiError {
            return message(for: ffiError)
        }

        if let mappedMessage = message(forRawMessage: String(describing: error)) {
            return mappedMessage
        }

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty,
           !looksLikeRawCDKError(description) {
            return description
        }

        let localizedDescription = error.localizedDescription
        if !localizedDescription.isEmpty,
           !looksLikeRawCDKError(localizedDescription),
           !localizedDescription.contains("Swift.Error error 1") {
            return localizedDescription
        }

        return "Something went wrong. Try again in a moment."
    }

    private static func message(for error: WalletError) -> String {
        switch error {
        case .notInitialized:
            return "The wallet is still starting up. Try again in a moment."
        case .mintAlreadyExists:
            return "This mint is already in your wallet."
        case .invalidMnemonic:
            return "That seed phrase doesn't look right. Check the spelling and try again."
        case .insufficientBalance:
            return "Not enough spendable ecash for this payment."
        case .networkError(let message):
            if let mappedMessage = self.message(forRawMessage: message) {
                return mappedMessage
            }

            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedMessage.isEmpty,
               !looksLikeRawCDKError(trimmedMessage),
               !trimmedMessage.contains("Swift.Error error 1") {
                return trimmedMessage
            }

            return "The wallet could not complete that request. Try again in a moment."
        }
    }

    private static func message(for ffiError: Cdk.FfiError) -> String {
        switch ffiError {
        case .Cdk(let code, let errorMessage):
            return message(forCDKCode: code, rawMessage: errorMessage)
        case .Internal(let errorMessage):
            return message(forRawMessage: errorMessage)
                ?? "The wallet could not complete that request. Try again in a moment."
        }
    }

    private static func message(forCDKCode code: UInt32, rawMessage: String) -> String {
        switch code {
        case 10002:
            return "This token has already been processed by the mint."
        case 10003:
            return "This token could not be verified. Ask the sender for a new token."
        case 11001:
            return "This token was already redeemed."
        case 11002:
            return "The mint rejected this transaction because the amounts did not balance. Try again."
        case 11005:
            return "This mint does not support that unit."
        case 11006:
            return "This amount is outside the mint's allowed limits."
        case 11007:
            return "This token contains duplicate proofs and cannot be redeemed."
        case 11008:
            return "The mint rejected duplicate outputs. Try again."
        case 11009:
            return "This token mixes multiple units and cannot be redeemed here."
        case 11010:
            return "The token unit does not match this wallet action."
        case 11012:
            return "This token is still pending. Try again shortly."
        case 12001:
            return "This token uses an unknown keyset for this mint."
        case 12002:
            return "This mint no longer accepts this token's keyset."
        case 20000:
            return "The mint could not complete the Lightning payment. Try again or use another mint."
        case 20001:
            return "The invoice has not been paid yet."
        case 20002:
            return "Ecash has already been issued for this quote."
        case 20003:
            return "This mint has disabled receiving new ecash."
        case 20005:
            return "The payment is still pending. Try again shortly."
        case 20006:
            return "This invoice has already been paid."
        case 20007:
            return "This quote has expired. Create a new request."
        case 20008:
            return "The token lock signature is missing or invalid."
        case 30001:
            return "This mint requires authentication before this action."
        case 30002:
            return "Mint authentication failed. Check your mint credentials."
        case 31001:
            return "This mint requires blind authentication before this action."
        case 31002:
            return "Blind authentication failed. Check the mint and try again."
        default:
            return message(forRawMessage: rawMessage)
                ?? "The mint rejected the request. Try again or choose another mint."
        }
    }

    private static func message(forRawMessage rawMessage: String) -> String? {
        let message = extractedCDKMessage(from: rawMessage)
        let normalized = message.lowercased()

        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if normalized.contains("already being minted") {
            return "This payment is already being claimed. Give it a moment and refresh."
        }

        if normalized.contains("already issued")
            || normalized.contains("already minted")
            || normalized.contains("quote is issued")
            || normalized.contains("tokens already issued") {
            return "Ecash has already been issued for this quote."
        }

        if normalized.contains("already paid")
            || normalized.contains("request already paid")
            || normalized.contains("invoice already paid") {
            return "This invoice has already been paid."
        }

        if normalized.contains("not paid")
            || normalized.contains("unpaid quote")
            || normalized.contains("quote is not paid") {
            return "The invoice has not been paid yet."
        }

        if normalized.contains("not credited this on-chain quote yet")
            || (normalized.contains("not credited") && normalized.contains("on-chain")) {
            return "The mint has not credited this on-chain payment yet. Try again shortly."
        }

        if normalized.contains("pending quote")
            || normalized.contains("payment pending")
            || normalized.contains("quote pending") {
            return "The payment is still pending. Try again shortly."
        }

        if normalized.contains("expired quote")
            || normalized.contains("quote expired")
            || normalized.contains("invoice expired") {
            return "This quote has expired. Create a new request."
        }

        if normalized.contains("payment failed") {
            return "The payment failed. Try again or use another mint."
        }

        if normalized.contains("max fee exceeded")
            || normalized.contains("fee exceeded")
            || normalized.contains("fee is higher") {
            return "The fee is higher than the wallet limit for this payment."
        }

        if normalized.contains("insufficient")
            || normalized.contains("not enough")
            || normalized.contains("no spendable")
            || normalized.contains("no available proofs")
            || normalized.contains("balance too low") {
            return "Not enough spendable ecash for this payment."
        }

        if normalized.contains("token already spent")
            || normalized.contains("proof already used")
            || normalized.contains("already redeemed")
            || normalized.contains("proofs are spent") {
            return "This token was already redeemed."
        }

        if normalized.contains("token not verified")
            || normalized.contains("invalid proof")
            || normalized.contains("could not verify")
            || normalized.contains("dleq") {
            return "This token could not be verified. Ask the sender for a new token."
        }

        if normalized.contains("keyset not found")
            || normalized.contains("unknown keyset")
            || normalized.contains("keyset id not known") {
            return "This token uses an unknown keyset for this mint."
        }

        if normalized.contains("keyset inactive")
            || normalized.contains("inactive keyset") {
            return "This mint no longer accepts this token's keyset."
        }

        if normalized.contains("unsupported unit")
            || normalized.contains("unit unsupported") {
            return "This mint does not support that unit."
        }

        if normalized.contains("unsupported payment method")
            || normalized.contains("invalid payment method")
            || normalized.contains("payment method not supported") {
            return "This mint does not support that payment method."
        }

        if normalized.contains("no key for amount")
            || normalized.contains("amount key")
            || normalized.contains("no active keyset") {
            return "This mint cannot issue ecash for that amount right now."
        }

        if normalized.contains("amountless invoice")
            || normalized.contains("invoice amount undefined")
            || normalized.contains("amount is required") {
            return "This payment request does not include an amount."
        }

        if normalized.contains("amount out")
            || normalized.contains("outside of allowed")
            || normalized.contains("amount is outside") {
            return "This amount is outside the mint's allowed limits."
        }

        if normalized.contains("minting disabled") {
            return "This mint has disabled receiving new ecash."
        }

        if normalized.contains("melting disabled") {
            return "This mint has disabled payments."
        }

        if normalized.contains("clear auth required") {
            return "This mint requires authentication before this action."
        }

        if normalized.contains("clear auth failed") {
            return "Mint authentication failed. Check your mint credentials."
        }

        if normalized.contains("blind auth required") {
            return "This mint requires blind authentication before this action."
        }

        if normalized.contains("blind auth failed") {
            return "Blind authentication failed. Check the mint and try again."
        }

        if normalized.contains("no on-chain melt fee options") {
            return "This mint cannot quote an on-chain payment right now. Try another mint."
        }

        if normalized.contains("invalid payment request")
            || normalized.contains("invalid invoice")
            || (normalized.contains("bolt11") && normalized.contains("parse"))
            || (normalized.contains("bolt12") && normalized.contains("parse")) {
            return "This payment request does not look valid."
        }

        if normalized.contains("timeout")
            || normalized.contains("timed out") {
            return "The mint took too long to respond. Check your connection and try again."
        }

        if normalized.contains("network")
            || normalized.contains("http")
            || normalized.contains("connection")
            || normalized.contains("connect")
            || normalized.contains("dns")
            || normalized.contains("resolve")
            || normalized.contains("offline")
            || normalized.contains("tls")
            || normalized.contains("ssl")
            || normalized.contains("certificate")
            || normalized.contains("couldn't reach")
            || normalized.contains("could not reach") {
            return "Couldn't reach the mint. Check your connection and try again."
        }

        if normalized.contains("not found") {
            return "The mint could not find that quote. Create a new request and try again."
        }

        if normalized.contains("sqlite")
            || normalized.contains("database")
            || normalized.contains("corrupt")
            || normalized.contains("malformed") {
            return "The wallet database could not be opened. Restart the app and try again."
        }

        return nil
    }

    private static func extractedCDKMessage(from rawMessage: String) -> String {
        let keys = ["errorMessage: \"", "error_message: \"", "message: \""]
        for key in keys {
            guard let keyRange = rawMessage.range(of: key) else { continue }
            let remainder = rawMessage[keyRange.upperBound...]
            if let end = remainder.firstIndex(of: "\"") {
                return String(remainder[..<end])
            }
        }

        return rawMessage
    }

    private static func looksLikeRawCDKError(_ message: String) -> Bool {
        message.contains("FfiError")
            || message.contains("CashuDevKit")
            || message.contains("errorMessage:")
            || message.contains("CALL_ERROR")
    }
}

extension Error {
    var userFacingWalletMessage: String {
        WalletErrorMessage.message(for: self)
    }
}

enum WalletError: LocalizedError {
    case notInitialized
    case mintAlreadyExists
    case invalidMnemonic
    case insufficientBalance
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "The wallet is still starting up. Try again in a moment."
        case .mintAlreadyExists:
            return "This mint is already in your wallet."
        case .invalidMnemonic:
            return "That seed phrase doesn't look right. Check the spelling and try again."
        case .insufficientBalance:
            return "Not enough spendable ecash for this payment."
        case .networkError:
            return WalletErrorMessage.message(for: self)
        }
    }
}
