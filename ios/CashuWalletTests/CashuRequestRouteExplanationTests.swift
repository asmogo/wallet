import XCTest
@testable import CashuWallet

final class CashuRequestRouteExplanationTests: XCTestCase {
    func testCompatibleMintRouteHasNoRedundantExplanation() {
        XCTAssertNil(CashuRequestRouteExplanation(state: .compatibleMint))
    }

    func testLightningFallbackNamesTheRailChange() {
        XCTAssertEqual(
            CashuRequestRouteExplanation(state: .lightningFallback),
            .lightningFallback
        )
    }

    func testAddMintRecoveryNamesRequestedMintHost() {
        XCTAssertEqual(
            CashuRequestRouteExplanation(
                state: .addRequestedMint(targetMintURL: "https://mint.example.com:3338/path")
            ),
            .addRequestedMint(target: "mint.example.com:3338")
        )
    }

    func testTopUpRecoveryNamesTargetMintHost() {
        XCTAssertEqual(
            CashuRequestRouteExplanation(
                state: .topUpTargetMint(targetMintURL: "https://target.example.com/")
            ),
            .topUpTargetMint(target: "target.example.com")
        )
    }

    func testUnavailableRouteDoesNotInventAnExplanation() {
        XCTAssertNil(CashuRequestRouteExplanation(state: .unavailable))
    }

    func testMissingOrMalformedTargetKeepsGenericRecoveryExplanation() {
        XCTAssertEqual(
            CashuRequestRouteExplanation(state: .addRequestedMint(targetMintURL: "  ")),
            .addRequestedMint(target: nil)
        )
        XCTAssertEqual(
            CashuRequestRouteExplanation(state: .topUpTargetMint(targetMintURL: "https://")),
            .topUpTargetMint(target: nil)
        )
    }
}
