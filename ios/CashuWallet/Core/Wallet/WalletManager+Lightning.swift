import Foundation
import Cdk

extension WalletManager {
    // MARK: - Lightning Operations (Delegate to LightningService)

    func createMintQuote(
        amount: UInt64?,
        method: PaymentMethodKind = .bolt11,
        targetMintURL: String? = nil,
        unit: String = "sat"
    ) async throws -> MintQuoteInfo {
        try await operationCoordinator.perform(
            kind: .mintQuote,
            resourceID: targetMintURL
        ) {
            let quote = try await self.lightningService.createMintQuote(
                amount: amount,
                method: method,
                targetMintURL: targetMintURL,
                unit: PaymentRequestDecoder.currencyUnit(from: unit)
            )
            await self.loadTransactionsAssumingWalletOperationLease()
            return quote
        }
    }

    func existingAmountlessOffer(
        mintURL: String,
        unit: String
    ) async throws -> MintQuoteInfo? {
        try await operationCoordinator.perform(kind: .mintQuote, resourceID: mintURL) {
            try await self.lightningService.existingAmountlessOffer(
                mintURL: mintURL,
                unit: PaymentRequestDecoder.currencyUnit(from: unit)
            )
        }
    }

    func existingOnchainMintQuote(mintURL: String? = nil) async throws -> MintQuoteInfo? {
        try await operationCoordinator.perform(kind: .mintQuote) {
            try await self.lightningService.existingOnchainMintQuote(mintURL: mintURL)
        }
    }

    func checkMintQuote(quoteId: String) async throws -> MintQuoteInfo {
        return try await operationCoordinator.perform(
            kind: .mintQuote,
            resourceID: quoteId
        ) {
            try await self.lightningService.checkMintQuote(quoteId: quoteId)
        }
    }

    func mintTokens(quoteId: String) async throws -> UInt64 {
        let amount = try await operationCoordinator.perform(
            kind: .mint,
            resourceID: quoteId,
            protectsBackgroundExecution: true,
            defaultFailureOutcome: .ambiguousFailure
        ) {
            do {
                let amount = try await self.lightningService.mintTokens(quoteId: quoteId)
                await self.refreshBalanceAssumingWalletOperationLease()
                await self.loadTransactionsAssumingWalletOperationLease()
                return amount
            } catch {
                await self.captureWalletFailureDiagnostics(kind: .mint, quoteID: quoteId)
                await self.recoverWalletStateAfterFailureAssumingWalletOperationLease(
                    kind: .mint,
                    preferredMintURL: nil
                )
                await self.captureWalletFailureDiagnostics(kind: .mint, quoteID: quoteId)
                throw error
            }
        }
        SentryService.breadcrumb("Lightning invoice minted", category: "wallet.lightning")
        return amount
    }

    /// Fire-and-forget: keep trying to mint a paid quote so a slow/transiently
    /// failing mint never blocks the receive sheet. `mintTokens` already
    /// refreshes balance + history on success, so the wallet credits the moment
    /// it lands; `syncPendingMintQuotes()` (History pull-to-refresh) is the
    /// ultimate backstop if all attempts here fail.
    func claimPaidMintQuote(quoteId: String) async {
        for _ in 0..<8 {
            guard !Task.isCancelled else { return }
            do {
                _ = try await mintTokens(quoteId: quoteId)
                return
            } catch {
                do { try await Task.sleep(for: .milliseconds(2500)) }
                catch { return }
            }
        }
        AppLogger.wallet.error(
            "claimPaidMintQuote: gave up minting resource=\(WalletOperationCoordinator.privacySafeIdentifier(quoteId), privacy: .public)"
        )
        SentryService.breadcrumb("Lightning mint claim gave up after retries", category: "wallet.lightning")
    }

    func createMeltQuote(
        request: String,
        preferredMintURL: String? = nil
    ) async throws -> MeltQuoteInfo {
        try await operationCoordinator.perform(
            kind: .meltQuote,
            resourceID: preferredMintURL
        ) {
            try await self.lightningService.createMeltQuote(
                request: request,
                preferredMintURL: preferredMintURL
            )
        }
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
        try await operationCoordinator.perform(
            kind: .meltQuote,
            resourceID: preferredMintURL
        ) {
            try await self.lightningService.createHumanReadableMeltQuote(
                address: address,
                amount: amount,
                preferredMintURL: preferredMintURL
            )
        }
    }

    func createOnchainMeltQuote(
        address: String,
        amount: UInt64,
        preferredMintURL: String? = nil
    ) async throws -> MeltQuoteInfo {
        try await operationCoordinator.perform(
            kind: .meltQuote,
            resourceID: preferredMintURL
        ) {
            try await self.lightningService.createOnchainMeltQuote(
                address: address,
                amount: amount,
                preferredMintURL: preferredMintURL
            )
        }
    }

    func subscribeToMintQuote(
        quoteId: String,
        paymentMethod: PaymentMethodKind
    ) async throws -> ActiveSubscription? {
        // Creating the subscription touches the wallet and is serialized. The
        // caller's long-lived `recv()` only waits for notifications; any quote
        // status or mint work it triggers re-enters through coordinated methods.
        return try await operationCoordinator.perform(
            kind: .mintQuote,
            resourceID: quoteId
        ) {
            try await self.lightningService.subscribeToMintQuote(
                quoteId: quoteId,
                paymentMethod: paymentMethod
            )
        }
    }

    func meltTokens(quoteId: String, mintUrl: String? = nil) async throws -> MeltPaymentResult {
        let confirmation: LightningService.MeltConfirmation
        do {
            confirmation = try await operationCoordinator.perform(
                kind: .melt,
                resourceID: quoteId,
                protectsBackgroundExecution: true,
                defaultFailureOutcome: .ambiguousFailure
            ) {
                do {
                    return try await self.lightningService.meltTokens(quoteId: quoteId, mintUrl: mintUrl)
                } catch {
                    await self.captureWalletFailureDiagnostics(
                        kind: .melt,
                        operationID: (error as? MeltPaymentRecoveryError)?.operationID,
                        quoteID: quoteId
                    )
                    throw error
                }
            }
        } catch let recoveryError as MeltPaymentRecoveryError {
            // CDK persists the melt saga and its Pending transaction, so an
            // unresolved outcome needs no local record: startup recovery and
            // the foreground poll reconcile it.
            throw recoveryError
        }
        let result = confirmation.result
        if result.settlement == .pending {
            // Mint accepted the payment for asynchronous NUT-05 settlement and
            // it outlived the in-lane lightning wait (or is on-chain). CDK
            // tracks the pending transaction; the coordinated foreground poll
            // and startup recovery drive terminal reconciliation, including
            // after relaunch.
            SentryService.breadcrumb("Melt accepted for async settlement", category: "wallet.lightning")

            // A capped lightning wait hands back the still-running settlement
            // watcher. Observe it so balance/history refresh the moment the
            // melt lands, instead of waiting for the next poll tick. Coordinated
            // re-entry — never the AssumingLease variants.
            if let deferred = confirmation.deferredSettlement {
                Task { [weak self] in
                    guard (try? await deferred.value) != nil else { return }
                    await self?.refreshBalance()
                    await self?.loadTransactions()
                }
            }
        } else {
            SentryService.breadcrumb("Lightning payment sent", category: "wallet.lightning")
        }
        await refreshBalance()
        await loadTransactions()
        return result
    }
}
