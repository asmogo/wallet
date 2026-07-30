import XCTest

/// UI tests verifying tab-bar navigation after wallet creation.
final class MainTabUITests: UITestBase {
    override var launchMode: LaunchMode { .seededWallet }

    // MARK: - Tests

    func testWalletNoMintEmptyStateLinksToMintSetup() throws {
        waitForMainTab()

        XCTAssertTrue(
            app.staticTexts["Add a mint to get started"].waitForExistence(timeout: 5),
            "A wallet without mints should explain that a mint is required"
        )

        let addMint = app.buttons["Add mint"]
        tapWhenReady(addMint)

        XCTAssertTrue(
            app.navigationBars["Add Mint"].waitForExistence(timeout: 5),
            "The Wallet empty-state CTA should open mint setup directly"
        )
        XCTAssertTrue(
            app.textFields["mints-add-url-field"].waitForExistence(timeout: 5),
            "Mint setup should expose the mint URL field"
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
            "Mints tab should show the Add Mint button when no mint is configured"
        )

        tapTab("Wallet")
    }
}
