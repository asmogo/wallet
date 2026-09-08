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

    func testDisplayCurrencyPersistsAcrossRelaunchAndCanBeDisabled() {
        navigateToSettings()
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Currency")).firstMatch)
        tapWhenReady(app.buttons["EUR"])
        XCTAssertTrue(screen("settings-screen").waitForExistence(timeout: 5))
        relaunchPreservingWallet()
        navigateToSettings()
        let currency = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Currency")).firstMatch
        XCTAssertTrue(currency.label.contains("EUR"), "Currency preference must survive a fresh process")
        tapWhenReady(currency)
        tapWhenReady(app.buttons["USD"])
        tapWhenReady(currency)
        tapWhenReady(app.buttons["Off, sats only"])
        relaunchPreservingWallet()
        navigateToSettings()
        XCTAssertTrue(currency.label.contains("Off"))
    }

    func testCancellingCurrencyPickerPreservesSelection() {
        navigateToSettings()
        let currency = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Currency")).firstMatch
        let original = currency.label
        tapWhenReady(currency)
        let picker = app.navigationBars["Currency"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let grabber = app.buttons["Sheet Grabber"]
        XCTAssertTrue(grabber.waitUntilEnabledAndHittable(timeout: 10))
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        XCTAssertTrue(picker.waitForNonExistence(timeout: 10), "Dragging the sheet grabber should dismiss the picker")
        XCTAssertTrue(currency.waitUntilEnabledAndHittable(timeout: 5))
        XCTAssertEqual(currency.label, original)
    }

    func testPrivacyDependenciesAndPreferencesSurviveRelaunch() {
        navigateToSettings()
        scrollToSettingsRow("Privacy")
        tapWhenReady(app.buttons["Privacy"].firstMatch)
        let incoming = privacySwitch("Check incoming invoice")
        setSwitch(incoming, toOn: false)
        XCTAssertFalse(privacySwitch("Repeat checks on a timer").isEnabled)
        setSwitch(privacySwitch("Check sent ecash"), toOn: false)
        setSwitch(privacySwitch("Use WebSockets"), toOn: true)
        relaunchPreservingWallet()
        navigateToSettings()
        scrollToSettingsRow("Privacy")
        tapWhenReady(app.buttons["Privacy"].firstMatch)
        XCTAssertEqual(incoming.value as? String, "0")
        XCTAssertEqual(privacySwitch("Check sent ecash").value as? String, "0")
        XCTAssertEqual(privacySwitch("Use WebSockets").value as? String, "1")
        XCTAssertTrue(privacySwitch("Use WebSockets").isEnabled)
        setSwitch(incoming, toOn: true)
        XCTAssertTrue(privacySwitch("Repeat checks on a timer").isEnabled)
    }

    func testDeleteConfirmationRemovesWalletAcrossRelaunch() {
        navigateToSettings()
        scrollToSettingsRow("Delete Wallet")
        tapWhenReady(app.buttons["Delete Wallet"])
        tapWhenReady(app.buttons["Delete"])
        XCTAssertTrue(app.buttons["onboarding-create-wallet"].waitForExistence(timeout: 15))
        app.terminate()
        for key in ["RESET_WALLET", "UITEST_SEED_WALLET", "UITEST_SEED_MINT"] {
            app.launchEnvironment.removeValue(forKey: key)
        }
        app.launch()
        XCTAssertTrue(app.buttons["onboarding-create-wallet"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["wallet-settings-button"].exists)
    }

    func testSecurityAndBackupScreensReturnToSettings() {
        navigateToSettings()
        for title in ["App Lock", "Backup & Restore", "Locked Ecash", "Nostr"] {
            scrollToSettingsRow(title)
            tapWhenReady(app.buttons[title].firstMatch)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            tapWhenReady(app.navigationBars.buttons.element(boundBy: 0))
            XCTAssertTrue(screen("settings-screen").waitForExistence(timeout: 5))
        }
    }

    func testUnavailableAuthenticationCannotEnableAppLock() {
        launchWithAuthentication("unavailable")
        navigateToSettings()
        tapWhenReady(app.buttons["App Lock"])
        let toggle = app.switches.firstMatch
        setSwitch(toggle, toOn: false)
        tapSwitchControl(toggle)
        XCTAssertTrue(app.staticTexts["Authentication failed. App Lock was not enabled. Try turning it on again."]
            .waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
    }

    func testRejectedAuthenticationCannotEnableAppLock() {
        launchWithAuthentication("deny")
        navigateToSettings()
        tapWhenReady(app.buttons["App Lock"])
        let toggle = app.switches.firstMatch
        setSwitch(toggle, toOn: false)
        tapSwitchControl(toggle)
        XCTAssertTrue(app.staticTexts["Authentication failed. App Lock was not enabled. Try turning it on again."]
            .waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
    }

    func testSuccessfulAppLockEnablementPersistsAfterRelaunch() {
        launchWithAuthentication("allow")
        navigateToSettings()
        tapWhenReady(app.buttons["App Lock"])
        let toggle = app.switches.firstMatch
        setSwitch(toggle, toOn: true)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        relaunchPreservingWallet()
        navigateToSettings()
        tapWhenReady(app.buttons["App Lock"])
        XCTAssertEqual(toggle.value as? String, "1")
    }

    func testRejectedSeedRevealKeepsWordsHiddenWithAppLockOff() {
        launchWithAuthentication("deny")
        navigateToSettings()
        tapWhenReady(app.buttons["Backup & Restore"])
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Backup seed phrase")).firstMatch)
        tapWhenReady(app.buttons["Reveal Recovery Phrase"])
        XCTAssertTrue(app.buttons["Reveal Recovery Phrase"].exists)
        XCTAssertFalse(app.buttons["Copy Recovery Phrase"].exists)
    }

    func testSuccessfulSeedRevealCanBeDismissedWithoutPersistingReveal() {
        launchWithAuthentication("allow")
        navigateToSettings()
        tapWhenReady(app.buttons["Backup & Restore"])
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Backup seed phrase")).firstMatch)
        tapWhenReady(app.buttons["Reveal Recovery Phrase"])
        XCTAssertTrue(app.buttons["Copy Recovery Phrase"].waitForExistence(timeout: 5))
        relaunchPreservingWallet()
        navigateToSettings()
        tapWhenReady(app.buttons["Backup & Restore"])
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Backup seed phrase")).firstMatch)
        XCTAssertTrue(app.buttons["Reveal Recovery Phrase"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Copy Recovery Phrase"].exists)
    }

    func testNostrRelayAdditionAndResetPersist() {
        navigateToSettings()
        scrollToSettingsRow("Nostr")
        tapWhenReady(app.buttons["Nostr"])
        let field = app.textFields["wss://relay.example.com"]
        for _ in 0..<6 {
            if field.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        tapWhenReady(field)
        field.typeText("wss://relay.test")
        tapWhenReady(app.buttons["Add relay"])
        XCTAssertTrue(app.staticTexts["wss://relay.test"].waitForExistence(timeout: 5))
        relaunchPreservingWallet()
        navigateToSettings()
        scrollToSettingsRow("Nostr")
        tapWhenReady(app.buttons["Nostr"])
        let reset = app.buttons["Reset to default relays"]
        for _ in 0..<8 {
            if reset.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        tapWhenReady(reset)
        XCTAssertTrue(app.staticTexts["Reset to default relays?"].waitForExistence(timeout: 5))
        tapWhenReady(app.buttons["Cancel"])
        XCTAssertTrue(app.staticTexts["wss://relay.test"].exists)
        tapWhenReady(reset)
        tapWhenReady(app.buttons["Reset"])
        XCTAssertTrue(app.staticTexts["wss://relay.test"].waitForNonExistence(timeout: 5))
    }

    func testNostrIdentityReplacementCanBeCancelled() {
        navigateToSettings()
        scrollToSettingsRow("Nostr")
        tapWhenReady(app.buttons["Nostr"])
        let generate = app.buttons["Generate new key"]
        for _ in 0..<5 {
            if generate.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        tapWhenReady(generate)
        XCTAssertTrue(app.staticTexts["Generate new key?"].waitForExistence(timeout: 5))
        tapWhenReady(app.buttons["Cancel"])
        XCTAssertTrue(generate.waitUntilEnabledAndHittable(timeout: 5))
        XCTAssertFalse(app.buttons["Reset to wallet seed"].exists)
    }

    func testLightningAddressEnableAutoClaimAndDisablePersist() {
        navigateToSettings()
        tapWhenReady(app.buttons["Lightning"])
        let enabled = app.switches["Enable Lightning Address"]
        setSwitch(enabled, toOn: true)
        let automatic = app.switches["Auto-claim payments"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 10))
        setSwitch(automatic, toOn: false)
        relaunchPreservingWallet()
        navigateToSettings()
        tapWhenReady(app.buttons["Lightning"])
        XCTAssertEqual(enabled.value as? String, "1")
        XCTAssertEqual(automatic.value as? String, "0")
        setSwitch(enabled, toOn: false)
        XCTAssertTrue(automatic.waitForNonExistence(timeout: 5))
    }

    func testWalletConnectLimitAndResetPersist() {
        app.terminate()
        app.launchEnvironment["UITEST_SEED_MINT"] = "1"
        app.launchEnvironment["UITEST_SEED_MINT_URL"] = "https://mint.test"
        app.launch()
        navigateToSettings()
        scrollToSettingsRow("Nostr")
        tapWhenReady(app.buttons["Nostr"])
        let connect = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wallet Connect")).firstMatch
        for _ in 0..<8 {
            if connect.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        tapWhenReady(connect)
        setSwitch(privacySwitch("Enable Wallet Connect"), toOn: true)
        let originalCode = walletConnectCode()
        let limit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Payment limit")).firstMatch
        tapWhenReady(limit)
        let field = app.textFields["No limit"]
        tapWhenReady(field)
        field.typeText("250")
        tapWhenReady(app.buttons["Save"])
        XCTAssertTrue(limit.waitForExistence(timeout: 5))
        XCTAssertTrue(limit.label.contains("250"))
        relaunchPreservingWallet()
        navigateToSettings()
        scrollToSettingsRow("Nostr")
        tapWhenReady(app.buttons["Nostr"])
        for _ in 0..<8 {
            if connect.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        tapWhenReady(connect)
        XCTAssertEqual(privacySwitch("Enable Wallet Connect").value as? String, "1")
        XCTAssertTrue(limit.label.contains("250"))
        XCTAssertEqual(walletConnectCode(), originalCode)
        let reset = app.buttons["Reset connection"]
        tapWhenReady(reset)
        tapWhenReady(app.buttons["Cancel"])
        XCTAssertTrue(limit.label.contains("250"))
        XCTAssertEqual(walletConnectCode(), originalCode)
        tapWhenReady(reset)
        tapWhenReady(app.buttons["Reset"])
        XCTAssertTrue(limit.waitUntilEnabledAndHittable(timeout: 5))
        XCTAssertTrue(limit.label.contains("250"))
        XCTAssertNotEqual(walletConnectCode(), originalCode)
        setSwitch(privacySwitch("Enable Wallet Connect"), toOn: false)
        XCTAssertTrue(limit.waitForNonExistence(timeout: 5))
    }

    private func launchWithAuthentication(_ outcome: String) {
        app.terminate()
        app.launchEnvironment["UITEST_AUTHENTICATION"] = outcome
        app.launch()
        waitForMainTab()
    }

    private func walletConnectCode() -> String {
        let connection = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Connection code.")).firstMatch
        tapWhenReady(connection, timeout: 10)
        let code = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "nostr+walletconnect://")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        let value = code.label
        // The connection row also contains this text behind the QR sheet.
        // The sheet-only Copy action is the unambiguous dismissal boundary.
        let copy = app.buttons["Copy"]
        app.buttons["Sheet Grabber"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        XCTAssertTrue(copy.waitForNonExistence(timeout: 5))
        return value
    }

    private func scrollToSettingsRow(_ title: String) {
        let row = app.buttons[title].firstMatch
        for _ in 0..<8 {
            if row.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(row.isHittable, "Settings row must be reachable: \(title)")
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
