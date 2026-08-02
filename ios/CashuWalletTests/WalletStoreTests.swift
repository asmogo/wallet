import XCTest
@testable import CashuWallet

@MainActor
final class CashuRequestStoreBoundaryTests: XCTestCase {
    func testResetForWalletBoundaryClearsRequestsAndDefaults() {
        let suiteName = "CashuRequestStoreBoundaryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CashuRequestStore(userDefaults: defaults)
        _ = store.createNew(mints: ["https://mint.example.com"], encoded: "creqAexample")
        XCTAssertFalse(store.requests.isEmpty)
        XCTAssertNotNil(store.currentRequestId)

        store.resetForWalletBoundary()

        XCTAssertTrue(store.requests.isEmpty)
        XCTAssertNil(store.currentRequestId)
        XCTAssertNil(defaults.data(forKey: StorageKeys.cashuRequests))
        XCTAssertNil(defaults.string(forKey: StorageKeys.cashuRequestsCurrentId))
        // A fresh store over the same defaults must not resurrect anything.
        XCTAssertTrue(CashuRequestStore(userDefaults: defaults).requests.isEmpty)
    }
}

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

    func testSaveAndLoadBalancesByUnit() {
        store.saveBalancesByUnit(["sat": 21, "usd": 500])
        XCTAssertEqual(store.loadBalancesByUnit(), ["sat": 21, "usd": 500])
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
        let token = PendingToken(
            tokenId: "id1",
            token: "cashuAtoken",
            amount: 21,
            fee: 1,
            date: Date(),
            mintUrl: "https://mint.example.com",
            memo: nil,
            unit: "usd"
        )
        store.savePendingTokens([token])
        let loaded = store.loadPendingTokens()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].tokenId, "id1")
        XCTAssertEqual(loaded[0].amount, 21)
        XCTAssertEqual(loaded[0].unit, "usd")
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
            claimedDate: Date(),
            unit: "eur"
        )
        store.saveClaimedTokens([claimed])
        let loaded = store.loadClaimedTokens()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].tokenId, "claimed1")
        XCTAssertEqual(loaded[0].amount, 30)
        XCTAssertEqual(loaded[0].unit, "eur")
    }

    func testLegacyPendingTokenWithoutUnitDefaultsToSatWhenTokenIsUndecodable() throws {
        let json = """
        {
          "tokenId": "legacy",
          "token": "legacy-token",
          "amount": 10,
          "fee": 0,
          "date": 0,
          "mintUrl": "https://mint.example.com"
        }
        """

        let decoded = try JSONDecoder().decode(PendingToken.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.unit, "sat")
    }

    func testLegacyPendingTokenWithoutUnitRecoversUnitFromToken() throws {
        // NUT-00 V3 token for {"token":[],"unit":"usd"}. It has no proofs on
        // purpose: unit migration must not depend on proof expansion.
        let token = "cashuAeyJ0b2tlbiI6W10sInVuaXQiOiJ1c2QifQ=="
        let json = """
        {
          "tokenId": "legacy-usd",
          "token": "\(token)",
          "amount": 10,
          "fee": 0,
          "date": 0,
          "mintUrl": "https://mint.example.com"
        }
        """

        let decoded = try JSONDecoder().decode(PendingToken.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.unit, "usd")
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

    func testSaveAndLoadMintKeysetRefreshTimestamps() {
        let ts: TimeInterval = 1_700_000_000
        store.saveMintKeysetRefreshTimestamps(["https://mint.example.com": ts])
        XCTAssertEqual(store.loadMintKeysetRefreshTimestamps()["https://mint.example.com"], ts)
    }

    func testWalletStartupPolicyRefreshesMissingOrStaleKeysets() {
        let now: TimeInterval = 10_000
        XCTAssertTrue(WalletStartupPolicy.shouldRefreshKeysets(lastRefresh: nil, now: now))
        XCTAssertTrue(WalletStartupPolicy.shouldRefreshKeysets(
            lastRefresh: now - WalletStartupPolicy.keysetRefreshInterval,
            now: now
        ))
        XCTAssertFalse(WalletStartupPolicy.shouldRefreshKeysets(
            lastRefresh: now - WalletStartupPolicy.keysetRefreshInterval + 1,
            now: now
        ))
        XCTAssertTrue(WalletStartupPolicy.shouldRefreshKeysets(lastRefresh: now + 1, now: now))
    }

    func testWalletStartupPolicyKeepsPublishedCacheVisibleOnRuntimeFailure() {
        XCTAssertFalse(WalletStartupPolicy.needsOnboardingAfterRuntimeFailure(
            cachedWalletPublished: true
        ))
        XCTAssertTrue(WalletStartupPolicy.needsOnboardingAfterRuntimeFailure(
            cachedWalletPublished: false
        ))
    }

    func testIncompleteICloudRestoreSuppressesBackupWrites() {
        XCTAssertFalse(ICloudRestorePolicy.shouldPerformBackup(restoreIncomplete: true))
        XCTAssertTrue(ICloudRestorePolicy.shouldPerformBackup(restoreIncomplete: false))
    }

    func testIncompleteICloudRestoreRequiresOnboardingWithStoredSeed() {
        XCTAssertTrue(ICloudRestorePolicy.needsOnboarding(
            hasStoredMnemonic: true,
            restoreIncomplete: true,
            onboardingCompleted: true
        ))
        XCTAssertFalse(ICloudRestorePolicy.needsOnboarding(
            hasStoredMnemonic: true,
            restoreIncomplete: false,
            onboardingCompleted: true
        ))
        XCTAssertTrue(ICloudRestorePolicy.needsOnboarding(
            hasStoredMnemonic: false,
            restoreIncomplete: false,
            onboardingCompleted: false
        ))
    }

    func testIncompleteOnboardingRequiresOnboardingWithStoredSeed() {
        // Killed mid-onboarding: seed persisted, completion marker false.
        XCTAssertTrue(ICloudRestorePolicy.needsOnboarding(
            hasStoredMnemonic: true,
            restoreIncomplete: false,
            onboardingCompleted: false
        ))
    }

    func testOnboardingCompletionMarkerRoundTrips() {
        let suiteName = "OnboardingCompletionStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(OnboardingCompletionState.hasMarker(defaults: defaults))
        XCTAssertFalse(OnboardingCompletionState.isCompleted(defaults: defaults))

        OnboardingCompletionState.setCompleted(false, defaults: defaults)
        XCTAssertTrue(OnboardingCompletionState.hasMarker(defaults: defaults))
        XCTAssertFalse(OnboardingCompletionState.isCompleted(defaults: defaults))

        OnboardingCompletionState.setCompleted(true, defaults: defaults)
        XCTAssertTrue(OnboardingCompletionState.hasMarker(defaults: defaults))
        XCTAssertTrue(OnboardingCompletionState.isCompleted(defaults: defaults))

        OnboardingCompletionState.clear(defaults: defaults)
        XCTAssertFalse(OnboardingCompletionState.hasMarker(defaults: defaults))
    }

    func testIncompleteICloudRestoreOverridesPublishedCacheAfterRuntimeFailure() {
        XCTAssertTrue(WalletStartupPolicy.needsOnboardingAfterRuntimeFailure(
            cachedWalletPublished: true,
            iCloudRestoreIncomplete: true
        ))
    }

    func testIncompleteICloudRestoreStatePersistsUntilCleared() {
        let suiteName = "ICloudRestoreStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(ICloudRestoreState.isIncomplete(defaults: defaults))

        ICloudRestoreState.setIncomplete(true, defaults: defaults)
        XCTAssertTrue(ICloudRestoreState.isIncomplete(
            defaults: UserDefaults(suiteName: suiteName)!
        ))

        ICloudRestoreState.setIncomplete(false, defaults: defaults)
        XCTAssertFalse(ICloudRestoreState.isIncomplete(defaults: defaults))
    }

    // MARK: - removeAllWalletData

    func testRemoveAllWalletDataClearsMints() {
        store.saveMints([mint("https://mint.example.com", name: "X")])
        store.removeAllWalletData()
        XCTAssertTrue(store.loadMints().isEmpty)
    }

    func testRemoveAllWalletDataClearsBalancesByUnit() {
        store.saveBalancesByUnit(["sat": 21, "eur": 100])
        store.removeAllWalletData()
        XCTAssertTrue(store.loadBalancesByUnit().isEmpty)
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

    func testRemoveAllWalletDataClearsMintKeysetRefreshTimestamps() {
        store.saveMintKeysetRefreshTimestamps(["https://mint.example.com": 123])
        store.removeAllWalletData()
        XCTAssertTrue(store.loadMintKeysetRefreshTimestamps().isEmpty)
    }

    func testRemoveAllWalletDataClearsCashuRequestKeys() {
        let storage = InMemoryStorage()
        try! storage.set("payload", forKey: StorageKeys.cashuRequests)
        try! storage.set("current", forKey: StorageKeys.cashuRequestsCurrentId)
        try! storage.set(["id1"], forKey: StorageKeys.cashuRequestsProcessedNIP17Ids)

        WalletStore(storage: storage).removeAllWalletData()

        XCTAssertFalse(storage.exists(forKey: StorageKeys.cashuRequests))
        XCTAssertFalse(storage.exists(forKey: StorageKeys.cashuRequestsCurrentId))
        XCTAssertFalse(storage.exists(forKey: StorageKeys.cashuRequestsProcessedNIP17Ids))
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
            memo: nil,
            unit: "sat"
        )
    }
}

@MainActor
final class CashuRequestStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "CashuRequestStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCreateNewPreservesEmbeddedPaymentRequestId() {
        let store = CashuRequestStore(userDefaults: defaults)

        let request = store.createNew(
            id: "request-id",
            amount: 42,
            unit: "sat",
            mints: ["https://mint.example.com"],
            memo: "coffee",
            encoded: "creqAtest"
        )

        XCTAssertEqual(request.id, "request-id")
        XCTAssertEqual(store.currentRequestId, "request-id")
        XCTAssertEqual(store.request(withId: "request-id")?.encoded, "creqAtest")

        store.attachPayment(requestId: "request-id", transactionId: "tx-1", amount: 42)
        XCTAssertEqual(store.request(withId: "request-id")?.receivedPayments.first?.transactionId, "tx-1")

        let reloaded = CashuRequestStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.currentRequestId, "request-id")
        XCTAssertEqual(reloaded.request(withId: "request-id")?.receivedPayments.first?.amount, 42)
    }

    func testUpdateReparameterizesInPlaceWithoutNewRow() {
        let store = CashuRequestStore(userDefaults: defaults)

        _ = store.createNew(id: "request-id", encoded: "creqAamountless")
        store.attachPayment(requestId: "request-id", transactionId: "tx-1", amount: 21)

        store.update(
            id: "request-id",
            amount: 42,
            unit: "eur",
            mints: ["https://mint.example.com"],
            encoded: "creqAamounted"
        )

        XCTAssertEqual(store.requests.count, 1)
        let updated = store.request(withId: "request-id")
        XCTAssertEqual(updated?.amount, 42)
        XCTAssertEqual(updated?.unit, "eur")
        XCTAssertEqual(updated?.mints, ["https://mint.example.com"])
        XCTAssertEqual(updated?.encoded, "creqAamounted")
        XCTAssertEqual(updated?.receivedPayments.first?.transactionId, "tx-1")
        XCTAssertEqual(store.currentRequestId, "request-id")

        let reloaded = CashuRequestStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.requests.count, 1)
        XCTAssertEqual(reloaded.request(withId: "request-id")?.encoded, "creqAamounted")
        XCTAssertEqual(reloaded.request(withId: "request-id")?.unit, "eur")
    }
}
