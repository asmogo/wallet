import Foundation
import Cdk

extension WalletManager {
    /// Cooldown-gated sync for passive triggers (opening History, returning to
    /// foreground). Skips when a sync ran within `mintQuoteSyncCooldown`, so a
    /// paid offer settles on its own without re-polling the mint on every tab
    /// switch. Pull-to-refresh calls `syncPendingMintQuotes()` directly to
    /// bypass the cooldown (explicit user intent).
    func syncPendingMintQuotesIfStale() async {
        if let last = lastMintQuoteSyncAt,
           Date().timeIntervalSince(last) < mintQuoteSyncCooldown {
            return
        }
        await syncPendingMintQuotes()
    }

    func syncPendingMintQuotes() async {
        // Coarse in-flight guard: collapse overlapping triggers (e.g. opening
        // History while a foreground sync is already running) into one pass so
        // the full per-quote loop never runs twice concurrently.
        guard !isSyncingMintQuotes else { return }
        isSyncingMintQuotes = true
        lastMintQuoteSyncAt = Date()
        defer { isSyncingMintQuotes = false }

        guard let db else {
            await loadTransactions()
            return
        }

        var mintedAny = false

        do {
            let pendingQuotes = try await db.getUnissuedMintQuotes()
            for quote in pendingQuotes {
                let minted = await syncPendingMintQuote(
                    quoteId: quote.id,
                    allowPendingOnchainMintAttempt: false
                )
                mintedAny = mintedAny || minted
            }
        } catch {
            AppLogger.wallet.error("Failed to sync pending mint quotes: \(error)")
        }

        if mintedAny {
            await refreshBalance()
        }

        await loadTransactions()
    }

    func reclaimPendingToken(pendingToken: PendingToken) async throws -> UInt64 {
        let amount = try await receiveTokens(tokenString: pendingToken.token)
        transactionService.removePendingToken(tokenId: pendingToken.tokenId)
        await loadTransactions()
        return amount
    }

    // MARK: - Transaction History

    func loadTransactions(includeRemoteObservations: Bool = true) async {
        await transactionService.loadTransactions(includeRemoteObservations: includeRemoteObservations)
        reconcileQuoteIntents()
        objectWillChange.send()
    }

    /// Attach freshly-loaded incoming Lightning / on-chain transactions to the
    /// receive-intent backing their mint quote, so a reusable BOLT12 offer (or a
    /// BOLT11 invoice / on-chain address) aggregates its payments into one row
    /// and the duplicate per-payment row is suppressed via the intent's
    /// `receivedPayments` (the same mechanic Cashu Requests already use).
    /// Idempotent: `attachPayment(quoteId:)` skips ids already recorded, so a
    /// steady-state reload does nothing and never re-persists.
    private func reconcileQuoteIntents() {
        let store = CashuRequestStore.shared
        let ownedQuoteIds = Set(store.requests.compactMap(\.quoteId))
        guard !ownedQuoteIds.isEmpty else { return }

        for tx in transactionService.transactions where tx.type == .incoming {
            guard let quoteId = tx.quoteId, ownedQuoteIds.contains(quoteId) else { continue }
            store.attachPayment(quoteId: quoteId, transactionId: tx.id, amount: tx.amount)
        }
    }

    @discardableResult
    private func syncPendingMintQuote(
        quoteId: String,
        allowPendingOnchainMintAttempt: Bool
    ) async -> Bool {
        guard !mintQuoteSyncsInFlight.contains(quoteId) else {
            return false
        }

        mintQuoteSyncsInFlight.insert(quoteId)
        defer {
            mintQuoteSyncsInFlight.remove(quoteId)
        }

        do {
            let updatedQuote = try await lightningService.checkMintQuote(quoteId: quoteId)

            guard updatedQuote.state == .paid
                || updatedQuote.state == .issued
                || (allowPendingOnchainMintAttempt && updatedQuote.paymentMethod == .onchain) else {
                return false
            }

            // BOLT12 quotes always appear in `getUnissuedMintQuotes()` because
            // CDK's SQL filter is `amount_issued = 0 OR payment_method = 'bolt12'`.
            // Skip them when nothing new has been paid since the last issuance,
            // otherwise every history refresh would re-trigger `mint_bolt12` and
            // could spawn duplicate transactions on any local/mint state drift.
            if updatedQuote.paymentMethod == .bolt12, let db {
                let storedQuote = try? await db.getMintQuote(quoteId: quoteId)
                if let storedQuote,
                   storedQuote.amountPaid.value > 0,
                   storedQuote.amountIssued.value >= storedQuote.amountPaid.value {
                    return false
                }
            }

            do {
                _ = try await lightningService.mintTokens(quoteId: quoteId)
                return true
            } catch {
                if isAlreadyIssuedMintError(error) {
                    return true
                }

                if updatedQuote.paymentMethod == .onchain, updatedQuote.state == .pending {
                    return false
                }

                AppLogger.wallet.error("Failed to mint pending quote \(quoteId): \(error)")
                return false
            }
        } catch {
            if isMissingQuoteError(error) {
                return false
            }
            AppLogger.wallet.error("Failed to refresh pending quote \(quoteId): \(error)")
            return false
        }
    }

    private func isMissingQuoteError(_ error: Error) -> Bool {
        if let walletError = error as? WalletError,
           case .networkError(let message) = walletError,
           message.localizedCaseInsensitiveContains("not found") {
            return true
        }

        return String(describing: error).localizedCaseInsensitiveContains("not found")
    }

    func isAlreadyIssuedMintError(_ error: Error) -> Bool {
        let errorString = "\(error.localizedDescription) \(String(describing: error))".lowercased()

        if errorString.contains("already being minted")
            || errorString.contains("not issued")
            || errorString.contains("not yet")
            || errorString.contains("unissued") {
            return false
        }

        return errorString.contains("already issued")
            || errorString.contains("already minted")
            || errorString.contains("quote is issued")
            || errorString.contains("state=issued")
    }
}
