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

        let settingsContent = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Display' OR label CONTAINS 'Balance' OR label CONTAINS 'Wallet'")).firstMatch
        XCTAssertTrue(settingsContent.waitForExistence(timeout: 10), "Settings content should be visible")
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

    func testMintsTabShowsEmptyStateWithoutMint() throws {
        navigateToSettings()

        app.tabBars.buttons["Mints"].tap()
        XCTAssertTrue(app.tabBars.buttons["Mints"].isSelected)

        let addMintButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Add' OR label CONTAINS 'mint'")).firstMatch
        let navigationTitle = app.navigationBars.staticTexts.firstMatch
        let contentExists = addMintButton.waitForExistence(timeout: 5) || navigationTitle.waitForExistence(timeout: 5)
        XCTAssertTrue(contentExists, "Mints tab should show some content")
    }
}
