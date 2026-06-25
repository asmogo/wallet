import XCTest

/// Shared base for all CashuWallet UI tests.
///
/// Provides a pre-launched XCUIApplication and the common wallet-creation
/// helpers so individual test files don't duplicate setUp/tearDown or
/// the multi-step onboarding walk-through.
class UITestBase: XCTestCase {
    var app: XCUIApplication!
    var mintURL: String {
        ProcessInfo.processInfo.environment["NUTSHELL_MINT_URL"] ?? "http://localhost:3338"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment = [
            "CI_INTEGRATION_TEST": "1",
            "RESET_WALLET": "1",
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Onboarding helpers

    /// Walk through: welcome → create wallet → acknowledge seed → saved seed.
    /// Leaves the app on the "Pick your first mint" screen.
    func createWalletThroughSeed() {
        let create = app.buttons["onboarding-create-wallet"]
        XCTAssertTrue(create.waitForExistence(timeout: 30))
        create.tap()

        let ack = app.buttons["onboarding-ack-seed"]
        XCTAssertTrue(ack.waitForExistence(timeout: 15))
        ack.tap()

        let saved = app.buttons["onboarding-saved-seed"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
    }

    /// Full onboarding: create wallet, skip mint setup, wait for main tab bar.
    func createWalletAndSkipMint() {
        createWalletThroughSeed()

        let skip = app.buttons["onboarding-skip-mint"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()

        waitForMainTab()
    }

    /// Full onboarding: create wallet, add live mint, wait for main tab bar.
    func createWalletWithMint() {
        createWalletThroughSeed()

        let addCustom = app.buttons["onboarding-add-custom-mint"]
        XCTAssertTrue(addCustom.waitForExistence(timeout: 10))
        addCustom.tap()

        let field = app.textFields["onboarding-custom-mint-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(mintURL)

        app.buttons["onboarding-commit-custom-mint"].tap()

        let cont = app.buttons["onboarding-continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5))
        cont.tap()

        waitForMainTab(timeout: 30)
    }

    func waitForMainTab(timeout: TimeInterval = 20) {
        XCTAssertTrue(
            app.tabBars.buttons["Wallet"].waitForExistence(timeout: timeout),
            "Main wallet tab bar should appear"
        )
    }
}
