import XCTest
@testable import CashuWallet

final class HomeActionAccessibilityTests: XCTestCase {
    func testReceiveHintDescribesUnifiedDestinationAndInputs() {
        XCTAssertEqual(
            HomeActionAccessibility.receiveHint,
            "Opens the unified flow for a pasted ecash token or a new Cashu Request, " +
                "Lightning invoice, BOLT12 offer, or Bitcoin address"
        )
        assertNoRetiredChooserWording(HomeActionAccessibility.receiveHint)
    }

    func testSendHintDescribesUnifiedDestinationAndInputs() {
        XCTAssertEqual(
            HomeActionAccessibility.sendHint,
            "Opens the unified flow for ecash, Lightning addresses, BOLT11 invoices, " +
                "BOLT12 offers, Bitcoin addresses, or Cashu Requests"
        )
        assertNoRetiredChooserWording(HomeActionAccessibility.sendHint)
    }

    private func assertNoRetiredChooserWording(
        _ hint: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let lowercased = hint.lowercased()
        XCTAssertFalse(lowercased.contains("option"), file: file, line: line)
        XCTAssertFalse(lowercased.contains("chooser"), file: file, line: line)
    }
}
