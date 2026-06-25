import XCTest
@testable import CashuWallet

@MainActor
final class MintServiceTests: XCTestCase {
    private var service: MintService!

    override func setUp() {
        super.setUp()
        service = MintService(
            walletRepository: { nil },
            walletStore: WalletStore(storage: InMemoryStorage())
        )
    }

    // MARK: - validateMintUrl

    func testValidHttpsUrlAccepted() {
        XCTAssertNil(service.validateMintUrl("https://mint.example.com"))
    }

    func testValidHttpLocalhostAccepted() {
        XCTAssertNil(service.validateMintUrl("http://localhost:3338"))
    }

    func testTrailingSlashNormalizationBeforeValidation() {
        XCTAssertNil(service.validateMintUrl("https://mint.example.com/"))
    }

    func testMissingHostReturnsError() {
        XCTAssertNotNil(service.validateMintUrl("not-a-url-at-all"))
    }

    func testFtpSchemeReturnsError() {
        XCTAssertNotNil(service.validateMintUrl("ftp://mint.example.com"))
    }

    // MARK: - isMintTracked

    func testIsMintTrackedFalseWhenEmpty() {
        XCTAssertFalse(service.isMintTracked(url: "https://mint.example.com"))
    }

    func testIsMintTrackedTrueAfterLoad() {
        let storage = InMemoryStorage()
        let ws = WalletStore(storage: storage)
        ws.saveMints([mint("https://mint.example.com", name: "Test")])

        let s = MintService(walletRepository: { nil }, walletStore: ws)
        s.loadCachedMints()
        XCTAssertTrue(s.isMintTracked(url: "https://mint.example.com"))
    }

    func testIsMintTrackedNormalizesTrailingSlash() {
        let storage = InMemoryStorage()
        let ws = WalletStore(storage: storage)
        ws.saveMints([mint("https://mint.example.com", name: "Test")])

        let s = MintService(walletRepository: { nil }, walletStore: ws)
        s.loadCachedMints()
        XCTAssertTrue(s.isMintTracked(url: "https://mint.example.com/"))
    }

    // MARK: - loadCachedMints / activeMint

    func testLoadCachedMintsSetsFirstAsActive() {
        let storage = InMemoryStorage()
        let ws = WalletStore(storage: storage)
        let m = mint("https://mint.example.com", name: "First")
        ws.saveMints([m])
        ws.activeMintURL = m.url

        let s = MintService(walletRepository: { nil }, walletStore: ws)
        s.loadCachedMints()
        XCTAssertEqual(s.activeMint?.url, "https://mint.example.com")
    }

    func testLoadCachedMintsFallsBackToFirstWhenNoActiveSaved() {
        let storage = InMemoryStorage()
        let ws = WalletStore(storage: storage)
        ws.saveMints([
            mint("https://mint1.example.com", name: "Mint 1"),
            mint("https://mint2.example.com", name: "Mint 2"),
        ])

        let s = MintService(walletRepository: { nil }, walletStore: ws)
        s.loadCachedMints()
        XCTAssertEqual(s.activeMint?.url, "https://mint1.example.com")
    }

    // MARK: - updateMintBalances

    func testUpdateMintBalanceUpdatesMatchingURL() {
        service.mints = [mint("https://mint.example.com", name: "X")]
        service.updateMintBalance(url: "https://mint.example.com", balance: 100)
        XCTAssertEqual(service.mints[0].balance, 100)
    }

    func testUpdateMintBalanceIgnoresUnknownURL() {
        service.mints = [mint("https://mint.example.com", name: "X")]
        service.updateMintBalance(url: "https://other.example.com", balance: 999)
        XCTAssertEqual(service.mints[0].balance, 0)
    }

    func testUpdateMintBalanceNormalizesTrailingSlash() {
        service.mints = [mint("https://mint.example.com", name: "X")]
        service.updateMintBalance(url: "https://mint.example.com/", balance: 42)
        XCTAssertEqual(service.mints[0].balance, 42)
    }

    func testUpdateMintBalancesUpdatesActiveMintBalance() {
        let m = mint("https://mint.example.com", name: "Active")
        service.mints = [m]
        service.activeMint = m
        service.updateMintBalance(url: "https://mint.example.com", balance: 77)
        XCTAssertEqual(service.activeMint?.balance, 77)
    }

    func testUpdateMintBalancesNoOpWhenUnchanged() {
        var m = mint("https://mint.example.com", name: "X")
        m.balance = 50
        service.mints = [m]
        let before = service.mints[0].balance
        service.updateMintBalance(url: "https://mint.example.com", balance: 50)
        XCTAssertEqual(service.mints[0].balance, before)
    }

    func testUpdateMultipleBalancesInOneCall() {
        service.mints = [
            mint("https://mint1.example.com", name: "A"),
            mint("https://mint2.example.com", name: "B"),
        ]
        service.updateMintBalances([
            "https://mint1.example.com": 10,
            "https://mint2.example.com": 20,
        ])
        XCTAssertEqual(service.mints[0].balance, 10)
        XCTAssertEqual(service.mints[1].balance, 20)
    }

    // MARK: - saveMints / persistence

    func testSaveMintsPersistsToStore() {
        let storage = InMemoryStorage()
        let ws = WalletStore(storage: storage)
        let s = MintService(walletRepository: { nil }, walletStore: ws)
        s.mints = [mint("https://mint.example.com", name: "Saved")]
        s.saveMints()

        let s2 = MintService(walletRepository: { nil }, walletStore: ws)
        s2.loadCachedMints()
        XCTAssertEqual(s2.mints.count, 1)
        XCTAssertEqual(s2.mints[0].name, "Saved")
    }

    // MARK: - Helpers

    private func mint(_ url: String, name: String) -> MintInfo {
        MintInfo(url: url, name: name, description: nil, isActive: true, balance: 0)
    }
}
