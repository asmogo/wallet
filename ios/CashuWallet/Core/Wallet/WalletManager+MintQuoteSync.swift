import Foundation
import Cdk

extension WalletManager {
    /// Cooldown-gated sync for passive triggers (opening History, returning to
    /// foreground, the foreground poll). Skips when a sync ran within
    /// `mintQuoteSyncCooldown`, so a paid offer settles on its own without
    /// re-polling the mint on every tab switch. Pull-to-refresh calls
    /// `syncPendingMintQuotes(force: true)` to bypass the cooldown (explicit
    /// user intent).
    func syncPendingMintQuotesIfStale() async {
        if let last = lastMintQuoteSyncAt,
           Date().timeIntervalSince(last) < mintQuoteSyncCooldown {
            return
        }
        await syncPendingMintQuotes(force: false)
    }

    /// Silent single-quote check + mint if paid. Used when opening a pending
    /// Lightning / on-chain receive in transaction detail (Android
    /// `refreshPendingMintQuote` parity). Does not touch the global loading flag.
    @discardableResult
    func refreshPendingMintQuote(quoteId: String) async -> Bool {
        do {
            return try await operationCoordinator.perform(
                kind: .mintQuote,
                resourceID: quoteId
            ) {
                let minted = await self.mintQuoteIfPaid(quoteId: quoteId)
                if minted {
                    await self.refreshBalanceAssumingWalletOperationLease()
                }
                await self.loadTransactionsAssumingWalletOperationLease()
                return minted
            }
        } catch {
            return false
        }
    }

    // MARK: - Foreground polling

    /// While the app is active, re-check pending quotes every
    /// `pendingQuotePollInterval` so a payment lands on its own — e.g. a
    /// BOLT12 offer paid from another wallet while Home sits open — instead of
    /// waiting for pull-to-refresh. The mint sync stays cooldown-gated (the
    /// poll interval equals `mintQuoteSyncCooldown`, so this never exceeds one
    /// pass per interval); the melt sync is a cheap no-op unless a NUT-05
    /// async melt is in flight and its in-process waiter died.
    /// Started/stopped from `CashuWalletApp` on scenePhase (Android parity).
    func startPendingQuoteForegroundPolling() {
        guard pendingQuotePollTask == nil else { return }
        pendingQuotePollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.pendingQuotePollInterval else { break }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.syncPendingMintQuotesIfStale()
                await self?.syncPendingMeltQuotes()
            }
        }
    }

    func stopPendingQuoteForegroundPolling() {
        pendingQuotePollTask?.cancel()
        pendingQuotePollTask = nil
    }

    /// Check every tracked wallet for paid-but-unissued mint quotes and mint
    /// them. CDK 0.18's `mintUnissuedQuotes()` refreshes each quote's NUT-04
    /// counters with the mint and mints only the outstanding delta, which
    /// covers reusable BOLT12 offers without any local heuristics.
    /// - Parameter force: `false` (poll / startup / History open) only runs
    ///   when the repository lane is idle; `true` (pull-to-refresh) preempts.
    func syncPendingMintQuotes(force: Bool = false) async {
        if force {
            do {
                try await operationCoordinator.perform(kind: .quotePoll) {
                    await self.mintUnissuedQuotesAcrossWallets()
                }
            } catch {
                // Explicit refresh cancellation is expected when its view exits.
            }
            return
        }

        do {
            try await operationCoordinator.performIfIdle(kind: .quotePoll) {
                await self.mintUnissuedQuotesAcrossWallets()
            }
        } catch {
            // Passive maintenance is best effort and will run again next tick.
        }
    }

    private func mintUnissuedQuotesAcrossWallets() async {
        guard walletRepository != nil else { return }
        lastMintQuoteSyncAt = Date()

        var mintedAny = false
        for wallet in await trackedWalletsAssumingWalletOperationLease() {
            guard !Task.isCancelled else { break }
            do {
                let minted = try await wallet.mintUnissuedQuotes()
                mintedAny = mintedAny || minted.value > 0
            } catch is CancellationError {
                break
            } catch {
                AppLogger.wallet.error(
                    "unissued quote sweep failed error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                )
            }
            if await operationCoordinator.hasWaitingUserOperation() { break }
        }

        if mintedAny {
            await refreshBalanceAssumingWalletOperationLease()
        }

        await loadTransactionsAssumingWalletOperationLease()
    }

    /// Check one quote with its mint and mint it when an unpaid amount is
    /// outstanding. The NUT-04 `amountPaid`/`amountIssued` counters make this
    /// correct for reusable BOLT12 offers too: fully-issued offers mint 0.
    @discardableResult
    private func mintQuoteIfPaid(quoteId: String) async -> Bool {
        do {
            _ = try await lightningService.checkMintQuote(quoteId: quoteId)
        } catch {
            AppLogger.wallet.error(
                "pending quote refresh failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(quoteId), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            return false
        }

        let storedQuote: MintQuote??
        do {
            storedQuote = try await db?.getMintQuote(quoteId: quoteId)
        } catch {
            storedQuote = nil
        }
        guard let quote = storedQuote ?? nil,
              quote.amountPaid.value > quote.amountIssued.value else {
            return false
        }

        do {
            _ = try await lightningService.mintTokens(quoteId: quoteId)
            return true
        } catch {
            if isAlreadyIssuedMintError(error) {
                return true
            }
            AppLogger.wallet.error(
                "pending quote mint failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(quoteId), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            return false
        }
    }

    // MARK: - Transaction History

    func loadTransactions(includeRemoteObservations: Bool = true) async {
        do {
            try await operationCoordinator.perform(kind: .history) {
                await self.loadTransactionsAssumingWalletOperationLease(
                    includeRemoteObservations: includeRemoteObservations
                )
            }
        } catch {
            // History refresh is best effort and may be cancelled with its view.
        }
    }

    /// Internal form for workflows that already own the repository lease.
    func loadTransactionsAssumingWalletOperationLease(
        includeRemoteObservations: Bool = true
    ) async {
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
