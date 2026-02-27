import SwiftUI
import P256K

// MARK: - Settings Manager

@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    // Theme colors matching cashu.me
    static let themeColors: [ThemeColor] = [
        ThemeColor(name: "Green", color: Color(red: 0, green: 0.9, blue: 0.46)),       // Cashu Green (#00E676)
        ThemeColor(name: "Yellow", color: Color(red: 1, green: 0.84, blue: 0)),        // Yellow/Gold
        ThemeColor(name: "Orange", color: Color(red: 1, green: 0.5, blue: 0)),         // Orange
        ThemeColor(name: "Red", color: Color(red: 1, green: 0.3, blue: 0.3)),          // Red
        ThemeColor(name: "Pink", color: Color(red: 1, green: 0.4, blue: 0.7)),         // Pink
        ThemeColor(name: "Purple", color: Color(red: 0.7, green: 0.4, blue: 1)),       // Purple
        ThemeColor(name: "Blue", color: Color(red: 0.4, green: 0.6, blue: 1)),         // Blue
        ThemeColor(name: "Cyan", color: Color(red: 0, green: 0.9, blue: 0.9)),         // Cyan
        ThemeColor(name: "Mint", color: Color(red: 0.4, green: 0.9, blue: 0.6)),       // Mint green
        ThemeColor(name: "Olive", color: Color(red: 0.6, green: 0.7, blue: 0.3)),      // Olive
    ]

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
    
    @Published var useNumericKeyboard: Bool {
        didSet { UserDefaults.standard.set(useNumericKeyboard, forKey: "useNumericKeyboard") }
    }
    
    @Published var useBitcoinSymbol: Bool {
        didSet { UserDefaults.standard.set(useBitcoinSymbol, forKey: "useBitcoinSymbol") }
    }
    
    @Published var selectedThemeIndex: Int {
        didSet { 
            UserDefaults.standard.set(selectedThemeIndex, forKey: "selectedThemeIndex")
            updateThemeColor()
        }
    }
    
    @Published var showFiatBalance: Bool {
        didSet { 
            UserDefaults.standard.set(showFiatBalance, forKey: "showFiatBalance")
            // Enable/disable price service based on this setting
            PriceService.shared.isEnabled = showFiatBalance
        }
    }

    @Published var bitcoinPriceCurrency: String {
        didSet {
            UserDefaults.standard.set(bitcoinPriceCurrency, forKey: "bitcoinPriceCurrency")
            PriceService.shared.currencyCode = bitcoinPriceCurrency
        }
    }

    @Published var checkPendingOnStartup: Bool {
        didSet {
            UserDefaults.standard.set(checkPendingOnStartup, forKey: "checkPendingOnStartup")
        }
    }

    @Published var checkSentTokens: Bool {
        didSet {
            UserDefaults.standard.set(checkSentTokens, forKey: "checkSentTokens")
        }
    }

    @Published var autoPasteEcashReceive: Bool {
        didSet {
            UserDefaults.standard.set(autoPasteEcashReceive, forKey: "autoPasteEcashReceive")
        }
    }

    @Published var useWebsockets: Bool {
        didSet {
            UserDefaults.standard.set(useWebsockets, forKey: "useWebsockets")
        }
    }

    @Published var enablePaymentRequests: Bool {
        didSet {
            UserDefaults.standard.set(enablePaymentRequests, forKey: "enablePaymentRequests")
        }
    }

    @Published var receivePaymentRequestsAutomatically: Bool {
        didSet {
            UserDefaults.standard.set(receivePaymentRequestsAutomatically, forKey: "receivePaymentRequestsAutomatically")
        }
    }

    @Published var enableNWC: Bool {
        didSet {
            UserDefaults.standard.set(enableNWC, forKey: "enableNWC")
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
            UserDefaults.standard.set(showP2PKButtonInDrawer, forKey: "showP2PKButtonInDrawer")
        }
    }

    @Published var p2pkKeys: [P2PKKey] {
        didSet {
            persistP2PKKeys()
        }
    }

    @Published var checkIncomingInvoices: Bool {
        didSet {
            UserDefaults.standard.set(checkIncomingInvoices, forKey: "checkIncomingInvoices")
            NPCService.shared.applyPollingPreferences()
        }
    }

    @Published var periodicallyCheckIncomingInvoices: Bool {
        didSet {
            UserDefaults.standard.set(periodicallyCheckIncomingInvoices, forKey: "periodicallyCheckIncomingInvoices")
            NPCService.shared.applyPollingPreferences()
        }
    }

    @Published var nostrRelays: [String] {
        didSet {
            UserDefaults.standard.set(nostrRelays, forKey: "nostrRelays")
        }
    }
    
    @Published var accentColor: Color = Color(red: 0, green: 1, blue: 0)
    private lazy var decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter
    }()
    
    // MARK: - Initialization
    
    init() {
        self.useNumericKeyboard = UserDefaults.standard.object(forKey: "useNumericKeyboard") as? Bool ?? true
        self.useBitcoinSymbol = UserDefaults.standard.object(forKey: "useBitcoinSymbol") as? Bool ?? false
        self.selectedThemeIndex = UserDefaults.standard.object(forKey: "selectedThemeIndex") as? Int ?? 0
        self.showFiatBalance = UserDefaults.standard.object(forKey: "showFiatBalance") as? Bool ?? false
        self.bitcoinPriceCurrency = UserDefaults.standard.string(forKey: "bitcoinPriceCurrency") ?? "USD"
        self.checkPendingOnStartup = UserDefaults.standard.object(forKey: "checkPendingOnStartup") as? Bool ?? true
        self.checkSentTokens = UserDefaults.standard.object(forKey: "checkSentTokens") as? Bool ?? true
        self.autoPasteEcashReceive = UserDefaults.standard.object(forKey: "autoPasteEcashReceive") as? Bool ?? true
        self.useWebsockets = UserDefaults.standard.object(forKey: "useWebsockets") as? Bool ?? true
        self.enablePaymentRequests = UserDefaults.standard.object(forKey: "enablePaymentRequests") as? Bool ?? false
        self.receivePaymentRequestsAutomatically = UserDefaults.standard.object(forKey: "receivePaymentRequestsAutomatically") as? Bool ?? false
        self.enableNWC = UserDefaults.standard.object(forKey: "enableNWC") as? Bool ?? false
        self.nwcConnections = Self.loadNWCConnections()
        self.showP2PKButtonInDrawer = UserDefaults.standard.object(forKey: "showP2PKButtonInDrawer") as? Bool ?? false
        self.p2pkKeys = Self.loadP2PKKeys()
        self.checkIncomingInvoices = UserDefaults.standard.object(forKey: "checkIncomingInvoices") as? Bool ?? true
        self.periodicallyCheckIncomingInvoices = UserDefaults.standard.object(forKey: "periodicallyCheckIncomingInvoices") as? Bool ?? true
        self.nostrRelays = UserDefaults.standard.stringArray(forKey: "nostrRelays") ?? Self.defaultNostrRelays
        
        updateThemeColor()

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
    
    private func updateThemeColor() {
        if selectedThemeIndex >= 0 && selectedThemeIndex < Self.themeColors.count {
            accentColor = Self.themeColors[selectedThemeIndex].color
        }
    }

    private static func loadNWCConnections() -> [NWCConnection] {
        guard let data = UserDefaults.standard.data(forKey: "nwcConnections"),
              let decoded = try? JSONDecoder().decode([NWCConnection].self, from: data) else {
            return []
        }
        return decoded
    }

    private func persistNWCConnections() {
        guard let data = try? JSONEncoder().encode(nwcConnections) else { return }
        UserDefaults.standard.set(data, forKey: "nwcConnections")
    }

    private static func loadP2PKKeys() -> [P2PKKey] {
        guard let data = UserDefaults.standard.data(forKey: "p2pkKeys"),
              let decoded = try? JSONDecoder().decode([P2PKKey].self, from: data) else {
            return []
        }
        return decoded
    }

    private func persistP2PKKeys() {
        guard let data = try? JSONEncoder().encode(p2pkKeys) else { return }
        UserDefaults.standard.set(data, forKey: "p2pkKeys")
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
        let formatted = decimalFormatter.string(from: NSNumber(value: sats)) ?? "\(sats)"
        
        if useBitcoinSymbol {
            return "₿\(formatted)"
        } else {
            return "\(formatted) sat"
        }
    }
    
    func formatAmountShort(_ sats: UInt64) -> String {
        if useBitcoinSymbol {
            return "₿\(sats)"
        } else {
            return "\(sats)"
        }
    }
    
    func formatAmountBalance(_ sats: UInt64) -> String {
        return decimalFormatter.string(from: NSNumber(value: sats)) ?? "\(sats)"
    }
    
    var unitSuffix: String {
        useBitcoinSymbol ? "" : " sat"
    }
    
    var unitLabel: String {
        useBitcoinSymbol ? "BTC" : "SAT"
    }
}

// MARK: - Theme Color Model

struct ThemeColor: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
}

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

extension Color {
    /// Dynamic accent color based on settings
    @MainActor static var cashuAccent: Color {
        SettingsManager.shared.accentColor
    }
}
