import XCTest
@testable import CashuWallet

@MainActor
final class CashuRequestPaymentObservationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: CashuRequestStore!

    override func setUp() {
        super.setUp()
        suiteName = "CashuRequestPaymentObservationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = CashuRequestStore(userDefaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testUnrelatedConcurrentBalanceIncreaseDoesNotProduceRequestSuccess() throws {
        let watchedRequest = store.createNew(id: "watched-request", encoded: "creqAwatched")
        _ = store.createNew(id: "unrelated-request", encoded: "creqAunrelated")
        var observation = CashuRequestPaymentObservation(
            existingPayments: watchedRequest.receivedPayments
        )
        var walletBalance: UInt64 = 100

        store.attachPayment(
            requestId: "unrelated-request",
            transactionId: "unrelated-payment",
            amount: 25
        )
        walletBalance += 25

        XCTAssertEqual(walletBalance, 125)
        let watchedPayments = try XCTUnwrap(
            store.request(withId: "watched-request")?.receivedPayments
        )
        XCTAssertNil(observation.newlyLinkedPayment(in: watchedPayments))
    }

    func testNewlyLinkedRequestPaymentProducesRequestSuccess() throws {
        let request = store.createNew(id: "watched-request", encoded: "creqAwatched")
        var observation = CashuRequestPaymentObservation(
            existingPayments: request.receivedPayments
        )
        store.attachPayment(
            requestId: request.id,
            transactionId: "request-payment",
            amount: 21
        )
        let linkedPayments = try XCTUnwrap(
            store.request(withId: request.id)?.receivedPayments
        )
        let payment = try XCTUnwrap(linkedPayments.first)

        XCTAssertEqual(
            observation.newlyLinkedPayment(in: linkedPayments),
            payment
        )
        XCTAssertNil(observation.newlyLinkedPayment(in: linkedPayments))
    }

    func testExistingRequestPaymentsEstablishBaselineWithoutReplayingSuccess() {
        let existing = CashuRequestPayment(
            transactionId: "existing-payment",
            amount: 13,
            receivedAt: Date()
        )
        var observation = CashuRequestPaymentObservation(existingPayments: [existing])

        XCTAssertNil(observation.newlyLinkedPayment(in: [existing]))
    }
}
