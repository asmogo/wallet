import Foundation
import Cdk

/// Asynchronous melt settlement (NUT-05).
///
/// When a mint accepts a melt with `Prefer: respond-async` — on-chain payments
/// especially can take minutes to settle — `confirmPreferAsync()` hands back a
/// `PendingMelt` instead of a final result. We intentionally do not run its
/// long-lived `wait()` future beside normal wallet work: it can update the same
/// native store after the app-level lease has ended. Instead, every pending
/// quote is persisted and re-checked through the coordinator on launch and in
/// the foreground. `checkMeltQuoteStatus` completes the underlying wallet saga
/// when the mint reports a terminal state.
extension WalletManager {
    /// Poll mints for melts still recorded as pending — e.g. after a relaunch
    /// killed the in-process waiter. Cheap no-op when nothing is tracked.
    func syncPendingMeltQuotes() async {
        let tracked = walletStore.loadPendingMeltQuotes()
        guard !tracked.isEmpty, let repo = walletRepository else { return }

        do {
            try await operationCoordinator.performIfIdle(kind: .pendingMeltPoll) {
                await self.syncPendingMeltQuotesAssumingWalletOperationLease(
                    tracked: tracked,
                    repository: repo
                )
            }
        } catch {
            // Passive settlement polling will retry on the next foreground tick.
        }
    }

    private func syncPendingMeltQuotesAssumingWalletOperationLease(
        tracked: [String: String],
        repository repo: WalletRepository
    ) async {
        var settledAny = false
        for (quoteId, mintUrlString) in tracked {
            do {
                let wallet = try await repo.getWallet(mintUrl: MintUrl(url: mintUrlString), unit: .sat)
                let operationID = try await db?.getMeltQuote(quoteId: quoteId)?.usedByOperation
                let quote = try await wallet.checkMeltQuoteStatus(quoteId: quoteId)
                switch quote.state {
                case .paid, .issued:
                    guard await meltReservationIsReleased(
                        wallet: wallet,
                        quoteID: quoteId,
                        operationID: operationID
                    ) else { continue }
                    recordFinalizedMelt(quoteId: quoteId, preimage: quote.paymentProof, feePaid: nil)
                    forgetPendingMeltQuote(quoteId: quoteId)
                    SentryService.breadcrumb("Async melt settled after resync", category: "wallet.lightning")
                    settledAny = true
                case .unpaid:
                    // Treat unpaid as terminal only after local reads prove the
                    // saga, quote reservation, and reserved proofs are gone.
                    // Otherwise recovery/polling remains armed and retry stays
                    // blocked by the unresolved pending record.
                    guard await meltReservationIsReleased(
                        wallet: wallet,
                        quoteID: quoteId,
                        operationID: operationID
                    ) else { continue }
                    forgetPendingMeltQuote(quoteId: quoteId)
                    SentryService.breadcrumb("Async melt failed after resync", category: "wallet.lightning")
                    settledAny = true
                case .pending:
                    continue
                }
            } catch {
                AppLogger.wallet.error(
                    "pending melt status check failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(quoteId), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                )
            }

            if await operationCoordinator.hasWaitingUserOperation() {
                break
            }
        }

        if settledAny {
            await refreshBalanceAssumingWalletOperationLease()
            await loadTransactionsAssumingWalletOperationLease()
        }
    }

    private func meltReservationIsReleased(
        wallet: Wallet,
        quoteID: String,
        operationID: String?
    ) async -> Bool {
        guard let db else { return false }

        func stateIsReleased() async throws -> Bool {
            let quote = try await db.getMeltQuote(quoteId: quoteID)
            let resolvedOperationID = operationID ?? quote?.usedByOperation
            guard quote?.usedByOperation == nil else { return false }
            guard let resolvedOperationID else { return true }
            let saga = try await db.getSaga(id: resolvedOperationID)
            let reservedProofs = try await db.getReservedProofs(operationId: resolvedOperationID)
            return saga == nil && reservedProofs.isEmpty
        }

        do {
            if try await stateIsReleased() { return true }

            let report = try await wallet.recoverIncompleteSagas()
            AppLogger.wallet.info(
                "wallet-op pending melt recovery resource=\(WalletOperationCoordinator.privacySafeIdentifier(quoteID), privacy: .public) recovered=\(report.recovered, privacy: .public) compensated=\(report.compensated, privacy: .public) skipped=\(report.skipped, privacy: .public) failed=\(report.failed, privacy: .public)"
            )
            return try await stateIsReleased()
        } catch {
            AppLogger.wallet.warning(
                "wallet-op pending melt release unresolved resource=\(WalletOperationCoordinator.privacySafeIdentifier(quoteID), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            return false
        }
    }

    /// Persist the durable facts of a settled melt (payment proof, actual fee).
    func recordFinalizedMelt(quoteId: String, preimage: String?, feePaid: UInt64?) {
        if let preimage {
            transactionService.savePreimage(quoteId: quoteId, preimage: preimage)
        }
        if let feePaid {
            transactionService.saveMeltFeePaid(quoteId: quoteId, feePaid: feePaid)
        }
    }

    func rememberPendingMeltQuote(quoteId: String, mintUrl: String) {
        var tracked = walletStore.loadPendingMeltQuotes()
        tracked[quoteId] = mintUrl
        walletStore.savePendingMeltQuotes(tracked)
    }

    func forgetPendingMeltQuote(quoteId: String) {
        var tracked = walletStore.loadPendingMeltQuotes()
        guard tracked.removeValue(forKey: quoteId) != nil else { return }
        walletStore.savePendingMeltQuotes(tracked)
    }

}
