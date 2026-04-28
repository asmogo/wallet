import Foundation

final class SettingsStore {
    static let shared = SettingsStore()
    private static let defaultNostrRelays: [String] = [
        "wss://relay.damus.io",
        "wss://relay.8333.space/",
        "wss://nos.lol",
        "wss://relay.primal.net"
    ]

    private let storage: StorageProtocol

    init(storage: StorageProtocol = UserDefaultsStorage()) {
        self.storage = storage
    }

    var useBitcoinSymbol: Bool {
        get { bool(StorageKeys.useBitcoinSymbol, legacy: StorageKeys.Legacy.useBitcoinSymbol, default: false) }
        set { set(newValue, forKey: StorageKeys.useBitcoinSymbol) }
    }

    var showFiatBalance: Bool {
        get { bool(StorageKeys.showFiatBalance, legacy: StorageKeys.Legacy.showFiatBalance, default: false) }
        set { set(newValue, forKey: StorageKeys.showFiatBalance) }
    }

    var bitcoinPriceCurrency: String {
        get { value(StorageKeys.bitcoinPriceCurrency, legacy: StorageKeys.Legacy.bitcoinPriceCurrency) ?? "USD" }
        set { set(newValue, forKey: StorageKeys.bitcoinPriceCurrency) }
    }

    var checkPendingOnStartup: Bool {
        get { bool(StorageKeys.checkPendingOnStartup, legacy: StorageKeys.Legacy.checkPendingOnStartup, default: true) }
        set { set(newValue, forKey: StorageKeys.checkPendingOnStartup) }
    }

    var checkSentTokens: Bool {
        get { bool(StorageKeys.checkSentTokens, legacy: StorageKeys.Legacy.checkSentTokens, default: true) }
        set { set(newValue, forKey: StorageKeys.checkSentTokens) }
    }

    var autoPasteEcashReceive: Bool {
        get { bool(StorageKeys.autoPasteEcashReceive, legacy: StorageKeys.Legacy.autoPasteEcashReceive, default: true) }
        set { set(newValue, forKey: StorageKeys.autoPasteEcashReceive) }
    }

    var useWebsockets: Bool {
        get { bool(StorageKeys.useWebsockets, legacy: StorageKeys.Legacy.useWebsockets, default: true) }
        set { set(newValue, forKey: StorageKeys.useWebsockets) }
    }

    var enablePaymentRequests: Bool {
        get { bool(StorageKeys.enablePaymentRequests, legacy: StorageKeys.Legacy.enablePaymentRequests, default: false) }
        set { set(newValue, forKey: StorageKeys.enablePaymentRequests) }
    }

    var receivePaymentRequestsAutomatically: Bool {
        get {
            bool(
                StorageKeys.receivePaymentRequestsAutomatically,
                legacy: StorageKeys.Legacy.receivePaymentRequestsAutomatically,
                default: false
            )
        }
        set { set(newValue, forKey: StorageKeys.receivePaymentRequestsAutomatically) }
    }

    var enableNWC: Bool {
        get { bool(StorageKeys.enableNWC, legacy: StorageKeys.Legacy.enableNWC, default: false) }
        set { set(newValue, forKey: StorageKeys.enableNWC) }
    }

    var nwcConnections: [NWCConnection] {
        get { value(StorageKeys.nwcConnections, legacy: StorageKeys.Legacy.nwcConnections) ?? [] }
        set { set(newValue, forKey: StorageKeys.nwcConnections) }
    }

    var showP2PKButtonInDrawer: Bool {
        get { bool(StorageKeys.showP2PKButtonInDrawer, legacy: StorageKeys.Legacy.showP2PKButtonInDrawer, default: false) }
        set { set(newValue, forKey: StorageKeys.showP2PKButtonInDrawer) }
    }

    var p2pkKeys: [P2PKKey] {
        get { value(StorageKeys.p2pkKeys, legacy: StorageKeys.Legacy.p2pkKeys) ?? [] }
        set { set(newValue, forKey: StorageKeys.p2pkKeys) }
    }

    var checkIncomingInvoices: Bool {
        get { bool(StorageKeys.checkIncomingInvoices, legacy: StorageKeys.Legacy.checkIncomingInvoices, default: true) }
        set { set(newValue, forKey: StorageKeys.checkIncomingInvoices) }
    }

    var periodicallyCheckIncomingInvoices: Bool {
        get {
            bool(
                StorageKeys.periodicallyCheckIncomingInvoices,
                legacy: StorageKeys.Legacy.periodicallyCheckIncomingInvoices,
                default: true
            )
        }
        set { set(newValue, forKey: StorageKeys.periodicallyCheckIncomingInvoices) }
    }

    var nostrRelays: [String] {
        get { value(StorageKeys.nostrRelays, legacy: StorageKeys.Legacy.nostrRelays) ?? Self.defaultNostrRelays }
        set { set(newValue, forKey: StorageKeys.nostrRelays) }
    }

    var nostrSignerType: String? {
        get { value(StorageKeys.nostrSignerType, legacy: StorageKeys.Legacy.nostrSignerType) }
        set { setOptional(newValue, forKey: StorageKeys.nostrSignerType) }
    }

    var priceEnabled: Bool {
        get { bool(StorageKeys.priceEnabled, legacy: StorageKeys.Legacy.priceEnabled, default: false) }
        set { set(newValue, forKey: StorageKeys.priceEnabled) }
    }

    var priceCurrencyCode: String {
        get { value(StorageKeys.priceCurrencyCode, legacy: StorageKeys.Legacy.priceCurrencyCode) ?? "USD" }
        set { set(newValue, forKey: StorageKeys.priceCurrencyCode) }
    }

    var npcEnabled: Bool {
        get { bool(StorageKeys.npcEnabled, default: false) }
        set { set(newValue, forKey: StorageKeys.npcEnabled) }
    }

    var npcAutomaticClaim: Bool {
        get { bool(StorageKeys.npcAutomaticClaim, default: true) }
        set { set(newValue, forKey: StorageKeys.npcAutomaticClaim) }
    }

    var npcSelectedMint: String? {
        get { value(StorageKeys.npcSelectedMint) }
        set { setOptional(newValue, forKey: StorageKeys.npcSelectedMint) }
    }

    var npcLastCheck: Date? {
        get { value(StorageKeys.npcLastCheck) }
        set { setOptional(newValue, forKey: StorageKeys.npcLastCheck) }
    }

    func cachedPrice(currency: String) -> Double? {
        value(
            StorageKeys.cachedBTCPrice(currency: currency),
            legacyKeys: [
                StorageKeys.Legacy.cachedBTCPrice(currency: currency),
                StorageKeys.Legacy.cachedBTCPrice
            ]
        )
    }

    func setCachedPrice(_ price: Double, currency: String) {
        set(price, forKey: StorageKeys.cachedBTCPrice(currency: currency))
        set(price, forKey: StorageKeys.cachedBTCPrice)
    }

    func cachedPriceDate(currency: String) -> Date? {
        value(
            StorageKeys.cachedBTCPriceDate(currency: currency),
            legacyKeys: [
                StorageKeys.Legacy.cachedBTCPriceDate(currency: currency),
                StorageKeys.Legacy.cachedBTCPriceDate
            ]
        )
    }

    func setCachedPriceDate(_ date: Date, currency: String) {
        set(date, forKey: StorageKeys.cachedBTCPriceDate(currency: currency))
        set(date, forKey: StorageKeys.cachedBTCPriceDate)
    }

    private func bool(_ key: String, legacy: String? = nil, default defaultValue: Bool) -> Bool {
        value(key, legacyKeys: legacy.map { [$0] } ?? []) ?? defaultValue
    }

    private func value<T: Codable>(_ key: String, legacy: String? = nil) -> T? {
        value(key, legacyKeys: legacy.map { [$0] } ?? [])
    }

    private func value<T: Codable>(_ key: String, legacyKeys: [String]) -> T? {
        if let value: T = try? storage.get(forKey: key) {
            return value
        }

        for legacyKey in legacyKeys {
            if let value: T = try? storage.get(forKey: legacyKey) {
                set(value, forKey: key)
                return value
            }
        }

        return nil
    }

    private func set<T: Codable>(_ value: T, forKey key: String) {
        do {
            try storage.set(value, forKey: key)
        } catch {
            AppLogger.wallet.error("Failed to save \(key): \(error)")
        }
    }

    private func setOptional<T: Codable>(_ value: T?, forKey key: String) {
        do {
            if let value {
                try storage.set(value, forKey: key)
            } else {
                try storage.remove(forKey: key)
            }
        } catch {
            AppLogger.wallet.error("Failed to update \(key): \(error)")
        }
    }
}
