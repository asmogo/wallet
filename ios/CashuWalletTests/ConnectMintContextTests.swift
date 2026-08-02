import XCTest
@testable import CashuWallet

/// Pins the one thing the two connect-a-mint contexts are allowed to differ on.
/// The whole point of the shared surface is that everything below the header is
/// identical, so drift here is the failure mode worth catching.
final class ConnectMintContextTests: XCTestCase {
    func testSendContextKeepsItsOwnTitleAndCarriesTheHeadline() {
        // The sheet is still "Send", so the body has to say why it stalled.
        XCTAssertEqual(ConnectMintContext.send.navigationTitle, "Send")
        XCTAssertTrue(ConnectMintContext.send.showsHeadline)
    }

    func testAddMintContextDropsTheRedundantHeadline() {
        // The CTA said "Add mint" and so does the title — a third restatement is
        // the header stacking this redesign removed.
        XCTAssertEqual(ConnectMintContext.addMint.navigationTitle, "Add Mint")
        XCTAssertFalse(ConnectMintContext.addMint.showsHeadline)
    }

    func testCopyIsSharedAcrossBothEntryPoints() {
        XCTAssertEqual(ConnectMintContext.headline, "Connect a mint first")
        XCTAssertEqual(
            ConnectMintContext.subtitle,
            "Mints issue the ecash you send and receive. Add one to get started."
        )
    }

    func testCuratedShortlistIsNonEmptyAndUsesHTTPS() {
        // The picker's whole value is recognition over recall; an empty list
        // would silently degrade it to a bare "Add custom mint URL" link.
        XCTAssertFalse(RecommendedMint.suggested.isEmpty)
        for mint in RecommendedMint.suggested {
            XCTAssertTrue(
                mint.url.hasPrefix("https://"),
                "Curated mint \(mint.name) must be HTTPS"
            )
            XCTAssertFalse(mint.name.isEmpty)
        }
    }
}
