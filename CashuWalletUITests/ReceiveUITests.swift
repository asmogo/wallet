import XCTest

/// UI tests for the Receive flow options sheet.
final class ReceiveUITests: UITestBase {

    // MARK: - Tests

    func testReceiveOptionsAppear() throws {
        createWalletAndSkipMint()

        let receiveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Receive'")).firstMatch
        XCTAssertTrue(receiveButton.waitForExistence(timeout: 10), "Receive button should be visible on wallet tab")
        receiveButton.tap()

        let pasteOption = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Paste Ecash Token'")).firstMatch
        let scanOption = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Scan QR Code'")).firstMatch
        let paymentRequestOption = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Payment Request'")).firstMatch

        XCTAssertTrue(pasteOption.waitForExistence(timeout: 10), "Paste Ecash Token option should appear")
        XCTAssertTrue(scanOption.exists, "Scan QR Code option should appear")
        XCTAssertTrue(paymentRequestOption.exists, "Payment Request option should appear")
    }

    func testReceiveSheetCanBeDismissed() throws {
        createWalletAndSkipMint()

        let receiveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Receive'")).firstMatch
        XCTAssertTrue(receiveButton.waitForExistence(timeout: 10))
        receiveButton.tap()

        let pasteOption = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Paste Ecash Token'")).firstMatch
        XCTAssertTrue(pasteOption.waitForExistence(timeout: 10))

        app.swipeDown()

        XCTAssertTrue(app.tabBars.buttons["Wallet"].waitForExistence(timeout: 5))
    }

    func testPaymentRequestOptionOpensLightningFlow() throws {
        createWalletWithMint()

        let receiveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Receive'")).firstMatch
        XCTAssertTrue(receiveButton.waitForExistence(timeout: 10))
        receiveButton.tap()

        let paymentRequestOption = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Payment Request'")).firstMatch
        XCTAssertTrue(paymentRequestOption.waitForExistence(timeout: 10))
        paymentRequestOption.tap()

        let lightningContent = app.otherElements.matching(NSPredicate(format: "label CONTAINS 'Receive method'")).firstMatch
        XCTAssertTrue(lightningContent.waitForExistence(timeout: 10), "Lightning receive view should open")
    }
}
