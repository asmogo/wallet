import XCTest

/// UI integration tests driving the real onboarding flow end-to-end.
///
/// Each test launches the app with `RESET_WALLET=1`, which makes `WalletManager`
/// wipe any persisted wallet on startup so onboarding always begins from a
/// known-empty state (see `IntegrationTestConfig` / `WalletManager.initialize`).
///
/// The mint-add test connects to the live Nutshell mint, so a mint must be
/// running on `http://localhost:3338` (see `CI/start-nutshell.sh`).
final class WalletIntegrationTests: UITestBase {

    // MARK: - Tests

    /// Create a wallet and skip mint setup — should land on the main tab bar.
    func testOnboardingCreateWalletAndSkipMint() throws {
        createWalletThroughSeed()

        let skip = app.buttons["onboarding-skip-mint"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "First-mint step should appear")
        skip.tap()

        waitForMainTab()
    }

    /// Create a wallet and connect the live Nutshell mint via a custom URL.
    /// Reaching the wallet tab means `addMint` succeeded against the mint.
    func testOnboardingAddLocalMint() throws {
        createWalletWithMint()

        // The added mint should be listed on the Mints tab.
        app.tabBars.buttons["Mints"].tap()
        let mintRow = app.staticTexts[mintURL]
        XCTAssertTrue(mintRow.waitForExistence(timeout: 10), "Added mint should appear in the Mints list")
    }
}
