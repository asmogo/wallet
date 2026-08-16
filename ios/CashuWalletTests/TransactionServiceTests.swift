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

    func testTransactionIdLookupByTokenString() {
        XCTAssertNil(service.transactionId(forToken: "cashuAmissing"))
        service.saveToken(txId: "tx1", token: "cashuAtoken123")
        XCTAssertEqual(service.transactionId(forToken: "cashuAtoken123"), "tx1")
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

    // MARK: - Manual pending-send claim checks

    func testManualClaimCheckIsOnlyOfferedWhenAutomaticChecksAreDisabled() {
        var pending = transaction(id: "manual", status: .pending, date: Date())
        pending.token = "cashuAtokenmanual"
        pending.sagaId = "operation-id"

        XCTAssertTrue(
            shouldOfferManualClaimCheck(
                automaticChecksEnabled: false,
                transaction: pending
            )
        )
        XCTAssertFalse(
            shouldOfferManualClaimCheck(
                automaticChecksEnabled: true,
                transaction: pending
            )
        )

        let completed = transaction(id: "settled", status: .completed, date: Date())
        XCTAssertFalse(
            shouldOfferManualClaimCheck(
                automaticChecksEnabled: false,
                transaction: completed
            )
        )
    }

    func testIsPendingSentTokenMatchesOnlyUnclaimedOutgoingEcash() {
        var pending = transaction(id: "p", status: .pending, date: Date())
        pending.token = "cashuAtokenp"
        XCTAssertTrue(isPendingSentToken(pending))

        // Without the token string the row is not actionable (no QR/Copy).
        var tokenless = transaction(id: "t", status: .pending, date: Date())
        tokenless.sagaId = "operation-id"
        XCTAssertFalse(isPendingSentToken(tokenless))

        var incoming = transaction(id: "i", status: .pending, date: Date(), type: .incoming)
        incoming.token = "cashuAtokeni"
        XCTAssertFalse(isPendingSentToken(incoming))

        var claimed = transaction(id: "c", status: .completed, date: Date())
        claimed.token = "cashuAtokenc"
        XCTAssertFalse(isPendingSentToken(claimed))
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
        service.savePendingReceiveToken(receiveToken(id: "r", amount: 2))
        service.clearState()
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

    // MARK: - Detail lookup (quote-row → transaction-row follow)

    func testLiveDetailPrefersExactIdMatch() {
        let open = transaction(id: "quote-1", status: .pending, date: Date())
        let other = WalletTransaction(
            id: "cdk-9", amount: 1, type: .incoming, kind: .lightning,
            date: Date(), memo: nil, status: .completed
        )

        XCTAssertEqual([other, open].liveDetail(openId: "quote-1")?.id, "quote-1")
    }

    func testLiveDetailFallsBackToQuoteIdAfterMintSwap() {
        // The pending row's id was the quote id; after minting, only the CDK
        // transaction (saga-derived id, same quoteId) remains.
        var completed = transaction(id: "cdk-9", status: .completed, date: Date())
        completed.quoteId = "quote-1"
        let unrelated = transaction(id: "other", status: .completed, date: Date())

        let resolved = [unrelated, completed].liveDetail(openId: "quote-1", openQuoteId: "quote-1")

        XCTAssertEqual(resolved?.id, "cdk-9")
    }

    func testLiveDetailResolvesReusableOfferToNewestPayment() {
        // Rows are stored newest-first; several payments share one offer's
        // quoteId, so the fallback yields the latest one.
        var newer = transaction(id: "cdk-2", status: .completed, date: Date())
        newer.quoteId = "offer"
        var older = transaction(id: "cdk-1", status: .completed, date: Date(timeIntervalSince1970: 100))
        older.quoteId = "offer"

        XCTAssertEqual(
            [newer, older].liveDetail(openId: "offer", openQuoteId: "offer")?.id,
            "cdk-2"
        )
    }

    func testLiveDetailReturnsNilWhenNothingMatches() {
        XCTAssertNil(
            [transaction(id: "a", status: .completed, date: Date())]
                .liveDetail(openId: "missing", openQuoteId: "also-missing")
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
