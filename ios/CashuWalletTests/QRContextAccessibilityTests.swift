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
}
