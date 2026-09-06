import XCTest

/// UI tests verifying tab-bar navigation after wallet creation.
final class MainTabUITests: UITestBase {
    override var launchMode: LaunchMode { .seededWallet }

    // MARK: - Tests

    func testWalletNoMintEmptyStateOpensConnectMintPicker() throws {
        waitForMainTab()

        XCTAssertTrue(
            app.staticTexts["Add a mint to get started"].waitForExistence(timeout: 5),
            "A wallet without mints should explain that a mint is required"
        )

        let addMint = app.buttons["Add mint"]
        tapWhenReady(addMint)

        XCTAssertTrue(
            app.navigationBars["Add mint"].waitForExistence(timeout: 5),
            "The Wallet empty-state CTA should open mint setup directly"
        )
        XCTAssertTrue(
            app.staticTexts["KNOWN MINTS"].waitForExistence(timeout: 5),
            "Mint setup should lead with the curated shortlist, not a URL field"
        )
        // The CTA and the sheet title already say "Add mint"; a third restatement
        // is exactly the header stacking this surface removed.
        XCTAssertFalse(
            app.staticTexts["Add a mint first"].exists,
            "The headline is for the Send context, where the title says 'Send'"
        )

        tapWhenReady(app.buttons["Add by URL"])

        XCTAssertTrue(
            app.textFields["mints-add-url-field"].waitForExistence(timeout: 5),
            "Custom URL entry should push into the same sheet"
        )
    }

    func testSendWithoutMintOffersConnectMintAndUnwindsWithBack() throws {
        waitForMainTab()

        // Send is tappable with no mints: the sheet answers with the
        // connect-a-mint surface rather than the button sitting dead.
        tapWhenReady(app.buttons["Send"])

        XCTAssertTrue(
            app.navigationBars["Send"].waitForExistence(timeout: 5),
            "The Send sheet keeps its own title"
        )
        XCTAssertTrue(
            app.staticTexts["Add a mint first"].waitForExistence(timeout: 5),
            "The Send context explains why the flow stalled"
        )

        tapWhenReady(app.buttons["Add by URL"])

        XCTAssertTrue(
            app.navigationBars["Add by URL"].waitForExistence(timeout: 5),
            "Custom URL entry pushes inside the Send sheet"
        )
        XCTAssertTrue(app.textFields["mints-add-url-field"].waitForExistence(timeout: 5))

        app.navigationBars["Add by URL"].buttons.element(boundBy: 0).tap()

        XCTAssertTrue(
            app.staticTexts["Add a mint first"].waitForExistence(timeout: 5),
            "Back should return to the picker, not dismiss the sheet"
        )
    }

    func testPrimaryNavigationAndEmptyMintsState() throws {
        waitForMainTab()

        let tabBar = mainTabBar()
        XCTAssertEqual(tabBar.buttons.count, 3)
        XCTAssertTrue(tabButton("History").exists)
        XCTAssertTrue(tabButton("Mints").exists)
        waitForSelectedTab("Wallet")

        tapTab("History")
        XCTAssertTrue(
            screen("history-screen").waitForExistence(timeout: 10),
            "History view should appear"
        )
        // The screen container exists even when its content fails to mount
        // (the identifier is on the NavigationStack), so also assert rendered
        // content: a fresh wallet must show the title and the empty state.
        XCTAssertTrue(
            app.navigationBars["History"].waitForExistence(timeout: 5),
            "History title should render on an empty wallet"
        )
        XCTAssertTrue(
            app.staticTexts["No Activity Yet"].waitForExistence(timeout: 5),
            "Fresh wallet should show the History empty state"
        )

        tapTab("Mints")
        XCTAssertTrue(
            screen("mints-screen").waitForExistence(timeout: 10),
            "Mints view should appear"
        )
        XCTAssertTrue(
            app.buttons["mints-add-button"].waitForExistence(timeout: 5),
            "Mints tab should show the Add mint button when no mint is configured"
        )

        tapTab("Wallet")
    }
}


/// Actual receipt sheets with deterministic catalog records, without a live mint.
final class ActivityDetailUITests: XCTestCase {
    func testReceiptLayoutAndVisiblePaymentCode() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["SHOW_COMPONENT_CATALOG": "activity", "CI_INTEGRATION_TEST": "1"]
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        for id in ["pending-lightning", "paid-lightning", "sent-lightning", "received-ecash", "received-bitcoin", "reusable-invoice"] {
            let row = app.buttons[id]
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(app.staticTexts["Status"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Date"].exists)
            XCTAssertTrue(app.staticTexts["Mint"].exists)
            XCTAssertFalse(app.buttons["Close"].exists)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = id
            attachment.lifetime = .keepAlways
            add(attachment)

            if id == "pending-lightning" || id == "reusable-invoice" {
                XCTAssertTrue(app.descendants(matching: .any)["cashu.history.payment-code"].firstMatch.exists)
            } else {
                XCTAssertFalse(app.descendants(matching: .any)["cashu.history.payment-code"].firstMatch.exists)
            }
            XCTAssertFalse(app.buttons["Show QR code"].exists)
            XCTAssertFalse(app.buttons["Hide QR code"].exists)
            // Native sheet gesture, starting on the title to avoid scrolling its body.
            let title = app.navigationBars.firstMatch
            title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
            XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        }
    }
}
