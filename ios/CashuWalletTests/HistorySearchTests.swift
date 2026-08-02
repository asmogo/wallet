import XCTest
@testable import CashuWallet

final class HistorySearchTests: XCTestCase {

    private func makeTransaction(
        amount: UInt64 = 210,
        memo: String? = nil
    ) -> WalletTransaction {
        WalletTransaction(
            id: "tx-1",
            amount: amount,
            type: .incoming,
            kind: .ecash,
            date: Date(),
            memo: memo,
            status: .completed
        )
    }

    private func makeRequest(
        amount: UInt64? = 500,
        memo: String? = nil
    ) -> CashuRequest {
        CashuRequest(
            encoded: "creqAtest",
            amount: amount,
            memo: memo
        )
    }

    func testTransactionMatchesMemoCaseInsensitively() {
        let tx = makeTransaction(memo: "Coffee with Alice")
        XCTAssertTrue(HistorySearch.matches(query: "coffee", transaction: tx))
        XCTAssertTrue(HistorySearch.matches(query: "ALICE", transaction: tx))
        XCTAssertTrue(HistorySearch.matches(query: "  With Alice  ", transaction: tx))
    }

    func testTransactionWithoutMemoDoesNotMatchMemoQuery() {
        let tx = makeTransaction(memo: nil)
        XCTAssertFalse(HistorySearch.matches(query: "coffee", transaction: tx))
    }

    func testTransactionStillMatchesTitleAndAmount() {
        let tx = makeTransaction(amount: 210, memo: nil)
        XCTAssertTrue(HistorySearch.matches(query: "ecash", transaction: tx))
        XCTAssertTrue(HistorySearch.matches(query: "21", transaction: tx))
    }

    func testRequestMatchesMemoCaseInsensitively() {
        let req = makeRequest(memo: "Dinner split Friday")
        XCTAssertTrue(HistorySearch.matches(query: "dinner", request: req, receivedTotal: 0))
        XCTAssertTrue(HistorySearch.matches(query: "FRIDAY", request: req, receivedTotal: 0))
    }

    func testRequestWithoutMemoDoesNotMatchMemoQuery() {
        let req = makeRequest(memo: nil)
        XCTAssertFalse(HistorySearch.matches(query: "dinner", request: req, receivedTotal: 0))
    }

    func testRequestStillMatchesTitleAndAmounts() {
        let req = makeRequest(amount: 500, memo: nil)
        XCTAssertTrue(HistorySearch.matches(query: "cashu", request: req, receivedTotal: 0))
        XCTAssertTrue(HistorySearch.matches(query: "50", request: req, receivedTotal: 0))
        XCTAssertTrue(HistorySearch.matches(query: "42", request: req, receivedTotal: 420))
    }

    func testBlankQueryMatchesEverything() {
        let tx = makeTransaction(memo: nil)
        let req = makeRequest(amount: nil, memo: nil)
        XCTAssertTrue(HistorySearch.matches(query: "", transaction: tx))
        XCTAssertTrue(HistorySearch.matches(query: "   ", transaction: tx))
        XCTAssertTrue(HistorySearch.matches(query: "", request: req, receivedTotal: 0))
        XCTAssertTrue(HistorySearch.matches(query: "   ", request: req, receivedTotal: 0))
    }
}
