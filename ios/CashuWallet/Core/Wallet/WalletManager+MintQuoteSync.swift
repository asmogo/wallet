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

    /// Reconcile one persisted quote against its mint. The returned counters
    /// distinguish "the Lightning payment arrived" from "the ecash was
    /// actually issued"; callers must never present success from the former.
    /// Does not touch the global loading flag.
    @discardableResult
    func refreshPendingMintQuote(quoteId: String) async -> MintQuoteReconciliationResult? {
        do {
            return try await operationCoordinator.perform(
                kind: .mintQuote,
                resourceID: quoteId
            ) {
                guard let result = await self.reconcileMintQuote(quoteId: quoteId) else {
                    await self.loadTransactionsAssumingWalletOperationLease()
                    return nil
                }
                if result.newlyIssued > 0 {
                    await self.refreshBalanceAssumingWalletOperationLease()
                }
                await self.loadTransactionsAssumingWalletOperationLease()
                return result
            }
        } catch {
            return nil
        }
    }

    /// Restore the last honest paid-but-unissued state when a receive screen is
    /// reopened. The schedule metadata is advisory only; quote counters remain
    /// authoritative and callers must ignore this status once no amount is
    /// outstanding.
    func mintQuoteRetryStatus(quoteID: String) -> MintQuoteRetryStatus {
        guard let record = walletStore.loadMintQuoteSchedules()[quoteID] else {
            return MintQuoteRetryStatus()
        }
        return MintQuoteSchedulePolicy.retryStatus(for: record)
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

    /// Check every persisted, reconcilable quote and mint its outstanding
    /// counter delta. CDK keeps every BOLT12 quote in this list permanently,
    /// including fully-issued reusable offers, so later payments are still
    /// found after dismissal, app suspension, or relaunch.
    /// - Parameter force: `false` (poll / startup / History open) only runs
    ///   when the repository lane is idle; `true` (pull-to-refresh) preempts.
    func syncPendingMintQuotes(force: Bool = false) async {
        if force {
            do {
                try await operationCoordinator.perform(kind: .quotePoll) {
                    await self.mintUnissuedQuotesAcrossWallets(force: true)
                }
            } catch {
                // Explicit refresh cancellation is expected when its view exits.
            }
            return
        }

        do {
            try await operationCoordinator.performIfIdle(kind: .quotePoll) {
                await self.mintUnissuedQuotesAcrossWallets(force: false)
            }
        } catch {
            // Passive maintenance is best effort and will run again next tick.
        }
    }

    private func mintUnissuedQuotesAcrossWallets(force: Bool) async {
        lastMintQuoteSyncAt = Date()

        // The CDK database is the durable ledger. Union it with app-level
        // receive intents so an older/migrated BOLT12 row is still explicitly
        // checked and produces a useful missing-quote diagnostic instead of
        // silently disappearing from maintenance.
        var quoteIDs = Set(CashuRequestStore.shared.requests.compactMap(\.quoteId))
        if let db {
            do {
                quoteIDs.formUnion(try await db.getUnissuedMintQuotes().map(\.id))
            } catch {
                AppLogger.wallet.error(
                    "mint quote ledger scan failed error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                )
            }
        }

        let selection = MintQuoteSchedulePolicy.select(
            quoteIDs: quoteIDs,
            existing: walletStore.loadMintQuoteSchedules(),
            now: Date(),
            force: force
        )
        walletStore.saveMintQuoteSchedules(selection.records)
        guard !selection.quoteIDs.isEmpty else { return }

        var mintedAny = false
        for quoteID in selection.quoteIDs {
            guard !Task.isCancelled else { return }
            guard let result = await reconcileMintQuote(quoteId: quoteID) else { continue }
            if result.newlyIssued > 0 {
                mintedAny = true
                postReceivedMintNotification(
                    amount: result.newlyIssued,
                    unit: result.quote.unit,
                    homeHaptic: true
                )
            }
            if await operationCoordinator.hasWaitingUserOperation() { break }
        }

        if mintedAny {
            await refreshBalanceAssumingWalletOperationLease()
        }

        await loadTransactionsAssumingWalletOperationLease()
    }

    /// Check → mint → verify one quote while the wallet operation lane is held.
    /// A follow-up check also resolves the important ambiguous case where the
    /// mint issued ecash but the client lost the response. If another payment
    /// arrives during the attempt, `remainingAmount` stays positive and the
    /// next foreground tick mints that new delta.
    private func reconcileMintQuote(quoteId: String) async -> MintQuoteReconciliationResult? {
        let observed: MintQuoteInfo
        do {
            observed = try await lightningService.checkMintQuote(quoteId: quoteId)
        } catch {
            if error is CancellationError { return nil }
            AppLogger.wallet.error(
                "pending quote refresh failed resource=\(WalletOperationCoordinator.privacySafeIdentifier(quoteId), privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            guard let cached = await lightningService.storedMintQuote(quoteId: quoteId) else {
                _ = recordMintQuoteFailure(quoteID: quoteId, quote: nil)
                return nil
            }
            return MintQuoteReconciliationResult(
                observed: cached,
                retryStatus: recordMintQuoteFailure(quoteID: quoteId, quote: cached)
            )
        }

        guard observed.mintableAmount > 0 else {
            recordMintQuoteObservation(observed)
            return MintQuoteReconciliationResult(observed: observed)
        }

        var mintedAmount: UInt64 = 0
        var mintError: Error?
        do {
            mintedAmount = try await lightningService.mintTokens(quoteId: quoteId)
        } catch is CancellationError {
            return nil
        } catch {
            mintError = error
        }

        // Always verify counters after the attempt. This turns a response-loss
        // failure into success when the mint did issue, without relying on
        // fragile error-message matching.
        let verified: MintQuoteInfo?
        do {
            verified = try await lightningService.checkMintQuote(quoteId: quoteId)
        } catch is CancellationError {
            return nil
        } catch {
            verified = nil
        }
        let result = MintQuoteReconciliationResult(
            observed: observed,
            mintedAmount: mintedAmount,
            verified: verified
        )

        if result.remainingAmount > 0 {
            AppLogger.wallet.error(
                "pending quote mint remains unissued resource=\(WalletOperationCoordinator.privacySafeIdentifier(quoteId), privacy: .public) remaining=\(result.remainingAmount, privacy: .public) error_type=\(String(reflecting: type(of: mintError ?? WalletError.networkError("Mint quote made no verified issuance progress."))), privacy: .public)"
            )
            return MintQuoteReconciliationResult(
                observed: observed,
                mintedAmount: mintedAmount,
                verified: verified,
                retryStatus: recordMintQuoteFailure(quoteID: quoteId, quote: result.quote)
            )
        }

        recordMintQuoteObservation(result.quote)
        return result
    }

    /// Register a newly-created/discovered quote without postponing an already
    /// due reconciliation. The first sweep sees it immediately.
    func rememberMintQuoteForScheduling(_ quote: MintQuoteInfo) {
        var schedules = walletStore.loadMintQuoteSchedules()
        guard schedules[quote.id] == nil else { return }
        schedules[quote.id] = MintQuoteScheduleRecord(
            firstObservedAt: Date().timeIntervalSince1970,
            isReusable: quote.paymentMethod == .bolt12
        )
        walletStore.saveMintQuoteSchedules(schedules)
    }

    private func recordMintQuoteObservation(_ quote: MintQuoteInfo) {
        var schedules = walletStore.loadMintQuoteSchedules()
        schedules[quote.id] = MintQuoteSchedulePolicy.observed(
            previous: schedules[quote.id],
            quote: quote,
            now: Date()
        )
        walletStore.saveMintQuoteSchedules(schedules)
    }

    @discardableResult
    private func recordMintQuoteFailure(
        quoteID: String,
        quote: MintQuoteInfo?
    ) -> MintQuoteRetryStatus {
        var schedules = walletStore.loadMintQuoteSchedules()
        let record = MintQuoteSchedulePolicy.failed(
            previous: schedules[quoteID],
            now: Date(),
            hadOutstandingPayment: (quote?.mintableAmount ?? 0) > 0,
            isReusable: quote?.paymentMethod == .bolt12
        )
        schedules[quoteID] = record
        walletStore.saveMintQuoteSchedules(schedules)
        return MintQuoteSchedulePolicy.retryStatus(for: record)
    }

    func postReceivedMintNotification(amount: UInt64, unit: String, homeHaptic: Bool) {
        guard amount > 0 else { return }
        NotificationCenter.default.post(
            name: .cashuTokenReceived,
            object: nil,
            userInfo: [
                "amount": amount,
                "unit": unit,
                "homeHaptic": homeHaptic
            ]
        )
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
