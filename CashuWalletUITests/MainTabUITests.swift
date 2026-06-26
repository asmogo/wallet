import XCTest

/// UI tests verifying tab-bar navigation after wallet creation.
final class MainTabUITests: UITestBase {

    // MARK: - Tests

    func testAllTabsExist() throws {
        createWalletAndSkipMint()
        waitForMainTab()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.buttons["Wallet"].exists)
        XCTAssertTrue(tabBar.buttons["History"].exists)
        XCTAssertTrue(tabBar.buttons["Mints"].exists)
        XCTAssertTrue(tabBar.buttons["Settings"].exists)
    }

    func testNavigateToHistoryTab() throws {
        createWalletAndSkipMint()
        waitForMainTab()

        app.tabBars.buttons["History"].tap()

        // History view should appear — at minimum the tab should be selected
        let historyTab = app.tabBars.buttons["History"]
        XCTAssertTrue(historyTab.isSelected, "History tab should become selected")
    }

    func testNavigateToMintsTab() throws {
        createWalletAndSkipMint()
        waitForMainTab()

        app.tabBars.buttons["Mints"].tap()

        let mintsTab = app.tabBars.buttons["Mints"]
        XCTAssertTrue(mintsTab.isSelected)
    }

    /// With no mint configured, the Mints tab shows its add-mint form.
    func testMintsTabShowsAddMintWithoutMint() throws {
        createWalletAndSkipMint()
        waitForMainTab()

        app.tabBars.buttons["Mints"].tap()
        XCTAssertTrue(app.tabBars.buttons["Mints"].isSelected)

        XCTAssertTrue(
            app.navigationBars["Mints"].waitForExistence(timeout: 10),
            "Mints navigation bar should appear"
        )
        XCTAssertTrue(
            app.buttons["mints-add-button"].waitForExistence(timeout: 5),
            "Mints tab should show the Add Mint button when no mint is configured"
        )
    }

    func testNavigateToSettingsTab() throws {
        createWalletAndSkipMint()
        waitForMainTab()

        app.tabBars.buttons["Settings"].tap()

        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.isSelected)
    }

    func testWalletTabIsDefaultSelected() throws {
        createWalletAndSkipMint()
        waitForMainTab()

        let walletTab = app.tabBars.buttons["Wallet"]
        XCTAssertTrue(walletTab.isSelected, "Wallet should be selected by default")
    }

    func testNavigateBetweenMultipleTabs() throws {
        createWalletAndSkipMint()
        waitForMainTab()

        app.tabBars.buttons["Mints"].tap()
        XCTAssertTrue(app.tabBars.buttons["Mints"].isSelected)

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)

        app.tabBars.buttons["Wallet"].tap()
        XCTAssertTrue(app.tabBars.buttons["Wallet"].isSelected)
    }
}
