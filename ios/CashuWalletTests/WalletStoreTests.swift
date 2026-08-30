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

    func testRemoveAllWalletDataClearsRetiredPendingTokenKeys() {
        let storage = InMemoryStorage()
        try! storage.set(["token"], forKey: StorageKeys.Retired.pendingTokens)
        try! storage.set(["token"], forKey: StorageKeys.Retired.claimedTokens)

        WalletStore(storage: storage).removeAllWalletData()

        XCTAssertFalse(storage.exists(forKey: StorageKeys.Retired.pendingTokens))
        XCTAssertFalse(storage.exists(forKey: StorageKeys.Retired.claimedTokens))
    }

    func testPurgeRetiredKeysRemovesCDK17Stores() {
        let storage = InMemoryStorage()
        for key in StorageKeys.Retired.all {
            try! storage.set("x", forKey: key)
        }
        try! storage.set("keep", forKey: StorageKeys.savedTokens)

        WalletStore(storage: storage).purgeRetiredKeys()

        for key in StorageKeys.Retired.all {
            XCTAssertFalse(storage.exists(forKey: key), "\(key) should be purged")
        }
        XCTAssertTrue(storage.exists(forKey: StorageKeys.savedTokens))
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

    // MARK: - Helpers

    private func mint(_ url: String, name: String) -> MintInfo {
        MintInfo(url: url, name: name, description: nil, isActive: true, balance: 0)
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

final class WalletReplacementSafetyTests: XCTestCase {
    private enum TestError: Error {
        case forcedMoveFailure
    }

    private final class SecureStorageSpy: SecureStorageProtocol {
        var secrets: [String: String] = [:]

        func saveSecret(_ secret: String, forKey key: String) throws {
            secrets[key] = secret
        }

        func loadSecret(forKey key: String) throws -> String? {
            secrets[key]
        }

        func deleteSecret(forKey key: String) throws {
            secrets.removeValue(forKey: key)
        }

        func hasSecret(forKey key: String) -> Bool {
            secrets[key] != nil
        }
    }

    func testMnemonicRollbackRestoresPreviousSeed() throws {
        let storage = SecureStorageSpy()
        storage.secrets[StorageKeys.Secure.mnemonic] = "replacement seed"

        try WalletMnemonicRollback.restore(
            previousMnemonic: "original seed",
            secureStorage: storage
        )

        XCTAssertEqual(
            storage.secrets[StorageKeys.Secure.mnemonic],
            "original seed"
        )
    }

    func testMnemonicRollbackDeletesReplacementWhenNoSeedExisted() throws {
        let storage = SecureStorageSpy()
        storage.secrets[StorageKeys.Secure.mnemonic] = "replacement seed"

        try WalletMnemonicRollback.restore(
            previousMnemonic: nil,
            secureStorage: storage
        )

        XCTAssertNil(storage.secrets[StorageKeys.Secure.mnemonic])
    }

    func testPartialBackupFailureRestoresEveryMovedOriginal() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("first.db")
        let second = directory.appendingPathComponent("second.db")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        var forwardMoveCount = 0
        let operations = WalletReplacementFileOperations(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            moveItem: { source, destination in
                if !source.lastPathComponent.hasSuffix(".backup") {
                    forwardMoveCount += 1
                    if forwardMoveCount == 2 {
                        throw TestError.forcedMoveFailure
                    }
                }
                try FileManager.default.moveItem(at: source, to: destination)
            },
            removeItem: { try FileManager.default.removeItem(at: $0) }
        )

        XCTAssertThrowsError(
            try WalletReplacementFiles.backup(
                urls: [first, second],
                operations: operations,
                backupURL: { $0.appendingPathExtension("backup") }
            )
        )
        XCTAssertEqual(try Data(contentsOf: first), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("second".utf8))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: first.appendingPathExtension("backup").path
            )
        )
    }

    func testMissingBackupNeverDeletesReplacementDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("wallet.db")
        let missingBackup = directory.appendingPathComponent("wallet.db.backup")
        try Data("replacement".utf8).write(to: original)

        XCTAssertThrowsError(
            try WalletReplacementFiles.restore(
                [WalletFileBackup(originalURL: original, backupURL: missingBackup)],
                displacedURL: { $0.appendingPathExtension("displaced") }
            )
        )
        XCTAssertEqual(try Data(contentsOf: original), Data("replacement".utf8))
    }

    func testRestorePreflightsEveryBackupBeforeMovingAnyDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstOriginal = directory.appendingPathComponent("first.db")
        let firstMissingBackup = directory.appendingPathComponent("first.db.backup")
        let secondOriginal = directory.appendingPathComponent("second.db")
        let secondBackup = directory.appendingPathComponent("second.db.backup")
        try Data("new first".utf8).write(to: firstOriginal)
        try Data("new second".utf8).write(to: secondOriginal)
        try Data("old second".utf8).write(to: secondBackup)

        XCTAssertThrowsError(
            try WalletReplacementFiles.restore(
                [
                    WalletFileBackup(
                        originalURL: firstOriginal,
                        backupURL: firstMissingBackup
                    ),
                    WalletFileBackup(
                        originalURL: secondOriginal,
                        backupURL: secondBackup
                    ),
                ],
                displacedURL: { $0.appendingPathExtension("displaced") }
            )
        )
        XCTAssertEqual(try Data(contentsOf: secondOriginal), Data("new second".utf8))
        XCTAssertEqual(try Data(contentsOf: secondBackup), Data("old second".utf8))
    }

    func testRollbackRemovesDatabaseCreatedWithoutAnOriginalBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let newlyCreatedDatabase = directory.appendingPathComponent("wallet.db")
        try Data("replacement".utf8).write(to: newlyCreatedDatabase)

        try WalletReplacementFiles.removeUnbackedReplacements(
            at: [newlyCreatedDatabase],
            backups: []
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: newlyCreatedDatabase.path)
        )
    }

    func testFailedRestoreMovePutsReplacementDatabaseBack() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("wallet.db")
        let backup = directory.appendingPathComponent("wallet.db.backup")
        try Data("replacement".utf8).write(to: original)
        try Data("original".utf8).write(to: backup)

        var moveCount = 0
        let operations = WalletReplacementFileOperations(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            moveItem: { source, destination in
                moveCount += 1
                if moveCount == 2 {
                    throw TestError.forcedMoveFailure
                }
                try FileManager.default.moveItem(at: source, to: destination)
            },
            removeItem: { try FileManager.default.removeItem(at: $0) }
        )

        XCTAssertThrowsError(
            try WalletReplacementFiles.restore(
                [WalletFileBackup(originalURL: original, backupURL: backup)],
                operations: operations,
                displacedURL: { $0.appendingPathExtension("displaced") }
            )
        )
        XCTAssertEqual(try Data(contentsOf: original), Data("replacement".utf8))
        XCTAssertEqual(try Data(contentsOf: backup), Data("original".utf8))
    }

    func testLaterRestoreFailureRestoresEveryReplacementAndBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstOriginal = directory.appendingPathComponent("first.db")
        let firstBackup = directory.appendingPathComponent("first.db.backup")
        let secondOriginal = directory.appendingPathComponent("second.db")
        let secondBackup = directory.appendingPathComponent("second.db.backup")
        let firstDisplaced = firstOriginal.appendingPathExtension("displaced")
        let secondDisplaced = secondOriginal.appendingPathExtension("displaced")
        try Data("new first".utf8).write(to: firstOriginal)
        try Data("old first".utf8).write(to: firstBackup)
        try Data("new second".utf8).write(to: secondOriginal)
        try Data("old second".utf8).write(to: secondBackup)

        var backupMoveCount = 0
        let operations = WalletReplacementFileOperations(
            fileExists: { FileManager.default.fileExists(atPath: $0.path) },
            moveItem: { source, destination in
                if source.pathExtension == "backup" {
                    backupMoveCount += 1
                    if backupMoveCount == 2 {
                        throw TestError.forcedMoveFailure
                    }
                }
                try FileManager.default.moveItem(at: source, to: destination)
            },
            removeItem: { try FileManager.default.removeItem(at: $0) }
        )

        XCTAssertThrowsError(
            try WalletReplacementFiles.restore(
                [
                    WalletFileBackup(
                        originalURL: firstOriginal,
                        backupURL: firstBackup
                    ),
                    WalletFileBackup(
                        originalURL: secondOriginal,
                        backupURL: secondBackup
                    ),
                ],
                operations: operations,
                displacedURL: { $0.appendingPathExtension("displaced") }
            )
        )

        XCTAssertEqual(backupMoveCount, 2)
        XCTAssertEqual(try Data(contentsOf: firstOriginal), Data("new first".utf8))
        XCTAssertEqual(try Data(contentsOf: firstBackup), Data("old first".utf8))
        XCTAssertEqual(try Data(contentsOf: secondOriginal), Data("new second".utf8))
        XCTAssertEqual(try Data(contentsOf: secondBackup), Data("old second".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstDisplaced.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondDisplaced.path))
    }
}
