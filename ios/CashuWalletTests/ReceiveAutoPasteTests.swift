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
                clipboardText: "cashu:cashuA-token"
            )
        )
        XCTAssertNil(
            UnifiedReceiveView.automaticReceiveClipboardToken(
                enabled: true,
                currentInput: "",
                clipboardText: "lightning:lnbc1invoice"
            )
        )
    }

    func testAutomaticPasteDoesNotReplaceExplicitInput() {
        XCTAssertNil(
            UnifiedReceiveView.automaticReceiveClipboardToken(
                enabled: true,
                currentInput: "cashuB-existing",
                clipboardText: "cashuA-clipboard"
            )
        )
        XCTAssertNil(
            UnifiedReceiveView.automaticReceiveClipboardToken(
                enabled: false,
                currentInput: "",
                clipboardText: "cashuA-clipboard"
            )
        )
        XCTAssertNil(
            UnifiedReceiveView.automaticReceiveClipboardToken(
                enabled: true,
                currentInput: "",
                clipboardText: nil
            )
        )
    }
}
