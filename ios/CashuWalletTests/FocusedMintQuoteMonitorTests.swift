import XCTest
@testable import CashuWallet

@MainActor
final class FocusedMintQuoteMonitorTests: XCTestCase {
    func testDetailMonitoringIncludesSettledOffersButExcludesPaidInvoicesAndOutgoingPayments() {
        func transaction(
            status: WalletTransaction.TransactionStatus,
            invoice: String,
            type: WalletTransaction.TransactionType = .incoming
        ) -> WalletTransaction {
            WalletTransaction(
                id: "payment", amount: 21, type: type, kind: .lightning, date: Date(),
                status: status, invoice: invoice, quoteId: "quote"
            )
        }
        XCTAssertEqual(transaction(status: .pending, invoice: "lnbc1").mintQuoteIdForStatusRefresh, "quote")
        XCTAssertEqual(transaction(status: .expired, invoice: "lnbc1").mintQuoteIdForStatusRefresh, "quote")
        XCTAssertEqual(transaction(status: .completed, invoice: "LNO1").mintQuoteIdForStatusRefresh, "quote")
        XCTAssertNil(transaction(status: .completed, invoice: "lnbc1").mintQuoteIdForStatusRefresh)
        XCTAssertNil(transaction(status: .pending, invoice: "lno1", type: .outgoing).mintQuoteIdForStatusRefresh)
    }

    func testChecksOnlyDisplayedInvoiceImmediatelyAndStopsAfterIssuance() async {
        let monitor = FocusedMintQuoteMonitor()
        var ids: [String] = []
        var intervals: [Duration] = []
        await monitor.monitor(quoteID: "displayed", refresh: { id in
            XCTAssertTrue(monitor.isActive)
            ids.append(id)
            return self.quote(method: .bolt11, paid: 21, issued: ids.count == 1 ? 0 : 21)
        }, sleep: { interval in
            intervals.append(interval)
        })

        XCTAssertEqual(ids, ["displayed", "displayed"])
        XCTAssertEqual(intervals, [.seconds(2)])
        XCTAssertFalse(monitor.isActive)
    }

    func testPreviouslyPaidReusableOfferKeepsCheckingForLaterPayments() async {
        let monitor = FocusedMintQuoteMonitor()
        var checks = 0
        var intervals: [Duration] = []
        await monitor.monitor(quoteID: "displayed", refresh: { _ in
            checks += 1
            // An issued BOLT12 counter is a baseline, never a terminal state.
            return self.quote(method: .bolt12, paid: checks == 1 ? 10 : 31,
                              issued: checks == 1 ? 10 : 31)
        }, sleep: { interval in
            intervals.append(interval)
            if intervals.count == 2 { throw CancellationError() }
        })

        XCTAssertEqual(checks, 2)
        XCTAssertEqual(intervals, [.seconds(2), .seconds(2)])
        XCTAssertFalse(monitor.isActive)
    }

    func testCancellationReleasesFocusAndReopeningChecksImmediately() async {
        let monitor = FocusedMintQuoteMonitor()
        let sleeping = expectation(description: "Waiting between checks")
        var ids: [String] = []
        let task = Task {
            await monitor.monitor(quoteID: "first", refresh: { id in
                ids.append(id)
                return nil // Missing/temporarily unavailable quote keeps retrying.
            }, sleep: { _ in
                sleeping.fulfill()
                try await Task.sleep(for: .seconds(60))
            })
        }
        await fulfillment(of: [sleeping], timeout: 2)
        XCTAssertTrue(monitor.isActive)
        task.cancel()
        await task.value
        XCTAssertFalse(monitor.isActive)

        await monitor.monitor(quoteID: "second", refresh: { id in
            ids.append(id)
            return self.quote(method: .bolt11, paid: 21, issued: 21)
        }, sleep: { _ in XCTFail("Settled invoice must stop") })
        XCTAssertEqual(ids, ["first", "second"])
        XCTAssertFalse(monitor.isActive)
    }

    func testExpiredUnpaidInvoiceStopsButPaidUnissuedInvoiceKeepsRetrying() async {
        let monitor = FocusedMintQuoteMonitor()
        await monitor.monitor(quoteID: "displayed", refresh: { _ in
            self.quote(method: .bolt11, expiry: 1)
        }, sleep: { _ in XCTFail("Expired unpaid invoice must stop") })

        var checks = 0
        await monitor.monitor(quoteID: "displayed", refresh: { _ in
            checks += 1
            return self.quote(method: .bolt11, paid: 21, issued: checks == 1 ? 0 : 21, expiry: 1)
        }, sleep: { _ in })
        XCTAssertEqual(checks, 2)
    }

    func testOnchainDepositKeepsCheckingAfterExpiry() async {
        let monitor = FocusedMintQuoteMonitor()
        var checks = 0
        await monitor.monitor(quoteID: "displayed", refresh: { _ in
            checks += 1
            return self.quote(method: .onchain, paid: checks == 1 ? 0 : 21,
                              issued: checks == 1 ? 0 : 21, expiry: 1)
        }, sleep: { interval in XCTAssertEqual(interval, .seconds(10)) })
        XCTAssertEqual(checks, 2)
        XCTAssertFalse(monitor.isActive)
    }

    private func quote(
        method: PaymentMethodKind, paid: UInt64 = 0, issued: UInt64 = 0, expiry: UInt64? = nil
    ) -> MintQuoteInfo {
        MintQuoteInfo(
            id: "displayed", request: "request", amount: nil, isAmountless: true,
            paymentMethod: method, state: paid > issued ? .paid : paid > 0 ? .issued : .pending,
            expiry: expiry, createdAt: nil, amountPaid: paid, amountIssued: issued
        )
    }
}
