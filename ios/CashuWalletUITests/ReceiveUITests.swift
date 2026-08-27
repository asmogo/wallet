import XCTest

/// UI tests for the unified Receive sheet.
final class ReceiveUITests: UITestBase {
    override var launchMode: LaunchMode { .seededWalletWithMint }

    // MARK: - Helpers

    private var receiveButton: XCUIElement {
        app.buttons["wallet-action-receive"]
    }

    private var receiveEcashOption: XCUIElement {
        app.buttons["wallet-flow-receiveEcash"]
    }

    private var receiveBitcoinOption: XCUIElement {
        app.buttons["wallet-flow-receiveLightning"]
    }

    private var receiveDestinationField: XCUIElement {
        app.textFields["Paste a Cashu token"]
    }

    private func openReceiveSheet() {
        tapWhenReady(
            receiveButton,
            timeout: 10,
            message: "Receive button should be visible on wallet tab"
        )

        XCTAssertTrue(
            receiveEcashOption.waitForExistence(timeout: 10),
            "Receive sheet should show the Ecash option"
        )
    }

    // MARK: - Tests

    func testReceiveSheetCanBeDismissed() throws {
        waitForMainTab()

        openReceiveSheet()
        XCTAssertTrue(
            receiveBitcoinOption.waitForExistence(timeout: 5),
            "Receive sheet should show the Bitcoin option"
        )

        let dismissTarget = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        receiveEcashOption.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: dismissTarget)

        XCTAssertTrue(
            receiveDestinationField.waitForNonExistence(timeout: 5),
            "Receive sheet should dismiss after dragging down"
        )
    }

    func testBitcoinOptionOpensLightningFlow() throws {
        waitForMainTab()

        openReceiveSheet()

        XCTAssertTrue(
            receiveBitcoinOption.waitForExistence(timeout: 10),
            "Receive sheet should show the Bitcoin option"
        )
        tapWhenReady(receiveBitcoinOption)

        XCTAssertTrue(
            screen("receive-lightning-screen").waitForExistence(timeout: 10),
            "Lightning receive view should open"
        )
    }
}
