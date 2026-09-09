import XCTest

/// Full app journeys against the local FakeWallet mint started by CI.
/// Setup itself follows onboarding; all money-moving operations use real CDK.
final class WalletLifecycleUITests: UITestBase {
    func testAddDuplicateSwitchAndRefuseMultiUnitRemovalPersists() {
        createWalletWithMint()
        tapTab("Mints")
        addMint(url: mintURL + "/")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "already")).firstMatch
            .waitForExistence(timeout: 10))
        tapWhenReady(app.buttons["mints-add-clear-button"])
        app.textFields["mints-add-url-field"].typeText(cdkMintURL)
        tapWhenReady(app.buttons["mints-add-submit-button"])
        let second = mintRow(url: cdkMintURL)
        tapWhenReady(second, timeout: 30)
        scrollTo("Set as Default")
        tapWhenReady(app.buttons["Set as Default"])
        tapWhenReady(app.navigationBars.buttons.element(boundBy: 0))
        XCTAssertEqual(second.value as? String, "Default mint")
        relaunchPreservingWallet()
        tapTab("Mints")
        XCTAssertEqual(second.value as? String, "Default mint")
        tapWhenReady(second)
        scrollTo("Remove mint")
        tapWhenReady(app.buttons["Remove mint"])
        tapWhenReady(app.buttons["Cancel"])
        XCTAssertTrue(app.buttons["Remove mint"].exists)
        tapWhenReady(app.buttons["Remove mint"])
        tapWhenReady(app.buttons["Remove"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "multiple currency units")).firstMatch
            .waitForExistence(timeout: 15))
        relaunchPreservingWallet()
        tapTab("Mints")
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        XCTAssertEqual(second.value as? String, "Default mint")
        XCTAssertTrue(mintRow(url: mintURL).waitForExistence(timeout: 10))
    }

    func testRemovingLastMintReturnsToEmptyWalletAfterRelaunch() {
        createWalletWithMint()
        tapTab("Mints")
        tapWhenReady(mintRow(url: mintURL))
        scrollTo("Remove mint")
        tapWhenReady(app.buttons["Remove mint"])
        XCTAssertTrue(app.staticTexts["Remove mint?"].waitForExistence(timeout: 5))
        tapWhenReady(app.buttons["Remove"])
        XCTAssertTrue(mintRow(url: mintURL).waitForNonExistence(timeout: 15))
        relaunchPreservingWallet()
        XCTAssertTrue(app.staticTexts["Add a mint to get started"].waitForExistence(timeout: 10))
        tapWhenReady(app.buttons["wallet-action-send"])
        XCTAssertTrue(app.staticTexts["Add a mint first"].waitForExistence(timeout: 5))
    }

    func testReceiveLightningPersistsBalanceAndHistory() {
        createWalletWithMint()
        receive(sats: "100")
        assertBalance("100")
        relaunchPreservingWallet()
        assertBalance("100")
        tapTab("History")
        let payment = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Lightning received")).firstMatch
        tapWhenReady(payment)
        XCTAssertTrue(app.staticTexts["Lightning received"].waitForExistence(timeout: 10))
    }

    func testSendEcashUpdatesBalanceAndPendingReceipt() {
        createWalletWithMint()
        receive(sats: "100")
        openSendEcash()
        tapWhenReady(app.buttons["2"])
        tapWhenReady(app.buttons["5"])
        tapWhenReady(app.buttons["cashu.send.ecash.submit"])
        XCTAssertTrue(app.staticTexts["Pending Ecash"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Copy"].exists)
        tapWhenReady(app.buttons["Close"])
        assertBalance("75")
        relaunchPreservingWallet()
        assertBalance("75")
        tapTab("History")
        let outgoing = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Ecash sent")).firstMatch
        let incoming = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Lightning received")).firstMatch
        XCTAssertTrue(outgoing.waitForExistence(timeout: 10))
        tapWhenReady(app.buttons["Filter transactions"])
        tapWhenReady(app.buttons["Pending only"])
        XCTAssertTrue(outgoing.exists)
        XCTAssertFalse(incoming.exists)
        tapWhenReady(app.buttons["Filter transactions"])
        tapWhenReady(app.buttons["Completed only"])
        XCTAssertTrue(incoming.exists)
        XCTAssertFalse(outgoing.exists)
        tapWhenReady(app.buttons["Search history"])
        app.searchFields.firstMatch.typeText("no matching payment")
        XCTAssertTrue(app.staticTexts["No Results"].waitForExistence(timeout: 5))
    }

    func testAmountClearAndInsufficientBalanceCannotSpend() {
        createWalletWithMint()
        receive(sats: "100")
        openSendEcash()
        XCTAssertFalse(app.buttons["cashu.send.ecash.submit"].isEnabled)
        tapWhenReady(app.buttons["2"])
        tapWhenReady(app.buttons["5"])
        tapWhenReady(app.buttons["Delete"])
        XCTAssertTrue(app.buttons["cashu.send.ecash.submit"].isEnabled)
        app.buttons["Delete"].press(forDuration: 0.6)
        XCTAssertFalse(app.buttons["cashu.send.ecash.submit"].isEnabled)
        for _ in 0..<3 { tapWhenReady(app.buttons["9"]) }
        XCTAssertTrue(app.staticTexts["Insufficient balance"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["cashu.send.ecash.submit"].isEnabled)
        tapWhenReady(app.buttons["Close"])
        assertBalance("100")
    }

    func testEcashRoundTripThroughClipboardRestoresBalance() {
        createWalletWithMint()
        receive(sats: "100")
        tapWhenReady(app.buttons["wallet-settings-button"])
        let privacy = app.buttons["Privacy"]
        for _ in 0..<8 {
            if privacy.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        tapWhenReady(privacy)
        let polling = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Check sent ecash")).firstMatch
        if (polling.value as? String) != "0" {
            polling.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        tapWhenReady(app.navigationBars.buttons.element(boundBy: 0))
        tapWhenReady(app.navigationBars.buttons.element(boundBy: 0))
        openSendEcash()
        tapWhenReady(app.buttons["2"])
        tapWhenReady(app.buttons["5"])
        tapWhenReady(app.buttons["cashu.send.ecash.submit"])
        XCTAssertTrue(app.staticTexts["Pending Ecash"].waitForExistence(timeout: 30))
        tapWhenReady(app.buttons["cashu.send.ecash.check-status"])
        XCTAssertTrue(app.staticTexts["This token has not been claimed yet."].waitForExistence(timeout: 15))
        tapWhenReady(app.buttons["Copy"])
        tapWhenReady(app.buttons["Close"])
        assertBalance("75")
        tapWhenReady(app.buttons["wallet-action-receive"])
        tapWhenReady(app.buttons["Paste from clipboard"])
        let receive = app.buttons["receive-token-confirm"]
        tapWhenReady(receive)
        XCTAssertTrue(app.staticTexts["Payment Received!"].waitForExistence(timeout: 30))
        tapWhenReady(app.buttons["Done"])
        assertBalance("100")
    }

    func testQuickLockCanBeSelectedAndRemovedWithoutLosingAmount() {
        createWalletWithMint()
        receive(sats: "100")
        tapWhenReady(app.buttons["wallet-settings-button"])
        let row = app.buttons["Locked Ecash"]
        for _ in 0..<8 {
            if row.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        tapWhenReady(row)
        let quickLock = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Quick lock to my key")).firstMatch
        if (quickLock.value as? String) != "1" {
            quickLock.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        relaunchPreservingWallet()
        openSendEcash()
        tapWhenReady(app.buttons["2"])
        tapWhenReady(app.buttons["5"])
        tapWhenReady(app.buttons["Lock ecash"])
        tapWhenReady(app.buttons["Lock to my key"])
        XCTAssertTrue(app.buttons["Locked to public key"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["cashu.send.ecash.submit"].isEnabled)
        tapWhenReady(app.buttons["Remove lock"])
        XCTAssertFalse(app.buttons["Locked to public key"].exists)
        tapWhenReady(app.buttons["cashu.send.ecash.submit"])
        XCTAssertTrue(app.staticTexts["Pending Ecash"].waitForExistence(timeout: 30))
        tapWhenReady(app.buttons["Close"])
        assertBalance("75")
    }

    func testRestoreFromRevealedTestSeedRecoversFunds() {
        app.terminate()
        app.launchEnvironment["UITEST_AUTHENTICATION"] = "allow"
        app.launch()
        createWalletWithMint()
        receive(sats: "100")
        tapWhenReady(app.buttons["wallet-settings-button"])
        tapWhenReady(app.buttons["Backup & Restore"])
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Backup seed phrase")).firstMatch)
        tapWhenReady(app.buttons["Reveal Recovery Phrase"])
        XCTAssertTrue(app.buttons["Copy Recovery Phrase"].waitForExistence(timeout: 5))
        // Read only this newly created synthetic wallet's words through the UI.
        // Do not log or attach the phrase to assertion messages.
        let words = (1...12).map { index in
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label BEGINSWITH %@", "Word \(index), ")
            ).firstMatch.label.components(separatedBy: ", ").last!
        }
        app.staticTexts["Backup Wallet"].swipeDown()
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Restore,")).firstMatch)
        let field = app.textFields.firstMatch
        tapWhenReady(field)
        for (index, word) in words.enumerated() {
            field.typeText(word)
            tapWhenReady(app.buttons[word].firstMatch)
            if index < 11 {
                XCTAssertTrue(app.textFields["word \(index + 2)"].waitForExistence(timeout: 5))
            }
        }
        tapWhenReady(app.buttons["Next"])
        let mintField = app.textFields["mint.example.com"]
        tapWhenReady(mintField)
        mintField.typeText(mintURL)
        tapWhenReady(app.buttons["Add"])
        tapWhenReady(app.buttons["Restore from 1 mint"])
        XCTAssertTrue(app.staticTexts["Restore Complete"].waitForExistence(timeout: 60))
        XCTAssertTrue(app.staticTexts["Recovered: 100 sats"].exists)
        tapWhenReady(app.buttons["Continue"])
        tapWhenReady(app.navigationBars.buttons.element(boundBy: 0))
        tapWhenReady(app.navigationBars.buttons.element(boundBy: 0))
        assertBalance("100")
        relaunchPreservingWallet()
        assertBalance("100")
    }

    func testUsdAmountEntryAndSendUseCents() {
        createWalletWithMint(at: cdkMintURL)
        tapWhenReady(app.buttons["wallet-action-receive"])
        tapWhenReady(app.buttons["wallet-flow-receiveLightning"])
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Unit:")).firstMatch)
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "USD")).firstMatch)
        tapWhenReady(app.buttons["1"])
        tapWhenReady(app.buttons["0"])
        tapWhenReady(app.buttons["receive-lightning-create-request"])
        XCTAssertTrue(app.staticTexts["Payment Received!"].waitForExistence(timeout: 45))
        tapWhenReady(app.buttons["Done"])
        openSendEcash()
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Unit:")).firstMatch)
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "USD")).firstMatch)
        tapWhenReady(app.buttons["2"])
        tapWhenReady(app.buttons["Decimal point"])
        tapWhenReady(app.buttons["5"])
        tapWhenReady(app.buttons["0"])
        tapWhenReady(app.buttons["9"])
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Unit:")).firstMatch)
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "USD")).firstMatch)
        tapWhenReady(app.buttons["cashu.send.ecash.submit"])
        XCTAssertTrue(app.staticTexts["Pending Ecash"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["$2.50"].exists)
        XCTAssertTrue(app.staticTexts["USD"].exists)
        tapWhenReady(app.buttons["Close"])
        relaunchPreservingWallet()
        tapTab("History")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Ecash sent", "$2.50")).firstMatch
            .waitForExistence(timeout: 10))
    }

    private func receive(sats: String) {
        tapWhenReady(app.buttons["wallet-action-receive"])
        tapWhenReady(app.buttons["wallet-flow-receiveLightning"])
        for digit in sats { tapWhenReady(app.buttons[String(digit)]) }
        tapWhenReady(app.buttons["receive-lightning-create-request"])
        XCTAssertTrue(app.staticTexts["Payment Received!"].waitForExistence(timeout: 45))
        tapWhenReady(app.buttons["Done"])
        waitForMainTab()
    }

    private func openSendEcash() {
        tapWhenReady(app.buttons["wallet-action-send"])
        tapWhenReady(app.buttons["Ecash. Create ecash"])
        XCTAssertTrue(app.buttons["cashu.send.ecash.submit"].waitForExistence(timeout: 10))
    }

    private func assertBalance(_ amount: String) {
        let balance = app.descendants(matching: .any).matching(
            NSPredicate(format: "label MATCHES %@", "Balance: .*\\b" + amount + "\\b.*")
        ).firstMatch
        XCTAssertTrue(balance.waitForExistence(timeout: 15), "Wallet must display the settled balance")
    }

    private func mintRow(url: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", url)).firstMatch
    }

    private func addMint(url: String) {
        tapWhenReady(app.buttons["mints-add-button"])
        let field = app.textFields["mints-add-url-field"]
        tapWhenReady(field)
        field.typeText(url)
        tapWhenReady(app.buttons["mints-add-submit-button"])
    }

    private func scrollTo(_ title: String) {
        scrollToButton(app.buttons[title])
    }
}
