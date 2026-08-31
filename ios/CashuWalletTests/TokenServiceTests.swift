import XCTest
@testable import CashuWallet

@MainActor
final class TokenServiceTests: XCTestCase {
    private var service: TokenService!

    override func setUp() {
        super.setUp()
        service = TokenService(
            walletRepository: { nil },
            getActiveMint: { nil }
        )
    }

    // MARK: - sendTokens / receiveTokens — wallet not initialised

    func testSendTokensThrowsWhenNoRepository() async {
        do {
            _ = try await service.sendTokens(amount: 10)
            XCTFail("Expected WalletError.notInitialized")
        } catch let err as WalletError {
            guard case .notInitialized = err else {
                XCTFail("Expected .notInitialized, got \(err)"); return
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testSendTokensThrowsWhenNoActiveMintAndNoRepository() async {
        do {
            _ = try await service.sendTokens(amount: 1, mintUrl: nil)
            XCTFail("Expected WalletError.notInitialized")
        } catch let err as WalletError {
            guard case .notInitialized = err else {
                XCTFail("Expected .notInitialized, got \(err)"); return
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testReceiveTokensThrowsNotInitializedWhenNoRepository() async {
        // The repository guard runs before Token.decode, so the error must be
        // WalletError.notInitialized — not a CDK decode error.
        do {
            _ = try await service.receiveTokens(tokenString: "cashuAtest")
            XCTFail("Expected WalletError.notInitialized")
        } catch let err as WalletError {
            guard case .notInitialized = err else {
                XCTFail("Expected .notInitialized, got \(err)"); return
            }
        } catch {
            XCTFail("Expected WalletError.notInitialized, got \(error)")
        }
    }

    // MARK: - calculateReceiveFee — wallet not initialised

    func testCalculateReceiveFeeThrowsNotInitializedWhenNoRepository() async {
        do {
            _ = try await service.calculateReceiveFee(tokenString: "cashuAtest")
            XCTFail("Expected WalletError.notInitialized")
        } catch let err as WalletError {
            guard case .notInitialized = err else {
                XCTFail("Expected .notInitialized, got \(err)"); return
            }
        } catch {
            XCTFail("Expected WalletError.notInitialized, got \(error)")
        }
    }

    // MARK: - checkTokenSpendable — wallet not initialised

    func testCheckTokenSpendableReturnsFalseWhenNoRepository() async {
        let result = await service.checkTokenSpendable(
            token: "cashuAtest",
            mintUrl: "https://mint.example.com"
        )
        XCTAssertFalse(result)
    }

    // MARK: - isLoading state

    func testIsLoadingFalseInitially() {
        XCTAssertFalse(service.isLoading)
    }

    func testClearStateResetsLoading() {
        service.isLoading = true
        service.clearState()
        XCTAssertFalse(service.isLoading, "clearState must reset isLoading to false")
    }

    // MARK: - P2PK pubkey validation (normalizedP2PKPubkey)
    //
    // Tested directly: `sendTokens` only reaches this validator after the
    // repository guard and `getWallet`, both of which need a live mint, so
    // driving it through `sendTokens` with a nil repository never exercises
    // these branches — it always short-circuits with WalletError.notInitialized.

    func testNormalizedP2PKReturnsNilForNil() throws {
        XCTAssertNil(try service.normalizedP2PKPubkey(nil))
    }

    func testNormalizedP2PKReturnsNilForEmpty() throws {
        XCTAssertNil(try service.normalizedP2PKPubkey(""))
    }

    func testNormalizedP2PKReturnsNilForWhitespace() throws {
        XCTAssertNil(try service.normalizedP2PKPubkey("   "))
    }

    func testNormalizedP2PKPrefixesBare64HexKey() throws {
        let bare = String(repeating: "a", count: 64)
        XCTAssertEqual(try service.normalizedP2PKPubkey(bare), "02" + bare)
    }

    func testNormalizedP2PKAcceptsCompressed02Key() throws {
        let key = "02" + String(repeating: "b", count: 64)
        XCTAssertEqual(try service.normalizedP2PKPubkey(key), key)
    }

    func testNormalizedP2PKAcceptsCompressed03Key() throws {
        let key = "03" + String(repeating: "c", count: 64)
        XCTAssertEqual(try service.normalizedP2PKPubkey(key), key)
    }

    func testNormalizedP2PKLowercasesInput() throws {
        let key = "02" + String(repeating: "AB", count: 32)
        XCTAssertEqual(try service.normalizedP2PKPubkey(key), key.lowercased())
    }

    func testNormalizedP2PKThrowsOnNonHex() {
        XCTAssertThrowsError(try service.normalizedP2PKPubkey("not-a-pubkey")) { error in
            XCTAssertEqual(error as? TokenServiceError, .invalidP2PKPubkey)
        }
    }

    func testNormalizedP2PKThrowsOnTooShortHex() {
        XCTAssertThrowsError(try service.normalizedP2PKPubkey("02aabb")) { error in
            XCTAssertEqual(error as? TokenServiceError, .invalidP2PKPubkey)
        }
    }

    func testNormalizedP2PKThrowsOnWrongPrefix() {
        // 66 hex chars but an invalid SEC1 prefix (04 = uncompressed, not allowed).
        let key = "04" + String(repeating: "a", count: 64)
        XCTAssertThrowsError(try service.normalizedP2PKPubkey(key)) { error in
            XCTAssertEqual(error as? TokenServiceError, .invalidP2PKPubkey)
        }
    }

    func testNormalizedP2PKThrowsOnBare64NonHex() {
        // 64 chars but contains non-hex 'g' — must not be auto-prefixed.
        let key = String(repeating: "g", count: 64)
        XCTAssertThrowsError(try service.normalizedP2PKPubkey(key)) { error in
            XCTAssertEqual(error as? TokenServiceError, .invalidP2PKPubkey)
        }
    }

    // MARK: - TokenServiceError descriptions

    func testInvalidP2PKPubkeyErrorHasDescription() {
        let error = TokenServiceError.invalidP2PKPubkey
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
    }

    func testMissingP2PKSigningKeyErrorHasDescription() {
        let error = TokenServiceError.missingP2PKSigningKey
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
    }

    // MARK: - isCounterDesyncError (stale NUT-13 keyset counter detection)
    //
    // The receive retry loop only fires when this returns true, so it must match
    // every wording mints use for the same "you asked me to re-sign an output I
    // already signed" rejection — notably macadamia's "Blinded Message is already
    // signed", which the original "duplicate outputs"-only check missed (the bug).

    private struct StubError: Error, CustomStringConvertible {
        let description: String
    }

    func testCounterDesyncMatchesBlindedMessageAlreadySigned() {
        XCTAssertTrue(TokenService.isCounterDesyncError(
            StubError(description: "Blinded Message is already signed")))
    }

    func testCounterDesyncMatchesDuplicateOutputs() {
        XCTAssertTrue(TokenService.isCounterDesyncError(
            StubError(description: "NUT03: Duplicate outputs")))
    }

    func testCounterDesyncMatchesOutputsAlreadySigned() {
        XCTAssertTrue(TokenService.isCounterDesyncError(
            StubError(description: "outputs already signed")))
    }

    func testCounterDesyncIsCaseInsensitive() {
        XCTAssertTrue(TokenService.isCounterDesyncError(
            StubError(description: "BLINDED MESSAGE IS ALREADY SIGNED")))
    }

    func testCounterDesyncDoesNotMatchAlreadySpent() {
        // "already spent" / "already redeemed" is a real, distinct terminal error
        // — it must NOT be treated as a recoverable counter desync.
        XCTAssertFalse(TokenService.isCounterDesyncError(
            StubError(description: "Token already spent")))
        XCTAssertFalse(TokenService.isCounterDesyncError(
            StubError(description: "proofs are already redeemed")))
    }

    func testCounterDesyncDoesNotMatchUnrelatedErrors() {
        XCTAssertFalse(TokenService.isCounterDesyncError(
            StubError(description: "insufficient funds")))
        XCTAssertFalse(TokenService.isCounterDesyncError(
            StubError(description: "Could not connect to the server.")))
    }
}

@MainActor
final class SettingsManagerP2PKStorageTests: XCTestCase {
    private let privateKeyHex = String(repeating: "0", count: 63) + "1"
    private let publicKeyHex = "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

    func testGenerateDoesNotPublishMetadataWhenSecureWriteFails() {
        let storage = InMemoryStorage()
        let settingsStore = SettingsStore(storage: storage)
        let secureStorage = P2PKTestSecureStorage()
        secureStorage.failSaves = true
        let manager = SettingsManager(
            settingsStore: settingsStore,
            secureStorage: secureStorage
        )

        XCTAssertThrowsError(try manager.generateP2PKKey()) { error in
            XCTAssertEqual(error as? SettingsFeatureError, .secureStorageUnavailable)
        }
        XCTAssertTrue(manager.p2pkKeys.isEmpty)
        XCTAssertTrue(settingsStore.p2pkKeys.isEmpty)
        XCTAssertTrue(secureStorage.secrets.isEmpty)
    }

    func testImportWritesSecureSecretBeforePublishingSanitizedMetadata() throws {
        let storage = InMemoryStorage()
        let settingsStore = SettingsStore(storage: storage)
        let secureStorage = P2PKTestSecureStorage()
        let manager = SettingsManager(
            settingsStore: settingsStore,
            secureStorage: secureStorage
        )

        try manager.importP2PKNsec(nsecForPrivateKeyOne())

        let key = try XCTUnwrap(manager.p2pkKeys.first)
        XCTAssertEqual(key.privateKey, privateKeyHex)
        XCTAssertEqual(
            secureStorage.secrets[secureStorageKey(for: key.id)],
            privateKeyHex
        )
        XCTAssertEqual(settingsStore.p2pkKeys.first?.privateKey, "")
        XCTAssertTrue(manager.isKnownP2PKPublicKey(publicKeyHex))
    }

    func testMetadataWriteFailureRollsBackNewSecureSecretAndPublishedState() throws {
        let storage = P2PKFailingStorage()
        let settingsStore = SettingsStore(storage: storage)
        let secureStorage = P2PKTestSecureStorage()
        let manager = SettingsManager(
            settingsStore: settingsStore,
            secureStorage: secureStorage
        )
        storage.failP2PKWrites = true

        XCTAssertThrowsError(try manager.importP2PKNsec(nsecForPrivateKeyOne())) { error in
            XCTAssertEqual(error as? SettingsFeatureError, .settingsPersistenceUnavailable)
        }
        XCTAssertTrue(manager.p2pkKeys.isEmpty)
        XCTAssertTrue(secureStorage.secrets.isEmpty)
        XCTAssertTrue(settingsStore.p2pkKeys.isEmpty)
    }

    func testFailedMetadataRepairDoesNotDeleteExistingSecureSecret() throws {
        let id = UUID()
        let storage = P2PKFailingStorage()
        let settingsStore = SettingsStore(storage: storage)
        try settingsStore.saveP2PKKeys([
            P2PKKey(
                id: id,
                publicKey: publicKeyHex,
                privateKey: "",
                used: false,
                usedCount: 0
            )
        ])
        let secureStorage = P2PKTestSecureStorage()
        let storageKey = secureStorageKey(for: id)
        try secureStorage.saveSecret(privateKeyHex, forKey: storageKey)
        secureStorage.failLoads = true
        let manager = SettingsManager(
            settingsStore: settingsStore,
            secureStorage: secureStorage
        )
        storage.failP2PKWrites = true

        XCTAssertThrowsError(try manager.importP2PKNsec(nsecForPrivateKeyOne())) { error in
            XCTAssertEqual(error as? SettingsFeatureError, .settingsPersistenceUnavailable)
        }
        XCTAssertEqual(secureStorage.secrets[storageKey], privateKeyHex)
        XCTAssertFalse(manager.isKnownP2PKPublicKey(publicKeyHex))
    }

    func testFailedLegacyMigrationPreservesOnlyCopyAcrossMetadataUpdates() throws {
        let id = UUID()
        let storage = InMemoryStorage()
        try storage.set(
            [legacyRecord(id: id, privateKey: privateKeyHex)],
            forKey: StorageKeys.p2pkKeys
        )
        let settingsStore = SettingsStore(storage: storage)
        let secureStorage = P2PKTestSecureStorage()
        secureStorage.failSaves = true

        let manager = SettingsManager(
            settingsStore: settingsStore,
            secureStorage: secureStorage
        )

        XCTAssertEqual(manager.p2pkKeys.first?.privateKey, privateKeyHex)
        XCTAssertTrue(manager.isKnownP2PKPublicKey(publicKeyHex))
        XCTAssertEqual(settingsStore.p2pkKeys.first?.privateKey, privateKeyHex)

        manager.setP2PKKeyNickname("Legacy", for: id)

        let persisted = try XCTUnwrap(settingsStore.p2pkKeys.first)
        XCTAssertEqual(persisted.nickname, "Legacy")
        XCTAssertEqual(persisted.privateKey, privateKeyHex)
    }

    func testSuccessfulLegacyMigrationMovesSecretAndScrubsMetadata() throws {
        let id = UUID()
        let storage = InMemoryStorage()
        try storage.set(
            [legacyRecord(id: id, privateKey: privateKeyHex)],
            forKey: StorageKeys.p2pkKeys
        )
        let settingsStore = SettingsStore(storage: storage)
        let secureStorage = P2PKTestSecureStorage()

        let manager = SettingsManager(
            settingsStore: settingsStore,
            secureStorage: secureStorage
        )

        XCTAssertEqual(secureStorage.secrets[secureStorageKey(for: id)], privateKeyHex)
        XCTAssertEqual(settingsStore.p2pkKeys.first?.privateKey, "")
        XCTAssertTrue(manager.isKnownP2PKPublicKey(publicKeyHex))
    }

    func testKnownKeyCheckRejectsMetadataWithoutUsableSecret() throws {
        let storage = InMemoryStorage()
        let settingsStore = SettingsStore(storage: storage)
        try settingsStore.saveP2PKKeys([
            P2PKKey(
                publicKey: publicKeyHex,
                privateKey: "",
                used: false,
                usedCount: 0
            )
        ])
        let manager = SettingsManager(
            settingsStore: settingsStore,
            secureStorage: P2PKTestSecureStorage()
        )

        XCTAssertFalse(manager.isKnownP2PKPublicKey(publicKeyHex))
        XCTAssertFalse(manager.allP2PKSigningKeyHexes().contains(privateKeyHex))
    }

    func testImportRepairsMatchingMetadataOnlyKeyWithoutDuplicatingIt() throws {
        let id = UUID()
        let storage = InMemoryStorage()
        let settingsStore = SettingsStore(storage: storage)
        try settingsStore.saveP2PKKeys([
            P2PKKey(
                id: id,
                publicKey: publicKeyHex,
                privateKey: "",
                used: true,
                usedCount: 2,
                nickname: "Recovered"
            )
        ])
        let secureStorage = P2PKTestSecureStorage()
        let manager = SettingsManager(
            settingsStore: settingsStore,
            secureStorage: secureStorage
        )
        XCTAssertFalse(manager.isKnownP2PKPublicKey(publicKeyHex))

        try manager.importP2PKNsec(nsecForPrivateKeyOne())

        XCTAssertEqual(manager.p2pkKeys.count, 1)
        let repaired = try XCTUnwrap(manager.p2pkKeys.first)
        XCTAssertEqual(repaired.id, id)
        XCTAssertEqual(repaired.usedCount, 2)
        XCTAssertEqual(repaired.nickname, "Recovered")
        XCTAssertEqual(secureStorage.secrets[secureStorageKey(for: id)], privateKeyHex)
        XCTAssertTrue(manager.isKnownP2PKPublicKey(publicKeyHex))
    }

    func testRemovalJournalWriteFailureKeepsPublishedAndSecureKey() throws {
        let storage = P2PKFailingStorage()
        let settingsStore = SettingsStore(storage: storage)
        let secureStorage = P2PKTestSecureStorage()
        let manager = SettingsManager(
            settingsStore: settingsStore,
            secureStorage: secureStorage
        )
        try manager.importP2PKNsec(nsecForPrivateKeyOne())
        let key = try XCTUnwrap(manager.p2pkKeys.first)
        storage.failP2PKJournalWrites = true

        XCTAssertThrowsError(try manager.removeP2PKKey(key)) { error in
            XCTAssertEqual(error as? SettingsFeatureError, .keyRemovalFailed)
        }

        XCTAssertEqual(manager.p2pkKeys, [key])
        XCTAssertEqual(settingsStore.p2pkKeys.first?.privateKey, "")
        XCTAssertEqual(
            secureStorage.secrets[secureStorageKey(for: key.id)],
            privateKeyHex
        )
        XCTAssertTrue(manager.isKnownP2PKPublicKey(publicKeyHex))
        XCTAssertTrue(settingsStore.p2pkPendingDeletionIDs.isEmpty)
        XCTAssertNil(secureStorage.secrets[secureRemovalFallbackKey(for: key.id)])
    }

    func testRemovalSecureDeleteFailureKeepsDurableFallbackAndPublishedKey() throws {
        let storage = P2PKFailingStorage()
        let settingsStore = SettingsStore(storage: storage)
        let secureStorage = P2PKTestSecureStorage()
        let manager = SettingsManager(
            settingsStore: settingsStore,
            secureStorage: secureStorage
        )
        try manager.importP2PKNsec(nsecForPrivateKeyOne())
        let key = try XCTUnwrap(manager.p2pkKeys.first)
        secureStorage.failDeletes = true

        XCTAssertThrowsError(try manager.removeP2PKKey(key)) { error in
            XCTAssertEqual(error as? SettingsFeatureError, .keyRemovalFailed)
        }

        XCTAssertEqual(manager.p2pkKeys, [key])
        XCTAssertEqual(settingsStore.p2pkKeys.first?.privateKey, "")
        XCTAssertEqual(
            secureStorage.secrets[secureStorageKey(for: key.id)],
            privateKeyHex
        )
        XCTAssertEqual(
            secureStorage.secrets[secureRemovalFallbackKey(for: key.id)],
            privateKeyHex
        )
        XCTAssertEqual(settingsStore.p2pkPendingDeletionIDs, [key.id])
        XCTAssertTrue(manager.isKnownP2PKPublicKey(publicKeyHex))
    }

    func testRemovalFinalMetadataWriteFailureRestoresRecoverableKey() throws {
        let storage = P2PKFailingStorage()
        let settingsStore = SettingsStore(storage: storage)
        let secureStorage = P2PKTestSecureStorage()
        let manager = SettingsManager(
            settingsStore: settingsStore,
            secureStorage: secureStorage
        )
        try manager.importP2PKNsec(nsecForPrivateKeyOne())
        let key = try XCTUnwrap(manager.p2pkKeys.first)
        storage.failP2PKWriteNumbers = [2]

        XCTAssertThrowsError(try manager.removeP2PKKey(key)) { error in
            XCTAssertEqual(error as? SettingsFeatureError, .keyRemovalFailed)
        }

        XCTAssertEqual(manager.p2pkKeys, [key])
        XCTAssertEqual(settingsStore.p2pkKeys.first?.privateKey, "")
        XCTAssertEqual(
            secureStorage.secrets[secureStorageKey(for: key.id)],
            privateKeyHex
        )
        XCTAssertNil(secureStorage.secrets[secureRemovalFallbackKey(for: key.id)])
        XCTAssertTrue(settingsStore.p2pkPendingDeletionIDs.isEmpty)

        let reloaded = SettingsManager(
            settingsStore: settingsStore,
            secureStorage: secureStorage
        )
        XCTAssertTrue(reloaded.isKnownP2PKPublicKey(publicKeyHex))
        XCTAssertEqual(reloaded.p2pkKeys.first?.privateKey, privateKeyHex)
        XCTAssertEqual(settingsStore.p2pkKeys.first?.privateKey, "")
    }

    func testInterruptedRemovalRecoveryRestoresSecureSecretWithoutUsingMetadata() throws {
        let id = UUID()
        let storage = InMemoryStorage()
        let settingsStore = SettingsStore(storage: storage)
        try settingsStore.saveP2PKKeys([
            P2PKKey(
                id: id,
                publicKey: publicKeyHex,
                privateKey: "",
                used: false,
                usedCount: 0
            )
        ])
        try settingsStore.saveP2PKPendingDeletionIDs([id])
        let secureStorage = P2PKTestSecureStorage()
        try secureStorage.saveSecret(privateKeyHex, forKey: secureRemovalFallbackKey(for: id))

        let manager = SettingsManager(
            settingsStore: settingsStore,
            secureStorage: secureStorage
        )

        XCTAssertEqual(secureStorage.secrets[secureStorageKey(for: id)], privateKeyHex)
        XCTAssertNil(secureStorage.secrets[secureRemovalFallbackKey(for: id)])
        XCTAssertTrue(settingsStore.p2pkPendingDeletionIDs.isEmpty)
        XCTAssertTrue(manager.isP2PKKeyUsable(id))
        XCTAssertEqual(settingsStore.p2pkKeys.first?.privateKey, "")
    }

    func testInterruptedCommittedRemovalRecoveryDeletesSecureFallback() throws {
        let id = UUID()
        let storage = InMemoryStorage()
        let settingsStore = SettingsStore(storage: storage)
        try settingsStore.saveP2PKPendingDeletionIDs([id])
        let secureStorage = P2PKTestSecureStorage()
        try secureStorage.saveSecret(privateKeyHex, forKey: secureRemovalFallbackKey(for: id))

        _ = SettingsManager(
            settingsStore: settingsStore,
            secureStorage: secureStorage
        )

        XCTAssertTrue(secureStorage.secrets.isEmpty)
        XCTAssertTrue(settingsStore.p2pkPendingDeletionIDs.isEmpty)
        XCTAssertTrue(settingsStore.p2pkKeys.isEmpty)
    }

    private func nsecForPrivateKeyOne() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        bytes[31] = 1
        return try Bech32.encode(hrp: "nsec", data: Data(bytes))
    }

    private func secureStorageKey(for id: UUID) -> String {
        "settings.p2pk.\(id.uuidString).privateKey"
    }

    private func secureRemovalFallbackKey(for id: UUID) -> String {
        "\(secureStorageKey(for: id)).removalFallback"
    }

    private func legacyRecord(id: UUID, privateKey: String) -> P2PKLegacyTestRecord {
        P2PKLegacyTestRecord(
            id: id,
            publicKey: publicKeyHex,
            privateKey: privateKey,
            used: false,
            usedCount: 0,
            nickname: nil
        )
    }
}

private enum P2PKTestFailure: Error {
    case expected
}

private final class P2PKTestSecureStorage: SecureStorageProtocol {
    private(set) var secrets: [String: String] = [:]
    var failLoads = false
    var failSaves = false
    var failDeletes = false

    func saveSecret(_ secret: String, forKey key: String) throws {
        if failSaves { throw P2PKTestFailure.expected }
        secrets[key] = secret
    }

    func loadSecret(forKey key: String) throws -> String? {
        if failLoads { throw P2PKTestFailure.expected }
        return secrets[key]
    }

    func deleteSecret(forKey key: String) throws {
        if failDeletes { throw P2PKTestFailure.expected }
        secrets.removeValue(forKey: key)
    }

    func hasSecret(forKey key: String) -> Bool {
        secrets[key] != nil
    }
}

private final class P2PKFailingStorage: StorageProtocol {
    private let backing = InMemoryStorage()
    var failP2PKWrites = false
    var failP2PKWriteNumbers: Set<Int> = []
    var failP2PKJournalWrites = false
    private(set) var p2pkWriteCount = 0

    func set<T: Codable>(_ value: T, forKey key: String) throws {
        if key == StorageKeys.p2pkPendingDeletionIDs, failP2PKJournalWrites {
            throw P2PKTestFailure.expected
        }
        if key == StorageKeys.p2pkKeys {
            p2pkWriteCount += 1
            if failP2PKWrites || failP2PKWriteNumbers.contains(p2pkWriteCount) {
                throw P2PKTestFailure.expected
            }
        }
        try backing.set(value, forKey: key)
    }

    func get<T: Codable>(forKey key: String) throws -> T? {
        try backing.get(forKey: key)
    }

    func remove(forKey key: String) throws {
        try backing.remove(forKey: key)
    }

    func exists(forKey key: String) -> Bool {
        backing.exists(forKey: key)
    }

    func keys(withPrefix prefix: String) -> [String] {
        backing.keys(withPrefix: prefix)
    }
}

private struct P2PKLegacyTestRecord: Codable {
    let id: UUID
    let publicKey: String
    let privateKey: String
    let used: Bool
    let usedCount: Int
    let nickname: String?
}

@MainActor
final class WalletOperationCoordinatorTests: XCTestCase {
    private enum TestFailure: Error { case expected }

    func testReceiveFeeAndRedemptionNeverOverlap() async throws {
        let coordinator = WalletOperationCoordinator(watchdogThreshold: 0)
        let probe = ConcurrencyProbe()

        let tasks = (0..<12).map { index in
            Task {
                try await coordinator.perform(kind: index.isMultiple(of: 2) ? .receiveFee : .receive) {
                    await probe.enter()
                    try await Task.sleep(nanoseconds: 5_000_000)
                    await probe.leave()
                }
            }
        }

        for task in tasks {
            try await task.value
        }

        let maximumConcurrentCount = await probe.maximumConcurrentCount()
        XCTAssertEqual(maximumConcurrentCount, 1)
    }

    func testCriticalOperationKindsShareOneExecutionLane() async throws {
        let coordinator = WalletOperationCoordinator(watchdogThreshold: 0)
        let probe = ConcurrencyProbe()
        let kinds: [WalletOperationCoordinator.Kind] = [
            .send, .receive, .melt, .mint, .restore, .balance, .history, .recovery,
        ]

        let tasks = kinds.map { kind in
            Task {
                try await coordinator.perform(kind: kind) {
                    await probe.enter()
                    try await Task.sleep(nanoseconds: 5_000_000)
                    await probe.leave()
                }
            }
        }

        for task in tasks {
            try await task.value
        }

        let maximumConcurrentCount = await probe.maximumConcurrentCount()
        XCTAssertEqual(maximumConcurrentCount, 1)
    }

    func testThrownOperationReleasesPermit() async throws {
        let coordinator = WalletOperationCoordinator(watchdogThreshold: 0)

        do {
            _ = try await coordinator.perform(kind: .receive) {
                throw TestFailure.expected
            }
            XCTFail("Expected the first operation to throw")
        } catch TestFailure.expected {
            // Expected.
        }

        let value = try await coordinator.perform(kind: .send) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testCancellationWhileWaitingRemovesWaiter() async throws {
        let coordinator = WalletOperationCoordinator(watchdogThreshold: 0)
        let gate = AsyncTestGate()

        let active = Task {
            try await coordinator.perform(kind: .receive) {
                await gate.wait()
            }
        }
        let receiveBecameActive = await eventually { await coordinator.snapshot().activeKind == .receive }
        XCTAssertTrue(receiveBecameActive)

        let waiting = Task {
            try await coordinator.perform(kind: .send) { 1 }
        }
        let waiterWasQueued = await eventually { await coordinator.snapshot().waitingCount == 1 }
        XCTAssertTrue(waiterWasQueued)

        waiting.cancel()
        do {
            _ = try await waiting.value
            XCTFail("Expected the waiting operation to be cancelled")
        } catch is CancellationError {
            // Expected.
        }
        let waiterWasRemoved = await eventually { await coordinator.snapshot().waitingCount == 0 }
        XCTAssertTrue(waiterWasRemoved)

        await gate.open()
        try await active.value
    }

    func testCancellationDoesNotUnlockExecutingNativeWork() async throws {
        let coordinator = WalletOperationCoordinator(watchdogThreshold: 0)
        let nativeGate = AsyncTestGate()
        let secondStarted = BooleanProbe()

        let first = Task {
            try await coordinator.perform(kind: .melt) {
                // CheckedContinuation intentionally ignores Swift cancellation,
                // matching the iOS UniFFI bridge described by the regression.
                await nativeGate.wait()
                return 1
            }
        }
        let meltBecameActive = await eventually { await coordinator.snapshot().activeKind == .melt }
        XCTAssertTrue(meltBecameActive)
        first.cancel()

        let second = Task {
            try await coordinator.perform(kind: .receive) {
                await secondStarted.setTrue()
                return 2
            }
        }

        let secondWasQueued = await eventually { await coordinator.snapshot().waitingCount == 1 }
        XCTAssertTrue(secondWasQueued)
        let didStartBeforeNativeReturn = await secondStarted.value()
        XCTAssertFalse(didStartBeforeNativeReturn)

        await nativeGate.open()
        let firstValue = try await first.value
        let secondValue = try await second.value
        XCTAssertEqual(firstValue, 1)
        XCTAssertEqual(secondValue, 2)
        let didStartAfterNativeReturn = await secondStarted.value()
        XCTAssertTrue(didStartAfterNativeReturn)
    }

    func testPassiveMaintenanceSkipsWhileUserOperationIsActive() async throws {
        let coordinator = WalletOperationCoordinator(watchdogThreshold: 0)
        let gate = AsyncTestGate()

        let active = Task {
            try await coordinator.perform(kind: .send) {
                await gate.wait()
            }
        }
        let sendBecameActive = await eventually { await coordinator.snapshot().activeKind == .send }
        XCTAssertTrue(sendBecameActive)

        let performed = try await coordinator.performIfIdle(kind: .quotePoll) {
            XCTFail("Passive operation should have been skipped")
        }
        XCTAssertFalse(performed)

        await gate.open()
        try await active.value
    }

    func testUserOperationRunsBeforeQueuedMaintenance() async throws {
        let coordinator = WalletOperationCoordinator(watchdogThreshold: 0)
        let gate = AsyncTestGate()
        let order = StringRecorder()

        let active = Task {
            try await coordinator.perform(kind: .restore) {
                await gate.wait()
            }
        }
        let restoreBecameActive = await eventually { await coordinator.snapshot().activeKind == .restore }
        XCTAssertTrue(restoreBecameActive)

        let maintenance = Task {
            try await coordinator.perform(kind: .history, priority: .maintenance) {
                await order.append("maintenance")
            }
        }
        let user = Task {
            try await coordinator.perform(kind: .receive) {
                await order.append("user")
            }
        }
        let bothWereQueued = await eventually { await coordinator.snapshot().waitingCount == 2 }
        XCTAssertTrue(bothWereQueued)

        await gate.open()
        try await active.value
        try await user.value
        try await maintenance.value

        let recordedOrder = await order.values()
        XCTAssertEqual(recordedOrder, ["user", "maintenance"])
    }

    func testMeltWorkflowCannotBeInterleavedByPollingOrHistory() async throws {
        let coordinator = WalletOperationCoordinator(watchdogThreshold: 0)
        let nativeGate = AsyncTestGate()
        let order = StringRecorder()

        let melt = Task {
            try await coordinator.perform(kind: .melt) {
                await order.append("prepare")
                await nativeGate.wait()
                await order.append("confirm")
            }
        }
        let meltBecameActive = await eventually { await coordinator.snapshot().activeKind == .melt }
        XCTAssertTrue(meltBecameActive)

        let pollRan = try await coordinator.performIfIdle(kind: .quotePoll) {
            await order.append("poll")
        }
        XCTAssertFalse(pollRan)

        let history = Task {
            try await coordinator.perform(kind: .history) {
                await order.append("history")
            }
        }
        let historyWasQueued = await eventually { await coordinator.snapshot().waitingCount == 1 }
        XCTAssertTrue(historyWasQueued)

        await nativeGate.open()
        try await melt.value
        try await history.value

        let recordedOrder = await order.values()
        XCTAssertEqual(recordedOrder, ["prepare", "confirm", "history"])
    }

    func testCompensatedMeltRequiresFreshQuoteAndAllowsRetry() {
        let error = MeltPaymentRecoveryError.compensated(operationID: "operation")
        let message = error.walletMessage

        XCTAssertTrue(error.retryRequiresFreshQuote)
        if case .retryable = message.recoverability {
            // Expected.
        } else {
            XCTFail("A compensated payment should permit a fresh-quote retry")
        }
    }

    func testUnresolvedMeltBlocksRetryAndKeepsQuoteForReconciliation() {
        let error = MeltPaymentRecoveryError.unresolved(
            quoteID: "quote",
            mintURL: "https://mint.invalid",
            operationID: "operation"
        )
        let message = error.walletMessage

        XCTAssertFalse(error.retryRequiresFreshQuote)
        XCTAssertEqual(error.unresolvedQuote?.id, "quote")
        if case .terminal = message.recoverability {
            // Expected: terminal means no immediate retry CTA, not that the
            // payment is known to have failed.
        } else {
            XCTFail("An unknown payment outcome must block immediate retry")
        }
        XCTAssertEqual(error.walletOperationFailureOutcome, .ambiguousFailure)
    }

    private func eventually(
        attempts: Int = 200,
        condition: () async -> Bool
    ) async -> Bool {
        for _ in 0..<attempts {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return false
    }
}

private actor AsyncTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor ConcurrencyProbe {
    private var activeCount = 0
    private var maximumCount = 0

    func enter() {
        activeCount += 1
        maximumCount = max(maximumCount, activeCount)
    }

    func leave() {
        activeCount -= 1
    }

    func maximumConcurrentCount() -> Int { maximumCount }
}

private actor BooleanProbe {
    private var storedValue = false
    func setTrue() { storedValue = true }
    func value() -> Bool { storedValue }
}

private actor StringRecorder {
    private var storedValues: [String] = []
    func append(_ value: String) { storedValues.append(value) }
    func values() -> [String] { storedValues }
}
