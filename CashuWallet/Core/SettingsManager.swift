import SwiftUI
import P256K

// MARK: - Settings Manager

@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    private let settingsStore = SettingsStore.shared
    
    static let supportedFiatCurrencies: [String] = [
        "USD", "EUR", "AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "GBP",
        "HKD", "HUF", "ILS", "INR", "JPY", "KRW", "MXN", "NZD", "NOK", "PLN",
        "RUB", "SEK", "SGD", "THB", "TRY", "ZAR"
    ]

    static let defaultNostrRelays: [String] = [
        "wss://relay.damus.io",
        "wss://relay.8333.space/",
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

    @Published var p2pkKeys: [P2PKKey] {
        didSet {
            persistP2PKKeys()
        }
    }

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

    @Published var nostrRelays: [String] {
        didSet {
            settingsStore.nostrRelays = nostrRelays
        }
    }

    @Published var amountDisplayPrimary: AmountDisplayPrimary {
        didSet {
            settingsStore.amountDisplayPrimary = amountDisplayPrimary.rawValue
        }
    }

    @Published var appLockEnabled: Bool {
        didSet {
            settingsStore.appLockEnabled = appLockEnabled
            guard appLockEnabled != oldValue else { return }
            AppLockManager.shared.setEnabled(appLockEnabled)
        }
    }

    // MARK: - Initialization
    
    init() {
        self.useBitcoinSymbol = settingsStore.useBitcoinSymbol
        self.showFiatBalance = settingsStore.showFiatBalance
        self.bitcoinPriceCurrency = settingsStore.bitcoinPriceCurrency
        self.checkSentTokens = settingsStore.checkSentTokens
        self.autoPasteEcashReceive = settingsStore.autoPasteEcashReceive
        self.useWebsockets = settingsStore.useWebsockets
        self.showP2PKButtonInDrawer = settingsStore.showP2PKButtonInDrawer
        self.p2pkKeys = Self.loadP2PKKeys()
        self.checkIncomingInvoices = settingsStore.checkIncomingInvoices
        self.periodicallyCheckIncomingInvoices = settingsStore.periodicallyCheckIncomingInvoices
        self.nostrRelays = settingsStore.nostrRelays
        self.amountDisplayPrimary = AmountDisplayPrimary(rawValue: settingsStore.amountDisplayPrimary) ?? .fiat
        self.appLockEnabled = settingsStore.appLockEnabled

        persistP2PKKeys()
        
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
    func generateP2PKKey() -> Bool {
        do {
            let key = try createP2PKKey(privateKeyBytes: generateRandomPrivateKeyBytes())
            p2pkKeys.append(key)
            return true
        } catch {
            return false
        }
    }

    func importP2PKNsec(_ nsec: String) throws {
        let trimmed = nsec.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("nsec1") else {
            throw SettingsFeatureError.invalidNsec
        }

        let privateKeyBytes = try Bech32.decode(hrp: "nsec", bech32: trimmed)
        let key = try createP2PKKey(privateKeyBytes: privateKeyBytes)
        let normalizedImportedKey = normalizeP2PKPublicKeyForComparison(key.publicKey)

        guard !p2pkKeys.contains(where: { normalizeP2PKPublicKeyForComparison($0.publicKey) == normalizedImportedKey }) else {
            throw SettingsFeatureError.duplicateP2PKKey
        }

        p2pkKeys.append(key)
    }

    func markP2PKKeyUsed(publicKey: String) {
        let normalizedTargetKey = normalizeP2PKPublicKeyForComparison(publicKey)
        guard let index = p2pkKeys.firstIndex(where: {
            normalizeP2PKPublicKeyForComparison($0.publicKey) == normalizedTargetKey
        }) else { return }
        p2pkKeys[index].used = true
        p2pkKeys[index].usedCount += 1
    }

    func removeP2PKKey(_ key: P2PKKey) {
        try? KeychainService().deleteSecret(forKey: Self.secureP2PKPrivateKey(key.id))
        p2pkKeys.removeAll { $0.id == key.id }
    }

    func resetWalletScopedData(resetRuntimeServices: Bool = true) {
        let keychain = KeychainService()

        for key in p2pkKeys {
            try? keychain.deleteSecret(forKey: Self.secureP2PKPrivateKey(key.id))
        }

        try? keychain.deleteNostrPrivateKey()

        showP2PKButtonInDrawer = false
        p2pkKeys = []

        if resetRuntimeServices {
            NostrService.shared.resetForWalletBoundary()
            NPCService.shared.resetForWalletBoundary()
        }
        settingsStore.clearWalletScopedData()
    }
    
    private static func loadP2PKKeys() -> [P2PKKey] {
        let decoded = SettingsStore.shared.p2pkKeys
        let keychain = KeychainService()
        return decoded.map { key in
            let privateKey = secureSecret(
                key: secureP2PKPrivateKey(key.id),
                legacyValue: key.privateKey,
                keychain: keychain
            )
            return P2PKKey(
                id: key.id,
                publicKey: key.publicKey,
                privateKey: privateKey,
                used: key.used,
                usedCount: key.usedCount,
                nickname: key.nickname
            )
        }
    }

    private func persistP2PKKeys() {
        let keychain = KeychainService()
        for key in p2pkKeys {
            try? keychain.saveSecret(key.privateKey, forKey: Self.secureP2PKPrivateKey(key.id))
        }
        settingsStore.p2pkKeys = p2pkKeys
    }

    private static func secureSecret(key: String, legacyValue: String, keychain: KeychainService) -> String {
        if let secret = try? keychain.loadSecret(forKey: key) {
            return secret
        }
        if !legacyValue.isEmpty {
            try? keychain.saveSecret(legacyValue, forKey: key)
        }
        return legacyValue
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

    private func normalizeP2PKPublicKeyForComparison(_ publicKey: String) -> String {
        let normalized = publicKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.count == 66, normalized.hasPrefix("02") || normalized.hasPrefix("03") {
            return String(normalized.dropFirst(2))
        }
        return normalized
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
        for hex in [primaryP2PKPrivateKeyHex].compactMap({ $0 }) + p2pkKeys.map({ $0.privateKey }) {
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
        return p2pkKeys.contains { normalizeP2PKPublicKeyForComparison($0.publicKey) == target }
    }

    /// Assign or clear a human label for a stored key.
    func setP2PKKeyNickname(_ nickname: String?, for id: UUID) {
        guard let index = p2pkKeys.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        p2pkKeys[index].nickname = (trimmed?.isEmpty == false) ? trimmed : nil
    }
}

enum AmountDisplayPrimary: String, Codable {
    case fiat
    case sats

    mutating func toggle() {
        self = (self == .fiat) ? .sats : .fiat
    }
}

enum SettingsFeatureError: LocalizedError {
    case invalidNsec
    case duplicateP2PKKey
    case randomGenerationFailed

    var errorDescription: String? {
        switch self {
        case .invalidNsec:
            return "Invalid nsec format"
        case .duplicateP2PKKey:
            return "Key already exists"
        case .randomGenerationFailed:
            return "Failed to generate secure key"
        }
    }
}

// MARK: - Theme Colors Extension
