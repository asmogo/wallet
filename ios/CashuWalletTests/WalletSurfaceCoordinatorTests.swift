import XCTest
@testable import CashuWallet

/// The one-flow-surface contract owned by `NavigationManager`: present-when-
/// idle is immediate, present-while-open parks and fires once the outgoing
/// dismissal completes, and deep-linked interrupts queue without loss.
@MainActor
final class WalletSurfaceCoordinatorTests: XCTestCase {

    func testPresentWhenIdleAppliesImmediately() {
        let nav = NavigationManager()

        nav.present(.sheet(.receive))

        XCTAssertEqual(nav.activeWalletSheet?.id, "receive")
        XCTAssertTrue(nav.isFlowSurfaceOpen)
    }

    func testPresentWhileSheetOpenParksAndFiresAfterDismissal() {
        let nav = NavigationManager()
        nav.activeWalletSheet = .scanner

        nav.present(.cover(.receiveToken("cashuAexample")))

        // The sheet was cleared to start its dismissal; nothing presents yet.
        XCTAssertNil(nav.activeWalletSheet)
        XCTAssertNil(nav.activeFlowCover)
        XCTAssertTrue(nav.isFlowSurfaceOpen, "dismissal in flight still counts as open")

        nav.sheetDidDismiss()

        XCTAssertEqual(nav.activeFlowCover?.id, "token-cashuAexample")
    }

    func testParkedSurfaceFiresExactlyOnce() {
        let nav = NavigationManager()
        nav.activeWalletSheet = .scanner
        nav.present(.cover(.receiveToken("cashuAonce")))
        nav.sheetDidDismiss()
        XCTAssertNotNil(nav.activeFlowCover)

        nav.activeFlowCover = nil   // user closes the claim page
        nav.coverDidDismiss()

        XCTAssertNil(nav.activeFlowCover, "a consumed handoff must not re-fire")
        XCTAssertFalse(nav.isFlowSurfaceOpen)
    }

    func testLastRequestBeforeDismissalCompletesWins() {
        let nav = NavigationManager()
        nav.activeWalletSheet = .scanner

        nav.present(.cover(.receiveToken("cashuAfirst")))
        nav.present(.cover(.receiveToken("cashuAsecond")))
        nav.sheetDidDismiss()

        XCTAssertEqual(nav.activeFlowCover?.id, "token-cashuAsecond")
    }

    func testUserDismissalMarksDismissalInFlightUntilOnDismiss() {
        let nav = NavigationManager()
        nav.activeWalletSheet = .receive

        // SwiftUI's item binding writes nil the moment a swipe-dismissal
        // commits; the animation (and onDismiss) come after.
        nav.activeWalletSheet = nil
        XCTAssertTrue(nav.isFlowSurfaceOpen, "still animating out")

        // A surface presented inside that window must park, not stack.
        nav.present(.cover(.receiveToken("cashuAparked")))
        XCTAssertNil(nav.activeFlowCover)

        nav.sheetDidDismiss()
        XCTAssertEqual(nav.activeFlowCover?.id, "token-cashuAparked")
    }

    func testSheetContentSwapKeepsSurfaceOpen() {
        let nav = NavigationManager()
        nav.activeWalletSheet = .send(prefill: nil)

        // Story progression swaps the case in place — never a dismissal.
        nav.activeWalletSheet = .sendEcash

        XCTAssertEqual(nav.activeWalletSheet?.id, "sendEcash")
        XCTAssertTrue(nav.isFlowSurfaceOpen)
    }

    func testSendAmountSheetWaitsForCompactSheetDismissal() {
        let nav = NavigationManager()
        nav.activeWalletSheet = .send(prefill: nil)
        let destination = SendAmountDestination.melt(
            request: "wallet@example.com",
            mode: .lightning,
            decoded: .lightningAddress("wallet@example.com")
        )

        nav.present(.sheet(.sendAmount(destination)))

        XCTAssertNil(nav.activeWalletSheet)
        XCTAssertTrue(nav.isFlowSurfaceOpen, "the compact sheet is still dismissing")

        nav.sheetDidDismiss()

        XCTAssertEqual(nav.activeWalletSheet?.id, "sendAmount")
    }

    func testCashuRequestPayWaitsForScannerThenOpensAsSheet() {
        let nav = NavigationManager()
        let request = CashuPaymentRequestSummary(
            encoded: "creqAtest",
            amount: nil,
            unit: "sat",
            description: nil,
            mints: []
        )
        nav.activeWalletSheet = .scanner

        nav.present(.sheet(.cashuRequestPay(request)))

        XCTAssertNil(nav.activeWalletSheet)
        XCTAssertTrue(nav.isFlowSurfaceOpen, "the scanner sheet is still dismissing")

        nav.sheetDidDismiss()

        XCTAssertEqual(nav.activeWalletSheet?.id, "creq-creqAtest")
        XCTAssertNil(nav.activeFlowCover)
    }

    func testDeepLinkTokensQueueAndConsumeInOrder() {
        let nav = NavigationManager()

        nav.handleDeepLink(url: URL(string: "cashu:cashuAfirsttoken")!)
        nav.handleDeepLink(url: URL(string: "cashu:cashuBsecondtoken")!)

        XCTAssertEqual(nav.heldDeepLinkTokens, ["cashuAfirsttoken", "cashuBsecondtoken"])
        XCTAssertEqual(nav.consumeHeldDeepLinkToken(), "cashuAfirsttoken")
        XCTAssertEqual(nav.consumeHeldDeepLinkToken(), "cashuBsecondtoken")
        XCTAssertNil(nav.consumeHeldDeepLinkToken())
    }

    func testDeepLinkWhileSurfaceOpenLeavesSurfaceUntouched() {
        let nav = NavigationManager()
        nav.activeWalletSheet = .send(prefill: nil)

        nav.handleDeepLink(url: URL(string: "cashu:cashuAheld")!)

        // The open flow is never interrupted; the token just queues.
        XCTAssertEqual(nav.activeWalletSheet?.id, "send")
        XCTAssertEqual(nav.heldDeepLinkTokens, ["cashuAheld"])
    }

    func testInvalidDeepLinkIsIgnored() {
        let nav = NavigationManager()

        nav.handleDeepLink(url: URL(string: "cashu:notatoken")!)
        nav.handleDeepLink(url: URL(string: "https://example.com")!)

        XCTAssertTrue(nav.heldDeepLinkTokens.isEmpty)
    }
}
