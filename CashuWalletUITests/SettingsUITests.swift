import XCTest

/// UI tests for the Settings tab navigation and basic interactions.
final class SettingsUITests: UITestBase {

    // MARK: - Helpers

    private func navigateToSettings() {
        createWalletAndSkipMint()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)
    }

    // MARK: - Tests

    func testSettingsViewLoads() throws {
        navigateToSettings()

        // Assert the real Settings screen rendered: its nav bar plus a known row.
        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 10),
            "Settings navigation bar should appear"
        )
        XCTAssertTrue(
            app.buttons["Delete Wallet"].waitForExistence(timeout: 5),
            "Settings content should render (Delete Wallet row visible)"
        )
    }

    func testSettingsTabIsAccessible() throws {
        navigateToSettings()

        XCTAssertTrue(app.tabBars.firstMatch.exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)
    }

    func testCanReturnToWalletFromSettings() throws {
        navigateToSettings()

        app.tabBars.buttons["Wallet"].tap()
        XCTAssertTrue(app.tabBars.buttons["Wallet"].isSelected)
    }
}
