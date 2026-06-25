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

    func testMarkTokenAsClaimedNonexistentIsNoop() {
        service.savePendingToken(pendingToken(id: "d1", amount: 5))
        service.markTokenAsClaimed(token: "cashuAsome-other-token")
        XCTAssertEqual(service.pendingTokens.count, 1, "Unrelated pending token should remain")
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

    // MARK: - Helpers

    private func pendingToken(id: String, amount: UInt64) -> PendingToken {
        PendingToken(
            tokenId: id,
            token: "cashuAtoken\(id)",
            amount: amount,
            fee: 0,
            date: Date(),
            mintUrl: "https://mint.example.com",
            memo: nil
        )
    }

    private func receiveToken(id: String, amount: UInt64) -> PendingReceiveToken {
        PendingReceiveToken(
            tokenId: id,
            token: "cashuArecv\(id)",
            amount: amount,
            date: Date(),
            mintUrl: "https://mint.example.com"
        )
    }
}
