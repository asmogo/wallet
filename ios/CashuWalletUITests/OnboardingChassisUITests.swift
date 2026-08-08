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

        /// The edge the chassis anchors to. `.safeAreaInset(edge: .bottom)`
        /// rides the software keyboard, and the seed step deliberately raises
        /// one, so "hugs the bottom" means the bottom of the *available* area —
        /// the window, less the keyboard when it is up.
        func contentBottom() -> CGFloat {
            let keyboard = app.keyboards.element
            guard keyboard.exists, keyboard.frame.height > 0 else { return window.frame.maxY }
            return keyboard.frame.minY
        }

        // 0.18 is the exact complement of the old window-relative 0.82, so the
        // steps that raise no keyboard assert precisely what they always did.
        func assertBottomAnchored(_ element: XCUIElement, _ step: String) {
            XCTAssertTrue(element.waitForExistence(timeout: 10), "\(step): element should exist")
            XCTAssertLessThan(
                contentBottom() - element.frame.maxY, window.frame.height * 0.18,
                "\(step): bottom-most action should hug the bottom of the available area, "
                    + "got \(element.frame) against a content bottom of \(contentBottom())"
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

        let methodTitle = app.staticTexts["Restore wallet."]
        XCTAssertTrue(methodTitle.waitForExistence(timeout: 10), "restoreMethod should title itself")
        XCTAssertEqual(
            welcomeTitleTop, methodTitle.frame.minY, accuracy: 1,
            "Welcome's title should land on the same line as every other step's"
        )

        app.buttons["Use Seed Phrase"].tap()
        // Word-by-word entry focuses on arrival, so the keyboard coming up
        // unprompted is itself part of the contract — and it is what makes the
        // bottom-anchoring assertion measure against the keyboard here.
        XCTAssertTrue(
            app.keyboards.element.waitForExistence(timeout: 10),
            "restoreInput should focus the seed field on arrival"
        )
        assertBottomAnchored(app.buttons["Continue"], "restoreInput")
        // Paste is a chip in the stage now (directly under the word card), not
        // a chassis action — assert it offers itself while nothing is entered.
        XCTAssertTrue(
            app.buttons["onboarding-seed-paste"].waitForExistence(timeout: 5),
            "restoreInput should offer the paste chip while nothing is entered"
        )

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

    /// The mint-backup lookup must not run itself.
    ///
    /// It used to fire on arrival, which left the step saying "your seed phrase
    /// doesn't record which mints you used" over a list of the user's mints that
    /// had appeared from nowhere. The disabled primary is the load-bearing
    /// assertion here: it can only read a bare "Restore" if nothing was staged
    /// without being asked.
    func testRestoreMintsDoesNotStageAnythingUntilAsked() throws {
        let create = app.buttons["onboarding-create-wallet"]
        XCTAssertTrue(create.waitForExistence(timeout: 30), "Welcome step should appear")

        tapWhenReady(app.buttons["Restore Wallet"], timeout: 30)
        tapWhenReady(app.buttons["Use Seed Phrase"], timeout: 10)

        // The canonical all-zeros BIP39 vector — twelve valid words with a good
        // checksum, so `validateMnemonic` lets the flow through.
        //
        // Entry is one word at a time now: a single persistent text field whose
        // ordinal advances on each space, so this is a `textFields` query and
        // the phrase goes in word by word rather than as one burst.
        let seedField = app.textFields.firstMatch
        XCTAssertTrue(seedField.waitForExistence(timeout: 10), "The seed word field should appear")
        XCTAssertTrue(
            app.keyboards.element.waitForExistence(timeout: 10),
            "Seed entry focuses on arrival, so the keyboard comes up unprompted"
        )

        let vector = Array(repeating: "abandon", count: 11) + ["about"]
        for (index, word) in vector.enumerated() {
            // No trailing space on the twelfth: a valid uncommitted last word
            // already counts, and pressing space there would have nowhere to go.
            seedField.typeText(index == vector.count - 1 ? word : "\(word) ")
        }

        // By identifier, not label — the seed keyboard's return key is also
        // labelled "Continue".
        let cont = app.buttons["onboarding-restore-continue"]
        XCTAssertTrue(
            cont.waitUntilEnabledAndHittable(timeout: 10),
            "Continue should arm once twelve valid words are entered"
        )
        tapWhenReady(cont)

        // --- Add your mints ---
        let restore = app.buttons["onboarding-restore-mints"]
        XCTAssertTrue(
            restore.waitForExistence(timeout: 30),
            "The mint step's primary should appear"
        )
        XCTAssertEqual(
            restore.label, "Restore",
            "Arriving on the mint step must stage nothing, so the primary can't "
                + "have counted any mints into its label"
        )
        XCTAssertFalse(
            restore.isEnabled,
            "Arriving on the mint step must stage nothing, leaving the primary disabled"
        )

        // The way through the step, and the line that names it.
        XCTAssertTrue(
            app.buttons["Find my mints"].exists,
            "The manual lookup should be the way through this step"
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Tap Find my mints'")
            ).firstMatch.exists,
            "The empty state should point at the lookup rather than describe the situation"
        )

        // The help affordance explains what that button does.
        let help = app.buttons["onboarding-mint-backup-info"]
        XCTAssertTrue(help.exists, "The mint step should offer the backup explainer")
        tapWhenReady(help)
        XCTAssertTrue(
            app.staticTexts["Your mint list can be backed up."].waitForExistence(timeout: 10),
            "The help button should open the mint-backup sheet"
        )
        tapWhenReady(app.buttons["Got it"], timeout: 10)

        // Tapping the lookup is allowed to find nothing — CI has no relay — but
        // it must acknowledge the tap and settle back.
        tapWhenReady(app.buttons["Find my mints"], timeout: 10)
        XCTAssertTrue(
            app.buttons["Find my mints"].waitForExistence(timeout: 30),
            "The lookup chip should settle back to its resting label"
        )
    }

    /// The rail scrubs: press-and-hold, then drag runs through the words with
    /// the focused slot tracking the finger, and a plain tap still jumps.
    /// Synthesized as a user actually does it — press, hold, drag — because
    /// this interaction shipped broken once: SwiftUI's sequenced long-press →
    /// drag loses its drag half to the ScrollView's pan on a device, which no
    /// amount of tapping-only coverage would ever have caught.
    func testSeedRailScrubRunsThroughTheWords() throws {
        tapWhenReady(app.buttons["Restore Wallet"], timeout: 30)
        tapWhenReady(app.buttons["Use Seed Phrase"], timeout: 10)

        let rail = app.otherElements["Seed word progress"]
        XCTAssertTrue(rail.waitForExistence(timeout: 10), "The rail should be one merged element")
        XCTAssertEqual(rail.value as? String, "Word 1 of 12")
        XCTAssertTrue(
            app.keyboards.element.waitForExistence(timeout: 10),
            "Seed entry focuses on arrival"
        )

        // Hold near the top tick, then drag to the bottom one. 0.6s of hold is
        // safely past the recognizer's 0.25s gate.
        let top = rail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04))
        let bottom = rail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.96))
        top.press(forDuration: 0.6, thenDragTo: bottom)

        let landed = NSPredicate(format: "value == 'Word 12 of 12'")
        let scrubbed = XCTNSPredicateExpectation(predicate: landed, object: rail)
        XCTAssertEqual(
            XCTWaiter().wait(for: [scrubbed], timeout: 5), .completed,
            "Scrubbing to the rail's bottom should land on the last word, got \(String(describing: rail.value))"
        )
        XCTAssertTrue(app.keyboards.element.exists, "The keyboard must survive a scrub")

        // The tap path lives on the same surface now, so prove it separately.
        top.tap()
        let tapped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'Word 1 of 12'"), object: rail
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [tapped], timeout: 5), .completed,
            "Tapping the top tick should jump back to word 1, got \(String(describing: rail.value))"
        )
    }
}
