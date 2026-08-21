import XCTest
@testable import CashuWallet

final class MintQuoteDomainTests: XCTestCase {
    func testReusableOfferReuseMatchesDescriptionExactly() {
        XCTAssertTrue(MintQuoteDomain.isReusableAmountlessOffer(
            paymentMethod: .bolt12, isAmountless: true,
            quoteMintUrl: "https://mint.example", quoteUnit: "sat",
            activeMintUrl: "https://mint.example", unit: "sat",
            storedMemo: nil, description: nil
        ))
        XCTAssertTrue(MintQuoteDomain.isReusableAmountlessOffer(
            paymentMethod: .bolt12, isAmountless: true,
            quoteMintUrl: "https://mint.example", quoteUnit: "sat",
            activeMintUrl: "https://mint.example", unit: "sat",
            storedMemo: "Coffee tips", description: "Coffee tips"
        ))
        XCTAssertFalse(MintQuoteDomain.isReusableAmountlessOffer(
            paymentMethod: .bolt12, isAmountless: true,
            quoteMintUrl: "https://mint.example", quoteUnit: "sat",
            activeMintUrl: "https://mint.example", unit: "sat",
            storedMemo: "Coffee tips", description: "Different memo"
        ))
        XCTAssertFalse(MintQuoteDomain.isReusableAmountlessOffer(
            paymentMethod: .bolt12, isAmountless: true,
            quoteMintUrl: "https://mint.example", quoteUnit: "sat",
            activeMintUrl: "https://mint.example", unit: "sat",
            storedMemo: "Coffee tips", description: nil
        ))
    }

    func testReusableOfferMatchRejectsOtherRailsAndFixedAmounts() {
        XCTAssertFalse(MintQuoteDomain.isReusableAmountlessOffer(
            paymentMethod: .bolt11, isAmountless: true,
            quoteMintUrl: "https://mint.example", quoteUnit: "sat",
            activeMintUrl: "https://mint.example", unit: "sat",
            storedMemo: nil, description: nil
        ))
        XCTAssertFalse(MintQuoteDomain.isReusableAmountlessOffer(
            paymentMethod: .bolt12, isAmountless: false,
            quoteMintUrl: "https://mint.example", quoteUnit: "sat",
            activeMintUrl: "https://mint.example", unit: "sat",
            storedMemo: nil, description: nil
        ))
        XCTAssertFalse(MintQuoteDomain.isReusableAmountlessOffer(
            paymentMethod: nil, isAmountless: true,
            quoteMintUrl: "https://mint.example", quoteUnit: "sat",
            activeMintUrl: "https://mint.example", unit: "sat",
            storedMemo: nil, description: nil
        ))
    }

    func testReusableOfferMatchRejectsWrongMintOrUnit() {
        XCTAssertFalse(MintQuoteDomain.isReusableAmountlessOffer(
            paymentMethod: .bolt12, isAmountless: true,
            quoteMintUrl: "https://other.example", quoteUnit: "sat",
            activeMintUrl: "https://mint.example", unit: "sat",
            storedMemo: nil, description: nil
        ))
        // Unit match is case-insensitive (Android parity).
        XCTAssertTrue(MintQuoteDomain.isReusableAmountlessOffer(
            paymentMethod: .bolt12, isAmountless: true,
            quoteMintUrl: "https://mint.example", quoteUnit: "SAT",
            activeMintUrl: "https://mint.example", unit: "sat",
            storedMemo: nil, description: nil
        ))
        XCTAssertFalse(MintQuoteDomain.isReusableAmountlessOffer(
            paymentMethod: .bolt12, isAmountless: true,
            quoteMintUrl: "https://mint.example", quoteUnit: "usd",
            activeMintUrl: "https://mint.example", unit: "sat",
            storedMemo: nil, description: nil
        ))
    }
}
