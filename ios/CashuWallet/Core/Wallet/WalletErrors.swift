import Foundation
import Cdk

// MARK: - User-facing message + severity

/// A resolved, user-facing wallet message paired with the severity tier the UI
/// should render it at. The text follows the contract **{what broke}. {what to
/// try next}** in the app's quiet, native voice.
struct WalletMessage {
    /// Whether re-attempting the identical action could plausibly succeed. `.terminal`
    /// marks a permanent outcome (already paid, already issued) where a retry is futile,
    /// so the UI can offer "Done" instead of "Try Again".
    enum Recoverability { case retryable, terminal }

    let text: String
    let severity: ErrorSeverity
    var recoverability: Recoverability = .retryable

    static func error(_ text: String) -> WalletMessage { .init(text: text, severity: .error) }
    static func caution(_ text: String) -> WalletMessage { .init(text: text, severity: .caution) }
    static func info(_ text: String) -> WalletMessage { .init(text: text, severity: .info) }

    /// Mark this message as a permanent outcome that a retry cannot change.
    func terminal() -> WalletMessage {
        WalletMessage(text: text, severity: severity, recoverability: .terminal)
    }
}

// MARK: - Error Types

enum WalletErrorMessage {
    /// Resolve an error to its user-facing message **and** severity.
    static func classified(for error: Error) -> WalletMessage {
        if let removalError = error as? MintRemovalPolicyError {
            // Preserve app-owned safety guidance before generic CDK matching.
            return .error(removalError.localizedDescription)
        }
        if let meltRecoveryError = error as? MeltPaymentRecoveryError {
            switch meltRecoveryError {
            case .compensated:
                return .error("The payment did not complete. Create a fresh quote and try again.")
            case .unresolved:
                return .caution("The payment outcome is still being checked. Do not retry it yet.").terminal()
            }
        }

        if error is KeychainError {
            return .error("Couldn't access the wallet's secure storage. Restart the app and try again.")
        }

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
        case .PaymentRequestDeliveryFailed:
            // The token was created but transport delivery failed; the send
            // stays pending and is reclaimed via revokeSend if unclaimed.
            return .error("The payment couldn't be delivered. Any reserved funds stay pending and are reclaimed if unclaimed.")
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
            return .error("Ecash has already been issued for this quote.").terminal()
        }

        if normalized.contains("already paid")
            || normalized.contains("request already paid")
            || normalized.contains("invoice already paid") {
            return .error("This invoice has already been paid.").terminal()
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

        // Raw CDK "Incorrect quote amount": the mint declined the amount for this quote
        // (amount drift / MPP / amountless mismatch). Curate it into the app's voice
        // rather than leaking the jargon; switching mints is the reliable recovery.
        if normalized.contains("incorrect quote amount")
            || normalized.contains("quote amount mismatch")
            || normalized.contains("mismatched quote amount") {
            return .error("The mint declined the payment amount. Try again or use another mint.")
        }

        // Same zeroing defect as the amount-limit rule below: a decoded 11002 response
        // becomes `TransactionUnbalanced(0, 0, 0)`, which CDK renders as
        // "Inputs: `0`, Outputs: `0`, Expected Fee: `0`". Unbalanced almost always means
        // the wallet and mint disagreed on the fee, and re-quoting usually clears it.
        if normalized.contains("transaction unbalanced")
            || normalized.contains("expected fee") {
            return .error("The wallet and mint disagreed on the fee. Try again or use another mint.")
        }

        if normalized.contains("insufficient")
            || normalized.contains("not enough")
            || normalized.contains("no spendable")
            || normalized.contains("no available proofs")
            || normalized.contains("balance too low") {
            return .error("Not enough balance.")
        }

        // Stale NUT-13 keyset counter: the wallet asked the mint to re-sign blinded
        // outputs it already signed for this seed. TokenService auto-recovers on
        // receive (restore + retry); this copy is the fallback if that recovery is
        // exhausted, and stays non-terminal so "Try Again" (which re-runs the
        // recovery) remains available.
        if normalized.contains("duplicate outputs")
            || normalized.contains("already signed")
            || normalized.contains("outputs already signed") {
            return .error("The wallet fell out of sync with this mint. Tap Try Again to resync and receive.")
        }

        if normalized.contains("token already spent")
            || normalized.contains("proof already used")
            || normalized.contains("already redeemed")
            || normalized.contains("proofs are spent") {
            return .error("This token was already redeemed.").terminal()
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

        if normalized.contains("invoice has no amount")
            || normalized.contains("has no amount")
            || normalized.contains("amountless invoice")
            || normalized.contains("invoice amount undefined")
            || normalized.contains("amount is required") {
            return .caution("This invoice doesn't set an amount. Ask the sender for one with the amount set.")
        }

        // CDK's own wording for a NUT-04/05 limit rejection is "Amount must be between
        // `{min}` and `{max}` is `{amount}`". Wallet-side that message is worthless: when
        // the mint's 11006 response is decoded back into an Error, cdk-common rebuilds the
        // variant with three `Amount::default()`, so it always reads `0`/`0`/`0` and the
        // mint's real limits (carried in the response `detail`) are dropped. Match the
        // phrasing here so the raw zeros never reach the UI.
        if normalized.contains("amount out")
            || normalized.contains("outside of allowed")
            || normalized.contains("amount is outside")
            || normalized.contains("amount must be between") {
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
        let lowered = message.lowercased()
        return message.contains("FfiError")
            || message.contains("CashuDevKit")
            || message.contains("errorMessage:")
            || message.contains("CALL_ERROR")
            // Generic CDK "Unknown error response: `code: N, detail: …`" wrappers. Any
            // detail we recognize is already mapped above in classified(forRawMessage:);
            // anything left carries only a numeric code + internal detail, so route it to
            // the clean generic fallback instead of leaking `code: 0` / `code: 50000`.
            || lowered.contains("unknown error response")
            // Raw Rust panics (e.g. a failed stderr write inside the CDK FFI). These carry
            // no useful user-facing detail, so route them to the generic fallback instead
            // of showing the panic text verbatim.
            || lowered.contains("failed printing to std")
            || lowered.contains("os error")
            || lowered.contains("panicked at")
            || lowered.contains("rustpanic")
    }
}

/// A melt failed after CDK may have reserved proofs or contacted the mint.
/// Keeping this separate from transport errors prevents the UI from treating
/// an unknown payment outcome as a safe retry.
enum MeltPaymentRecoveryError: LocalizedError, WalletOperationOutcomeError {
    case compensated(operationID: String)
    case unresolved(quoteID: String, mintURL: String, operationID: String)

    var operationID: String {
        switch self {
        case .compensated(let operationID): operationID
        case .unresolved(_, _, let operationID): operationID
        }
    }

    var retryRequiresFreshQuote: Bool {
        if case .compensated = self { return true }
        return false
    }

    var unresolvedQuote: (id: String, mintURL: String)? {
        guard case .unresolved(let quoteID, let mintURL, _) = self else { return nil }
        return (quoteID, mintURL)
    }

    var walletOperationFailureOutcome: WalletOperationCoordinator.FailureOutcome {
        switch self {
        case .compensated: .definiteFailure
        case .unresolved: .ambiguousFailure
        }
    }

    var errorDescription: String? {
        WalletErrorMessage.message(for: self)
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

    var meltRetryRequiresFreshQuote: Bool {
        (self as? MeltPaymentRecoveryError)?.retryRequiresFreshQuote == true
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
