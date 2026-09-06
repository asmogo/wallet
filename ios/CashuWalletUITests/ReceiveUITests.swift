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

/// Explicitly enabled live-mint UI coverage. Creates no payments and uses a fresh wallet.
final class LiveBolt12DescriptionUITests: UITestBase {
    override func setUpWithError() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["BOLT12_DESCRIPTION_MINT_URL"] == nil,
                      "Opt-in live mint quote test")
        try super.setUpWithError()
    }

    func testEditClearAndReopenLiveOffer() throws {
        let url = try XCTUnwrap(ProcessInfo.processInfo.environment["BOLT12_DESCRIPTION_MINT_URL"])
        createWalletWithMint(at: url)
        openOffer()
        editDescription("Coffee tips\nThank you")
        assertDescription("Coffee tips Thank you")
        tapWhenReady(app.buttons["Close"])
        openOffer()
        assertDescription("Coffee tips Thank you")
        editDescription("Updated coffee note")
        assertDescription("Updated coffee note")
        editDescription("   ")
        assertDescription("None")
        tapWhenReady(app.buttons["Close"])
        openOffer()
        assertDescription("None")
        let amountRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Amount")).firstMatch
        tapWhenReady(amountRow)
        tapWhenReady(app.buttons["2"])
        tapWhenReady(app.buttons["1"])
        tapWhenReady(app.buttons["Done"])
        assertAmount(amountRow)
        editDescription("Fixed amount coffee")
        assertDescription("Fixed amount coffee")
        assertAmount(amountRow)
        editDescription("   ")
        assertDescription("None")
        assertAmount(amountRow)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Live BOLT12 offer after clearing and reopening"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private var descriptionRow: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Description")).firstMatch
    }

    private func openOffer() {
        tapWhenReady(app.buttons["wallet-action-receive"])
        tapWhenReady(app.buttons["wallet-flow-receiveLightning"])
        tapWhenReady(app.buttons["Receive method: Lightning invoice, One-time, instant"])
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reusable invoice")).firstMatch)
        XCTAssertTrue(descriptionRow.waitForExistence(timeout: 30), "Live mint must enable the Description row")
    }

    private func editDescription(_ draft: String) {
        if !descriptionRow.isHittable { app.swipeUp() }
        tapWhenReady(descriptionRow)
        let field = screen("reusable-description-field")
        tapWhenReady(field)
        // A fresh simulator can show the system keyboard's first-use introduction.
        let keyboardIntroduction = app.buttons["Continue"]
        if keyboardIntroduction.waitForExistence(timeout: 2) { keyboardIntroduction.tap() }
        let existing = field.value as? String ?? ""
        if existing != "e.g. Coffee tips" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText(draft)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Live BOLT12 description editor"
        attachment.lifetime = .keepAlways
        add(attachment)
        tapWhenReady(app.buttons["reusable-description-save"])
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
    }

    private func assertDescription(_ text: String) {
        let updated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text), object: descriptionRow)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 30), .completed)
    }

    private func assertAmount(_ row: XCUIElement) {
        let updated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "21"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 30), .completed)
    }
}
