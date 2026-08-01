import XCTest
@testable import CashuWallet

@MainActor
final class TransactionServiceTests: XCTestCase {
    private var service: TransactionService!

    override func setUp() {
        super.setUp()
        service = TransactionService(
            walletRepository: { nil },
            walletDatabase: { nil },
            getTrackedMintUrls: { [] },
            walletStore: WalletStore(storage: InMemoryStorage())
        )
    }

    func testHomeActivityShowsOnlyLatestCompletedTransactions() {
        let now = Date()
        var completedIncoming = transaction(
            id: "received-via-request",
            status: .completed,
            date: now.addingTimeInterval(-10),
            type: .incoming
        )
        completedIncoming.cashuRequestId = "request"
        let completedOutgoing = transaction(
            id: "sent",
            status: .completed,
            date: now
        )
        let pending = transaction(
            id: "pending-request",
            status: .pending,
            date: now.addingTimeInterval(10)
        )
        let failed = transaction(
            id: "failed",
            status: .failed,
            date: now.addingTimeInterval(20)
        )
        let expired = transaction(
            id: "expired",
            status: .expired,
            date: now.addingTimeInterval(30)
        )

        let recent = HomeActivity.recentTransactions(
            from: [completedIncoming, pending, failed, completedOutgoing, expired],
            limit: 5
        )

        XCTAssertEqual(recent.map(\.id), ["sent", "received-via-request"])
        XCTAssertEqual(
            HomeActivity.recentTransactions(
                from: [completedIncoming, completedOutgoing],
                limit: 1
            ).map(\.id),
            ["sent"]
        )
    }

    // MARK: - Saved token (txId ↔ encoded token)

    func testGetTokenNilByDefault() {
        XCTAssertNil(service.getToken(txId: "nonexistent"))
    }

    func testSaveAndGetToken() {
        service.saveToken(txId: "tx1", token: "cashuAtoken123")
        XCTAssertEqual(service.getToken(txId: "tx1"), "cashuAtoken123")
    }

    func testSaveTokenOverwritesPrevious() {
        service.saveToken(txId: "tx1", token: "cashuAold")
        service.saveToken(txId: "tx1", token: "cashuAnew")
        XCTAssertEqual(service.getToken(txId: "tx1"), "cashuAnew")
    }

    func testSaveMultipleTokensIndependently() {
        service.saveToken(txId: "a", token: "cashuAaaa")
        service.saveToken(txId: "b", token: "cashuAbbb")
        XCTAssertEqual(service.getToken(txId: "a"), "cashuAaaa")
        XCTAssertEqual(service.getToken(txId: "b"), "cashuAbbb")
    }

    // MARK: - Preimage (quoteId ↔ preimage)

    func testGetPreimageNilByDefault() {
        XCTAssertNil(service.getPreimage(quoteId: "nonexistent"))
    }

    func testSaveAndGetPreimage() {
        service.savePreimage(quoteId: "quote1", preimage: "deadbeef")
        XCTAssertEqual(service.getPreimage(quoteId: "quote1"), "deadbeef")
    }

    func testSaveMultiplePreimagesIndependently() {
        service.savePreimage(quoteId: "q1", preimage: "pre1")
        service.savePreimage(quoteId: "q2", preimage: "pre2")
        XCTAssertEqual(service.getPreimage(quoteId: "q1"), "pre1")
        XCTAssertEqual(service.getPreimage(quoteId: "q2"), "pre2")
    }

    // MARK: - Melt quote fees

    func testGetMeltFeePaidNilByDefault() {
        XCTAssertNil(service.getMeltFeePaid(quoteId: "nonexistent"))
    }

    func testSaveAndGetMeltFeePaid() {
        service.saveMeltFeePaid(quoteId: "melt1", feePaid: 3)
        XCTAssertEqual(service.getMeltFeePaid(quoteId: "melt1"), 3)
    }

    func testMeltFeeZeroIsStoredDistinctlyFromMissing() {
        service.saveMeltFeePaid(quoteId: "free", feePaid: 0)
        XCTAssertEqual(service.getMeltFeePaid(quoteId: "free"), 0)
    }

    // MARK: - Pending Tokens (savePendingToken / removePendingToken)

    func testPendingTokensEmptyInitially() {
        XCTAssertTrue(service.pendingTokens.isEmpty)
    }

    func testSavePendingTokenAppendsNewEntry() {
        service.savePendingToken(pendingToken(id: "p1", amount: 10))
        XCTAssertEqual(service.pendingTokens.count, 1)
        XCTAssertEqual(service.pendingTokens[0].tokenId, "p1")
    }

    func testSavePendingTokenUpdatesExisting() {
        let initial = pendingToken(id: "p1", amount: 10)
        let updated = PendingToken(
            tokenId: "p1", token: "cashuAupdated",
            amount: 20, fee: 1, date: Date(),
            mintUrl: "https://mint.example.com", memo: "updated"
        )
        service.savePendingToken(initial)
        service.savePendingToken(updated)
        XCTAssertEqual(service.pendingTokens.count, 1)
        XCTAssertEqual(service.pendingTokens[0].amount, 20)
    }

    func testRemovePendingTokenByID() {
        service.savePendingToken(pendingToken(id: "a", amount: 10))
        service.savePendingToken(pendingToken(id: "b", amount: 20))
        service.removePendingToken(tokenId: "a")
        XCTAssertEqual(service.pendingTokens.count, 1)
        XCTAssertEqual(service.pendingTokens[0].tokenId, "b")
    }

    func testRemoveNonExistentTokenIDIsNoop() {
        service.savePendingToken(pendingToken(id: "x", amount: 5))
        service.removePendingToken(tokenId: "nonexistent")
        XCTAssertEqual(service.pendingTokens.count, 1)
    }

    // MARK: - markTokenAsClaimed state machine

    func testMarkTokenAsClaimedMovesFromPendingToClaimed() {
        let token = pendingToken(id: "c1", amount: 21)
        service.savePendingToken(token)
        service.markTokenAsClaimed(token: token.token)

        XCTAssertTrue(service.pendingTokens.isEmpty, "Pending list should be empty after claim")
    }

    func testMergePendingUSDTokenIntoMatchingRowDoesNotCreateSatDuplicate() {
        let date = Date()
        let pending = PendingToken(
            tokenId: "usd-pending",
            token: "not-needed-for-unit-matching",
            amount: 10,
            fee: 1,
            date: date,
            mintUrl: "https://mint.example.com",
            memo: nil,
            unit: "usd"
        )
        service.savePendingToken(pending)

        var transaction = WalletTransaction(
            id: "cdk-usd-send",
            amount: 10,
            type: .outgoing,
            kind: .ecash,
            date: date,
            memo: nil,
            status: .completed,
            mintUrl: "https://mint.example.com"
        )
        transaction.unit = "usd"
        var transactions = [transaction]

        service.mergeSentTokens(into: &transactions)

        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions[0].unit, "usd")
        XCTAssertEqual(transactions[0].status, .pending)
        XCTAssertTrue(transactions[0].isPendingToken)
        XCTAssertEqual(transactions[0].token, pending.token)
    }

    func testClaimedUSDTokenKeepsUnitWhenMerged() {
        let date = Date()
        let pending = PendingToken(
            tokenId: "usd-claimed",
            token: "claimed-usd-token",
            amount: 25,
            fee: 2,
            date: date,
            mintUrl: "https://mint.example.com",
            memo: nil,
            unit: "usd"
        )
        service.savePendingToken(pending)
        service.markTokenAsClaimed(token: pending.token)

        var transaction = WalletTransaction(
            id: "cdk-usd-claimed",
            amount: 25,
            type: .outgoing,
            kind: .ecash,
            date: date,
            memo: nil,
            status: .completed,
            mintUrl: "https://mint.example.com"
        )
        transaction.unit = "usd"
        var transactions = [transaction]

        service.mergeSentTokens(into: &transactions)

        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions[0].unit, "usd")
        XCTAssertEqual(transactions[0].status, .completed)
        XCTAssertEqual(transactions[0].token, pending.token)
    }

    func testMarkTokenAsClaimedNonexistentIsNoop() {
        service.savePendingToken(pendingToken(id: "d1", amount: 5))
        service.markTokenAsClaimed(token: "cashuAsome-other-token")
        XCTAssertEqual(service.pendingTokens.count, 1, "Unrelated pending token should remain")
    }

    // MARK: - Manual pending-token claim checks

    func testManualClaimCheckIsOnlyOfferedWhenAutomaticChecksAreDisabled() {
        let pending = pendingToken(id: "manual", amount: 42)

        XCTAssertTrue(
            shouldOfferManualClaimCheck(
                automaticChecksEnabled: false,
                pendingToken: pending
            )
        )
        XCTAssertFalse(
            shouldOfferManualClaimCheck(
                automaticChecksEnabled: true,
                pendingToken: pending
            )
        )
        XCTAssertFalse(
            shouldOfferManualClaimCheck(
                automaticChecksEnabled: false,
                pendingToken: nil
            )
        )
    }

    func testPendingSentTokenResolvesMergedHistoryRowByEncodedToken() {
        let pending = pendingToken(id: "local-pending-id", amount: 42)
        var mergedRow = transaction(
            id: "cdk-transaction-id",
            status: .pending,
            date: pending.date
        )
        mergedRow.isPendingToken = true
        mergedRow.token = pending.token

        let resolved = pendingSentTokenFor(
            transaction: mergedRow,
            pendingTokens: [pending]
        )

        XCTAssertEqual(resolved?.tokenId, pending.tokenId)
    }

    func testPendingSentTokenRejectsIncomingAndCompletedRows() {
        let pending = pendingToken(id: "local-pending-id", amount: 42)
        var incoming = transaction(
            id: pending.tokenId,
            status: .pending,
            date: pending.date,
            type: .incoming
        )
        incoming.isPendingToken = true
        incoming.token = pending.token

        var completed = transaction(
            id: pending.tokenId,
            status: .completed,
            date: pending.date
        )
        completed.isPendingToken = true
        completed.token = pending.token

        XCTAssertNil(
            pendingSentTokenFor(transaction: incoming, pendingTokens: [pending])
        )
        XCTAssertNil(
            pendingSentTokenFor(transaction: completed, pendingTokens: [pending])
        )
    }

    func testPendingTokenClaimCheckDistinguishesAllOutcomes() async throws {
        let claimed = try await runPendingTokenClaimCheck { true }
        guard case .claimed = claimed else {
            return XCTFail("Expected claimed result")
        }

        let notClaimed = try await runPendingTokenClaimCheck { false }
        guard case .notClaimed = notClaimed else {
            return XCTFail("Expected not-claimed result")
        }

        let failed = try await runPendingTokenClaimCheck {
            throw WalletError.networkError("network connection failed")
        }
        guard case .failed(let message) = failed else {
            return XCTFail("Expected failed result")
        }
        XCTAssertEqual(
            message.text,
            "Couldn't reach the mint. Check your connection and try again."
        )
        XCTAssertEqual(message.recoverability, .retryable)
    }

    func testPendingTokenClaimCheckPreservesCancellation() async {
        do {
            _ = try await runPendingTokenClaimCheck {
                throw CancellationError()
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: leaving the screen must cancel instead of showing an error.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    // MARK: - Pending Receive Tokens

    func testPendingReceiveTokensEmptyInitially() {
        XCTAssertTrue(service.pendingReceiveTokens.isEmpty)
    }

    func testSavePendingReceiveToken() {
        service.savePendingReceiveToken(receiveToken(id: "r1", amount: 50))
        XCTAssertEqual(service.pendingReceiveTokens.count, 1)
        XCTAssertEqual(service.pendingReceiveTokens[0].tokenId, "r1")
    }

    func testSavePendingReceiveTokenUpdatesExisting() {
        service.savePendingReceiveToken(receiveToken(id: "r1", amount: 10))
        service.savePendingReceiveToken(receiveToken(id: "r1", amount: 99))
        XCTAssertEqual(service.pendingReceiveTokens.count, 1)
        XCTAssertEqual(service.pendingReceiveTokens[0].amount, 99)
    }

    func testSavePendingReceiveTokenDeduplicatesSameEcash() {
        service.savePendingReceiveToken(receiveToken(id: "r1", token: "cashuAsame", amount: 10))
        service.savePendingReceiveToken(receiveToken(id: "r2", token: "cashuAsame", amount: 99))

        XCTAssertEqual(service.pendingReceiveTokens.count, 1)
        XCTAssertEqual(service.pendingReceiveTokens[0].tokenId, "r1")
        XCTAssertEqual(service.pendingReceiveTokens[0].amount, 99)
    }

    func testRemovePendingReceiveToken() {
        service.savePendingReceiveToken(receiveToken(id: "r1", amount: 10))
        service.savePendingReceiveToken(receiveToken(id: "r2", amount: 20))
        service.removePendingReceiveToken(tokenId: "r1")
        XCTAssertEqual(service.pendingReceiveTokens.count, 1)
        XCTAssertEqual(service.pendingReceiveTokens[0].tokenId, "r2")
    }

    // MARK: - clearState

    func testClearStateEmptiesAllCollections() {
        service.savePendingToken(pendingToken(id: "p", amount: 1))
        service.savePendingReceiveToken(receiveToken(id: "r", amount: 2))
        service.clearState()
        XCTAssertTrue(service.pendingTokens.isEmpty)
        XCTAssertTrue(service.pendingReceiveTokens.isEmpty)
        XCTAssertTrue(service.transactions.isEmpty)
    }

    func testWalletUnitsIncludeSatAndEveryAdvertisedUnit() {
        XCTAssertEqual(
            TransactionService.walletUnits(advertisedUnits: ["usd", "EUR", "points"]),
            ["sat", "usd", "EUR", "points"]
        )
    }

    func testWalletUnitsIgnoreEmptyAndCaseInsensitiveDuplicates() {
        XCTAssertEqual(
            TransactionService.walletUnits(advertisedUnits: [" SAT ", "usd", "USD", " "]),
            ["sat", "usd"]
        )
    }

    // MARK: - Unpaid / expired invoice display

    func testUnpaidInvoiceTitlesAsInvoiceUntilPaid() {
        var transaction = WalletTransaction(
            id: "quote",
            amount: 500,
            type: .incoming,
            kind: .lightning,
            date: Date(),
            memo: nil,
            status: .pending
        )
        transaction.isUnpaidInvoice = true

        XCTAssertEqual(transaction.displayTitle, "Lightning invoice")

        transaction.isUnpaidInvoice = false
        XCTAssertEqual(transaction.displayTitle, "Lightning received")
    }

    func testExpiredStatusDisplayAndQuietPending() {
        var transaction = WalletTransaction(
            id: "quote",
            amount: 500,
            type: .incoming,
            kind: .lightning,
            date: Date(),
            memo: nil,
            status: .expired
        )
        transaction.isUnpaidInvoice = true

        XCTAssertEqual(transaction.status.displayText, "Expired")
        XCTAssertEqual(transaction.displayStatusText, "Expired")
        XCTAssertEqual(transaction.displayTitle, "Lightning invoice")
        XCTAssertTrue(transaction.isUnsettled)
        XCTAssertFalse(WalletTransaction(
            id: "settled",
            amount: 500,
            type: .incoming,
            kind: .lightning,
            date: Date(),
            memo: nil,
            status: .completed
        ).isUnsettled)
    }

    // MARK: - Helpers

    private func transaction(
        id: String,
        status: WalletTransaction.TransactionStatus,
        date: Date,
        type: WalletTransaction.TransactionType = .outgoing
    ) -> WalletTransaction {
        WalletTransaction(
            id: id,
            amount: 1,
            type: type,
            kind: .ecash,
            date: date,
            memo: nil,
            status: status
        )
    }

    private func pendingToken(id: String, amount: UInt64) -> PendingToken {
        PendingToken(
            tokenId: id,
            token: "cashuAtoken\(id)",
            amount: amount,
            fee: 0,
            date: Date(),
            mintUrl: "https://mint.example.com",
            memo: nil,
            unit: "sat"
        )
    }

    private func receiveToken(id: String, token: String? = nil, amount: UInt64) -> PendingReceiveToken {
        PendingReceiveToken(
            tokenId: id,
            token: token ?? "cashuArecv\(id)",
            amount: amount,
            date: Date(),
            mintUrl: "https://mint.example.com"
        )
    }
}
