import Foundation

// MARK: - Storage Protocol

/// Protocol for persistent storage operations.
/// Abstracts storage implementation to allow for different backends (UserDefaults, SQLite, Keychain, etc.)
protocol StorageProtocol {
    /// Store a value for a key
    func set<T: Codable>(_ value: T, forKey key: String) throws
    
    /// Retrieve a value for a key
    func get<T: Codable>(forKey key: String) throws -> T?
    
    /// Remove a value for a key
    func remove(forKey key: String) throws
    
    /// Check if a key exists
    func exists(forKey key: String) -> Bool
    
    /// Get all keys with a given prefix
    func keys(withPrefix prefix: String) -> [String]
}

// MARK: - Secure Storage Protocol

/// Protocol for secure storage (Keychain)
protocol SecureStorageProtocol {
    /// Store a secret securely
    func saveSecret(_ secret: String, forKey key: String) throws
    
    /// Retrieve a secret
    func loadSecret(forKey key: String) throws -> String?
    
    /// Delete a secret
    func deleteSecret(forKey key: String) throws
    
    /// Check if a secret exists
    func hasSecret(forKey key: String) -> Bool
}

// MARK: - UserDefaults Storage Implementation

/// Storage implementation using UserDefaults
final class UserDefaultsStorage: StorageProtocol {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    func set<T: Codable>(_ value: T, forKey key: String) throws {
        let data = try encoder.encode(value)
        defaults.set(data, forKey: key)
    }
    
    func get<T: Codable>(forKey key: String) throws -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try decoder.decode(T.self, from: data)
    }
    
    func remove(forKey key: String) throws {
        defaults.removeObject(forKey: key)
    }
    
    func exists(forKey key: String) -> Bool {
        defaults.object(forKey: key) != nil
    }
    
    func keys(withPrefix prefix: String) -> [String] {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
    }
}

// MARK: - Storage Keys

/// Centralized storage key definitions
enum StorageKeys {
    // Wallet
    static let mints = "wallet.mints"
    static let activeMintUrl = "wallet.activeMintUrl"
    static let pendingTokens = "wallet.pendingTokens"
    static let pendingReceiveTokens = "wallet.pendingReceiveTokens"
    static let claimedTokens = "wallet.claimedTokens"
    static let transactions = "wallet.transactions"
    static let processedNPCQuotes = "wallet.processedNPCQuotes"
    
    // Settings
    static let useNumericKeyboard = "settings.useNumericKeyboard"
    static let useBitcoinSymbol = "settings.useBitcoinSymbol"
    static let selectedThemeIndex = "settings.selectedThemeIndex"
    static let showFiatBalance = "settings.showFiatBalance"
    
    // NPC
    static let npcEnabled = "npc.enabled"
    static let npcLastCheck = "npc.lastCheckTimestamp"
    
    // Price
    static let priceEnabled = "price.enabled"
    static let cachedBTCPrice = "price.cachedBTC"
    static let cachedBTCPriceDate = "price.cachedBTCDate"
    
    // Keychain (Secure Storage)
    enum Secure {
        static let mnemonic = "wallet_mnemonic"
        static let nostrPrivateKey = "nostr_private_key"
    }
}
