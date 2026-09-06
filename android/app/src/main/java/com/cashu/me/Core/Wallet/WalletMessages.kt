package com.cashu.me.Core.Wallet

/** Severity tier the UI should render a wallet message at (iOS ErrorSeverity). */
enum class WalletMessageSeverity { Error, Caution, Info }

/**
 * A resolved, user-facing wallet message paired with the severity tier the UI
 * should render it at. Port of iOS `WalletErrors.swift`: the text follows the
 * contract **{what broke}. {what to try next}** in the app's quiet, native voice.
 *
 * `isTerminal` marks a permanent outcome (already spent / already paid) where a
 * retry is futile, so the UI can offer "Done" instead of "Try again".
 */
data class WalletMessage(
    val text: String,
    val severity: WalletMessageSeverity = WalletMessageSeverity.Error,
    val isTerminal: Boolean = false,
) {
    val isRetryable: Boolean get() = !isTerminal
}

/** Resolve any thrown error to its user-facing message, severity, and recoverability. */
val Throwable.walletMessage: WalletMessage
    get() = WalletErrorMessages.classify(this)

/** Text-only convenience for call sites that just need the copy. */
val Throwable.userFacingWalletMessage: String
    get() = walletMessage.text

/**
 * Whether the error classifies as insufficient balance (iOS
 * `isInsufficientBalanceError`). Call sites holding balance context use it to
 * upgrade the copy — e.g. the amount fits the balance but the change-swap fee
 * doesn't.
 */
val Throwable.isInsufficientBalance: Boolean
    get() = walletMessage.text == "Not enough balance."

object WalletErrorMessages {

    private const val GENERIC_FALLBACK =
        "The wallet couldn't finish that action. Try again in a moment."

    fun classify(error: Throwable): WalletMessage {
        val raw = error.message ?: error.toString()

        classifyRawMessage(raw)?.let { return it }

        // No mapping matched: surface the CDK/mint's own message if it reads like
        // a sentence, otherwise fall back to clean generic copy instead of leaking
        // `code=11001, errorMessage=…` FFI wrappers.
        val extracted = extractCdkMessage(raw).trim()
        if (extracted.isNotEmpty() && !looksLikeRawCdkError(extracted)) {
            return WalletMessage(extracted)
        }
        return WalletMessage(GENERIC_FALLBACK)
    }

    /** Convenience for call sites holding a raw message string instead of a Throwable. */
    fun classifyMessage(rawMessage: String): WalletMessage {
        classifyRawMessage(rawMessage)?.let { return it }
        val extracted = extractCdkMessage(rawMessage).trim()
        if (extracted.isNotEmpty() && !looksLikeRawCdkError(extracted)) {
            return WalletMessage(extracted)
        }
        return WalletMessage(GENERIC_FALLBACK)
    }

    // Substring table ported from iOS WalletErrors.swift `classified(forRawMessage:)`.
    private fun classifyRawMessage(rawMessage: String): WalletMessage? {
        val normalized = extractCdkMessage(rawMessage).lowercase()
        if (normalized.isBlank()) return null

        fun has(vararg needles: String): Boolean = needles.any { normalized.contains(it) }

        return when {
            has("already being minted") ->
                error("This payment is already being claimed. Give it a moment and refresh.")

            has("already issued", "already minted", "quote is issued", "tokens already issued") ->
                terminal("Ecash has already been issued for this quote.")

            has("already paid", "request already paid", "invoice already paid") ->
                terminal("This invoice has already been paid.")

            has("not paid", "unpaid quote", "quote is not paid") ->
                error("The invoice has not been paid yet.")

            has("not credited this on-chain quote yet") ||
                (has("not credited") && has("on-chain")) ->
                error("The mint has not credited this on-chain payment yet. Try again shortly.")

            has("pending quote", "payment pending", "quote pending") ->
                error("The payment is still pending. Try again shortly.")

            has("expired quote", "quote expired", "invoice expired") ->
                error("This quote has expired. Create a new request.")

            has("payment failed") ->
                error("The payment failed. Try again or use another mint.")

            has("max fee exceeded", "fee exceeded", "fee is higher") ->
                caution("The fee is higher than this wallet allows. Lower the amount or try another mint.")

            has("incorrect quote amount", "quote amount mismatch", "mismatched quote amount") ->
                error("The mint declined the payment amount. Try again or use another mint.")

            // Same zeroing defect as the amount-limit rule below: a decoded 11002 response
            // becomes `TransactionUnbalanced(0, 0, 0)`, which CDK renders as
            // "Inputs: `0`, Outputs: `0`, Expected Fee: `0`". Unbalanced almost always means
            // the wallet and mint disagreed on the fee, and re-quoting usually clears it.
            has("transaction unbalanced", "expected fee") ->
                error("The wallet and mint disagreed on the fee. Try again or use another mint.")

            has("insufficient", "not enough", "no spendable", "no available proofs", "balance too low") ->
                error("Not enough balance.")

            has("duplicate outputs", "already signed", "outputs already signed") ->
                error("The wallet fell out of sync with this mint. Tap Try Again to resync and receive.")

            has("token already spent", "proof already used", "already redeemed", "proofs are spent") ->
                terminal("This token was already redeemed.")

            has("token not verified", "invalid proof", "could not verify", "dleq") ->
                error("This token could not be verified. Ask the sender for a new token.")

            has("keyset not found", "unknown keyset", "keyset id not known") ->
                error("This token uses a keyset this mint doesn't recognize. Add the matching mint and try again.")

            has("keyset inactive", "inactive keyset") ->
                error("This mint no longer accepts this token's keyset.")

            has("unsupported unit", "unit unsupported") ->
                caution("This mint doesn't support that unit. Choose another mint.")

            has("unsupported payment method", "invalid payment method", "payment method not supported") ->
                caution("This mint doesn't support that payment method. Choose another mint.")

            has("no key for amount", "amount key", "no active keyset") ->
                error("This mint can't issue ecash for that amount right now. Try another mint.")

            has(
                "invoice has no amount", "has no amount", "amountless invoice",
                "invoice amount undefined", "amount is required",
            ) ->
                caution("This invoice doesn't set an amount. Ask the sender for one with the amount set.")

            // CDK's own wording for a NUT-04/05 limit rejection is "Amount must be between
            // `{min}` and `{max}` is `{amount}`". Wallet-side that message is worthless: when
            // the mint's 11006 response is decoded back into an Error, cdk-common rebuilds the
            // variant with three `Amount::default()`, so it always reads `0`/`0`/`0` and the
            // mint's real limits (carried in the response `detail`) are dropped. Match the
            // phrasing here so the raw zeros never reach the UI.
            has("amount out", "outside of allowed", "amount is outside", "amount must be between") ->
                caution("This amount is outside the mint's limits. Try a different amount.")

            has("minting disabled") ->
                caution("This mint has paused deposits. Choose another mint.")

            has("melting disabled") ->
                caution("This mint has paused payments. Choose another mint.")

            has("clear auth required") ->
                error("This mint requires authentication before this action.")

            has("clear auth failed") ->
                error("Mint authentication failed. Check your mint credentials.")

            has("blind auth required") ->
                error("This mint requires blind authentication before this action.")

            has("blind auth failed") ->
                error("Blind authentication failed. Check the mint and try again.")

            has("no on-chain melt fee options") ->
                caution("This mint can't quote an on-chain payment right now. Try another mint.")

            has("invalid payment request", "invalid invoice") ||
                (has("bolt11") && has("parse")) ||
                (has("bolt12") && has("parse")) ->
                error("That payment request isn't valid. Check it and try again.")

            has("timeout", "timed out") ->
                error("The mint took too long to respond. Check your connection and try again.")

            has(
                "network", "http", "connection", "connect", "dns", "resolve",
                "offline", "tls", "ssl", "certificate", "couldn't reach", "could not reach",
            ) ->
                error("Couldn't reach the mint. Check your connection and try again.")

            has("not found") ->
                error("The mint could not find that quote. Create a new request and try again.")

            has("keystore", "keychain", "secure storage") ->
                error("Couldn't access the wallet's secure storage. Restart the app and try again.")

            has("sqlite", "database", "corrupt", "malformed") ->
                error("The wallet database could not be opened. Restart the app and try again.")

            else -> null
        }
    }

    /**
     * Pull the human sentence out of a raw CDK/FFI wrapper. Handles both quoted
     * Rust-debug forms (`errorMessage: "Token Already Spent"`) and the Kotlin
     * data-class form the bindings throw (`code=11001, errorMessage=Token Already Spent`).
     */
    private fun extractCdkMessage(rawMessage: String): String {
        for (key in listOf("errorMessage: \"", "error_message: \"", "message: \"")) {
            val start = rawMessage.indexOf(key)
            if (start >= 0) {
                val begin = start + key.length
                val end = rawMessage.indexOf('"', begin)
                if (end > begin) return rawMessage.substring(begin, end)
            }
        }
        for (key in listOf("errorMessage=", "error_message=", "message=")) {
            val start = rawMessage.indexOf(key)
            if (start >= 0) {
                return rawMessage.substring(start + key.length).trim().removeSuffix(")")
            }
        }
        return rawMessage
    }

    private fun looksLikeRawCdkError(message: String): Boolean {
        val lowered = message.lowercase()
        return message.contains("FfiError") ||
            message.contains("FfiException") ||
            message.contains("errorMessage") ||
            message.contains("CALL_ERROR") ||
            message.contains("::") ||
            lowered.contains("cashudevkit") ||
            lowered.contains("cdk_wallet") ||
            lowered.contains("uniffi") ||
            lowered.contains("code=") ||
            lowered.contains("unknown error response") ||
            lowered.contains("backtrace") ||
            lowered.contains("failed printing to std") ||
            lowered.contains("os error") ||
            lowered.contains("panicked at") ||
            lowered.contains("rustpanic") ||
            lowered.contains("exception")
    }

    private fun error(text: String) = WalletMessage(text, WalletMessageSeverity.Error)
    private fun caution(text: String) = WalletMessage(text, WalletMessageSeverity.Caution)
    private fun terminal(text: String) = WalletMessage(text, WalletMessageSeverity.Error, isTerminal = true)
}
