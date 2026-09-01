import Foundation
import Security

/// Secure storage for the mnemonic seed phrase using the platform Keychain.
///
/// All access goes through the wrappers at the bottom of this file rather than
/// calling `SecItem*` directly, so every query picks the right keychain on
/// macOS. See ``runWithPreferredKeychain(_:_:)`` for why that is not a constant.
class KeychainService: SecureStorageProtocol {
    private let serviceName = "com.cashu.me"
    private let mnemonicKey = "wallet_mnemonic"
    private let nostrPrivateKeyKey = "nostr_private_key"
    
    // MARK: - Mnemonic Operations
    
    /// Save mnemonic to Keychain
    func saveMnemonic(_ mnemonic: String) throws {
        try saveSecret(mnemonic, forKey: mnemonicKey)
    }
    
    /// Load mnemonic from Keychain
    func loadMnemonic() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: mnemonicKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = Self.copyMatching(query, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }
        
        guard let data = result as? Data,
              let mnemonic = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        
        return mnemonic
    }
    
    /// Delete mnemonic from Keychain
    func deleteMnemonic() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: mnemonicKey
        ]
        
        let status = Self.delete(query)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    /// Check if mnemonic exists
    func hasMnemonic() -> Bool {
        do {
            return try loadMnemonic() != nil
        } catch {
            return false
        }
    }
    
    // MARK: - Nostr Private Key Operations
    
    /// Save Nostr private key to Keychain (hex format)
    func saveNostrPrivateKey(_ privateKeyHex: String) throws {
        try saveSecret(privateKeyHex, forKey: nostrPrivateKeyKey)
    }
    
    /// Load Nostr private key from Keychain
    func loadNostrPrivateKey() throws -> String? {
        try loadSecret(forKey: nostrPrivateKeyKey)
    }
    
    /// Delete Nostr private key from Keychain
    func deleteNostrPrivateKey() throws {
        try deleteSecret(forKey: nostrPrivateKeyKey)
    }
    
    /// Check if custom Nostr private key exists
    func hasNostrPrivateKey() -> Bool {
        hasSecret(forKey: nostrPrivateKeyKey)
    }

    // MARK: - Generic Secure Storage

    func saveSecret(_ secret: String, forKey key: String) throws {
        guard let data = secret.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = Self.update(query, update)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.saveFailed(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = Self.add(addQuery)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func loadSecret(forKey key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = Self.copyMatching(query, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }
        
        guard let data = result as? Data,
              let privateKey = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        
        return privateKey
    }

    func deleteSecret(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        
        let status = Self.delete(query)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    func hasSecret(forKey key: String) -> Bool {
        do {
            return try loadSecret(forKey: key) != nil
        } catch {
            return false
        }
    }

    // MARK: - iCloud Keychain (Synchronizable)

    private let iCloudMnemonicKey = "wallet_mnemonic_icloud"

    func saveSynchronizableMnemonic(_ mnemonic: String) throws {
        guard let data = mnemonic.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: iCloudMnemonicKey,
            kSecAttrSynchronizable as String: kCFBooleanTrue!
        ]

        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = Self.update(query, update)
        if updateStatus == errSecSuccess { return }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.saveFailed(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = Self.add(addQuery)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func loadSynchronizableMnemonic() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: iCloudMnemonicKey,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = Self.copyMatching(query, &result)

        if status == errSecItemNotFound { return nil }

        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }

        guard let data = result as? Data,
              let mnemonic = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }

        return mnemonic
    }

    func deleteSynchronizableMnemonic() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: iCloudMnemonicKey,
            kSecAttrSynchronizable as String: kCFBooleanTrue!
        ]

        let status = Self.delete(query)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    func hasSynchronizableMnemonic() -> Bool {
        do {
            return try loadSynchronizableMnemonic() != nil
        } catch {
            return false
        }
    }

    // MARK: - Keychain access

    /// Runs a keychain call against the modern data-protection keychain, falling
    /// back to the legacy one when this build is not entitled to it.
    ///
    /// The data-protection keychain is the one iOS uses and the right home for a
    /// sandboxed Mac app — items are scoped to the app rather than shared, and
    /// reads do not prompt. Reaching it requires a keychain access group, which
    /// comes from the team identifier in the code signature.
    ///
    /// An ad-hoc signed local build has no team identifier, so the OS rejects the
    /// request outright and wallet creation fails with "failed to save keychain".
    /// Falling back keeps `Scripts/build-macos.sh` usable with no Apple Developer
    /// account, at the cost of using the legacy keychain on those builds only.
    ///
    /// On iOS there is only one keychain, the flag is inert, and the fallback
    /// never fires.
    private static func runWithPreferredKeychain(
        _ query: [String: Any],
        _ perform: ([String: Any]) -> OSStatus
    ) -> OSStatus {
        var preferred = query
        preferred[kSecUseDataProtectionKeychain as String] = true

        let status = perform(preferred)
        // Only these two mean "you may not use that keychain". Anything else is
        // a real failure and must not be retried against a different store.
        guard status == errSecMissingEntitlement || status == errSecNotAvailable else {
            return status
        }

        AppLogger.security.notice(
            "data-protection keychain unavailable (status=\(status, privacy: .public)); using legacy keychain"
        )
        let fallback = perform(query)
        if fallback != errSecSuccess && fallback != errSecItemNotFound {
            AppLogger.security.error(
                "legacy keychain also refused the request (status=\(fallback, privacy: .public))"
            )
        }
        return fallback
    }

    private static func copyMatching(_ query: [String: Any], _ result: inout AnyObject?) -> OSStatus {
        var found: AnyObject?
        let status = runWithPreferredKeychain(query) {
            SecItemCopyMatching($0 as CFDictionary, &found)
        }
        result = found
        return status
    }

    private static func add(_ attributes: [String: Any]) -> OSStatus {
        runWithPreferredKeychain(attributes) { SecItemAdd($0 as CFDictionary, nil) }
    }

    private static func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        runWithPreferredKeychain(query) { SecItemUpdate($0 as CFDictionary, attributes as CFDictionary) }
    }

    private static func delete(_ query: [String: Any]) -> OSStatus {
        runWithPreferredKeychain(query) { SecItemDelete($0 as CFDictionary) }
    }

}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode mnemonic"
        case .decodingFailed:
            return "Failed to decode mnemonic"
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        case .loadFailed(let status):
            return "Failed to load from Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain (status: \(status))"
        }
    }
}
