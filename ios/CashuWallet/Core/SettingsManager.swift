import SwiftUI
import P256K

// MARK: - Settings Manager

@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    private let settingsStore: SettingsStore
    private let secureStorage: SecureStorageProtocol
    /// Legacy UserDefaults secrets that must remain encoded until their secure
    /// storage migration succeeds. This is intentionally separate from the
    /// published model so metadata updates cannot accidentally erase them.
    private var pendingLegacyP2PKSecrets: [UUID: String]
    private var suppressPaymentRequestSideEffects = false
    
    static let supportedFiatCurrencies: [String] = [
        "USD", "EUR", "AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "GBP",
        "HKD", "HUF", "ILS", "INR", "JPY", "KRW", "MXN", "NZD", "NOK", "PLN",
        "RUB", "SEK", "SGD", "THB", "TRY", "ZAR"
    ]

    static let defaultNostrRelays: [String] = [
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://relay.primal.net"
    ]

    // MARK: - Published Settings
    
    @Published var useBitcoinSymbol: Bool {
        didSet { settingsStore.useBitcoinSymbol = useBitcoinSymbol }
    }
    
    @Published var showFiatBalance: Bool {
        didSet { 
            settingsStore.showFiatBalance = showFiatBalance
            guard showFiatBalance != oldValue else { return }
            // Enable/disable price service based on this setting
            PriceService.shared.isEnabled = showFiatBalance
        }
    }

    @Published var bitcoinPriceCurrency: String {
        didSet {
            settingsStore.bitcoinPriceCurrency = bitcoinPriceCurrency
            guard bitcoinPriceCurrency != oldValue else { return }
            PriceService.shared.currencyCode = bitcoinPriceCurrency
        }
    }

    @Published var checkSentTokens: Bool {
        didSet {
            settingsStore.checkSentTokens = checkSentTokens
        }
    }

    @Published var autoPasteEcashReceive: Bool {
        didSet {
            settingsStore.autoPasteEcashReceive = autoPasteEcashReceive
        }
    }

    @Published var useWebsockets: Bool {
        didSet {
            settingsStore.useWebsockets = useWebsockets
        }
    }

    @Published var showP2PKButtonInDrawer: Bool {
        didSet {
            settingsStore.showP2PKButtonInDrawer = showP2PKButtonInDrawer
        }
    }

    @Published private(set) var p2pkKeys: [P2PKKey]

    @Published var checkIncomingInvoices: Bool {
        didSet {
            settingsStore.checkIncomingInvoices = checkIncomingInvoices
            NPCService.shared.applyPollingPreferences()
        }
    }

    @Published var periodicallyCheckIncomingInvoices: Bool {
        didSet {
            settingsStore.periodicallyCheckIncomingInvoices = periodicallyCheckIncomingInvoices
            NPCService.shared.applyPollingPreferences()
        }
    }

    /// Master switch for the NUT-18 Cashu Request listener (incoming ecash over
    /// Nostr). Off tears the relay subscription down entirely.
    @Published var enablePaymentRequests: Bool {
        didSet {
            settingsStore.enablePaymentRequests = enablePaymentRequests
            guard !suppressPaymentRequestSideEffects else { return }
            guard enablePaymentRequests != oldValue else { return }
            if enablePaymentRequests {
                CashuRequestListener.shared.requestStart()
            } else {
                CashuRequestListener.shared.requestStop()
            }
        }
    }

    /// Whether incoming Cashu Request payments are redeemed without asking.
    /// Off routes each payment through the approval queue (receive screen)
    /// instead — nothing is dropped, every payment just needs a tap.
    @Published var receivePaymentRequestsAutomatically: Bool {
        didSet {
            settingsStore.receivePaymentRequestsAutomatically = receivePaymentRequestsAutomatically
            guard !suppressPaymentRequestSideEffects else { return }
            guard receivePaymentRequestsAutomatically, !oldValue else { return }
            // Payments held while auto-claim was off can claim silently now
            // (known mints only — unknown mints always need approval).
            Task { @MainActor in
                await CashuRequestListener.shared.claimEligibleHeldPayments()
            }
        }
    }

    @Published var nostrRelays: [String] {
        didSet {
            settingsStore.nostrRelays = nostrRelays
        }
    }

    @Published var nostrMintBackupEnabled: Bool {
        didSet {
            settingsStore.nostrMintBackupEnabled = nostrMintBackupEnabled
        }
    }

    @Published var amountDisplayPrimary: AmountDisplayPrimary {
        didSet {
            settingsStore.amountDisplayPrimary = amountDisplayPrimary.rawValue
        }
    }

    /// Home and history-row amount ordering. Payment entry keeps [amountDisplayPrimary].
    @Published var homeBalancePrimary: AmountDisplayPrimary {
        didSet {
            settingsStore.homeBalancePrimary = homeBalancePrimary.rawValue
        }
    }

    @Published var appLockEnabled: Bool {
        didSet {
            settingsStore.appLockEnabled = appLockEnabled
            guard appLockEnabled != oldValue else { return }
            AppLockManager.shared.setEnabled(appLockEnabled)
        }
    }

    @Published var sentryEnabled: Bool {
        didSet {
            settingsStore.sentryEnabled = sentryEnabled
            guard sentryEnabled != oldValue else { return }
            if sentryEnabled {
                SentryService.initialize()
            } else {
                SentryService.shutdown()
            }
        }
    }

    // MARK: - Initialization
    
    init(
        settingsStore: SettingsStore = .shared,
        secureStorage: SecureStorageProtocol = KeychainService()
    ) {
        self.settingsStore = settingsStore
        self.secureStorage = secureStorage
        let loadedP2PKKeys = Self.loadP2PKKeys(
            settingsStore: settingsStore,
            secureStorage: secureStorage
        )
        self.pendingLegacyP2PKSecrets = loadedP2PKKeys.pendingLegacySecrets
        self.useBitcoinSymbol = settingsStore.useBitcoinSymbol
        self.showFiatBalance = settingsStore.showFiatBalance
        self.bitcoinPriceCurrency = settingsStore.bitcoinPriceCurrency
        self.checkSentTokens = settingsStore.checkSentTokens
        self.autoPasteEcashReceive = settingsStore.autoPasteEcashReceive
        self.useWebsockets = settingsStore.useWebsockets
        self.showP2PKButtonInDrawer = settingsStore.showP2PKButtonInDrawer
        self.p2pkKeys = loadedP2PKKeys.keys
        self.checkIncomingInvoices = settingsStore.checkIncomingInvoices
        self.periodicallyCheckIncomingInvoices = settingsStore.periodicallyCheckIncomingInvoices
        self.enablePaymentRequests = settingsStore.enablePaymentRequests
        self.receivePaymentRequestsAutomatically = settingsStore.receivePaymentRequestsAutomatically
        self.nostrRelays = settingsStore.nostrRelays
        self.nostrMintBackupEnabled = settingsStore.nostrMintBackupEnabled
        self.amountDisplayPrimary = AmountDisplayPrimary(rawValue: settingsStore.amountDisplayPrimary) ?? .fiat
        self.homeBalancePrimary = AmountDisplayPrimary(rawValue: settingsStore.homeBalancePrimary) ?? .sats
        self.appLockEnabled = settingsStore.appLockEnabled
        self.sentryEnabled = settingsStore.sentryEnabled

        if loadedP2PKKeys.encounteredLegacySecrets {
            do {
                try settingsStore.saveP2PKKeys(
                    p2pkKeys,
                    preservingLegacySecrets: pendingLegacyP2PKSecrets
                )
            } catch {
                // The existing record still contains every legacy secret, so a
                // failed cleanup is safe to retry on the next metadata change.
                AppLogger.security.error(
                    "Failed to finalize P2PK secure-storage migration error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                )
            }
        }
        
        let priceService = PriceService.shared
        if !priceService.isEnabled, priceService.currencyCode != bitcoinPriceCurrency {
            priceService.currencyCode = bitcoinPriceCurrency
        }
        if !showFiatBalance, priceService.isEnabled {
            priceService.isEnabled = false
        }
    }

    func addNostrRelay(_ relay: String) -> Bool {
        let normalized = relay.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        guard !nostrRelays.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) else { return false }
        nostrRelays.append(normalized)
        return true
    }

    func removeNostrRelay(_ relay: String) {
        nostrRelays.removeAll { $0 == relay }
    }

    func resetNostrRelaysToDefault() {
        nostrRelays = Self.defaultNostrRelays
    }

    @discardableResult
    func generateP2PKKey() throws -> P2PKKey {
        let key = try createP2PKKey(privateKeyBytes: generateRandomPrivateKeyBytes())
        try storeP2PKKey(key)
        return key
    }

    func importP2PKNsec(_ nsec: String) throws {
        let trimmed = nsec.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("nsec1") else {
            throw SettingsFeatureError.invalidNsec
        }

        let privateKeyBytes = try Bech32.decode(hrp: "nsec", bech32: trimmed)
        let key = try createP2PKKey(privateKeyBytes: privateKeyBytes)
        let normalizedImportedKey = normalizeP2PKPublicKeyForComparison(key.publicKey)

        if let existingIndex = p2pkKeys.firstIndex(where: {
            normalizeP2PKPublicKeyForComparison($0.publicKey) == normalizedImportedKey
        }) {
            let existing = p2pkKeys[existingIndex]
            guard !Self.hasUsablePrivateKey(existing) else {
                throw SettingsFeatureError.duplicateP2PKKey
            }

            // A metadata-only row must not prevent its owner from repairing it
            // by importing the corresponding private key.
            let repaired = P2PKKey(
                id: existing.id,
                publicKey: key.publicKey,
                privateKey: key.privateKey,
                used: existing.used,
                usedCount: existing.usedCount,
                nickname: existing.nickname
            )
            try storeP2PKKey(repaired, replacing: existingIndex)
            return
        }

        try storeP2PKKey(key)
    }

    func markP2PKKeyUsed(publicKey: String) {
        let normalizedTargetKey = normalizeP2PKPublicKeyForComparison(publicKey)
        guard let index = p2pkKeys.firstIndex(where: {
            Self.hasUsablePrivateKey($0)
                && normalizeP2PKPublicKeyForComparison($0.publicKey) == normalizedTargetKey
        }) else { return }
        p2pkKeys[index].used = true
        p2pkKeys[index].usedCount += 1
        persistP2PKMetadata()
    }

    func removeP2PKKey(_ key: P2PKKey) throws {
        guard let storedKey = p2pkKeys.first(where: { $0.id == key.id }) else { return }

        let storageKey = Self.secureP2PKPrivateKey(storedKey.id)
        let fallbackSecret: String?
        if !storedKey.privateKey.isEmpty {
            fallbackSecret = storedKey.privateKey
        } else if let pendingSecret = pendingLegacyP2PKSecrets[storedKey.id] {
            fallbackSecret = pendingSecret
        } else {
            do {
                fallbackSecret = try secureStorage.loadSecret(forKey: storageKey)
            } catch {
                AppLogger.security.error(
                    "Failed to load P2PK private key before removal error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                )
                throw SettingsFeatureError.keyRemovalFailed
            }
        }

        // Stage a recoverable copy before touching Keychain. If the process is
        // interrupted after deletion, the next launch migrates this legacy field
        // back into secure storage instead of silently losing the private key.
        var stagedLegacySecrets = pendingLegacyP2PKSecrets
        if let fallbackSecret, !fallbackSecret.isEmpty {
            stagedLegacySecrets[storedKey.id] = fallbackSecret
        }
        do {
            try settingsStore.saveP2PKKeys(
                p2pkKeys,
                preservingLegacySecrets: stagedLegacySecrets
            )
        } catch {
            AppLogger.security.error(
                "Failed to stage P2PK key removal fallback error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            throw SettingsFeatureError.keyRemovalFailed
        }
        pendingLegacyP2PKSecrets = stagedLegacySecrets

        do {
            try secureStorage.deleteSecret(forKey: storageKey)
        } catch {
            // The staged metadata row remains authoritative and observable state
            // is unchanged, so the user can retry without losing the key.
            AppLogger.security.error(
                "Failed to delete P2PK private key error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            throw SettingsFeatureError.keyRemovalFailed
        }

        let updatedKeys = p2pkKeys.filter { $0.id != storedKey.id }
        var updatedLegacySecrets = stagedLegacySecrets
        updatedLegacySecrets.removeValue(forKey: storedKey.id)
        do {
            try settingsStore.saveP2PKKeys(
                updatedKeys,
                preservingLegacySecrets: updatedLegacySecrets
            )
        } catch {
            // The first metadata write still contains the complete row and its
            // fallback secret. Restore Keychain when possible as an additional
            // runtime recovery path, but never discard that durable fallback.
            if let fallbackSecret, !fallbackSecret.isEmpty {
                try? secureStorage.saveSecret(fallbackSecret, forKey: storageKey)
            }
            AppLogger.security.error(
                "Failed to finalize P2PK key removal error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            throw SettingsFeatureError.keyRemovalFailed
        }

        pendingLegacyP2PKSecrets = updatedLegacySecrets
        p2pkKeys = updatedKeys
    }

    func resetWalletScopedData(resetRuntimeServices: Bool = true) {
        for key in p2pkKeys {
            try? secureStorage.deleteSecret(forKey: Self.secureP2PKPrivateKey(key.id))
        }

        try? KeychainService().deleteNostrPrivateKey()

        showP2PKButtonInDrawer = false
        pendingLegacyP2PKSecrets = [:]
        p2pkKeys = []
        nostrMintBackupEnabled = true
        let previousSuppression = suppressPaymentRequestSideEffects
        suppressPaymentRequestSideEffects = resetRuntimeServices
        defer { suppressPaymentRequestSideEffects = previousSuppression }
        enablePaymentRequests = true
        receivePaymentRequestsAutomatically = true

        if resetRuntimeServices {
            NostrService.shared.resetForWalletBoundary()
            NPCService.shared.resetForWalletBoundary()
        }
        NostrMintBackupService.shared.resetForWalletBoundary()
        settingsStore.clearWalletScopedData()
    }
    
    private struct LoadedP2PKKeys {
        let keys: [P2PKKey]
        let pendingLegacySecrets: [UUID: String]
        let encounteredLegacySecrets: Bool
    }

    private static func loadP2PKKeys(
        settingsStore: SettingsStore,
        secureStorage: SecureStorageProtocol
    ) -> LoadedP2PKKeys {
        let decoded = settingsStore.p2pkKeys
        var pendingLegacySecrets: [UUID: String] = [:]
        var encounteredLegacySecrets = false

        let keys = decoded.map { key in
            let storageKey = secureP2PKPrivateKey(key.id)
            var privateKey = ""

            do {
                if let storedSecret = try secureStorage.loadSecret(forKey: storageKey),
                   hasUsablePrivateKey(publicKey: key.publicKey, privateKey: storedSecret) {
                    privateKey = storedSecret
                }
            } catch {
                AppLogger.security.error(
                    "Failed to load P2PK private key error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                )
            }

            let legacySecret = key.privateKey
            if !legacySecret.isEmpty {
                encounteredLegacySecrets = true
            }

            if privateKey.isEmpty, !legacySecret.isEmpty {
                if hasUsablePrivateKey(publicKey: key.publicKey, privateKey: legacySecret) {
                    do {
                        try secureStorage.saveSecret(legacySecret, forKey: storageKey)
                        privateKey = legacySecret
                    } catch {
                        // Keep the legacy field in UserDefaults and the usable
                        // value in memory. A later metadata write retries migration.
                        privateKey = legacySecret
                        pendingLegacySecrets[key.id] = legacySecret
                        AppLogger.security.error(
                            "Failed to migrate legacy P2PK private key error_type=\(String(reflecting: type(of: error)), privacy: .public)"
                        )
                    }
                } else {
                    // Preserve malformed legacy data verbatim for compatibility,
                    // but never expose it as a signing key.
                    pendingLegacySecrets[key.id] = legacySecret
                }
            }

            return P2PKKey(
                id: key.id,
                publicKey: key.publicKey,
                privateKey: privateKey,
                used: key.used,
                usedCount: key.usedCount,
                nickname: key.nickname
            )
        }

        return LoadedP2PKKeys(
            keys: keys,
            pendingLegacySecrets: pendingLegacySecrets,
            encounteredLegacySecrets: encounteredLegacySecrets
        )
    }

    /// Store the secret before either durable metadata or observable state. If
    /// metadata persistence fails, remove the newly-written secret so the caller
    /// receives a failure instead of an unreachable half-created key.
    private func storeP2PKKey(_ key: P2PKKey, replacing index: Int? = nil) throws {
        guard Self.hasUsablePrivateKey(key) else {
            throw SettingsFeatureError.invalidNsec
        }

        let storageKey = Self.secureP2PKPrivateKey(key.id)
        do {
            try secureStorage.saveSecret(key.privateKey, forKey: storageKey)
        } catch {
            AppLogger.security.error(
                "Failed to store P2PK private key error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            throw SettingsFeatureError.secureStorageUnavailable
        }

        var updatedKeys = p2pkKeys
        let replacedPendingLegacySecret = pendingLegacyP2PKSecrets[key.id]
        if let index {
            updatedKeys[index] = key
            pendingLegacyP2PKSecrets.removeValue(forKey: key.id)
        } else {
            updatedKeys.append(key)
        }

        migratePendingLegacyP2PKSecrets(using: updatedKeys)
        do {
            try settingsStore.saveP2PKKeys(
                updatedKeys,
                preservingLegacySecrets: pendingLegacyP2PKSecrets
            )
        } catch {
            // Only a brand-new key needs rollback deletion. A repair reuses an
            // existing metadata row and storage identifier, so deleting here
            // could destroy a secret that predated this attempt (for example,
            // after a transient Keychain read failure).
            if index == nil {
                try? secureStorage.deleteSecret(forKey: storageKey)
            }
            if let replacedPendingLegacySecret {
                pendingLegacyP2PKSecrets[key.id] = replacedPendingLegacySecret
            }
            AppLogger.security.error(
                "Failed to store P2PK metadata error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
            throw SettingsFeatureError.settingsPersistenceUnavailable
        }

        p2pkKeys = updatedKeys
    }

    private func persistP2PKMetadata() {
        migratePendingLegacyP2PKSecrets(using: p2pkKeys)
        do {
            try settingsStore.saveP2PKKeys(
                p2pkKeys,
                preservingLegacySecrets: pendingLegacyP2PKSecrets
            )
        } catch {
            AppLogger.security.error(
                "Failed to persist P2PK metadata error_type=\(String(reflecting: type(of: error)), privacy: .public)"
            )
        }
    }

    private func migratePendingLegacyP2PKSecrets(using keys: [P2PKKey]) {
        var migratedIDs: [UUID] = []
        for (id, legacySecret) in pendingLegacyP2PKSecrets {
            guard let key = keys.first(where: { $0.id == id }),
                  Self.hasUsablePrivateKey(publicKey: key.publicKey, privateKey: legacySecret) else {
                continue
            }
            do {
                try secureStorage.saveSecret(
                    legacySecret,
                    forKey: Self.secureP2PKPrivateKey(id)
                )
                migratedIDs.append(id)
            } catch {
                // Retain the legacy value in the next metadata write.
            }
        }
        for id in migratedIDs {
            pendingLegacyP2PKSecrets.removeValue(forKey: id)
        }
    }

    private static func secureP2PKPrivateKey(_ id: UUID) -> String {
        "settings.p2pk.\(id.uuidString).privateKey"
    }

    private func generateRandomPrivateKeyBytes() throws -> [UInt8] {
        for _ in 0..<10 {
            var randomBytes = [UInt8](repeating: 0, count: 32)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            guard status == errSecSuccess else {
                throw SettingsFeatureError.randomGenerationFailed
            }

            if (try? P256K.Schnorr.PrivateKey(dataRepresentation: randomBytes)) != nil {
                return randomBytes
            }
        }

        throw SettingsFeatureError.randomGenerationFailed
    }

    private func createP2PKKey(privateKeyBytes: [UInt8]) throws -> P2PKKey {
        guard privateKeyBytes.count == 32 else {
            throw SettingsFeatureError.invalidNsec
        }

        let privateKey = try P256K.Schnorr.PrivateKey(dataRepresentation: privateKeyBytes)
        let privateKeyHex = privateKey.dataRepresentation.map { String(format: "%02x", $0) }.joined()
        let publicKeyHex = privateKey.xonly.bytes.map { String(format: "%02x", $0) }.joined()
        let p2pkPublicKey = "02\(publicKeyHex)"

        return P2PKKey(publicKey: p2pkPublicKey, privateKey: privateKeyHex, used: false, usedCount: 0)
    }

    private func generateKeypairHex() throws -> (privateKeyHex: String, publicKeyHex: String) {
        let privateKeyBytes = try generateRandomPrivateKeyBytes()
        let privateKey = try P256K.Schnorr.PrivateKey(dataRepresentation: privateKeyBytes)
        let privateKeyHex = privateKey.dataRepresentation.map { String(format: "%02x", $0) }.joined()
        let publicKeyHex = privateKey.xonly.bytes.map { String(format: "%02x", $0) }.joined()
        return (privateKeyHex: privateKeyHex, publicKeyHex: publicKeyHex)
    }

    private static func hasUsablePrivateKey(_ key: P2PKKey) -> Bool {
        hasUsablePrivateKey(publicKey: key.publicKey, privateKey: key.privateKey)
    }

    private static func hasUsablePrivateKey(publicKey: String, privateKey: String) -> Bool {
        guard privateKey.count == 64 else { return false }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(32)
        var offset = privateKey.startIndex
        for _ in 0..<32 {
            let next = privateKey.index(offset, offsetBy: 2)
            guard let byte = UInt8(privateKey[offset..<next], radix: 16) else { return false }
            bytes.append(byte)
            offset = next
        }
        guard let secret = try? P256K.Schnorr.PrivateKey(dataRepresentation: bytes) else {
            return false
        }
        let derivedPublicKey = "02" + secret.xonly.bytes.map { String(format: "%02x", $0) }.joined()
        return normalizeP2PKPublicKeyForComparison(derivedPublicKey)
            == normalizeP2PKPublicKeyForComparison(publicKey)
    }

    private static func normalizeP2PKPublicKeyForComparison(_ publicKey: String) -> String {
        let normalized = publicKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.count == 66, normalized.hasPrefix("02") || normalized.hasPrefix("03") {
            return String(normalized.dropFirst(2))
        }
        return normalized
    }

    private func normalizeP2PKPublicKeyForComparison(_ publicKey: String) -> String {
        Self.normalizeP2PKPublicKeyForComparison(publicKey)
    }
    
    // MARK: - Formatting Helpers
    
    func formatAmount(_ sats: UInt64) -> String {
        AmountFormatter.sats(sats, useBitcoinSymbol: useBitcoinSymbol)
    }
    
    func formatAmountShort(_ sats: UInt64) -> String {
        // Delegate to the canonical formatter so grouping ("2,500") is
        // consistent app-wide. includeUnit:false preserves the original
        // contract (symbol-or-nothing, never a " sat" suffix) — callers that
        // append `unitSuffix` themselves must not get a second unit here.
        AmountFormatter.sats(sats, useBitcoinSymbol: useBitcoinSymbol, includeUnit: false)
    }
    
    func formatAmountBalance(_ sats: UInt64) -> String {
        AmountFormatter.sats(sats, useBitcoinSymbol: false, includeUnit: false)
    }

    /// Grouped balance plus the active unit (₿ prefix or " sat" suffix). The
    /// canonical hero-balance string, shared by the wallet hero and the restore
    /// success screen so both render identically including the unit toggle.
    func formatBalanceWithUnit(_ sats: UInt64) -> String {
        let formatted = formatAmountBalance(sats)
        return useBitcoinSymbol ? "₿\(formatted)" : "\(formatted) sat"
    }

    var unitSuffix: String {
        useBitcoinSymbol ? "" : " sat"
    }
    
    var unitLabel: String {
        useBitcoinSymbol ? "BTC" : "SAT"
    }
}

struct P2PKKey: Identifiable, Codable, Hashable {
    let id: UUID
    let publicKey: String
    let privateKey: String
    var used: Bool
    var usedCount: Int
    /// Optional human label the user gives a key so it's recognizable in the list.
    var nickname: String?

    init(
        id: UUID = UUID(),
        publicKey: String,
        privateKey: String,
        used: Bool,
        usedCount: Int,
        nickname: String? = nil
    ) {
        self.id = id
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.used = used
        self.usedCount = usedCount
        self.nickname = nickname
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case publicKey
        case privateKey
        case used
        case usedCount
        case nickname
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.publicKey = try container.decode(String.self, forKey: .publicKey)
        self.privateKey = try container.decodeIfPresent(String.self, forKey: .privateKey) ?? ""
        self.used = try container.decode(Bool.self, forKey: .used)
        self.usedCount = try container.decode(Int.self, forKey: .usedCount)
        self.nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(publicKey, forKey: .publicKey)
        try container.encode(used, forKey: .used)
        try container.encode(usedCount, forKey: .usedCount)
        try container.encodeIfPresent(nickname, forKey: .nickname)
    }
}

// MARK: - Primary (seed-derived) P2PK key & signing helpers

extension SettingsManager {
    /// The wallet's primary P2PK key — the seed-derived Nostr identity. Unlike the
    /// random/imported keys in `p2pkKeys` (which live only in the Keychain), this
    /// key is recoverable from the seed phrase, so ecash locked to it survives a
    /// lost device. Returned as a 33-byte compressed pubkey ("02" + x-only hex),
    /// the same form NPubCash locked receives already use.
    var primaryP2PKPublicKey: String? {
        let nostr = NostrService.shared
        guard nostr.isInitialized, nostr.publicKeyHex.count == 64 else { return nil }
        return "02\(nostr.publicKeyHex)"
    }

    /// Private-key hex for the primary key, used to sign when spending or receiving
    /// ecash locked to it. Nil until the Nostr identity is initialized.
    var primaryP2PKPrivateKeyHex: String? {
        let nostr = NostrService.shared
        guard nostr.isInitialized else { return nil }
        return nostr.getPrivateKeyHex()
    }

    /// Whether the primary key is derived from — and therefore restorable with —
    /// the seed phrase. False when a custom Nostr key has been imported.
    var primaryP2PKIsSeedBacked: Bool {
        NostrService.shared.signerType == .seed
    }

    /// Every private-key hex available for P2PK signing: the seed-derived primary
    /// key (when available) followed by each stored device/imported key, de-duped.
    /// This is the single source of truth for the wallet's signing set, so tokens
    /// locked to *any* of the user's keys — including the recoverable primary —
    /// are always spendable and receivable.
    func allP2PKSigningKeyHexes() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let storedKeys = p2pkKeys.compactMap { key in
            Self.hasUsablePrivateKey(key) ? key.privateKey : nil
        }
        for hex in [primaryP2PKPrivateKeyHex].compactMap({ $0 }) + storedKeys {
            guard !hex.isEmpty, seen.insert(hex.lowercased()).inserted else { continue }
            result.append(hex)
        }
        return result
    }

    /// True when `pubkey` matches the primary key or any stored key (prefix-agnostic).
    func isKnownP2PKPublicKey(_ pubkey: String) -> Bool {
        let target = normalizeP2PKPublicKeyForComparison(pubkey)
        if let primary = primaryP2PKPublicKey,
           normalizeP2PKPublicKeyForComparison(primary) == target {
            return true
        }
        return p2pkKeys.contains {
            Self.hasUsablePrivateKey($0)
                && normalizeP2PKPublicKeyForComparison($0.publicKey) == target
        }
    }

    /// Assign or clear a human label for a stored key.
    func setP2PKKeyNickname(_ nickname: String?, for id: UUID) {
        guard let index = p2pkKeys.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        p2pkKeys[index].nickname = (trimmed?.isEmpty == false) ? trimmed : nil
        persistP2PKMetadata()
    }
}

enum AmountDisplayPrimary: String, Codable {
    case fiat
    case sats

    mutating func toggle() {
        self = (self == .fiat) ? .sats : .fiat
    }
}

enum SettingsFeatureError: LocalizedError, Equatable {
    case invalidNsec
    case duplicateP2PKKey
    case randomGenerationFailed
    case secureStorageUnavailable
    case settingsPersistenceUnavailable
    case keyRemovalFailed

    var errorDescription: String? {
        switch self {
        case .invalidNsec:
            return "Invalid nsec format"
        case .duplicateP2PKKey:
            return "Key already exists"
        case .randomGenerationFailed:
            return "Failed to generate secure key"
        case .secureStorageUnavailable:
            return "Couldn't store the private key securely. Unlock your device and try again."
        case .settingsPersistenceUnavailable:
            return "Couldn't save the key. Please try again."
        case .keyRemovalFailed:
            return "Couldn't remove the key safely. It is still available; please try again."
        }
    }
}

// MARK: - Theme Colors Extension
