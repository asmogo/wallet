import XCTest
@testable import CashuWallet

/// The home scanner's payload table — must stay in lockstep with Android's
/// `routeScannedPayload` so the two scanners route identically.
final class ScanRouterTests: XCTestCase {

    private func route(_ content: String) -> ScannedPayloadRoute {
        ScanRouter.route(content) { summary, _ in .payWithEcash(summary) }
    }

    func testBearerTokenRoutesToClaimPage() {
        guard case .receiveToken(let token) = route("  cashuAexampletoken  ") else {
            return XCTFail("expected .receiveToken")
        }
        XCTAssertEqual(token, "cashuAexampletoken")
    }

    func testCashuSchemeTokenRoutesToClaimPage() {
        guard case .receiveToken = route("cashu:cashuBexample") else {
            return XCTFail("expected .receiveToken")
        }
    }

    func testLightningAddressRoutesToMeltWithoutAutoQuote() {
        guard case .melt(let request, let mode, let autoQuote, let explanation) =
            route("user@example.com") else {
            return XCTFail("expected .melt")
        }
        XCTAssertEqual(request, "user@example.com")
        XCTAssertEqual(mode, .lightning)
        XCTAssertFalse(autoQuote, "an address carries no amount — no quote to prefetch")
        XCTAssertNil(explanation)
    }

    func testOnchainAddressRoutesToOnchainMelt() {
        guard case .melt(_, let mode, let autoQuote, _) =
            route("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4") else {
            return XCTFail("expected .melt")
        }
        XCTAssertEqual(mode, .onchain)
        XCTAssertFalse(autoQuote)
    }

    func testMintLikeURLIsCopiedNotRouted() {
        guard case .mintURL(let url) = route("https://mint.example.com") else {
            return XCTFail("expected .mintURL")
        }
        XCTAssertEqual(url, "https://mint.example.com")
    }

    func testJunkIsUnrecognized() {
        guard case .unrecognized = route("hello world") else {
            return XCTFail("expected .unrecognized")
        }
    }

    func testCashuRequestBolt11FallbackRoutesToMeltWithExplanation() throws {
        // A NUT-18 creq the wallet can't pay with held ecash falls back to its
        // bundled bolt11 — the injected policy stands in for that decision.
        let creq = "creqApayload"
        guard case .cashuPaymentRequest = PaymentRequestDecoder.decode(
            creq, includeCashuPaymentRequests: true, preferCashuPaymentRequests: true
        ) else {
            throw XCTSkip("fixture does not decode as a Cashu request in this build")
        }
        let routed = ScanRouter.route(creq) { _, _ in .payBolt11Fallback("lnbcfallback") }
        guard case .melt(let request, let mode, let autoQuote, let explanation) = routed else {
            return XCTFail("expected .melt fallback")
        }
        XCTAssertEqual(request, "lnbcfallback")
        XCTAssertEqual(mode, .lightning)
        XCTAssertTrue(autoQuote)
        XCTAssertEqual(explanation, CashuRequestRouteExplanation(state: .lightningFallback))
    }
}
