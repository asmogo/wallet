import XCTest

/// Design review 2026-08-05: every onboarding step's actions hug the bottom of
/// the screen (no reserved slots), titles sit at the top on non-welcome steps,
/// and retreat-capable steps expose a glass back button. This walks both
/// branches, asserts the bottom-most action lands in the bottom band of the
/// window on every step, and exercises the new back navigation.
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

        // Welcome — tertiary link is the bottom-most action.
        let create = app.buttons["onboarding-create-wallet"]
        XCTAssertTrue(create.waitForExistence(timeout: 30), "Welcome step should appear")
        assertBottomAnchored(app.buttons["What is ecash?"], "welcome")

        // Restore branch: method chooser, then seed input, then back out via
        // the new glass back buttons.
        app.buttons["Restore Wallet"].tap()
        assertBottomAnchored(app.buttons["Use Seed Phrase"], "restoreMethod")

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
}
