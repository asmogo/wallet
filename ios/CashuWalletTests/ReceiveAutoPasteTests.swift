import XCTest
@testable import CashuWallet

/// Mirrors Android `ReceiveAutoPasteTest`: the unified receive input only
/// auto-pastes Cashu bearer tokens, only when the setting is enabled, and
/// never replaces explicit input.
final class ReceiveAutoPasteTests: XCTestCase {
    func testEnabledSettingAcceptsOnlyCashuTokens() {
        XCTAssertEqual(
            "cashuA-token",
            UnifiedReceiveView.automaticReceiveClipboardToken(
                enabled: true,
                currentInput: "",
                clipboardText: { "cashu:cashuA-token" }
            )
        )
        XCTAssertNil(
            UnifiedReceiveView.automaticReceiveClipboardToken(
                enabled: true,
                currentInput: "",
                clipboardText: { "lightning:lnbc1invoice" }
            )
        )
    }

    func testAutomaticPasteDoesNotReplaceExplicitInput() {
        XCTAssertNil(
            UnifiedReceiveView.automaticReceiveClipboardToken(
                enabled: true,
                currentInput: "cashuB-existing",
                clipboardText: { "cashuA-clipboard" }
            )
        )
        var clipboardRead = false
        XCTAssertNil(
            UnifiedReceiveView.automaticReceiveClipboardToken(
                enabled: false,
                currentInput: "",
                clipboardText: {
                    clipboardRead = true
                    return "cashuA-clipboard"
                }
            )
        )
        XCTAssertFalse(clipboardRead)
        XCTAssertNil(
            UnifiedReceiveView.automaticReceiveClipboardToken(
                enabled: true,
                currentInput: "",
                clipboardText: { nil }
            )
        )
    }

    /// Only a confirmed-spent clipboard token suppresses the auto-paste (and
    /// thereby the auto-route to the claim page). When the NUT-07 check can't
    /// run — offline, unreachable mint, undecodable token — the token is
    /// pasted anyway and the claim page surfaces its own error.
    func testOnlyConfirmedSpentClipboardTokenSkipsAutoPaste() {
        XCTAssertFalse(UnifiedReceiveView.shouldAutoPasteClipboardToken(spent: true))
        XCTAssertTrue(UnifiedReceiveView.shouldAutoPasteClipboardToken(spent: false))
        XCTAssertTrue(UnifiedReceiveView.shouldAutoPasteClipboardToken(spent: nil))
    }
}

final class ReceiveTokenMemoReviewTests: XCTestCase {
    func testPresentMemoIsTrimmedAndReviewedBeforeClaim() {
        let presentation = ReceiveTokenReviewPresentation(
            rawMemo: "  Thanks for dinner.\n"
        )

        XCTAssertEqual(presentation.memo?.text, "Thanks for dinner.")
        XCTAssertEqual(
            presentation.confirmationElements,
            [.memo("Thanks for dinner."), .claimAction]
        )
    }

    func testNilAndBlankMemosAreOmitted() {
        XCTAssertNil(ReceiveTokenReviewPresentation(rawMemo: nil).memo)
        XCTAssertNil(ReceiveTokenReviewPresentation(rawMemo: " \n\t ").memo)
        XCTAssertEqual(
            ReceiveTokenReviewPresentation(rawMemo: nil).confirmationElements,
            [.claimAction]
        )
    }

    func testMemoExposesFullAccessibilityCopyAndStableIdentifier() {
        let memo = ReceiveTokenReviewPresentation(rawMemo: "Coffee beans").memo

        XCTAssertEqual(memo?.accessibilityLabel, "Memo")
        XCTAssertEqual(memo?.accessibilityValue, "Coffee beans")
        XCTAssertEqual(memo?.accessibilityIdentifier, "receive-token-review-memo")
    }
}
