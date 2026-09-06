import Cdk
import XCTest
@testable import CashuWallet

final class MintQuoteDomainTests: XCTestCase {
    func testNormalizesDescriptionForPayerDisplay() {
        XCTAssertEqual(MintQuoteDomain.normalizedOfferDescription("  Coffee tips\r\n\tThank you ☕  "), "Coffee tips Thank you ☕")
        XCTAssertEqual(MintQuoteDomain.normalizedOfferDescription("Cof\u{0}fee"), "Coffee")
        XCTAssertNil(MintQuoteDomain.normalizedOfferDescription(" \r\n\t "))
        XCTAssertEqual(MintQuoteDomain.normalizedOfferDescription(String(repeating: "a", count: 650)), String(repeating: "a", count: 640))
    }

    func testBolt12MintDescriptionAdvertisementFailsClosed() {
        XCTAssertFalse(MintQuoteDomain.reportsBolt12MintDescription(methods: []))
        XCTAssertFalse(MintQuoteDomain.reportsBolt12MintDescription(methods: [
            (method: .bolt12, description: nil),
        ]))
        XCTAssertFalse(MintQuoteDomain.reportsBolt12MintDescription(methods: [
            (method: .bolt12, description: false),
        ]))
        XCTAssertFalse(MintQuoteDomain.reportsBolt12MintDescription(methods: [
            (method: .bolt11, description: true),
        ]))
        XCTAssertTrue(MintQuoteDomain.reportsBolt12MintDescription(methods: [
            (method: .bolt11, description: false),
            (method: .bolt12, description: true),
        ]))
        // Any bolt12 unit advertising true is enough.
        XCTAssertTrue(MintQuoteDomain.reportsBolt12MintDescription(methods: [
            (method: .bolt12, description: false),
            (method: .bolt12, description: true),
        ]))
    }

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

/// Opt-in against a real mint. Uses a fresh unfunded wallet and creates quotes only.
@MainActor
final class LiveBolt12DescriptionTests: XCTestCase {
    func testLiveOffersEncodeDescriptionsAndPreserveAmounts() async throws {
        let url = try XCTUnwrap(ProcessInfo.processInfo.environment["BOLT12_DESCRIPTION_MINT_URL"],
                                "Set BOLT12_DESCRIPTION_MINT_URL to enable this test")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        weak var releasedDatabase: LifecycleSafeWalletDatabase?
        do {
            let database = try LifecycleSafeWalletDatabase(filePath: directory.appendingPathComponent("wallet.sqlite").path)
            releasedDatabase = database
            let repository = try WalletRepository(mnemonic: generateMnemonic(), store: customWalletStore(db: database))
            try await repository.createWallet(mintUrl: MintUrl(url: url), unit: .sat, targetProofCount: nil)
            let mint = MintInfo(url: url, name: "Live test mint", isActive: true, balance: 0)
            let service = LightningService(walletRepository: { repository }, walletDatabase: { database }, getActiveMint: { mint })
            let plain = try await service.createMintQuote(amount: nil, method: .bolt12)
            XCTAssertNil(try decodeInvoice(invoiceStr: plain.request).amountMsat)

            for description in ["Coffee tips\nThank you ☕", "Updated coffee note", String(repeating: "a", count: 640)] {
                let quote = try await service.createMintQuote(amount: nil, method: .bolt12, description: description)
                let decoded = try decodeInvoice(invoiceStr: quote.request)
                XCTAssertEqual(decoded.description, description.replacingOccurrences(of: "\n", with: " "))
                XCTAssertNil(decoded.amountMsat)
                XCTAssertNotEqual(quote.request, plain.request)
            }
            for description in ["Fixed amount coffee", "Edited fixed amount", nil] {
                let quote = try await service.createMintQuote(amount: 21, method: .bolt12, description: description)
                let decoded = try decodeInvoice(invoiceStr: quote.request)
                XCTAssertEqual(decoded.amountMsat, 21_000)
                if let description { XCTAssertEqual(decoded.description, description.replacingOccurrences(of: "\n", with: " ")) }
                else { XCTAssertEqual(decoded.description, try decodeInvoice(invoiceStr: plain.request).description) }
            }
        }
        // Let native writer teardown finish in this test, not in the next one.
        let deadline = Date().addingTimeInterval(3)
        while releasedDatabase != nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(releasedDatabase)
    }

    override func setUpWithError() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["BOLT12_DESCRIPTION_MINT_URL"] == nil,
                      "Opt-in live mint quote test")
    }
}
