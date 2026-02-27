import Foundation
import Security

/// Secure storage for the mnemonic seed phrase using iOS Keychain
class KeychainService {
    private let serviceName = "com.cashu.wallet"
    private let mnemonicKey = "wallet_mnemonic"
    private let nostrPrivateKeyKey = "nostr_private_key"
    
    // MARK: - Mnemonic Operations
    
    /// Save mnemonic to Keychain
    func saveMnemonic(_ mnemonic: String) throws {
        guard let data = mnemonic.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        
        // Delete existing item first
        try? deleteMnemonic()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: mnemonicKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
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
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
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
        
        let status = SecItemDelete(query as CFDictionary)
        
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
        guard let data = privateKeyHex.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        
        // Delete existing item first
        try? deleteNostrPrivateKey()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: nostrPrivateKeyKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    /// Load Nostr private key from Keychain
    func loadNostrPrivateKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: nostrPrivateKeyKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
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
    
    /// Delete Nostr private key from Keychain
    func deleteNostrPrivateKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: nostrPrivateKeyKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    /// Check if custom Nostr private key exists
    func hasNostrPrivateKey() -> Bool {
        do {
            return try loadNostrPrivateKey() != nil
        } catch {
            return false
        }
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
