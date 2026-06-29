import Foundation
import Cdk

extension WalletManager {
    // MARK: - Lightning Operations (Delegate to LightningService)

    func createMintQuote(
        amount: UInt64?,
        method: PaymentMethodKind = .bolt11
    ) async throws -> MintQuoteInfo {
        let quote = try await lightningService.createMintQuote(amount: amount, method: method)
        await loadTransactions()
        return quote
    }

    func existingAmountlessOffer() async throws -> MintQuoteInfo? {
        try await lightningService.existingAmountlessOffer()
    }

    func existingOnchainMintQuote() async throws -> MintQuoteInfo? {
        try await lightningService.existingOnchainMintQuote()
    }

    func checkMintQuote(quoteId: String) async throws -> MintQuoteInfo {
        return try await lightningService.checkMintQuote(quoteId: quoteId)
    }

    func mintTokens(quoteId: String) async throws -> UInt64 {
        let amount = try await lightningService.mintTokens(quoteId: quoteId)
        await refreshBalance()
        await loadTransactions()
        return amount
    }

    /// Fire-and-forget: keep trying to mint a paid quote so a slow/transiently
    /// failing mint never blocks the receive sheet. `mintTokens` already
    /// refreshes balance + history on success, so the wallet credits the moment
    /// it lands; `syncPendingMintQuotes()` (History pull-to-refresh) is the
    /// ultimate backstop if all attempts here fail.
    func claimPaidMintQuote(quoteId: String) async {
        for _ in 0..<8 {
            do {
                _ = try await mintTokens(quoteId: quoteId)
                return
            } catch {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
        AppLogger.wallet.error("claimPaidMintQuote: gave up minting \(quoteId, privacy: .public)")
    }

    func createMeltQuote(
        request: String,
        preferredMintURL: String? = nil
    ) async throws -> MeltQuoteInfo {
        try await lightningService.createMeltQuote(
            request: request,
            preferredMintURL: preferredMintURL
        )
    }

    func createMeltQuote(
        invoice: String,
        preferredMintURL: String? = nil
    ) async throws -> MeltQuoteInfo {
        return try await createMeltQuote(request: invoice, preferredMintURL: preferredMintURL)
    }

    func createHumanReadableMeltQuote(
        address: String,
        amount: UInt64,
        preferredMintURL: String? = nil
    ) async throws -> MeltQuoteInfo {
        try await lightningService.createHumanReadableMeltQuote(
            address: address,
            amount: amount,
            preferredMintURL: preferredMintURL
        )
    }

    func createOnchainMeltQuote(
        address: String,
        amount: UInt64,
        preferredMintURL: String? = nil
    ) async throws -> MeltQuoteInfo {
        try await lightningService.createOnchainMeltQuote(
            address: address,
            amount: amount,
            preferredMintURL: preferredMintURL
        )
    }

    func subscribeToMintQuote(
        quoteId: String,
        paymentMethod: PaymentMethodKind
    ) async throws -> ActiveSubscription? {
        return try await lightningService.subscribeToMintQuote(
            quoteId: quoteId,
            paymentMethod: paymentMethod
        )
    }

    func meltTokens(quoteId: String, mintUrl: String? = nil) async throws -> MeltPaymentResult {
        let result = try await lightningService.meltTokens(quoteId: quoteId, mintUrl: mintUrl)
        // Persist preimage as proof of payment
        if let preimage = result.preimage {
            transactionService.savePreimage(quoteId: quoteId, preimage: preimage)
        }
        transactionService.saveMeltFeePaid(quoteId: quoteId, feePaid: result.feePaid)
        await refreshBalance()
        await loadTransactions()
        return result
    }
}
