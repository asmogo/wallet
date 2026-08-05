import XCTest

/// Design review 2026-08-05: every onboarding step's actions hug the bottom of
/// the screen (no reserved slots), every step's title — welcome included — sits
/// at the top on the same line, and retreat-capable steps expose a glass back
/// button. This walks both branches, asserts the bottom-most action lands in
/// the bottom band of the window on every step, and exercises back navigation.
final class OnboardingChassisUITests: UITestBase {

    func testCtasAnchoredToBottomAndBackNavigation() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        let bottomBand = window.frame.height * 0.82

        func assertBottomAnchored(_ element: XCUIElement, _ step: String) {
            XCTAssertTrue(element.waitForExistence(timeout: 10), "\(step): element should exist")
            XCTAssertGreaterThan(
                element.frame.maxY, bottomBand,
                "\(step): bottom-most action should sit in the bottom band, got \(element.frame)"
            )
        }

        // Welcome — "Restore Wallet" is the bottom-most action now that the
        // chassis is two slots. "What is ecash?" moved to the bar-band icon
        // (2026-08-05), so welcome no longer carries a tertiary link.
        let create = app.buttons["onboarding-create-wallet"]
        XCTAssertTrue(create.waitForExistence(timeout: 30), "Welcome step should appear")
        assertBottomAnchored(app.buttons["Restore Wallet"], "welcome")
        XCTAssertTrue(
            app.buttons["onboarding-info"].exists,
            "Welcome should offer the ecash explainer from the bar band"
        )

        // Welcome titles itself at the top like every other step, on the line
        // `OnboardingMetrics.titleTopInset` puts them all on.
        let welcomeTitle = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Private cash.'")
        ).firstMatch
        XCTAssertTrue(welcomeTitle.waitForExistence(timeout: 10), "Welcome should title itself")
        let welcomeTitleTop = welcomeTitle.frame.minY

        // Restore branch: method chooser, then seed input, then back out via
        // the new glass back buttons.
        app.buttons["Restore Wallet"].tap()
        assertBottomAnchored(app.buttons["Use Seed Phrase"], "restoreMethod")

        let methodTitle = app.staticTexts["Restore Wallet"]
        XCTAssertTrue(methodTitle.waitForExistence(timeout: 10), "restoreMethod should title itself")
        XCTAssertEqual(
            welcomeTitleTop, methodTitle.frame.minY, accuracy: 1,
            "Welcome's title should land on the same line as every other step's"
        )

        app.buttons["Use Seed Phrase"].tap()
        assertBottomAnchored(app.buttons["Next"], "restoreInput")

        tapWhenReady(app.buttons["onboarding-back"], timeout: 10)
        XCTAssertTrue(create.waitForExistence(timeout: 10), "restoreInput back should return to welcome")

        // Create branch: seed step (back button returns to welcome), then on
        // through acknowledge to the first-mint step.
        tapWhenReady(create, timeout: 30)
        let saved = app.buttons["onboarding-saved-seed"]
        XCTAssertTrue(saved.waitForExistence(timeout: 15), "Seed step should appear")
        assertBottomAnchored(saved, "showMnemonic")

        tapWhenReady(app.buttons["onboarding-back"], timeout: 10)
        XCTAssertTrue(create.waitForExistence(timeout: 10), "seed back should return to welcome")

        tapWhenReady(create, timeout: 30)
        XCTAssertTrue(saved.waitForExistence(timeout: 15), "Seed step should reappear")
        tapWhenReady(app.buttons["onboarding-ack-seed"], timeout: 15)
        tapWhenReady(saved, timeout: 5)

        XCTAssertTrue(app.buttons["onboarding-continue"].waitForExistence(timeout: 10))
        assertBottomAnchored(app.buttons["onboarding-skip-mint"], "firstMint")
    }

    /// The seed card is a toggle: tapping a revealed card puts the phrase away
    /// again, and the hidden words leave the accessibility tree with it.
    func testTappingTheSeedCardTogglesTheReveal() throws {
        let create = app.buttons["onboarding-create-wallet"]
        XCTAssertTrue(create.waitForExistence(timeout: 30), "Welcome step should appear")
        tapWhenReady(create, timeout: 30)

        XCTAssertTrue(
            app.buttons["onboarding-saved-seed"].waitForExistence(timeout: 15),
            "Seed step should appear"
        )

        // The masked stand-in the grid renders while hidden. Keep in sync with
        // `showMnemonicStage` (and Android's `SeedGrid`) — a UI test is
        // black-box, so it cannot share the app's constant.
        let mask = app.staticTexts["••••••"]
        let reveal = app.staticTexts["Tap to reveal"]

        XCTAssertTrue(reveal.waitForExistence(timeout: 10), "Seed should start hidden")
        XCTAssertTrue(
            mask.exists,
            "A hidden phrase must publish masks, not the real words, to the accessibility tree"
        )
        reveal.tap()

        let firstIndex = app.staticTexts["01"]
        XCTAssertTrue(
            firstIndex.waitForExistence(timeout: 5),
            "Tapping the card should reveal the numbered words"
        )
        XCTAssertFalse(reveal.exists, "The reveal prompt should go away once revealed")
        XCTAssertFalse(mask.exists, "Revealing should swap the masks for the real words")

        firstIndex.tap()

        XCTAssertTrue(
            reveal.waitForExistence(timeout: 5),
            "Tapping a revealed card should blur the phrase again"
        )
        XCTAssertTrue(
            mask.waitForExistence(timeout: 5),
            "Re-hiding must put the masks back, so VoiceOver cannot read the seed aloud"
        )
    }

    /// Re-entering the seed step must present the phrase hidden and the
    /// acknowledgement cleared. The reveal/acknowledge/copied flags are `@State`
    /// on the onboarding root, so they survive the stage swap unless the step
    /// resets them on appear — leaving a revealed seed on screen and, worse, the
    /// CTA armed over words the user hasn't looked at this visit.
    func testSeedStepResetsRevealAndAcknowledgeOnReentry() throws {
        let create = app.buttons["onboarding-create-wallet"]
        XCTAssertTrue(create.waitForExistence(timeout: 30), "Welcome step should appear")
        tapWhenReady(create, timeout: 30)

        let saved = app.buttons["onboarding-saved-seed"]
        XCTAssertTrue(saved.waitForExistence(timeout: 15), "Seed step should appear")

        let reveal = app.staticTexts["Tap to reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 10), "Seed should start hidden")
        reveal.tap()
        XCTAssertTrue(
            reveal.waitForNonExistence(timeout: 5),
            "Tapping the card should reveal the phrase"
        )

        tapWhenReady(app.buttons["onboarding-ack-seed"], timeout: 10)
        XCTAssertTrue(saved.isEnabled, "Acknowledging should arm the CTA")

        // Back out to Welcome and come straight back in.
        tapWhenReady(app.buttons["onboarding-back"], timeout: 10)
        XCTAssertTrue(create.waitForExistence(timeout: 10), "Back should return to welcome")
        tapWhenReady(create, timeout: 30)
        XCTAssertTrue(saved.waitForExistence(timeout: 15), "Seed step should reappear")

        XCTAssertTrue(
            reveal.waitForExistence(timeout: 10),
            "Re-entering the seed step should present the phrase hidden again"
        )
        XCTAssertFalse(
            saved.isEnabled,
            "Re-entering the seed step should clear the acknowledgement and disarm the CTA"
        )
    }
}
