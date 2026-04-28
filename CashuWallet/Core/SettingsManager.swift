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

    static let defaultNWCAllowance = 1_000
    
    // MARK: - Published Settings
    
    @Published var useBitcoinSymbol: Bool {
        didSet { settingsStore.useBitcoinSymbol = useBitcoinSymbol }
    }
    
    @Published var showFiatBalance: Bool {
        didSet { 
            settingsStore.showFiatBalance = showFiatBalance
            // Enable/disable price service based on this setting
            PriceService.shared.isEnabled = showFiatBalance
        }
    }

    @Published var bitcoinPriceCurrency: String {
        didSet {
            settingsStore.bitcoinPriceCurrency = bitcoinPriceCurrency
            PriceService.shared.currencyCode = bitcoinPriceCurrency
        }
    }

    @Published var checkPendingOnStartup: Bool {
        didSet {
            settingsStore.checkPendingOnStartup = checkPendingOnStartup
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

    @Published var enablePaymentRequests: Bool {
        didSet {
            settingsStore.enablePaymentRequests = enablePaymentRequests
        }
    }

    @Published var receivePaymentRequestsAutomatically: Bool {
        didSet {
            settingsStore.receivePaymentRequestsAutomatically = receivePaymentRequestsAutomatically
        }
    }

    @Published var enableNWC: Bool {
        didSet {
            settingsStore.enableNWC = enableNWC
            if enableNWC {
                _ = generateNWCConnection()
            }
        }
    }

    @Published var nwcConnections: [NWCConnection] {
        didSet {
            persistNWCConnections()
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
    
    // MARK: - Initialization
    
    init() {
        self.useBitcoinSymbol = settingsStore.useBitcoinSymbol
        self.showFiatBalance = settingsStore.showFiatBalance
        self.bitcoinPriceCurrency = settingsStore.bitcoinPriceCurrency
        self.checkPendingOnStartup = settingsStore.checkPendingOnStartup
        self.checkSentTokens = settingsStore.checkSentTokens
        self.autoPasteEcashReceive = settingsStore.autoPasteEcashReceive
        self.useWebsockets = settingsStore.useWebsockets
        self.enablePaymentRequests = settingsStore.enablePaymentRequests
        self.receivePaymentRequestsAutomatically = settingsStore.receivePaymentRequestsAutomatically
        self.enableNWC = settingsStore.enableNWC
        self.nwcConnections = Self.loadNWCConnections()
        self.showP2PKButtonInDrawer = settingsStore.showP2PKButtonInDrawer
        self.p2pkKeys = Self.loadP2PKKeys()
        self.checkIncomingInvoices = settingsStore.checkIncomingInvoices
        self.periodicallyCheckIncomingInvoices = settingsStore.periodicallyCheckIncomingInvoices
        self.nostrRelays = settingsStore.nostrRelays
        
        PriceService.shared.currencyCode = bitcoinPriceCurrency
        PriceService.shared.isEnabled = showFiatBalance
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
    func generateNWCConnection() -> NWCConnection? {
        if let existingConnection = nwcConnections.first {
            return existingConnection
        }

        do {
            let walletKeypair = try generateKeypairHex()
            let connectionKeypair = try generateKeypairHex()
            let connection = NWCConnection(
                walletPublicKey: walletKeypair.publicKeyHex,
                walletPrivateKey: walletKeypair.privateKeyHex,
                connectionSecret: connectionKeypair.privateKeyHex,
                connectionPublicKey: connectionKeypair.publicKeyHex,
                allowanceLeft: Self.defaultNWCAllowance
            )
            nwcConnections.append(connection)
            return connection
        } catch {
            return nil
        }
    }

    func nwcConnectionString(for connection: NWCConnection) -> String {
        let relayParams = nostrRelays
            .map { relay in
                let value = relay.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? relay
                return "relay=\(value)"
            }
            .joined(separator: "&")

        if relayParams.isEmpty {
            return "nostr+walletconnect://\(connection.walletPublicKey)?secret=\(connection.connectionSecret)"
        }

        return "nostr+walletconnect://\(connection.walletPublicKey)?\(relayParams)&secret=\(connection.connectionSecret)"
    }

    func updateNWCAllowance(connectionId: UUID, allowanceLeft: Int) {
        guard let index = nwcConnections.firstIndex(where: { $0.id == connectionId }) else { return }
        nwcConnections[index].allowanceLeft = max(0, allowanceLeft)
    }

    func removeNWCConnection(_ connection: NWCConnection) {
        nwcConnections.removeAll { $0.id == connection.id }
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
        p2pkKeys.removeAll { $0.id == key.id }
    }
    
    private static func loadNWCConnections() -> [NWCConnection] {
        SettingsStore.shared.nwcConnections
    }

    private func persistNWCConnections() {
        settingsStore.nwcConnections = nwcConnections
    }

    private static func loadP2PKKeys() -> [P2PKKey] {
        SettingsStore.shared.p2pkKeys
    }

    private func persistP2PKKeys() {
        settingsStore.p2pkKeys = p2pkKeys
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
        if useBitcoinSymbol {
            return "₿\(sats)"
        } else {
            return "\(sats)"
        }
    }
    
    func formatAmountBalance(_ sats: UInt64) -> String {
        AmountFormatter.sats(sats, useBitcoinSymbol: false, includeUnit: false)
    }
    
    var unitSuffix: String {
        useBitcoinSymbol ? "" : " sat"
    }
    
    var unitLabel: String {
        useBitcoinSymbol ? "BTC" : "SAT"
    }
}

// MARK: - Theme Color Model

struct NWCConnection: Identifiable, Codable, Hashable {
    let id: UUID
    let walletPublicKey: String
    let walletPrivateKey: String
    let connectionSecret: String
    let connectionPublicKey: String
    var allowanceLeft: Int

    init(
        id: UUID = UUID(),
        walletPublicKey: String,
        walletPrivateKey: String,
        connectionSecret: String,
        connectionPublicKey: String,
        allowanceLeft: Int
    ) {
        self.id = id
        self.walletPublicKey = walletPublicKey
        self.walletPrivateKey = walletPrivateKey
        self.connectionSecret = connectionSecret
        self.connectionPublicKey = connectionPublicKey
        self.allowanceLeft = allowanceLeft
    }
}

struct P2PKKey: Identifiable, Codable, Hashable {
    let id: UUID
    let publicKey: String
    let privateKey: String
    var used: Bool
    var usedCount: Int

    init(
        id: UUID = UUID(),
        publicKey: String,
        privateKey: String,
        used: Bool,
        usedCount: Int
    ) {
        self.id = id
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.used = used
        self.usedCount = usedCount
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
