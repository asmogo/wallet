import XCTest

/// UI tests for wallet-header Settings navigation and basic interactions.
final class SettingsUITests: UITestBase {
    override var launchMode: LaunchMode { .seededWallet }

    // MARK: - Helpers

    private func navigateToSettings() {
        waitForMainTab()
        let settings = app.buttons["wallet-settings-button"]
        tapWhenReady(settings)
    }

    // MARK: - Tests

    func testCurrencyNamesRemainAccessibleAtLargeTextSizes() {
        for (language, locale) in [("en", "en_US"), ("de", "de_DE")] {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale,
                                    "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
            app.launch()
            navigateToSettings()
            tapWhenReady(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Currency")).firstMatch)
            let name = Locale(identifier: locale).localizedString(forCurrencyCode: "USD") ?? "USD"
            let row = app.buttons["USD, \(name)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            XCTAssertTrue(row.isHittable)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "currency-names-\(locale)-large-text"
            attachment.lifetime = .keepAlways
            add(attachment)
            tapWhenReady(row)
            XCTAssertTrue(screen("settings-screen").waitForExistence(timeout: 5))
        }
    }

    func testSettingsRoundTrip() throws {
        navigateToSettings()

        XCTAssertTrue(
            screen("settings-screen").waitForExistence(timeout: 10),
            "Settings screen should appear"
        )
        XCTAssertTrue(
            app.buttons["Delete Wallet"].waitForExistence(timeout: 5),
            "Settings content should render (Delete Wallet row visible)"
        )
        let tabBar = mainTabBar(timeout: 5)
        XCTAssertEqual(tabBar.buttons.count, 3)
        XCTAssertFalse(tabBar.buttons["Settings"].exists)

        let back = app.navigationBars.buttons.element(boundBy: 0)
        tapWhenReady(back)
        XCTAssertTrue(app.buttons["wallet-settings-button"].waitForExistence(timeout: 5))
        waitForSelectedTab("Wallet")
    }

    func testDeleteWalletSheetCancelPreservesWallet() throws {
        navigateToSettings()
        let deleteRow = app.buttons["Delete Wallet"]
        for _ in 0..<6 {
            if deleteRow.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        tapWhenReady(deleteRow)
        XCTAssertTrue(app.staticTexts["Delete wallet?"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertTrue(app.buttons["Delete"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Delete wallet confirmation"
        attachment.lifetime = .keepAlways
        add(attachment)
        tapWhenReady(app.buttons["Cancel"])
        XCTAssertFalse(app.staticTexts["Delete wallet?"].exists)
        XCTAssertTrue(screen("settings-screen").exists)
        tapWhenReady(app.navigationBars.buttons.element(boundBy: 0))
        XCTAssertTrue(app.buttons["wallet-settings-button"].waitForExistence(timeout: 5))
    }

    func testMintRemovalUsesTheSameSheetFromListAndDetail() throws {
        app.terminate()
        app.launchEnvironment["UITEST_SEED_MINT"] = "1"
        app.launchEnvironment["UITEST_SEED_MINT_URL"] = "https://mint.example.invalid"
        app.launch()
        waitForMainTab()
        tapTab("Mints")
        let mintRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cashu mint")).firstMatch
        tapWhenReady(mintRow)
        let removeRow = app.buttons["Remove mint"]
        for _ in 0..<6 {
            if removeRow.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        tapWhenReady(removeRow)
        XCTAssertTrue(app.staticTexts["Remove mint?"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Remove mint confirmation"
        attachment.lifetime = .keepAlways
        add(attachment)
        tapWhenReady(app.buttons["Cancel"])
        tapWhenReady(app.navigationBars.buttons.element(boundBy: 0))
        XCTAssertTrue(mintRow.waitForExistence(timeout: 5))
        mintRow.swipeLeft()
        tapWhenReady(app.buttons["Remove"])
        XCTAssertTrue(app.staticTexts["Remove mint?"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        tapWhenReady(app.buttons["Cancel"])
        XCTAssertTrue(mintRow.waitForExistence(timeout: 5))
    }

    private func privacySwitch(_ labelPrefix: String) -> XCUIElement {
        app.switches
            .matching(NSPredicate(format: "label BEGINSWITH %@", labelPrefix))
            .firstMatch
    }

    private func setSwitch(_ element: XCUIElement, toOn: Bool) {
        let isOn = (element.value as? String) == "1"
        if isOn != toOn {
            tapSwitchControl(element)
        }
    }

    /// SwiftUI Toggle outside a List only responds on the switch control at the
    /// trailing edge; a center tap lands on the label and does nothing.
    private func tapSwitchControl(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    }

    func testWebSocketsToggleStaysEnabledWhenPollingDisabled() throws {
        navigateToSettings()

        let privacyRow = app.buttons["Privacy"].firstMatch
        tapWhenReady(privacyRow, timeout: 10)

        let incoming = privacySwitch("Check incoming invoice")
        XCTAssertTrue(incoming.waitForExistence(timeout: 10), "Privacy settings should appear")
        setSwitch(incoming, toOn: false)

        let sent = privacySwitch("Check sent ecash")
        XCTAssertTrue(sent.waitForExistence(timeout: 5))
        setSwitch(sent, toOn: false)

        let webSockets = privacySwitch("Use WebSockets")
        XCTAssertTrue(webSockets.waitForExistence(timeout: 5))
        XCTAssertTrue(
            webSockets.isEnabled,
            "WebSockets toggle must stay enabled when invoice/token polling is off"
        )

        let before = webSockets.value as? String
        tapSwitchControl(webSockets)
        XCTAssertNotEqual(
            webSockets.value as? String,
            before,
            "WebSockets toggle must remain settable independently of polling settings"
        )
    }
}
