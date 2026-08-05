import XCTest

/// Brief §3: the primary CTA's frame is identical on every onboarding step —
/// the single measurable success criterion of the chassis redesign. This walks
/// both branches reachable in UI tests (create + seed restore) and diffs the
/// primary button's frame at each step. The iCloud phases are unreachable here
/// (no iCloud in the simulator test environment); the visual-review capture
/// matrix covers them.
final class OnboardingChassisUITests: UITestBase {

    func testPrimaryCtaFrameConstantAcrossSteps() throws {
        var frames: [String: CGRect] = [:]

        // Welcome
        let create = app.buttons["onboarding-create-wallet"]
        XCTAssertTrue(create.waitForExistence(timeout: 30), "Welcome step should appear")
        frames["welcome"] = create.frame

        // Restore branch: method chooser, then seed input. The primaries there
        // carry no accessibility identifiers, so match by label; disabled
        // buttons still expose frames.
        app.buttons["Restore Wallet"].tap()
        let restoreICloud = app.buttons["Restore from iCloud"]
        XCTAssertTrue(restoreICloud.waitForExistence(timeout: 10), "Restore method step should appear")
        frames["restoreMethod"] = restoreICloud.frame

        app.buttons["Use Seed Phrase"].tap()
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "Restore input step should appear")
        frames["restoreInput"] = next.frame

        // Back to welcome (restoreInput's Back deliberately returns to welcome).
        app.buttons["Back"].tap()
        XCTAssertTrue(create.waitForExistence(timeout: 10), "Back should return to welcome")

        // Create branch: seed step, then first mint.
        tapWhenReady(create, timeout: 30)
        let saved = app.buttons["onboarding-saved-seed"]
        XCTAssertTrue(saved.waitForExistence(timeout: 15), "Seed step should appear")
        frames["showMnemonic"] = saved.frame

        tapWhenReady(app.buttons["onboarding-ack-seed"], timeout: 15)
        tapWhenReady(saved, timeout: 5)

        let cont = app.buttons["onboarding-continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 10), "First-mint step should appear")
        frames["firstMint"] = cont.frame

        guard let reference = frames["welcome"] else {
            return XCTFail("Missing welcome reference frame")
        }
        for (step, frame) in frames.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(frame.minY, reference.minY, accuracy: 1.0,
                           "Primary CTA drifted vertically on \(step): \(frame) vs welcome \(reference)")
            XCTAssertEqual(frame.minX, reference.minX, accuracy: 1.0,
                           "Primary CTA drifted horizontally on \(step): \(frame) vs welcome \(reference)")
            XCTAssertEqual(frame.height, reference.height, accuracy: 1.0,
                           "Primary CTA height changed on \(step): \(frame) vs welcome \(reference)")
        }
    }
}
