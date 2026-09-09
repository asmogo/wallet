import Cdk
import XCTest
@testable import CashuWallet

final class NFCReceiveTests: XCTestCase {
    private let selectApplication: [UInt8] = [0, 0xA4, 4, 0, 7] + NFCType4Tag.aid + [0]
    private let selectNdef: [UInt8] = [0, 0xA4, 0, 0x0C, 2, 0xE1, 4]
    private let ok = Data([0x90, 0])

    private func selectedTag() throws -> NFCType4Tag {
        var tag = try NFCType4Tag(request: "creqAtest")
        XCTAssertEqual(tag.process(Data(selectApplication)).response, ok)
        XCTAssertEqual(tag.process(Data(selectNdef)).response, ok)
        return tag
    }

    private func update(_ offset: Int, _ bytes: [UInt8]) -> Data {
        Data([0, 0xD6, UInt8(offset >> 8), UInt8(offset & 255), UInt8(bytes.count)] + bytes)
    }

    func testAndroidCompatibleCapabilityContainerAndRequest() throws {
        var tag = try selectedTag()
        XCTAssertEqual(tag.process(Data([0, 0xB0, 0, 0, 0])).response,
                       Data(try NFCNdefCodec.textFile("creqAtest")) + ok)
        XCTAssertEqual(tag.process(Data([0, 0xA4, 0, 0x0C, 2, 0xE1, 3])).response, ok)
        XCTAssertEqual(tag.process(Data([0, 0xB0, 0, 0, 15])).response,
                       Data(NFCType4Tag.capabilityContainer) + ok)
        XCTAssertNotEqual(tag.process(update(0, [0, 1, 2])).response, ok)
    }

    func testShortAndLongUTF8TextRoundTrip() throws {
        for text in ["cashuBtoken", String(repeating: "é", count: 500)] {
            XCTAssertEqual(NFCNdefCodec.parseFile(try NFCNdefCodec.textFile(text)), .text(text))
        }
        XCTAssertThrowsError(try NFCNdefCodec.textFile(String(repeating: "a", count: 30_000)))
    }

    func testNlenFirstRequiresEveryByteIncludingHoles() throws {
        var tag = try selectedTag()
        let file = try NFCNdefCodec.textFile("cashuBtest")
        XCTAssertNil(tag.process(update(0, Array(file[0..<2]))).payload)
        XCTAssertNil(tag.process(update(8, Array(file[8...]))).payload)
        XCTAssertNil(tag.process(update(2, Array(file[2..<7]))).payload)
        XCTAssertEqual(tag.process(update(7, [file[7]])).payload, .text("cashuBtest"))
        XCTAssertNil(tag.process(update(7, [file[7]])).payload)
    }

    func testNlenLastAndOutOfOrderChunks() throws {
        var tag = try selectedTag()
        let file = try NFCNdefCodec.textFile("cashuBtest")
        XCTAssertNil(tag.process(update(0, [0, 0])).payload)
        XCTAssertNil(tag.process(update(8, Array(file[8...]))).payload)
        XCTAssertNil(tag.process(update(2, Array(file[2..<8]))).payload)
        XCTAssertEqual(tag.process(update(0, Array(file[0..<2]))).payload, .text("cashuBtest"))
    }

    func testDisconnectAndReselectDiscardPartialWrites() throws {
        for disconnect in [true, false] {
            var tag = try selectedTag()
            let file = try NFCNdefCodec.textFile("cashuBtest")
            _ = tag.process(update(0, Array(file[0..<8])))
            if disconnect { tag.reset() }
            _ = tag.process(Data(selectApplication))
            _ = tag.process(Data(selectNdef))
            XCTAssertNil(tag.process(update(8, Array(file[8...]))).payload)
            XCTAssertNil(tag.process(update(0, Array(file[0..<2]))).payload)
        }
    }

    func testZeroNlenDiscardsPreviousBody() throws {
        var tag = try selectedTag()
        let file = try NFCNdefCodec.textFile("cashuBtest")
        _ = tag.process(update(2, Array(file.dropFirst(2))))
        _ = tag.process(update(0, [0, 0]))
        XCTAssertNil(tag.process(update(0, Array(file.prefix(2)))).payload)
    }

    func testMalformedApdusAndBounds() throws {
        var tag = try selectedTag()
        for bytes: [UInt8] in [[], [0], [0, 0xB0], [0, 0xB0, 0, 0],
                               [0, 0xD6, 0, 0, 2, 1], [0, 0xD6, 0xFF, 0xFF, 1, 0],
                               [0, 0xB0, 0xFF, 0xFF, 1], [0x80, 0xB0, 0, 0, 1]] {
            XCTAssertNotEqual(tag.process(Data(bytes)).response, ok)
        }
        XCTAssertNotEqual(tag.process(update(0, [0xFF, 0xFF])).response, ok)
    }

    func testApplicationSelectionRequiredAndUnknownFileClearsSelection() throws {
        var tag = try NFCType4Tag(request: "creqAtest")
        XCTAssertNotEqual(tag.process(Data(selectNdef)).response, ok)
        _ = tag.process(Data(selectApplication))
        _ = tag.process(Data(selectNdef))
        _ = tag.process(Data([0, 0xA4, 0, 0x0C, 2, 0xE1, 9]))
        XCTAssertNotEqual(tag.process(update(0, [0, 0])).response, ok)
    }

    func testRejectsTruncationChunkingIdsAndTrailingBytes() throws {
        let valid = try NFCNdefCodec.textFile("cashuBtest")
        for count in 0..<valid.count {
            XCTAssertNil(NFCNdefCodec.parseFile(Array(valid.prefix(count))))
        }
        for header: UInt8 in [0x91, 0x51, 0xF1, 0xD9] {
            var invalid = valid
            invalid[2] = header
            XCTAssertNil(NFCNdefCodec.parseFile(invalid))
        }
        XCTAssertNil(NFCNdefCodec.parseFile(valid + [0]))
        // Huge long-record payload length must not allocate or index out of bounds.
        XCTAssertNil(NFCNdefCodec.parseFile([0, 7, 0xC1, 1, 0xFF, 0xFF, 0xFF, 0xFF, 0x54]))
    }

    func testBinaryMimeAndUriRecords() {
        let mime = Array("application/octet-stream".utf8)
        let record: [UInt8] = [0xD2, UInt8(mime.count), 3] + mime + [0, 1, 2]
        XCTAssertEqual(NFCNdefCodec.parseFile([0, UInt8(record.count)] + record), .cashuBinary(Data([0, 1, 2])))
        let uri: [UInt8] = [0xD1, 1, 7, 0x55, 0] + Array("cashuB".utf8)
        XCTAssertEqual(NFCNdefCodec.parseFile([0, UInt8(uri.count)] + uri), .text("cashuB"))
    }

    func testMalformedTextAndUnsupportedUriAreRejected() {
        for payload: [UInt8] in [[0x80], [0x40], [5, 0x65], [0, 0xFF]] {
            let record: [UInt8] = [0xD1, 1, UInt8(payload.count), 0x54] + payload
            XCTAssertNil(NFCNdefCodec.parseFile([0, UInt8(record.count)] + record))
        }
        XCTAssertNil(NFCNdefCodec.parseFile([0, 5, 0xD1, 1, 1, 0x55, 0xFF]))
    }

    func testTransportFreeRequestPreservesTerms() throws {
        let request = CashuRequest(id: "nfc", encoded: "unused", amount: 21, unit: "usd",
                                   mints: ["https://mint.example"], memo: "Coffee", reusable: false)
        let decoded = try decodePaymentRequest(encoded: PaymentRequestBuilder.buildNFC(request: request))
        XCTAssertEqual(decoded.paymentId(), "nfc")
        XCTAssertEqual(decoded.amount()?.value, 21)
        XCTAssertEqual(decoded.unit(), .usd)
        XCTAssertEqual(decoded.mints(), ["https://mint.example"])
        XCTAssertTrue(decoded.transports().isEmpty)
    }

    func testRequestValidationAndAvailability() {
        let request = CashuRequest(encoded: "unused", amount: 21, mints: ["https://mint.example/"])
        XCTAssertTrue(NFCReceivePayment.canPresent(request))
        XCTAssertNil(NFCReceivePayment.validationMessage(request: request, amount: 22, unit: "SAT", mint: "https://MINT.example"))
        XCTAssertNotNil(NFCReceivePayment.validationMessage(request: request, amount: 20, unit: "sat", mint: "https://mint.example"))
        XCTAssertNotNil(NFCReceivePayment.validationMessage(request: request, amount: 21, unit: "usd", mint: "https://mint.example"))
        XCTAssertNotNil(NFCReceivePayment.validationMessage(request: request, amount: 21, unit: "sat", mint: "https://other.example"))
        XCTAssertFalse(NFCReceivePayment.canPresent(CashuRequest(encoded: "unused")))
        XCTAssertFalse(NFCReceivePayment.canPresent(CashuRequest(encoded: "unused", amount: 21, expiry: .distantPast)))
        let paid = [CashuRequestPayment(transactionId: "tx", amount: 21, receivedAt: Date())]
        XCTAssertFalse(NFCReceivePayment.canPresent(CashuRequest(encoded: "unused", amount: 21, receivedPayments: paid, rail: .bolt11)))
        XCTAssertTrue(NFCReceivePayment.canPresent(CashuRequest(encoded: "unused", amount: 21, receivedPayments: paid)))
    }
}

@MainActor
final class NFCReceiveLifecycleTests: XCTestCase {
    private final class Transport: NFCReceiveTransport {
        var gate: CheckedContinuation<Void, Never>?
        var stopped = false
        var payload: NFCNdefPayload? = .text("token")

        func receive(request: String, accept: (NFCNdefPayload) throws -> NFCReceivePayment) async throws -> NFCReceivePayment? {
            await withCheckedContinuation { gate = $0 }
            guard let payload else { return nil }
            return try accept(payload)
        }

        func stop() { stopped = true }
        func deliver() { gate?.resume(); gate = nil }
    }

    private let request = CashuRequest(encoded: "unused", amount: 21)
    private func payment(review: Bool = false, validation: String? = nil) -> NFCReceivePayment {
        NFCReceivePayment(pending: PendingReceiveToken(
            tokenId: "receipt", token: "token", amount: 21, date: Date(), mintUrl: "https://mint.example"
        ), needsReview: review, validationMessage: validation)
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func testCancelledInitializationCannotAcceptOrClearReplacement() async {
        let old = Transport(), next = Transport()
        var transports = [old, next]
        let coordinator = NFCReceiveCoordinator { transports.removeFirst() }
        var staged = 0
        coordinator.start(request: request, stage: { _ in staged += 1; return self.payment() }, claim: { _ in 21 }, refresh: {})
        await settle()
        coordinator.stop()
        coordinator.start(request: request, stage: { _ in staged += 1; return self.payment() }, claim: { _ in 21 }, refresh: {})
        await settle()
        old.deliver()
        await settle()
        XCTAssertTrue(old.stopped)
        XCTAssertEqual(staged, 0)
        XCTAssertEqual(coordinator.phase, .presenting)
        next.deliver()
        await settle()
        XCTAssertEqual(staged, 1)
        XCTAssertEqual(coordinator.receivedAmount, 21)
    }

    func testAcceptedClaimSurvivesStopAndBlocksAnotherTap() async {
        let transport = Transport()
        let coordinator = NFCReceiveCoordinator { transport }
        var claimGate: CheckedContinuation<Void, Never>?
        var claims = 0
        coordinator.start(request: request, stage: { _ in self.payment() }, claim: { _ in
            claims += 1
            await withCheckedContinuation { claimGate = $0 }
            XCTAssertFalse(Task.isCancelled)
            return 20
        }, refresh: {})
        await settle()
        transport.deliver()
        await settle()
        XCTAssertEqual(coordinator.phase, .redeeming)
        coordinator.stop()
        coordinator.start(request: request, stage: { _ in XCTFail("Duplicate tap"); return self.payment() }, claim: { _ in 0 }, refresh: {})
        claimGate?.resume()
        await settle()
        XCTAssertEqual(claims, 1)
        XCTAssertEqual(coordinator.receivedAmount, 20)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testUnknownMintRequiresReviewWithoutClaim() async {
        let transport = Transport()
        let coordinator = NFCReceiveCoordinator { transport }
        coordinator.start(request: request, stage: { _ in self.payment(review: true) }, claim: { _ in
            XCTFail("Unknown mint must be reviewed")
            return 0
        }, refresh: {})
        await settle()
        transport.deliver()
        await settle()
        XCTAssertNotNil(coordinator.reviewPayment)
        XCTAssertNil(coordinator.receivedAmount)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testMismatchIsVisibleAndDoesNotShowPaymentSuccess() async {
        let transport = Transport()
        let coordinator = NFCReceiveCoordinator { transport }
        coordinator.start(request: request, stage: { _ in self.payment(review: true, validation: "Wrong amount.") }, claim: { _ in
            XCTFail("Mismatched payment must not fulfill request")
            return 0
        }, refresh: {})
        await settle()
        transport.deliver()
        await settle()
        XCTAssertNil(coordinator.reviewPayment)
        XCTAssertNil(coordinator.receivedAmount)
        XCTAssertTrue(coordinator.message?.contains("Wrong amount.") == true)
    }

    func testClaimFailureKeepsRecoveryReceipt() async {
        let transport = Transport()
        let coordinator = NFCReceiveCoordinator { transport }
        coordinator.start(request: request, stage: { _ in self.payment() }, claim: { _ in
            throw NFCReceiveError.message("Offline")
        }, refresh: {})
        await settle()
        transport.deliver()
        await settle()
        XCTAssertEqual(coordinator.reviewPayment?.tokenId, "receipt")
        XCTAssertNil(coordinator.receivedAmount)
        XCTAssertEqual(coordinator.phase, .idle)
    }

    func testPersistenceFailureDoesNotClaim() async {
        let transport = Transport()
        let coordinator = NFCReceiveCoordinator { transport }
        coordinator.start(request: request, stage: { _ in throw NFCReceiveError.message("Storage failed") }, claim: { _ in
            XCTFail("Unretained payment must not be claimed")
            return 0
        }, refresh: {})
        await settle()
        transport.deliver()
        await settle()
        XCTAssertNil(coordinator.receivedAmount)
        XCTAssertNotNil(coordinator.message)
        XCTAssertEqual(coordinator.phase, .idle)
    }
}
