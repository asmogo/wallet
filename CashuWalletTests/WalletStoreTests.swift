import XCTest
@testable import CashuWallet

final class WalletStoreTests: XCTestCase {
    private var store: WalletStore!

    override func setUp() {
        super.setUp()
        store = WalletStore(storage: InMemoryStorage())
    }

    // MARK: - Mints

    func testLoadMintsEmptyByDefault() {
        XCTAssertTrue(store.loadMints().isEmpty)
    }

    func testSaveAndLoadSingleMint() {
        let mint = mint("https://mint.example.com", name: "Test Mint")
        store.saveMints([mint])
        let loaded = store.loadMints()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].url, "https://mint.example.com")
        XCTAssertEqual(loaded[0].name, "Test Mint")
    }

    func testSaveMintsOverwritesPrevious() {
        store.saveMints([mint("https://mint1.example.com", name: "Mint 1")])
        store.saveMints([mint("https://mint2.example.com", name: "Mint 2")])
        let loaded = store.loadMints()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].url, "https://mint2.example.com")
    }

    func testSaveAndLoadMultipleMints() {
        let mints = [
            mint("https://mint1.example.com", name: "Mint 1"),
            mint("https://mint2.example.com", name: "Mint 2"),
        ]
        store.saveMints(mints)
        XCTAssertEqual(store.loadMints().count, 2)
    }

    // MARK: - Active Mint URL

    func testActiveMintURLNilByDefault() {
        XCTAssertNil(store.activeMintURL)
    }

    func testSetAndGetActiveMintURL() {
        store.activeMintURL = "https://mint.example.com"
        XCTAssertEqual(store.activeMintURL, "https://mint.example.com")
    }

    func testClearActiveMintURL() {
        store.activeMintURL = "https://mint.example.com"
        store.activeMintURL = nil
        XCTAssertNil(store.activeMintURL)
    }

    // MARK: - Pending Tokens (Outgoing)

    func testLoadPendingTokensEmptyByDefault() {
        XCTAssertTrue(store.loadPendingTokens().isEmpty)
    }

    func testSaveAndLoadPendingToken() {
        store.savePendingTokens([pendingToken(id: "id1", amount: 21)])
        let loaded = store.loadPendingTokens()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].tokenId, "id1")
        XCTAssertEqual(loaded[0].amount, 21)
    }

    func testSavePendingTokensPreservesMultiple() {
        store.savePendingTokens([
            pendingToken(id: "a", amount: 10),
            pendingToken(id: "b", amount: 20),
        ])
        XCTAssertEqual(store.loadPendingTokens().count, 2)
    }

    // MARK: - Pending Receive Tokens (Incoming)

    func testLoadPendingReceiveTokensEmptyByDefault() {
        XCTAssertTrue(store.loadPendingReceiveTokens().isEmpty)
    }

    func testSaveAndLoadPendingReceiveToken() {
        let token = PendingReceiveToken(
            tokenId: "recv1",
            token: "cashuAtoken",
            amount: 50,
            date: Date(),
            mintUrl: "https://mint.example.com"
        )
        store.savePendingReceiveTokens([token])
        let loaded = store.loadPendingReceiveTokens()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].tokenId, "recv1")
    }

    // MARK: - Claimed Tokens

    func testLoadClaimedTokensEmptyByDefault() {
        XCTAssertTrue(store.loadClaimedTokens().isEmpty)
    }

    func testSaveAndLoadClaimedTokens() {
        let claimed = ClaimedToken(
            tokenId: "claimed1",
            token: "cashuAtoken",
            amount: 30,
            fee: 1,
            date: Date(),
            mintUrl: "https://mint.example.com",
            memo: "test",
            claimedDate: Date()
        )
        store.saveClaimedTokens([claimed])
        let loaded = store.loadClaimedTokens()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].tokenId, "claimed1")
        XCTAssertEqual(loaded[0].amount, 30)
    }

    // MARK: - Saved Tokens (txId → encoded token)

    func testSaveAndLoadSavedToken() {
        store.saveSavedTokens(["tx1": "cashuAtoken123"])
        XCTAssertEqual(store.loadSavedTokens()["tx1"], "cashuAtoken123")
    }

    func testSavedTokensEmptyByDefault() {
        XCTAssertTrue(store.loadSavedTokens().isEmpty)
    }

    // MARK: - Payment Preimages

    func testLoadPaymentPreimagesEmptyByDefault() {
        XCTAssertTrue(store.loadPaymentPreimages().isEmpty)
    }

    func testSaveAndLoadPreimage() {
        store.savePaymentPreimages(["quoteId1": "deadbeef"])
        XCTAssertEqual(store.loadPaymentPreimages()["quoteId1"], "deadbeef")
    }

    // MARK: - Melt Quote Fees

    func testMeltQuoteFeesEmptyByDefault() {
        XCTAssertTrue(store.loadMeltQuoteFees().isEmpty)
    }

    func testSaveAndLoadMeltQuoteFees() {
        store.saveMeltQuoteFees(["q1": 5, "q2": 10])
        let loaded = store.loadMeltQuoteFees()
        XCTAssertEqual(loaded["q1"], 5)
        XCTAssertEqual(loaded["q2"], 10)
    }

    // MARK: - Mint Quote Timestamps

    func testMintQuoteTimestampsEmptyByDefault() {
        XCTAssertTrue(store.loadMintQuoteTimestamps().isEmpty)
    }

    func testSaveAndLoadMintQuoteTimestamps() {
        let ts: TimeInterval = 1_700_000_000
        store.saveMintQuoteTimestamps(["quoteA": ts])
        XCTAssertEqual(store.loadMintQuoteTimestamps()["quoteA"], ts)
    }

    // MARK: - removeAllWalletData

    func testRemoveAllWalletDataClearsMints() {
        store.saveMints([mint("https://mint.example.com", name: "X")])
        store.removeAllWalletData()
        XCTAssertTrue(store.loadMints().isEmpty)
    }

    func testRemoveAllWalletDataClearsPendingTokens() {
        store.savePendingTokens([pendingToken(id: "x", amount: 1)])
        store.removeAllWalletData()
        XCTAssertTrue(store.loadPendingTokens().isEmpty)
    }

    func testRemoveAllWalletDataClearsPreimages() {
        store.savePaymentPreimages(["q": "pre"])
        store.removeAllWalletData()
        XCTAssertTrue(store.loadPaymentPreimages().isEmpty)
    }

    func testRemoveAllWalletDataClearsSavedTokens() {
        store.saveSavedTokens(["tx": "cashuAtoken"])
        store.removeAllWalletData()
        XCTAssertTrue(store.loadSavedTokens().isEmpty)
    }

    // MARK: - Legacy key migration

    func testLegacyMintKeyMigratesOnLoad() {
        let legacyStorage = InMemoryStorage()
        let legacyMint = mint("https://legacy.example.com", name: "Legacy")
        try! legacyStorage.set([legacyMint], forKey: StorageKeys.Legacy.mints)

        let storeWithLegacy = WalletStore(storage: legacyStorage)
        let loaded = storeWithLegacy.loadMints()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].url, "https://legacy.example.com")
    }

    func testLegacyPendingTokensMigratesOnLoad() {
        let legacyStorage = InMemoryStorage()
        let token = pendingToken(id: "legacy1", amount: 99)
        try! legacyStorage.set([token], forKey: StorageKeys.Legacy.pendingTokens)

        let storeWithLegacy = WalletStore(storage: legacyStorage)
        let loaded = storeWithLegacy.loadPendingTokens()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].tokenId, "legacy1")
    }

    // MARK: - Helpers

    private func mint(_ url: String, name: String) -> MintInfo {
        MintInfo(url: url, name: name, description: nil, isActive: true, balance: 0)
    }

    private func pendingToken(id: String, amount: UInt64) -> PendingToken {
        PendingToken(
            tokenId: id,
            token: "cashuAtoken\(id)",
            amount: amount,
            fee: 0,
            date: Date(),
            mintUrl: "https://mint.example.com",
            memo: nil
        )
    }
}
