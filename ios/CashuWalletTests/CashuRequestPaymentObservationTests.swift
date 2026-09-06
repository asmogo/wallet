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

    func testSameRequestReceivesAgainAfterAcknowledgingFirstPayment() throws {
        let request = store.createNew(id: "reusable-request", encoded: "creqAreusable")
        var observation = CashuRequestPaymentObservation(existingPayments: [])
        for id in ["first", "second"] {
            store.attachPayment(requestId: request.id, transactionId: id, amount: 21)
            let current = try XCTUnwrap(store.request(withId: request.id))
            XCTAssertEqual(current.encoded, request.encoded)
            XCTAssertEqual(observation.newlyLinkedPayment(in: current.receivedPayments)?.transactionId, id)
            XCTAssertNil(observation.newlyLinkedPayment(in: current.receivedPayments))
        }
    }

    func testPaymentArrivingDuringReceiptRemainsAvailableAfterDone() {
        var observation = CashuRequestPaymentObservation(existingPayments: [])
        let first = CashuRequestPayment(transactionId: "first", amount: 21, receivedAt: Date())
        let second = CashuRequestPayment(transactionId: "second", amount: 34, receivedAt: Date())
        XCTAssertEqual(observation.newlyLinkedPayment(in: [first]), first)
        // The screen pauses observation while showing the first receipt.
        XCTAssertEqual(observation.newlyLinkedPayment(in: [first, second]), second)
        XCTAssertNil(observation.newlyLinkedPayment(in: [first, second]))
    }
}

final class ReusableMintPaymentObservationTests: XCTestCase {
    func testSuccessUsesEachPaymentDeltaAcrossRepeatedQRPresentations() {
        var observation = ReusableMintPaymentObservation()
        observation.startObserving(quoteID: "offer", amountIssued: 0)
        XCTAssertNil(observation.newlyIssuedAmount(0))
        XCTAssertEqual(observation.newlyIssuedAmount(21), 21)
        observation.startObserving(quoteID: "offer", amountIssued: 21)
        XCTAssertNil(observation.newlyIssuedAmount(21))
        XCTAssertEqual(observation.newlyIssuedAmount(42), 21)
        observation.startObserving(quoteID: "offer", amountIssued: 42)
        XCTAssertEqual(observation.newlyIssuedAmount(76), 34)
    }

    func testSavedOfferAndStaleSnapshotsDoNotReplaySuccess() {
        var observation = ReusableMintPaymentObservation()
        observation.startObserving(quoteID: "saved-offer", amountIssued: 100)
        XCTAssertNil(observation.newlyIssuedAmount(100))
        XCTAssertNil(observation.newlyIssuedAmount(0))
        XCTAssertEqual(observation.newlyIssuedAmount(121), 21)
        XCTAssertNil(observation.newlyIssuedAmount(100))
        XCTAssertNil(observation.newlyIssuedAmount(121))
    }

    func testPaymentIssuedWhileReceiptIsOpenIsNotAbsorbedIntoBaseline() {
        var observation = ReusableMintPaymentObservation()
        observation.startObserving(quoteID: "offer", amountIssued: 0)
        XCTAssertEqual(observation.newlyIssuedAmount(21), 21)
        observation.startObserving(quoteID: "offer", amountIssued: 55)
        XCTAssertEqual(observation.newlyIssuedAmount(55), 34)
    }

    func testSwitchingOfferEstablishesItsOwnBaseline() {
        var observation = ReusableMintPaymentObservation()
        observation.startObserving(quoteID: "first-offer", amountIssued: 100)
        observation.startObserving(quoteID: "second-offer", amountIssued: 7)
        XCTAssertNil(observation.newlyIssuedAmount(7))
        XCTAssertEqual(observation.newlyIssuedAmount(28), 21)
    }
}
