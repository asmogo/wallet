import Foundation
import Cdk

extension WalletManager {
    /// Cooldown-gated sync for passive triggers (opening History, returning to
    /// foreground, the foreground poll). Skips when a sync ran within
    /// `mintQuoteSyncCooldown`, so a paid offer settles on its own without
    /// re-polling the mint on every tab switch. Pull-to-refresh calls
    /// `syncPendingMintQuotes(force: true)` to bypass pass cooldown (explicit
    /// user intent). Per-quote exponential backoff still applies unless forced.
    func syncPendingMintQuotesIfStale() async {
        if let last = lastMintQuoteSyncAt,
           Date().timeIntervalSince(last) < mintQuoteSyncCooldown {
            return
        }
        await syncPendingMintQuotes(force: false)
    }

    /// Silent single-quote check + mint if paid. Used when opening a pending
    /// Lightning / on-chain receive in transaction detail (Android
    /// `refreshPendingMintQuote` parity). Forced past unpaid backoff (brief
    /// debounce only). Does not touch the global loading flag.
    @discardableResult
    func refreshPendingMintQuote(quoteId: String) async -> Bool {
        do {
            return try await operationCoordinator.perform(
                kind: .mintQuote,
                resourceID: quoteId
            ) {
                let minted = await self.syncPendingMintQuote(
                    quoteId: quoteId,
                    allowPendingOnchainMintAttempt: true,
                    force: true
                )
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
    /// async melt is tracked and its in-process waiter died.
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

    /// Re-check unissued mint quotes against their mints and mint the paid ones.
    /// - Parameter force: when `false` (poll / startup / History open), per-quote
    ///   exponential backoff applies and at most
    ///   `MintQuoteCheckBackoff.maxPassiveChecksPerPass` quotes are checked per
    ///   pass. When `true` (pull-to-refresh), every quote is eligible subject
    ///   only to a short per-quote debounce.
    func syncPendingMintQuotes(force: Bool = false) async {
        if force {
            do {
                try await operationCoordinator.perform(kind: .quotePoll) {
                    await self.syncPendingMintQuotesAssumingWalletOperationLease(force: true)
                }
            } catch {
                // Explicit refresh cancellation is expected when its view exits.
            }
            return
        }

        do {
            try await operationCoordinator.performIfIdle(kind: .quotePoll) {
                await self.syncPendingMintQuotesAssumingWalletOperationLease(force: false)
            }
        } catch {
            // Passive maintenance is best effort and will run again next tick.
        }
    }

    private func syncPendingMintQuotesAssumingWalletOperationLease(force: Bool) async {
        // Coarse in-flight guard: collapse overlapping triggers into one pass.
        guard !isSyncingMintQuotes else { return }
        isSyncingMintQuotes = true
        lastMintQuoteSyncAt = Date()
        defer { isSyncingMintQuotes = false }

        guard let db else {
            await loadTransactionsAssumingWalletOperationLease()
            return
        }

        var mintedAny = false
        let now = Date()

        do {
            let pendingQuotes = try await db.getUnissuedMintQuotes()
            let ordered = pendingQuotes
                .filter { quote in
                    MintQuoteCheckBackoff.shouldCheck(
                        entry: mintQuoteCheckThrottle[quote.id],
                        now: now,
                        force: force
                    )
                }
                .sorted { lhs, rhs in
                    let left = mintQuoteCheckThrottle[lhs.id]?.lastCheckedAt ?? .distantPast
                    let right = mintQuoteCheckThrottle[rhs.id]?.lastCheckedAt ?? .distantPast
                    return left < right
                }
            let toCheck = force
                ? ordered
                : Array(ordered.prefix(MintQuoteCheckBackoff.maxPassiveChecksPerPass))

            for quote in toCheck {
                let minted = await syncPendingMintQuote(
                    quoteId: quote.id,
                    allowPendingOnchainMintAttempt: false,
                    force: force
                )
                mintedAny = mintedAny || minted

                // A poll that was already running when the user acted yields
                // after the current quote instead of scanning the whole queue.
                if !force, await operationCoordinator.hasWaitingUserOperation() {
                    break
                }
            }
        } catch {
            AppLogger.wallet.error(
                "pending mint quote sync failed error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
        }

        if mintedAny {
            await refreshBalanceAssumingWalletOperationLease()
        }

        await loadTransactionsAssumingWalletOperationLease()
    }

    func reclaimPendingToken(pendingToken: PendingToken) async throws -> UInt64 {
        let amount = try await receiveTokens(tokenString: pendingToken.token)
        transactionService.removePendingToken(tokenId: pendingToken.tokenId)
        await loadTransactions()
        return amount
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

    @discardableResult
    private func syncPendingMintQuote(
        quoteId: String,
        allowPendingOnchainMintAttempt: Bool,
        force: Bool = false
    ) async -> Bool {
        let now = Date()
        let prior = mintQuoteCheckThrottle[quoteId]
        guard MintQuoteCheckBackoff.shouldCheck(entry: prior, now: now, force: force) else {
            return false
        }

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
                mintQuoteCheckThrottle[quoteId] = MintQuoteCheckBackoff.afterUnpaidOrError(
                    entry: prior,
                    now: now
                )
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
                    mintQuoteCheckThrottle[quoteId] = MintQuoteCheckBackoff.afterUnpaidOrError(
                        entry: prior,
                        now: now
                    )
                    return false
                }
            }

            do {
                _ = try await lightningService.mintTokens(quoteId: quoteId)
                mintQuoteCheckThrottle[quoteId] = MintQuoteCheckBackoff.afterMintedOrSettled(now: now)
                return true
            } catch {
                if isAlreadyIssuedMintError(error) {
                    mintQuoteCheckThrottle[quoteId] = MintQuoteCheckBackoff.afterMintedOrSettled(now: now)
                    return true
                }

                if updatedQuote.paymentMethod == .onchain, updatedQuote.state == .pending {
                    mintQuoteCheckThrottle[quoteId] = MintQuoteCheckBackoff.afterUnpaidOrError(
                        entry: prior,
                        now: now
                    )
                    return false
                }

                await captureWalletFailureDiagnostics(kind: .mint, quoteID: quoteId)
                await recoverWalletStateAfterFailureAssumingWalletOperationLease(
                    kind: .mint,
                    preferredMintURL: nil
                )
                await captureWalletFailureDiagnostics(kind: .mint, quoteID: quoteId)
                AppLogger.wallet.error(
                    "pending quote mint failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(quoteId), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                )
                mintQuoteCheckThrottle[quoteId] = MintQuoteCheckBackoff.afterUnpaidOrError(
                    entry: prior,
                    now: now
                )
                return false
            }
        } catch {
            mintQuoteCheckThrottle[quoteId] = MintQuoteCheckBackoff.afterUnpaidOrError(
                entry: prior,
                now: now
            )
            if isMissingQuoteError(error) {
                return false
            }
            AppLogger.wallet.error(
                "pending quote refresh failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(quoteId), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
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
