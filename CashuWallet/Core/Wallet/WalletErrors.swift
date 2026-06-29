import Foundation
import Cdk

// MARK: - User-facing message + severity

/// A resolved, user-facing wallet message paired with the severity tier the UI
/// should render it at. The text follows the contract **{what broke}. {what to
/// try next}** in the app's quiet, native voice.
struct WalletMessage {
    let text: String
    let severity: ErrorSeverity

    static func error(_ text: String) -> WalletMessage { .init(text: text, severity: .error) }
    static func caution(_ text: String) -> WalletMessage { .init(text: text, severity: .caution) }
    static func info(_ text: String) -> WalletMessage { .init(text: text, severity: .info) }
}

// MARK: - Error Types

enum WalletErrorMessage {
    /// Resolve an error to its user-facing message **and** severity.
    static func classified(for error: Error) -> WalletMessage {
        if let walletError = error as? WalletError {
            return classified(for: walletError)
        }

        if let ffiError = error as? Cdk.FfiError {
            return classified(for: ffiError)
        }

        if let mapped = classified(forRawMessage: String(describing: error)) {
            return mapped
        }

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty,
           !looksLikeRawCDKError(description) {
            return .error(description)
        }

        let localizedDescription = error.localizedDescription
        if !localizedDescription.isEmpty,
           !looksLikeRawCDKError(localizedDescription),
           !localizedDescription.contains("Swift.Error error 1") {
            return .error(localizedDescription)
        }

        return .error("The wallet couldn't finish that action. Try again in a moment.")
    }

    /// Text-only convenience that preserves the original string API.
    static func message(for error: Error) -> String {
        classified(for: error).text
    }

    private static func classified(for error: WalletError) -> WalletMessage {
        switch error {
        case .notInitialized:
            return .error("The wallet is still starting up. Try again in a moment.")
        case .mintAlreadyExists:
            return .error("This mint is already in your wallet.")
        case .invalidMnemonic:
            return .error("That seed phrase doesn't look right. Check the spelling and try again.")
        case .insufficientBalance:
            return .error("Not enough balance.")
        case .networkError(let message):
            if let mapped = classified(forRawMessage: message) {
                return mapped
            }

            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedMessage.isEmpty,
               !looksLikeRawCDKError(trimmedMessage),
               !trimmedMessage.contains("Swift.Error error 1") {
                return .error(trimmedMessage)
            }

            return .error("The wallet could not complete that request. Try again in a moment.")
        }
    }

    private static func classified(for ffiError: Cdk.FfiError) -> WalletMessage {
        // CDK's FfiError already carries a spec-accurate `error_message` for both
        // `.Cdk` (Cashu protocol) and `.Internal` errors. We deliberately do NOT
        // maintain our own numeric code -> message table: it drifts from the CDK /
        // Cashu spec and produced wrong copy (see issue #40). Surface CDK's own
        // message, lightly normalised for friendlier phrasing where we recognise it.
        switch ffiError {
        case .Cdk(_, let errorMessage):
            return classified(forRawMessage: errorMessage)
                ?? cleanedCDKMessage(errorMessage)
        case .Internal(let errorMessage):
            return classified(forRawMessage: errorMessage)
                ?? cleanedCDKMessage(errorMessage)
        }
    }

    private static func cleanedCDKMessage(_ rawMessage: String) -> WalletMessage {
        let message = extractedCDKMessage(from: rawMessage)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty, !looksLikeRawCDKError(message) {
            return .error(message)
        }
        return .error("The mint rejected the request. Try again or choose another mint.")
    }

    private static func classified(forRawMessage rawMessage: String) -> WalletMessage? {
        let message = extractedCDKMessage(from: rawMessage)
        let normalized = message.lowercased()

        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if normalized.contains("already being minted") {
            return .error("This payment is already being claimed. Give it a moment and refresh.")
        }

        if normalized.contains("already issued")
            || normalized.contains("already minted")
            || normalized.contains("quote is issued")
            || normalized.contains("tokens already issued") {
            return .error("Ecash has already been issued for this quote.")
        }

        if normalized.contains("already paid")
            || normalized.contains("request already paid")
            || normalized.contains("invoice already paid") {
            return .error("This invoice has already been paid.")
        }

        if normalized.contains("not paid")
            || normalized.contains("unpaid quote")
            || normalized.contains("quote is not paid") {
            return .error("The invoice has not been paid yet.")
        }

        if normalized.contains("not credited this on-chain quote yet")
            || (normalized.contains("not credited") && normalized.contains("on-chain")) {
            return .error("The mint has not credited this on-chain payment yet. Try again shortly.")
        }

        if normalized.contains("pending quote")
            || normalized.contains("payment pending")
            || normalized.contains("quote pending") {
            return .error("The payment is still pending. Try again shortly.")
        }

        if normalized.contains("expired quote")
            || normalized.contains("quote expired")
            || normalized.contains("invoice expired") {
            return .error("This quote has expired. Create a new request.")
        }

        if normalized.contains("payment failed") {
            return .error("The payment failed. Try again or use another mint.")
        }

        if normalized.contains("max fee exceeded")
            || normalized.contains("fee exceeded")
            || normalized.contains("fee is higher") {
            return .caution("The fee is higher than this wallet allows. Lower the amount or try another mint.")
        }

        if normalized.contains("insufficient")
            || normalized.contains("not enough")
            || normalized.contains("no spendable")
            || normalized.contains("no available proofs")
            || normalized.contains("balance too low") {
            return .error("Not enough balance.")
        }

        if normalized.contains("token already spent")
            || normalized.contains("proof already used")
            || normalized.contains("already redeemed")
            || normalized.contains("proofs are spent") {
            return .error("This token was already redeemed.")
        }

        if normalized.contains("token not verified")
            || normalized.contains("invalid proof")
            || normalized.contains("could not verify")
            || normalized.contains("dleq") {
            return .error("This token could not be verified. Ask the sender for a new token.")
        }

        if normalized.contains("keyset not found")
            || normalized.contains("unknown keyset")
            || normalized.contains("keyset id not known") {
            return .error("This token uses a keyset this mint doesn't recognize. Add the matching mint and try again.")
        }

        if normalized.contains("keyset inactive")
            || normalized.contains("inactive keyset") {
            return .error("This mint no longer accepts this token's keyset.")
        }

        if normalized.contains("unsupported unit")
            || normalized.contains("unit unsupported") {
            return .caution("This mint doesn't support that unit. Choose another mint.")
        }

        if normalized.contains("unsupported payment method")
            || normalized.contains("invalid payment method")
            || normalized.contains("payment method not supported") {
            return .caution("This mint doesn't support that payment method. Choose another mint.")
        }

        if normalized.contains("no key for amount")
            || normalized.contains("amount key")
            || normalized.contains("no active keyset") {
            return .error("This mint can't issue ecash for that amount right now. Try another mint.")
        }

        if normalized.contains("amountless invoice")
            || normalized.contains("invoice amount undefined")
            || normalized.contains("amount is required") {
            return .caution("This request doesn't include an amount. Enter one to continue.")
        }

        if normalized.contains("amount out")
            || normalized.contains("outside of allowed")
            || normalized.contains("amount is outside") {
            return .caution("This amount is outside the mint's limits. Try a different amount.")
        }

        if normalized.contains("minting disabled") {
            return .caution("This mint has paused deposits. Choose another mint.")
        }

        if normalized.contains("melting disabled") {
            return .caution("This mint has paused payments. Choose another mint.")
        }

        if normalized.contains("clear auth required") {
            return .error("This mint requires authentication before this action.")
        }

        if normalized.contains("clear auth failed") {
            return .error("Mint authentication failed. Check your mint credentials.")
        }

        if normalized.contains("blind auth required") {
            return .error("This mint requires blind authentication before this action.")
        }

        if normalized.contains("blind auth failed") {
            return .error("Blind authentication failed. Check the mint and try again.")
        }

        if normalized.contains("no on-chain melt fee options") {
            return .caution("This mint can't quote an on-chain payment right now. Try another mint.")
        }

        if normalized.contains("invalid payment request")
            || normalized.contains("invalid invoice")
            || (normalized.contains("bolt11") && normalized.contains("parse"))
            || (normalized.contains("bolt12") && normalized.contains("parse")) {
            return .error("That payment request isn't valid. Check it and try again.")
        }

        if normalized.contains("timeout")
            || normalized.contains("timed out") {
            return .error("The mint took too long to respond. Check your connection and try again.")
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
            return .error("Couldn't reach the mint. Check your connection and try again.")
        }

        if normalized.contains("not found") {
            return .error("The mint could not find that quote. Create a new request and try again.")
        }

        if normalized.contains("sqlite")
            || normalized.contains("database")
            || normalized.contains("corrupt")
            || normalized.contains("malformed") {
            return .error("The wallet database could not be opened. Restart the app and try again.")
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
    /// Text-only user-facing message (defaults the UI to the `.error` tier).
    var userFacingWalletMessage: String {
        WalletErrorMessage.message(for: self)
    }

    /// User-facing message paired with the severity tier the UI should render.
    var walletMessage: WalletMessage {
        WalletErrorMessage.classified(for: self)
    }

    /// True when the error is an out-of-balance condition — lets a call site
    /// render the richer "you have X here · choose another mint" notice.
    var isInsufficientBalanceError: Bool {
        if let walletError = self as? WalletError, case .insufficientBalance = walletError {
            return true
        }
        return WalletErrorMessage.classified(for: self).text == "Not enough balance."
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
            return "Not enough balance."
        case .networkError:
            return WalletErrorMessage.message(for: self)
        }
    }
}
