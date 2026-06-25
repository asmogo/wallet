import XCTest

/// UI integration tests driving the real onboarding flow end-to-end.
///
/// Each test launches the app with `RESET_WALLET=1`, which makes `WalletManager`
/// wipe any persisted wallet on startup so onboarding always begins from a
/// known-empty state (see `IntegrationTestConfig` / `WalletManager.initialize`).
///
/// The mint-add test connects to the live Nutshell mint, so a mint must be
/// running on `http://localhost:3338` (see `CI/start-nutshell.sh`).
final class WalletIntegrationTests: XCTestCase {

    private var app: XCUIApplication!
    private let mintURL = ProcessInfo.processInfo.environment["NUTSHELL_MINT_URL"] ?? "http://localhost:3338"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment = [
            "CI_INTEGRATION_TEST": "1",
            "RESET_WALLET": "1"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Advances welcome → create wallet → acknowledge seed → first-mint step.
    /// Leaves the app on the "Pick your first mint" screen.
    private func createWalletThroughSeed() {
        let create = app.buttons["onboarding-create-wallet"]
        XCTAssertTrue(create.waitForExistence(timeout: 30), "Onboarding welcome should appear")
        create.tap()

        let ack = app.buttons["onboarding-ack-seed"]
        XCTAssertTrue(ack.waitForExistence(timeout: 15), "Seed phrase step should appear")
        ack.tap()

        let saved = app.buttons["onboarding-saved-seed"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(saved.isEnabled, "Saved-seed button should enable after acknowledging")
        saved.tap()
    }

    private func assertReachedWallet(timeout: TimeInterval = 20) {
        let walletTab = app.tabBars.buttons["Wallet"]
        XCTAssertTrue(walletTab.waitForExistence(timeout: timeout), "Main wallet tab bar should appear")
    }

    // MARK: - Tests

    /// Create a wallet and skip mint setup — should land on the main tab bar.
    func testOnboardingCreateWalletAndSkipMint() throws {
        createWalletThroughSeed()

        let skip = app.buttons["onboarding-skip-mint"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "First-mint step should appear")
        skip.tap()

        assertReachedWallet()
    }

    /// Create a wallet and connect the live Nutshell mint via a custom URL.
    /// Reaching the wallet tab means `addMint` succeeded against the mint.
    func testOnboardingAddLocalMint() throws {
        createWalletThroughSeed()

        let addCustom = app.buttons["onboarding-add-custom-mint"]
        XCTAssertTrue(addCustom.waitForExistence(timeout: 10), "First-mint step should appear")
        addCustom.tap()

        let field = app.textFields["onboarding-custom-mint-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(mintURL)

        app.buttons["onboarding-commit-custom-mint"].tap()

        let cont = app.buttons["onboarding-continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5))
        XCTAssertTrue(cont.isEnabled, "Continue should enable once a mint is selected")
        cont.tap()

        // Reaching the wallet tab confirms the mint connected successfully.
        assertReachedWallet(timeout: 30)

        // The added mint should be listed on the Mints tab.
        app.tabBars.buttons["Mints"].tap()
        let mintRow = app.staticTexts[mintURL]
        XCTAssertTrue(mintRow.waitForExistence(timeout: 10), "Added mint should appear in the Mints list")
    }
}
