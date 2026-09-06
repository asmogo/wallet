import XCTest
@testable import CashuWallet

final class QRContextAccessibilityTests: XCTestCase {
    func testActionNamesMatchContextMenuEntries() {
        XCTAssertEqual(QRContextAccessibility.copyActionName, "Copy")
        XCTAssertEqual(QRContextAccessibility.shareActionName, "Share")
    }

    func testBaseQRViewPromisesNoActionsByDefault() {
        let qr = QRCodeView(content: "cashuAeyJwcm9vZnMiOlt7InByb29mIjoiIn1d")
        XCTAssertNil(qr.onCopy, "Non-actionable QR views must not promise a Copy action")
        XCTAssertNil(qr.onShare, "Non-actionable QR views must not promise a Share action")
    }

    func testActionableQRViewExposesCopyAndShareClosures() {
        var copied = false
        var shared = false
        let qr = QRCodeView(
            content: "lnbc1…",
            onCopy: { copied = true },
            onShare: { shared = true }
        )
        qr.onCopy?()
        qr.onShare?()
        XCTAssertTrue(copied)
        XCTAssertTrue(shared)
    }

    func testHistoryPaymentCodeAvailabilityAcrossDirectionsAndStates() {
        for kind in [WalletTransaction.TransactionKind.ecash, .lightning, .onchain] {
            for direction in [WalletTransaction.TransactionType.incoming, .outgoing] {
                for status in [WalletTransaction.TransactionStatus.pending, .completed, .failed, .expired] {
                    let transaction = WalletTransaction(
                        id: "receipt", amount: 21, type: direction, kind: kind, date: .now,
                        status: status, token: kind == .ecash ? "cashu-token" : nil,
                        invoice: kind == .ecash ? nil : "one-shot-request"
                    )
                    let expected = status == .pending &&
                        (kind == .ecash ? direction == .outgoing : direction == .incoming)
                    XCTAssertEqual(transaction.hasActionablePaymentCode, expected,
                                   "Unexpected QR availability for \(kind), \(direction), \(status)")
                }
            }
        }
    }

    func testReusableOfferStaysAvailableAfterPaymentButNeverOnOutgoingReceipt() {
        var transaction = WalletTransaction(
            id: "offer", amount: 21, type: .incoming, kind: .lightning, date: .now,
            status: .completed, invoice: "LNO1offer"
        )
        XCTAssertTrue(transaction.hasActionablePaymentCode)
        transaction.status = .failed
        XCTAssertFalse(transaction.hasActionablePaymentCode)
        let outgoing = WalletTransaction(
            id: "payment", amount: 21, type: .outgoing, kind: .lightning, date: .now,
            status: .pending, invoice: "lno1offer"
        )
        XCTAssertFalse(outgoing.hasActionablePaymentCode)
    }

}
