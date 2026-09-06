import XCTest
@testable import CashuWallet

@MainActor
final class CashuRequestStoreBoundaryTests: XCTestCase {
    func testClearingDescriptionRestoresLastUsedOfferWithoutChangingHistory() throws {
        let suiteName = "OfferReuseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CashuRequestStore(userDefaults: defaults)
        let url = "https://mint.example"
        let plain = store.upsertQuoteIntent(rail: .bolt12, quoteId: "plain", encoded: "lno-plain", mints: [url], reusable: true)
        store.upsertQuoteIntent(rail: .bolt12, quoteId: "described", encoded: "lno-described", mints: [url], memo: "Coffee", reusable: true)
        store.upsertQuoteIntent(rail: .bolt12, quoteId: "other-unit", encoded: "lno-usd", unit: "usd", mints: [url], memo: "USD", reusable: true)
        store.upsertQuoteIntent(rail: .bolt12, quoteId: "fixed", encoded: "lno-fixed", amount: 21, mints: [url], memo: "Fixed", reusable: true)
        XCTAssertEqual(store.lastPresentedAmountlessOffer(mintURL: url, unit: "sat")?.quoteId, "described")
        store.attachPayment(quoteId: "plain", transactionId: "payment", amount: 21)
        store.markQuotePresented("plain")
        let reloaded = CashuRequestStore(userDefaults: defaults)
        let restored = try XCTUnwrap(reloaded.lastPresentedAmountlessOffer(mintURL: url, unit: "SAT"))
        XCTAssertEqual(restored.id, plain.id)
        XCTAssertNil(restored.memo)
        XCTAssertEqual(restored.createdAt, plain.createdAt)
        XCTAssertEqual(restored.totalReceived, 21)
        XCTAssertEqual(reloaded.lastPresentedAmountlessOffer(mintURL: url, unit: "usd")?.quoteId, "other-unit")
        XCTAssertNil(reloaded.lastPresentedAmountlessOffer(mintURL: "https://other.example", unit: "sat"))
    }

    func testResetForWalletBoundaryClearsRequestsAndDefaults() {
        let suiteName = "CashuRequestStoreBoundaryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CashuRequestStore(userDefaults: defaults)
        _ = store.createNew(mints: ["https://mint.example.com"], encoded: "creqAexample")
        XCTAssertFalse(store.requests.isEmpty)
        XCTAssertNotNil(store.currentRequestId)

        store.resetForWalletBoundary()

        XCTAssertTrue(store.requests.isEmpty)
        XCTAssertNil(store.currentRequestId)
        XCTAssertNil(defaults.data(forKey: StorageKeys.cashuRequests))
        XCTAssertNil(defaults.string(forKey: StorageKeys.cashuRequestsCurrentId))
        // A fresh store over the same defaults must not resurrect anything.
        XCTAssertTrue(CashuRequestStore(userDefaults: defaults).requests.isEmpty)
    }
}

final class MintQuoteReconciliationResultTests: XCTestCase {
    func testSuccessfulMintInfersIssuedCounterWhenVerificationIsOffline() {
        let observed = quote(paid: 21, issued: 0)

        let result = MintQuoteReconciliationResult(
            observed: observed,
            mintedAmount: 21,
            verified: nil
        )

        XCTAssertEqual(result.newlyIssued, 21)
        XCTAssertEqual(result.quote.amountIssued, 21)
        XCTAssertEqual(result.remainingAmount, 0)
        XCTAssertTrue(result.hasSettledPayment)
        XCTAssertTrue(result.quote.isAmountless)
    }

    func testVerifiedCountersResolveLostMintResponse() {
        let observed = quote(paid: 13, issued: 0)
        let verified = quote(paid: 13, issued: 13)

        let result = MintQuoteReconciliationResult(
            observed: observed,
            mintedAmount: 0,
            verified: verified
        )

        XCTAssertEqual(result.newlyIssued, 13)
        XCTAssertTrue(result.hasSettledPayment)
        XCTAssertEqual(result.quote.state, .issued)
    }

    func testLaterReusablePaymentOnlyIssuesNewCounterDelta() {
        let observed = quote(paid: 34, issued: 21)
        let verified = quote(paid: 34, issued: 34)

        let result = MintQuoteReconciliationResult(
            observed: observed,
            mintedAmount: 13,
            verified: verified
        )

        XCTAssertEqual(result.newlyIssued, 13)
        XCTAssertEqual(result.quote.amountIssued, 34)
        XCTAssertTrue(result.hasSettledPayment)
    }

    func testUnissuedPaymentNeverBecomesFalseSuccess() {
        let observed = quote(paid: 8, issued: 0)

        let result = MintQuoteReconciliationResult(observed: observed)

        XCTAssertEqual(result.newlyIssued, 0)
        XCTAssertEqual(result.remainingAmount, 8)
        XCTAssertFalse(result.hasSettledPayment)
        XCTAssertEqual(result.quote.state, .paid)
    }

    private func quote(paid: UInt64, issued: UInt64) -> MintQuoteInfo {
        MintQuoteInfo(
            id: "reusable-quote",
            request: "lno1test",
            amount: paid > 0 ? paid : nil,
            isAmountless: true,
            paymentMethod: .bolt12,
            state: paid > issued ? .paid : .issued,
            expiry: nil,
            createdAt: nil,
            unit: "sat",
            mintURL: "https://mint.example",
            amountPaid: paid,
            amountIssued: issued
        )
    }
}

@MainActor
final class MintQuoteReconcilerTests: XCTestCase {
    func testRecoveryDuringFirstCheckReportsIssuanceOnce() async {
        let ledger = Ledger(paid: 21)
        ledger.recoverOnNextCheck = 21
        let recovered = await ledger.reconciler().reconcile(quoteID: ledger.quote.id)
        let duplicate = await ledger.reconciler().reconcile(quoteID: ledger.quote.id)

        XCTAssertEqual(recovered?.newlyIssued, 21)
        XCTAssertEqual(recovered?.hasSettledPayment, true)
        XCTAssertEqual(duplicate?.newlyIssued, 0)
        XCTAssertEqual(ledger.mintCalls, 0)
    }

    func testCheckRecoveryAndLaterPaymentReportCombinedDelta() async {
        let ledger = Ledger(paid: 34)
        ledger.recoverOnNextCheck = 21
        let result = await ledger.reconciler().reconcile(quoteID: ledger.quote.id)

        XCTAssertEqual(result?.newlyIssued, 34)
        XCTAssertEqual(result?.hasSettledPayment, true)
        XCTAssertEqual(ledger.mintCalls, 1)
    }

    func testAutomaticRetryWaitsAcrossRecreationAndManualRetryBypassesDeadline() async throws {
        let ledger = Ledger(paid: 8)
        ledger.failuresBeforeIssuance = 5
        let firstResult = await ledger.reconciler().reconcile(quoteID: ledger.quote.id)
        let first = try XCTUnwrap(firstResult)
        let calls = ledger.checkCalls
        let record = ledger.record

        // Recreate the reconciler while retaining the persisted schedule.
        let deferred = await ledger.reconciler().reconcile(quoteID: ledger.quote.id)
        XCTAssertEqual(deferred?.retryStatus, first.retryStatus)
        XCTAssertEqual(ledger.checkCalls, calls)
        XCTAssertEqual(ledger.mintCalls, 1)
        XCTAssertEqual(ledger.record, record)

        ledger.now = try XCTUnwrap(first.retryStatus.nextRetryAt)
        _ = await ledger.reconciler().reconcile(quoteID: ledger.quote.id)
        XCTAssertEqual(ledger.mintCalls, 2)

        ledger.failuresBeforeIssuance = 0
        let manual = await ledger.reconciler().reconcile(quoteID: ledger.quote.id, force: true)
        XCTAssertEqual(manual?.newlyIssued, 8)
        XCTAssertEqual(manual?.retryStatus.state, MintQuoteRetryState.none)
        XCTAssertEqual(ledger.mintCalls, 3)
    }

    func testDepositConfirmedAfterExpiryIsIssuedOnNextSweep() async {
        let ledger = Ledger(paid: 0, method: .onchain, expiry: 1)
        _ = await ledger.reconciler().reconcile(quoteID: ledger.quote.id)
        XCTAssertEqual(ledger.record?.isComplete, false)

        ledger.quote.amountPaid = 21
        ledger.quote.state = .paid
        ledger.now = ledger.now.addingTimeInterval(60)
        let selection = MintQuoteSchedulePolicy.select(
            quoteIDs: [ledger.quote.id], existing: [ledger.quote.id: ledger.record!],
            now: ledger.now, force: false
        )
        XCTAssertEqual(selection.quoteIDs, [ledger.quote.id])
        ledger.record = selection.records[ledger.quote.id]
        let result = await ledger.reconciler().reconcile(quoteID: ledger.quote.id)
        XCTAssertEqual(result?.newlyIssued, 21)
        XCTAssertEqual(result?.hasSettledPayment, true)
    }

    @MainActor
    private final class Ledger {
        var quote: MintQuoteInfo
        var now = Date(timeIntervalSince1970: 10)
        var record: MintQuoteScheduleRecord?
        var checkCalls = 0
        var mintCalls = 0
        var recoverOnNextCheck: UInt64 = 0
        var failuresBeforeIssuance = 0
        private enum Failure: Error { case temporary }

        init(paid: UInt64, method: PaymentMethodKind = .bolt12, expiry: UInt64? = nil) {
            quote = MintQuoteInfo(
                id: "quote", request: "request", amount: nil, isAmountless: true,
                paymentMethod: method, state: paid > 0 ? .paid : .pending,
                expiry: expiry, createdAt: nil, amountPaid: paid, amountIssued: 0
            )
        }

        func reconciler() -> MintQuoteReconciler {
            MintQuoteReconciler(
                storedQuote: { _ in self.quote },
                checkQuote: { _ in
                    self.checkCalls += 1
                    self.quote.amountIssued += self.recoverOnNextCheck
                    self.recoverOnNextCheck = 0
                    return self.quote
                },
                mintQuote: { _ in
                    self.mintCalls += 1
                    if self.failuresBeforeIssuance > 0 {
                        self.failuresBeforeIssuance -= 1
                        throw Failure.temporary
                    }
                    let amount = self.quote.mintableAmount
                    self.quote.amountIssued = self.quote.amountPaid
                    self.quote.state = .issued
                    return amount
                },
                schedule: { _ in self.record },
                observed: { quote in
                    self.record = MintQuoteSchedulePolicy.observed(
                        previous: self.record, quote: quote, now: self.now
                    )
                },
                failed: { _, quote in
                    let record = MintQuoteSchedulePolicy.failed(
                        previous: self.record, now: self.now,
                        hadOutstandingPayment: (quote?.mintableAmount ?? 0) > 0,
                        isReusable: quote?.paymentMethod == .bolt12
                    )
                    self.record = record
                    return MintQuoteSchedulePolicy.retryStatus(for: record)
                },
                logFailure: { _, _ in },
                now: { self.now }
            )
        }
    }
}

final class MintQuoteSchedulePolicyTests: XCTestCase {
    func testOnchainDepositRemainsEligibleAfterExpiryAndOldScheduleReopens() {
        let pending = MintQuoteInfo(
            id: "pending-confirmation", request: "address", amount: nil,
            isAmountless: true, paymentMethod: .onchain, state: .pending,
            expiry: 100, createdAt: nil
        )
        let record = MintQuoteSchedulePolicy.observed(
            previous: nil, quote: pending, now: Date(timeIntervalSince1970: 101)
        )
        XCTAssertFalse(record.isComplete)
        for force in [false, true] {
            let selection = MintQuoteSchedulePolicy.select(
                quoteIDs: [pending.id], existing: [pending.id: record],
                now: Date(timeIntervalSince1970: 700), force: force
            )
            XCTAssertEqual(selection.quoteIDs, [pending.id])
        }

        var oldRecord = record
        oldRecord.isComplete = true
        oldRecord.nextAttemptAt = .greatestFiniteMagnitude
        let restored = MintQuoteSchedulePolicy.select(
            quoteIDs: [pending.id], existing: [pending.id: oldRecord],
            now: Date(timeIntervalSince1970: 700), force: false,
            unsettledOnchainQuoteIDs: [pending.id]
        )
        XCTAssertEqual(restored.quoteIDs, [pending.id])
    }

    func testSelectingDueFailedQuoteDoesNotPostponeItsRetry() {
        let record = MintQuoteSchedulePolicy.failed(
            previous: nil, now: Date(timeIntervalSince1970: 10),
            hadOutstandingPayment: true, isReusable: true
        )
        let now = Date(timeIntervalSince1970: record.nextAttemptAt)
        let selection = MintQuoteSchedulePolicy.select(
            quoteIDs: ["quote"], existing: ["quote": record], now: now, force: false
        )
        XCTAssertEqual(selection.quoteIDs, ["quote"])
        XCTAssertTrue(MintQuoteSchedulePolicy.shouldAttempt(
            record: selection.records["quote"], now: now, force: false
        ))
    }

    func testPassiveSweepsAreBoundedAndRotateFairly() {
        let ids = Set((1...5).map { "quote-\($0)" })
        let now = Date(timeIntervalSince1970: 1_000)
        let first = MintQuoteSchedulePolicy.select(
            quoteIDs: ids,
            existing: [:],
            now: now,
            force: false
        )
        let second = MintQuoteSchedulePolicy.select(
            quoteIDs: ids,
            existing: first.records,
            now: now,
            force: false
        )

        XCTAssertEqual(first.quoteIDs.count, MintQuoteSchedulePolicy.passiveBatchLimit)
        XCTAssertEqual(second.quoteIDs.count, MintQuoteSchedulePolicy.passiveBatchLimit)
        XCTAssertTrue(Set(first.quoteIDs).isDisjoint(with: second.quoteIDs))
    }

    func testForcedSweepBypassesDueTimeButStaysBounded() {
        let ids = Set((1...30).map { "quote-\($0)" })
        let future = Dictionary(uniqueKeysWithValues: ids.map {
            ($0, MintQuoteScheduleRecord(
                firstObservedAt: 1,
                nextAttemptAt: .greatestFiniteMagnitude
            ))
        })

        XCTAssertTrue(MintQuoteSchedulePolicy.select(
            quoteIDs: ids,
            existing: future,
            now: Date(timeIntervalSince1970: 2_000),
            force: false
        ).quoteIDs.isEmpty)
        XCTAssertEqual(MintQuoteSchedulePolicy.select(
            quoteIDs: ids,
            existing: future,
            now: Date(timeIntervalSince1970: 2_000),
            force: true
        ).quoteIDs.count, MintQuoteSchedulePolicy.forcedBatchLimit)
    }

    func testPaidFailuresEscalateFromRetryScheduledToNeedsAttention() {
        var record: MintQuoteScheduleRecord?
        record = nil
        for failure in 0..<3 {
            record = MintQuoteSchedulePolicy.failed(
                previous: record,
                now: Date(timeIntervalSince1970: TimeInterval(failure * 10)),
                hadOutstandingPayment: true,
                isReusable: true
            )
        }
        XCTAssertEqual(
            MintQuoteSchedulePolicy.retryStatus(for: record!).state,
            .retryScheduled
        )

        record = MintQuoteSchedulePolicy.failed(
            previous: record,
            now: Date(timeIntervalSince1970: 40),
            hadOutstandingPayment: true,
            isReusable: true
        )
        XCTAssertEqual(MintQuoteSchedulePolicy.retryStatus(for: record!).state, .needsAttention)
        XCTAssertEqual(record?.consecutiveFailures, 4)
    }

    func testWaitingFailureBacksOffWithoutClaimingPaymentNeedsAttention() {
        let record = MintQuoteSchedulePolicy.failed(
            previous: nil,
            now: Date(timeIntervalSince1970: 10),
            hadOutstandingPayment: false,
            isReusable: true
        )

        XCTAssertEqual(MintQuoteSchedulePolicy.retryStatus(for: record).state, .none)
        XCTAssertGreaterThan(record.nextAttemptAt, 10)
    }

    func testFailureCounterSaturatesWithoutOverflowing() {
        let saturated = MintQuoteSchedulePolicy.failed(
            previous: MintQuoteScheduleRecord(
                firstObservedAt: 1,
                consecutiveFailures: .max,
                hadOutstandingPayment: true
            ),
            now: Date(timeIntervalSince1970: 10),
            hadOutstandingPayment: true,
            isReusable: true
        )

        XCTAssertEqual(saturated.consecutiveFailures, .max)
        XCTAssertEqual(MintQuoteSchedulePolicy.retryStatus(for: saturated).state, .needsAttention)
    }

    func testReusableQuoteRemainsScheduledAfterIssuanceCatchesUp() {
        let record = MintQuoteSchedulePolicy.observed(
            previous: nil,
            quote: quote(method: .bolt12),
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertTrue(record.isReusable)
        XCTAssertFalse(record.isComplete)
        XCTAssertGreaterThan(record.nextAttemptAt, 1_000)
    }

    func testSettledOneShotQuoteLeavesScheduler() {
        let record = MintQuoteSchedulePolicy.observed(
            previous: nil,
            quote: quote(method: .bolt11),
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertTrue(record.isComplete)
        XCTAssertTrue(MintQuoteSchedulePolicy.select(
            quoteIDs: ["quote"],
            existing: ["quote": record],
            now: .distantFuture,
            force: true
        ).quoteIDs.isEmpty)
    }

    private func quote(method: PaymentMethodKind) -> MintQuoteInfo {
        MintQuoteInfo(
            id: "quote",
            request: "request",
            amount: 21,
            isAmountless: method == .bolt12,
            paymentMethod: method,
            state: .issued,
            expiry: nil,
            createdAt: nil,
            amountPaid: 21,
            amountIssued: 21
        )
    }
}

final class WalletStoreTests: XCTestCase {
    private var store: WalletStore!

    override func setUp() {
        super.setUp()
        store = WalletStore(storage: InMemoryStorage())
    }

    // MARK: - Mints

    func testLoadMintsEmptyByDefault() {
        XCTAssertTrue(store.loadMints().isEmpty)
    }

    func testSaveAndLoadSingleMint() {
        let mint = mint("https://mint.example.com", name: "Test Mint")
        store.saveMints([mint])
        let loaded = store.loadMints()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].url, "https://mint.example.com")
        XCTAssertEqual(loaded[0].name, "Test Mint")
    }

    func testSaveMintsOverwritesPrevious() {
        store.saveMints([mint("https://mint1.example.com", name: "Mint 1")])
        store.saveMints([mint("https://mint2.example.com", name: "Mint 2")])
        let loaded = store.loadMints()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].url, "https://mint2.example.com")
    }

    func testSaveAndLoadMultipleMints() {
        let mints = [
            mint("https://mint1.example.com", name: "Mint 1"),
            mint("https://mint2.example.com", name: "Mint 2"),
        ]
        store.saveMints(mints)
        XCTAssertEqual(store.loadMints().count, 2)
    }

    func testSaveAndLoadBalancesByUnit() {
        store.saveBalancesByUnit(["sat": 21, "usd": 500])
        XCTAssertEqual(store.loadBalancesByUnit(), ["sat": 21, "usd": 500])
    }

    // MARK: - Active Mint URL

    func testActiveMintURLNilByDefault() {
        XCTAssertNil(store.activeMintURL)
    }

    func testSetAndGetActiveMintURL() {
        store.activeMintURL = "https://mint.example.com"
        XCTAssertEqual(store.activeMintURL, "https://mint.example.com")
    }

    func testClearActiveMintURL() {
        store.activeMintURL = "https://mint.example.com"
        store.activeMintURL = nil
        XCTAssertNil(store.activeMintURL)
    }

    // MARK: - Pending Receive Tokens (Incoming)

    func testLoadPendingReceiveTokensEmptyByDefault() {
        XCTAssertTrue(store.loadPendingReceiveTokens().isEmpty)
    }

    func testSaveAndLoadPendingReceiveToken() {
        let token = PendingReceiveToken(
            tokenId: "recv1",
            token: "cashuAtoken",
            amount: 50,
            date: Date(),
            mintUrl: "https://mint.example.com"
        )
        store.savePendingReceiveTokens([token])
        let loaded = store.loadPendingReceiveTokens()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].tokenId, "recv1")
    }

    // MARK: - Saved Tokens (txId → encoded token)

    func testSaveAndLoadSavedToken() {
        store.saveSavedTokens(["tx1": "cashuAtoken123"])
        XCTAssertEqual(store.loadSavedTokens()["tx1"], "cashuAtoken123")
    }

    func testSavedTokensEmptyByDefault() {
        XCTAssertTrue(store.loadSavedTokens().isEmpty)
    }

    // MARK: - Payment Preimages

    func testLoadPaymentPreimagesEmptyByDefault() {
        XCTAssertTrue(store.loadPaymentPreimages().isEmpty)
    }

    func testSaveAndLoadPreimage() {
        store.savePaymentPreimages(["quoteId1": "deadbeef"])
        XCTAssertEqual(store.loadPaymentPreimages()["quoteId1"], "deadbeef")
    }

    // MARK: - Mint Quote Timestamps

    func testMintQuoteTimestampsEmptyByDefault() {
        XCTAssertTrue(store.loadMintQuoteTimestamps().isEmpty)
    }

    func testSaveAndLoadMintQuoteTimestamps() {
        let ts: TimeInterval = 1_700_000_000
        store.saveMintQuoteTimestamps(["quoteA": ts])
        XCTAssertEqual(store.loadMintQuoteTimestamps()["quoteA"], ts)
    }

    func testSaveAndLoadMintQuoteSchedules() {
        let record = MintQuoteScheduleRecord(
            firstObservedAt: 1_700_000_000,
            nextAttemptAt: 1_700_000_010,
            consecutiveFailures: 2,
            hadOutstandingPayment: true,
            isReusable: true
        )
        store.saveMintQuoteSchedules(["quoteA": record])
        XCTAssertEqual(store.loadMintQuoteSchedules()["quoteA"], record)
    }

    func testSaveAndLoadMintKeysetRefreshTimestamps() {
        let ts: TimeInterval = 1_700_000_000
        store.saveMintKeysetRefreshTimestamps(["https://mint.example.com": ts])
        XCTAssertEqual(store.loadMintKeysetRefreshTimestamps()["https://mint.example.com"], ts)
    }

    func testWalletStartupPolicyRefreshesMissingOrStaleKeysets() {
        let now: TimeInterval = 10_000
        XCTAssertTrue(WalletStartupPolicy.shouldRefreshKeysets(lastRefresh: nil, now: now))
        XCTAssertTrue(WalletStartupPolicy.shouldRefreshKeysets(
            lastRefresh: now - WalletStartupPolicy.keysetRefreshInterval,
            now: now
        ))
        XCTAssertFalse(WalletStartupPolicy.shouldRefreshKeysets(
            lastRefresh: now - WalletStartupPolicy.keysetRefreshInterval + 1,
            now: now
        ))
        XCTAssertTrue(WalletStartupPolicy.shouldRefreshKeysets(lastRefresh: now + 1, now: now))
    }

    func testWalletStartupPolicyKeepsPublishedCacheVisibleOnRuntimeFailure() {
        XCTAssertFalse(WalletStartupPolicy.needsOnboardingAfterRuntimeFailure(
            cachedWalletPublished: true
        ))
        XCTAssertTrue(WalletStartupPolicy.needsOnboardingAfterRuntimeFailure(
            cachedWalletPublished: false
        ))
    }

    func testDatabaseRecoveryPolicyAcceptsOnlyExplicitCorruptionErrors() {
        let corruptionErrors = [
            "SQLite error SQLITE_CORRUPT: database disk image is malformed",
            "SQLite error SQLITE_NOTADB: file is not a database",
            "malformed database schema (wallets)",
            "database disk image is corrupt",
        ]

        for message in corruptionErrors {
            XCTAssertTrue(
                WalletDatabaseRecoveryPolicy.shouldRecover(errorDescription: message),
                message
            )
        }
    }

    func testDatabaseRecoveryPolicyRejectsTransientPermissionAndIOErrors() {
        let nonCorruptionErrors = [
            "SQLite database is locked",
            "SQLite database is busy",
            "unable to open database file",
            "attempt to write a readonly database",
            "permission denied while opening WalletDB",
            "SQLite disk I/O error",
            "WalletDB open failed",
            "Invalid seed phrase.",
            "Couldn't reach the mint.",
        ]

        for message in nonCorruptionErrors {
            XCTAssertFalse(
                WalletDatabaseRecoveryPolicy.shouldRecover(errorDescription: message),
                message
            )
        }
    }

    func testIncompleteICloudRestoreSuppressesBackupWrites() {
        XCTAssertFalse(ICloudRestorePolicy.shouldPerformBackup(restoreIncomplete: true))
        XCTAssertTrue(ICloudRestorePolicy.shouldPerformBackup(restoreIncomplete: false))
    }

    func testIncompleteICloudRestoreRequiresOnboardingWithStoredSeed() {
        XCTAssertTrue(ICloudRestorePolicy.needsOnboarding(
            hasStoredMnemonic: true,
            restoreIncomplete: true,
            onboardingCompleted: true
        ))
        XCTAssertFalse(ICloudRestorePolicy.needsOnboarding(
            hasStoredMnemonic: true,
            restoreIncomplete: false,
            onboardingCompleted: true
        ))
        XCTAssertTrue(ICloudRestorePolicy.needsOnboarding(
            hasStoredMnemonic: false,
            restoreIncomplete: false,
            onboardingCompleted: false
        ))
    }

    func testIncompleteOnboardingRequiresOnboardingWithStoredSeed() {
        // Killed mid-onboarding: seed persisted, completion marker false.
        XCTAssertTrue(ICloudRestorePolicy.needsOnboarding(
            hasStoredMnemonic: true,
            restoreIncomplete: false,
            onboardingCompleted: false
        ))
    }

    func testOnboardingCompletionMarkerRoundTrips() {
        let suiteName = "OnboardingCompletionStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(OnboardingCompletionState.hasMarker(defaults: defaults))
        XCTAssertFalse(OnboardingCompletionState.isCompleted(defaults: defaults))

        OnboardingCompletionState.setCompleted(false, defaults: defaults)
        XCTAssertTrue(OnboardingCompletionState.hasMarker(defaults: defaults))
        XCTAssertFalse(OnboardingCompletionState.isCompleted(defaults: defaults))

        OnboardingCompletionState.setCompleted(true, defaults: defaults)
        XCTAssertTrue(OnboardingCompletionState.hasMarker(defaults: defaults))
        XCTAssertTrue(OnboardingCompletionState.isCompleted(defaults: defaults))

        OnboardingCompletionState.clear(defaults: defaults)
        XCTAssertFalse(OnboardingCompletionState.hasMarker(defaults: defaults))
    }

    func testIncompleteICloudRestoreOverridesPublishedCacheAfterRuntimeFailure() {
        XCTAssertTrue(WalletStartupPolicy.needsOnboardingAfterRuntimeFailure(
            cachedWalletPublished: true,
            iCloudRestoreIncomplete: true
        ))
    }

    func testIncompleteICloudRestoreStatePersistsUntilCleared() {
        let suiteName = "ICloudRestoreStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(ICloudRestoreState.isIncomplete(defaults: defaults))

        ICloudRestoreState.setIncomplete(true, defaults: defaults)
        XCTAssertTrue(ICloudRestoreState.isIncomplete(
            defaults: UserDefaults(suiteName: suiteName)!
        ))

        ICloudRestoreState.setIncomplete(false, defaults: defaults)
        XCTAssertFalse(ICloudRestoreState.isIncomplete(defaults: defaults))
    }

    // MARK: - removeAllWalletData

    func testRemoveAllWalletDataClearsMints() {
        store.saveMints([mint("https://mint.example.com", name: "X")])
        store.removeAllWalletData()
        XCTAssertTrue(store.loadMints().isEmpty)
    }

    func testRemoveAllWalletDataClearsBalancesByUnit() {
        store.saveBalancesByUnit(["sat": 21, "eur": 100])
        store.removeAllWalletData()
        XCTAssertTrue(store.loadBalancesByUnit().isEmpty)
    }

    func testRemoveAllWalletDataClearsMintQuoteSchedules() {
        store.saveMintQuoteSchedules([
            "quote": MintQuoteScheduleRecord(
                firstObservedAt: 1,
                consecutiveFailures: 1,
                hadOutstandingPayment: true
            )
        ])
        store.removeAllWalletData()
        XCTAssertTrue(store.loadMintQuoteSchedules().isEmpty)
    }

    func testRemoveAllWalletDataClearsRetiredPendingTokenKeys() {
        let storage = InMemoryStorage()
        try! storage.set(["token"], forKey: StorageKeys.Retired.pendingTokens)
        try! storage.set(["token"], forKey: StorageKeys.Retired.claimedTokens)

        WalletStore(storage: storage).removeAllWalletData()

        XCTAssertFalse(storage.exists(forKey: StorageKeys.Retired.pendingTokens))
        XCTAssertFalse(storage.exists(forKey: StorageKeys.Retired.claimedTokens))
    }

    func testPurgeRetiredKeysRemovesCDK17Stores() {
        let storage = InMemoryStorage()
        for key in StorageKeys.Retired.all {
            try! storage.set("x", forKey: key)
        }
        try! storage.set("keep", forKey: StorageKeys.savedTokens)

        WalletStore(storage: storage).purgeRetiredKeys()

        for key in StorageKeys.Retired.all {
            XCTAssertFalse(storage.exists(forKey: key), "\(key) should be purged")
        }
        XCTAssertTrue(storage.exists(forKey: StorageKeys.savedTokens))
    }

    func testRemoveAllWalletDataClearsPreimages() {
        store.savePaymentPreimages(["q": "pre"])
        store.removeAllWalletData()
        XCTAssertTrue(store.loadPaymentPreimages().isEmpty)
    }

    func testRemoveAllWalletDataClearsSavedTokens() {
        store.saveSavedTokens(["tx": "cashuAtoken"])
        store.removeAllWalletData()
        XCTAssertTrue(store.loadSavedTokens().isEmpty)
    }

    func testRemoveAllWalletDataClearsMintKeysetRefreshTimestamps() {
        store.saveMintKeysetRefreshTimestamps(["https://mint.example.com": 123])
        store.removeAllWalletData()
        XCTAssertTrue(store.loadMintKeysetRefreshTimestamps().isEmpty)
    }

    func testRemoveAllWalletDataClearsCashuRequestKeys() {
        let storage = InMemoryStorage()
        try! storage.set("payload", forKey: StorageKeys.cashuRequests)
        try! storage.set("current", forKey: StorageKeys.cashuRequestsCurrentId)
        try! storage.set(["id1"], forKey: StorageKeys.cashuRequestsProcessedNIP17Ids)

        WalletStore(storage: storage).removeAllWalletData()

        XCTAssertFalse(storage.exists(forKey: StorageKeys.cashuRequests))
        XCTAssertFalse(storage.exists(forKey: StorageKeys.cashuRequestsCurrentId))
        XCTAssertFalse(storage.exists(forKey: StorageKeys.cashuRequestsProcessedNIP17Ids))
    }

    // MARK: - Legacy key migration

    func testLegacyMintKeyMigratesOnLoad() {
        let legacyStorage = InMemoryStorage()
        let legacyMint = mint("https://legacy.example.com", name: "Legacy")
        try! legacyStorage.set([legacyMint], forKey: StorageKeys.Legacy.mints)

        let storeWithLegacy = WalletStore(storage: legacyStorage)
        let loaded = storeWithLegacy.loadMints()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].url, "https://legacy.example.com")
    }

    // MARK: - Helpers

    private func mint(_ url: String, name: String) -> MintInfo {
        MintInfo(url: url, name: name, description: nil, isActive: true, balance: 0)
    }
}

@MainActor
final class CashuRequestStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "CashuRequestStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCreateNewPreservesEmbeddedPaymentRequestId() {
        let store = CashuRequestStore(userDefaults: defaults)

        let request = store.createNew(
            id: "request-id",
            amount: 42,
            unit: "sat",
            mints: ["https://mint.example.com"],
            memo: "coffee",
            encoded: "creqAtest"
        )

        XCTAssertEqual(request.id, "request-id")
        XCTAssertEqual(store.currentRequestId, "request-id")
        XCTAssertEqual(store.request(withId: "request-id")?.encoded, "creqAtest")

        store.attachPayment(requestId: "request-id", transactionId: "tx-1", amount: 42)
        XCTAssertEqual(store.request(withId: "request-id")?.receivedPayments.first?.transactionId, "tx-1")

        let reloaded = CashuRequestStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.currentRequestId, "request-id")
        XCTAssertEqual(reloaded.request(withId: "request-id")?.receivedPayments.first?.amount, 42)
    }

    func testUpdateReparameterizesInPlaceWithoutNewRow() {
        let store = CashuRequestStore(userDefaults: defaults)

        _ = store.createNew(id: "request-id", encoded: "creqAamountless")
        store.attachPayment(requestId: "request-id", transactionId: "tx-1", amount: 21)

        store.update(
            id: "request-id",
            amount: 42,
            unit: "eur",
            mints: ["https://mint.example.com"],
            encoded: "creqAamounted"
        )

        XCTAssertEqual(store.requests.count, 1)
        let updated = store.request(withId: "request-id")
        XCTAssertEqual(updated?.amount, 42)
        XCTAssertEqual(updated?.unit, "eur")
        XCTAssertEqual(updated?.mints, ["https://mint.example.com"])
        XCTAssertEqual(updated?.encoded, "creqAamounted")
        XCTAssertEqual(updated?.receivedPayments.first?.transactionId, "tx-1")
        XCTAssertEqual(store.currentRequestId, "request-id")

        let reloaded = CashuRequestStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.requests.count, 1)
        XCTAssertEqual(reloaded.request(withId: "request-id")?.encoded, "creqAamounted")
        XCTAssertEqual(reloaded.request(withId: "request-id")?.unit, "eur")
    }
}

final class WalletReplacementSafetyTests: XCTestCase {
    private enum TestError: Error {
        case forcedDeleteFailure
        case forcedMoveFailure
        case forcedSeedFailure
    }

    private final class SecureStorageSpy: SecureStorageProtocol {
        var secrets: [String: String] = [:]

        func saveSecret(_ secret: String, forKey key: String) throws {
            secrets[key] = secret
        }

        func loadSecret(forKey key: String) throws -> String? {
            secrets[key]
        }

        func deleteSecret(forKey key: String) throws {
            secrets.removeValue(forKey: key)
        }

        func hasSecret(forKey key: String) -> Bool {
            secrets[key] != nil
        }
    }

    func testMnemonicRollbackRestoresPreviousSeed() throws {
        let storage = SecureStorageSpy()
        storage.secrets[StorageKeys.Secure.mnemonic] = "replacement seed"

        try WalletMnemonicRollback.restore(
            previousMnemonic: "original seed",
            secureStorage: storage
        )

        XCTAssertEqual(
            storage.secrets[StorageKeys.Secure.mnemonic],
            "original seed"
        )
    }

    func testMnemonicRollbackDeletesReplacementWhenNoSeedExisted() throws {
        let storage = SecureStorageSpy()
        storage.secrets[StorageKeys.Secure.mnemonic] = "replacement seed"

        try WalletMnemonicRollback.restore(
            previousMnemonic: nil,
            secureStorage: storage
        )

        XCTAssertNil(storage.secrets[StorageKeys.Secure.mnemonic])
    }

    func testPartialBackupFailureRestoresEveryMovedOriginal() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("first.db")
        let second = directory.appendingPathComponent("second.db")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        var forwardMoveCount = 0
        let operations = WalletReplacementFileOperations(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            moveItem: { source, destination in
                if !source.lastPathComponent.hasSuffix(".backup") {
                    forwardMoveCount += 1
                    if forwardMoveCount == 2 {
                        throw TestError.forcedMoveFailure
                    }
                }
                try FileManager.default.moveItem(at: source, to: destination)
            },
            removeItem: { try FileManager.default.removeItem(at: $0) }
        )

        XCTAssertThrowsError(
            try WalletReplacementFiles.backup(
                urls: [first, second],
                operations: operations,
                backupURL: { $0.appendingPathExtension("backup") }
            )
        )
        XCTAssertEqual(try Data(contentsOf: first), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("second".utf8))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: first.appendingPathExtension("backup").path
            )
        )
    }

    func testPartialBackupFailureReportedAfterMoveRestoresCurrentOriginal() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("first.db")
        let second = directory.appendingPathComponent("second.db")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let operations = WalletReplacementFileOperations(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            moveItem: { source, destination in
                try FileManager.default.moveItem(at: source, to: destination)
                if source == second {
                    throw TestError.forcedMoveFailure
                }
            },
            removeItem: { try FileManager.default.removeItem(at: $0) }
        )

        XCTAssertThrowsError(
            try WalletReplacementFiles.backup(
                urls: [first, second],
                operations: operations,
                backupURL: { $0.appendingPathExtension("backup") }
            )
        )
        XCTAssertEqual(try Data(contentsOf: first), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("second".utf8))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: first.appendingPathExtension("backup").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: second.appendingPathExtension("backup").path
        ))
    }

    func testMissingBackupNeverDeletesReplacementDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("wallet.db")
        let missingBackup = directory.appendingPathComponent("wallet.db.backup")
        try Data("replacement".utf8).write(to: original)

        XCTAssertThrowsError(
            try WalletReplacementFiles.restore(
                at: [original],
                [WalletFileBackup(originalURL: original, backupURL: missingBackup)],
                displacedURL: { $0.appendingPathExtension("displaced") }
            )
        )
        XCTAssertEqual(try Data(contentsOf: original), Data("replacement".utf8))
    }

    func testRestorePreflightsEveryBackupBeforeMovingAnyDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstOriginal = directory.appendingPathComponent("first.db")
        let firstMissingBackup = directory.appendingPathComponent("first.db.backup")
        let secondOriginal = directory.appendingPathComponent("second.db")
        let secondBackup = directory.appendingPathComponent("second.db.backup")
        try Data("new first".utf8).write(to: firstOriginal)
        try Data("new second".utf8).write(to: secondOriginal)
        try Data("old second".utf8).write(to: secondBackup)

        XCTAssertThrowsError(
            try WalletReplacementFiles.restore(
                at: [firstOriginal, secondOriginal],
                [
                    WalletFileBackup(
                        originalURL: firstOriginal,
                        backupURL: firstMissingBackup
                    ),
                    WalletFileBackup(
                        originalURL: secondOriginal,
                        backupURL: secondBackup
                    ),
                ],
                displacedURL: { $0.appendingPathExtension("displaced") }
            )
        )
        XCTAssertEqual(try Data(contentsOf: secondOriginal), Data("new second".utf8))
        XCTAssertEqual(try Data(contentsOf: secondBackup), Data("old second".utf8))
    }

    func testCommittedRestoreRemovesDatabaseCreatedWithoutAnOriginalBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let newlyCreatedDatabase = directory.appendingPathComponent("wallet.db")
        try Data("replacement".utf8).write(to: newlyCreatedDatabase)

        try WalletReplacementFiles.restore(
            at: [newlyCreatedDatabase],
            [],
            displacedURL: { $0.appendingPathExtension("displaced") }
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: newlyCreatedDatabase.path)
        )
    }

    func testFailedRestoreMovePutsReplacementDatabaseBack() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("wallet.db")
        let backup = directory.appendingPathComponent("wallet.db.backup")
        try Data("replacement".utf8).write(to: original)
        try Data("original".utf8).write(to: backup)

        var moveCount = 0
        let operations = WalletReplacementFileOperations(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            moveItem: { source, destination in
                moveCount += 1
                if moveCount == 2 {
                    throw TestError.forcedMoveFailure
                }
                try FileManager.default.moveItem(at: source, to: destination)
            },
            removeItem: { try FileManager.default.removeItem(at: $0) }
        )

        XCTAssertThrowsError(
            try WalletReplacementFiles.restore(
                at: [original],
                [WalletFileBackup(originalURL: original, backupURL: backup)],
                operations: operations,
                displacedURL: { $0.appendingPathExtension("displaced") }
            )
        )
        XCTAssertEqual(try Data(contentsOf: original), Data("replacement".utf8))
        XCTAssertEqual(try Data(contentsOf: backup), Data("original".utf8))
    }

    func testDisplacementFailureReportedAfterMoveRestoresReplacement() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("wallet.db")
        let backup = directory.appendingPathComponent("wallet.db.backup")
        let displaced = original.appendingPathExtension("displaced")
        try Data("replacement".utf8).write(to: original)
        try Data("original".utf8).write(to: backup)

        let operations = WalletReplacementFileOperations(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            moveItem: { source, destination in
                try FileManager.default.moveItem(at: source, to: destination)
                if source == original && destination == displaced {
                    throw TestError.forcedMoveFailure
                }
            },
            removeItem: { try FileManager.default.removeItem(at: $0) }
        )

        XCTAssertThrowsError(
            try WalletReplacementFiles.restore(
                at: [original],
                [WalletFileBackup(originalURL: original, backupURL: backup)],
                operations: operations,
                displacedURL: { _ in displaced }
            )
        )
        XCTAssertEqual(try Data(contentsOf: original), Data("replacement".utf8))
        XCTAssertEqual(try Data(contentsOf: backup), Data("original".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: displaced.path))
    }

    func testRestoreFailureReportedAfterMoveRestoresReplacementAndBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("wallet.db")
        let backup = directory.appendingPathComponent("wallet.db.backup")
        let displaced = original.appendingPathExtension("displaced")
        try Data("replacement".utf8).write(to: original)
        try Data("original".utf8).write(to: backup)

        var didFail = false
        let operations = WalletReplacementFileOperations(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            moveItem: { source, destination in
                try FileManager.default.moveItem(at: source, to: destination)
                if source == backup && !didFail {
                    didFail = true
                    throw TestError.forcedMoveFailure
                }
            },
            removeItem: { try FileManager.default.removeItem(at: $0) }
        )

        XCTAssertThrowsError(
            try WalletReplacementFiles.restore(
                at: [original],
                [WalletFileBackup(originalURL: original, backupURL: backup)],
                operations: operations,
                displacedURL: { _ in displaced }
            )
        )
        XCTAssertEqual(try Data(contentsOf: original), Data("replacement".utf8))
        XCTAssertEqual(try Data(contentsOf: backup), Data("original".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: displaced.path))
    }

    func testSeedCommitFailureRollsFilesAndSeedForwardToReplacement() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("wallet.db")
        let backup = directory.appendingPathComponent("wallet.db.backup")
        let displaced = original.appendingPathExtension("displaced")
        try Data("replacement".utf8).write(to: original)
        try Data("original".utf8).write(to: backup)
        var activeSeed = "replacement seed"

        XCTAssertThrowsError(
            try WalletReplacementFiles.restore(
                at: [original],
                [WalletFileBackup(originalURL: original, backupURL: backup)],
                displacedURL: { _ in displaced },
                beforeCommit: {
                    activeSeed = "original seed"
                    throw TestError.forcedSeedFailure
                },
                onRollback: {
                    activeSeed = "replacement seed"
                }
            )
        )
        XCTAssertEqual(activeSeed, "replacement seed")
        XCTAssertEqual(try Data(contentsOf: original), Data("replacement".utf8))
        XCTAssertEqual(try Data(contentsOf: backup), Data("original".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: displaced.path))
    }

    func testLaterRestoreFailureRestoresEveryReplacementAndBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstOriginal = directory.appendingPathComponent("first.db")
        let firstBackup = directory.appendingPathComponent("first.db.backup")
        let secondOriginal = directory.appendingPathComponent("second.db")
        let secondBackup = directory.appendingPathComponent("second.db.backup")
        let firstDisplaced = firstOriginal.appendingPathExtension("displaced")
        let secondDisplaced = secondOriginal.appendingPathExtension("displaced")
        try Data("new first".utf8).write(to: firstOriginal)
        try Data("old first".utf8).write(to: firstBackup)
        try Data("new second".utf8).write(to: secondOriginal)
        try Data("old second".utf8).write(to: secondBackup)

        var backupMoveCount = 0
        let operations = WalletReplacementFileOperations(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            moveItem: { source, destination in
                if source.pathExtension == "backup" {
                    backupMoveCount += 1
                    if backupMoveCount == 2 {
                        throw TestError.forcedMoveFailure
                    }
                }
                try FileManager.default.moveItem(at: source, to: destination)
            },
            removeItem: { try FileManager.default.removeItem(at: $0) }
        )

        XCTAssertThrowsError(
            try WalletReplacementFiles.restore(
                at: [firstOriginal, secondOriginal],
                [
                    WalletFileBackup(
                        originalURL: firstOriginal,
                        backupURL: firstBackup
                    ),
                    WalletFileBackup(
                        originalURL: secondOriginal,
                        backupURL: secondBackup
                    ),
                ],
                operations: operations,
                displacedURL: { $0.appendingPathExtension("displaced") }
            )
        )

        XCTAssertEqual(backupMoveCount, 2)
        XCTAssertEqual(try Data(contentsOf: firstOriginal), Data("new first".utf8))
        XCTAssertEqual(try Data(contentsOf: firstBackup), Data("old first".utf8))
        XCTAssertEqual(try Data(contentsOf: secondOriginal), Data("new second".utf8))
        XCTAssertEqual(try Data(contentsOf: secondBackup), Data("old second".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstDisplaced.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondDisplaced.path))
    }

    func testLaterDatabaseMoveFailureRestoresSourcesAndExistingDestination() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSource = directory.appendingPathComponent("first-source.db")
        let secondSource = directory.appendingPathComponent("second-source.db")
        let firstDestination = directory.appendingPathComponent("first-destination.db")
        let secondDestination = directory.appendingPathComponent("second-destination.db")
        let displaced = secondDestination.appendingPathExtension("displaced")
        try Data("first source".utf8).write(to: firstSource)
        try Data("second source".utf8).write(to: secondSource)
        try Data("existing destination".utf8).write(to: secondDestination)

        let operations = WalletReplacementFileOperations(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            moveItem: { source, destination in
                if source == secondSource {
                    throw TestError.forcedMoveFailure
                }
                try FileManager.default.moveItem(at: source, to: destination)
            },
            removeItem: { try FileManager.default.removeItem(at: $0) }
        )

        XCTAssertThrowsError(
            try WalletFileMoves.move(
                [
                    WalletFileMove(
                        sourceURL: firstSource,
                        destinationURL: firstDestination
                    ),
                    WalletFileMove(
                        sourceURL: secondSource,
                        destinationURL: secondDestination
                    ),
                ],
                operations: operations,
                displacedURL: { $0.appendingPathExtension("displaced") }
            )
        )

        XCTAssertEqual(try Data(contentsOf: firstSource), Data("first source".utf8))
        XCTAssertEqual(try Data(contentsOf: secondSource), Data("second source".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstDestination.path))
        XCTAssertEqual(
            try Data(contentsOf: secondDestination),
            Data("existing destination".utf8)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: displaced.path))
    }

    func testDatabaseMoveFailureReportedAfterMoveRestoresEverySource() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSource = directory.appendingPathComponent("first-source.db")
        let secondSource = directory.appendingPathComponent("second-source.db")
        let firstDestination = directory.appendingPathComponent("first-destination.db")
        let secondDestination = directory.appendingPathComponent("second-destination.db")
        try Data("first source".utf8).write(to: firstSource)
        try Data("second source".utf8).write(to: secondSource)

        let operations = WalletReplacementFileOperations(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            moveItem: { source, destination in
                try FileManager.default.moveItem(at: source, to: destination)
                if source == secondSource {
                    throw TestError.forcedMoveFailure
                }
            },
            removeItem: { try FileManager.default.removeItem(at: $0) }
        )

        XCTAssertThrowsError(
            try WalletFileMoves.move(
                [
                    WalletFileMove(
                        sourceURL: firstSource,
                        destinationURL: firstDestination
                    ),
                    WalletFileMove(
                        sourceURL: secondSource,
                        destinationURL: secondDestination
                    ),
                ],
                operations: operations,
                displacedURL: { $0.appendingPathExtension("displaced") }
            )
        )

        XCTAssertEqual(try Data(contentsOf: firstSource), Data("first source".utf8))
        XCTAssertEqual(try Data(contentsOf: secondSource), Data("second source".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstDestination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondDestination.path))
    }

    func testCommittedDatabaseMoveSurvivesDisplacedCleanupFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.db")
        let destination = directory.appendingPathComponent("destination.db")
        let displaced = destination.appendingPathExtension("displaced")
        try Data("new".utf8).write(to: source)
        try Data("old".utf8).write(to: destination)

        let operations = WalletReplacementFileOperations(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            moveItem: { try FileManager.default.moveItem(at: $0, to: $1) },
            removeItem: { url in
                if url == displaced {
                    throw TestError.forcedDeleteFailure
                }
                try FileManager.default.removeItem(at: url)
            }
        )

        try WalletFileMoves.move(
            [WalletFileMove(sourceURL: source, destinationURL: destination)],
            operations: operations,
            displacedURL: { _ in displaced }
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: destination), Data("new".utf8))
        XCTAssertEqual(try Data(contentsOf: displaced), Data("old".utf8))
    }
}
