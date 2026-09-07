import XCTest

/// UI integration tests driving the real onboarding flow end-to-end.
///
/// Each test launches the app with `RESET_WALLET=1`, which makes `WalletManager`
/// wipe any persisted wallet on startup so onboarding always begins from a
/// known-empty state (see `IntegrationTestConfig` / `WalletManager.initialize`).
///
/// The mint-add smoke test connects to the live Nutshell mint started by CI.
/// Nutshell/CDK backend parity is covered by the faster mint integration suite.
final class WalletIntegrationTests: UITestBase {

    // MARK: - Tests

    /// Create a wallet and skip mint setup — should land on the main tab bar.
    func testOnboardingCreateWalletAndSkipMint() throws {
        createWalletThroughSeed()

        let skip = app.buttons["onboarding-skip-mint"]
        tapWhenReady(skip, timeout: 10, message: "First-mint step should appear")

        waitForMainTab()
    }

    /// Create a wallet and connect the live Nutshell mint via a custom URL.
    func testOnboardingAddNutshellMint() throws {
        assertCanAddMint(at: mintURL)
    }

    private func assertCanAddMint(at url: String) {
        createWalletWithMint(at: url)

        // The added mint should be listed on the Mints tab.
        tapTab("Mints")
        let mintRow = app.staticTexts[url]
        XCTAssertTrue(mintRow.waitForExistence(timeout: 10), "Added mint should appear in the Mints list")
    }
}

/// Real UI receive/send flow. Fixture endpoints generate invoices, never balances.
class LivePaymentUITestBase: UITestBase {
    var fixtureURL: String!
    var fixtureSession: String!
    var backend: String { "cdk" }
    override var mintURL: String { fixtureURL + "/sessions/" + fixtureSession + "/mint/" + backend }

    override func setUpWithError() throws {
        fixtureURL = ProcessInfo.processInfo.environment["PAYMENT_FIXTURE_URL"]
        try XCTSkipIf(fixtureURL == nil, "Local payment fixtures are required")
        fixtureSession = try fixtureCall("/sessions", method: "POST")["id"] as? String
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        if fixtureSession != nil { _ = try fixtureCall("/sessions/" + fixtureSession, method: "DELETE") }
    }

    override func launchEnvironment(for mode: LaunchMode) -> [String: String] {
        var environment = super.launchEnvironment(for: mode)
        environment["UITEST_LIVE_PAYMENTS"] = "1"
        environment["UITEST_PAYMENT_RELAY"] = fixtureURL.replacingOccurrences(of: "http://", with: "ws://") + "/sessions/" + fixtureSession + "/relay"
        return environment
    }

    func fixtureCall(_ path: String, method: String = "GET", body: [String: Any]? = nil) throws -> [String: Any] {
        var request = URLRequest(url: URL(string: fixtureURL + path)!)
        request.httpMethod = method
        request.timeoutInterval = 15
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let done = expectation(description: "Payment fixture response")
        var result: Result<[String: Any], Error>!
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { done.fulfill() }
            result = Result {
                if let error { throw error }
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), let data else {
                    throw NSError(domain: "PaymentFixture", code: 1)
                }
                return try JSONSerialization.jsonObject(with: data) as! [String: Any]
            }
        }.resume()
        wait(for: [done], timeout: 20)
        return try XCTUnwrap(result, "Fixture returned no response").get()
    }

    func receiveThroughUI() {
        tapWhenReady(app.buttons["wallet-action-receive"])
        tapWhenReady(app.buttons["wallet-flow-receiveLightning"])
        XCTAssertTrue(screen("receive-lightning-screen").waitForExistence(timeout: 15))
        for digit in ["1", "0", "0"] { tapWhenReady(app.buttons[digit]) }
        tapWhenReady(app.buttons["receive-lightning-create-request"])
        XCTAssertTrue(app.staticTexts["Payment Received!"].waitForExistence(timeout: 30))
        tapWhenReady(app.buttons["Done"])
        waitForMainTab()
    }

    func receiveThenPayAndReopenHistory() throws {
        createWalletWithMint()
        receiveThroughUI()
        let invoice = try fixtureCall("/sessions/" + fixtureSession + "/invoice", method: "POST", body: ["amount": 21])["invoice"] as! String
        tapWhenReady(app.buttons["wallet-action-send"])
        let field = app.descendants(matching: .any).matching(identifier: "Address, invoice, or Cashu Request").firstMatch
        tapWhenReady(field)
        field.typeText(invoice)
        let pay = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay 21")).firstMatch
        tapWhenReady(pay, timeout: 20)
        XCTAssertTrue(app.staticTexts["Payment Sent!"].waitForExistence(timeout: 30))
        tapWhenReady(app.buttons["Done"])
        tapTab("History")
        XCTAssertTrue(app.staticTexts["Lightning paid"].firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        app.launchEnvironment["RESET_WALLET"] = "0"
        app.launch()
        waitForMainTab(timeout: 30)
        tapTab("History")
        XCTAssertTrue(app.staticTexts["Lightning paid"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Lightning received"].firstMatch.exists)
    }
}

final class LiveCdkPaymentUITests: LivePaymentUITestBase {
    func testReceivePayAndRelaunch() throws { try receiveThenPayAndReopenHistory() }
}

final class LiveNutshellPaymentUITests: LivePaymentUITestBase {
    override var backend: String { "nutshell" }
    func testReceivePayAndRelaunch() throws { try receiveThenPayAndReopenHistory() }
}
