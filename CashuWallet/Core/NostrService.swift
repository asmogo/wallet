import Foundation
import SwiftUI
import CryptoKit
import P256K

// MARK: - Signer Type

/// Type of Nostr key source (matches cashu.me implementation)
enum NostrSignerType: String, Codable, CaseIterable {
    case seed = "SEED"           // Uses wallet seed (default)
    case privateKey = "PRIVATEKEY" // Uses custom nsec/private key
    
    var displayName: String {
        switch self {
        case .seed: return "Wallet Seed"
        case .privateKey: return "Custom Key"
        }
    }
    
    var description: String {
        switch self {
        case .seed: return "Derived from your wallet's seed phrase"
        case .privateKey: return "Use a custom Nostr private key"
        }
    }
}

/// Service for Nostr key management and NIP-98 HTTP authentication
/// Uses swift-secp256k1 P256K library for proper BIP-340 Schnorr signatures
@MainActor
class NostrService: ObservableObject {
    static let shared = NostrService()
    
    // MARK: - Published Properties
    
    /// Public key in hex format (32 bytes x-only)
    @Published var publicKeyHex: String = ""
    
    /// Public key in bech32 npub format
    @Published var npub: String = ""
    
    /// Private key in bech32 nsec format (for display/export)
    @Published var nsec: String = ""
    
    /// Whether the keypair has been initialized
    @Published var isInitialized: Bool = false
    
    /// Current signer type
    @Published var signerType: NostrSignerType = .seed {
        didSet {
            settingsStore.nostrSignerType = signerType.rawValue
        }
    }
    
    // MARK: - Private Properties
    
    private var privateKey: P256K.Schnorr.PrivateKey?
    private var currentSeed: Data?  // Store seed for switching back
    private let keychain = KeychainService()
    private let settingsStore = SettingsStore.shared
    
    // MARK: - Initialization
    
    private init() {
        // Load saved signer type
        if let savedType = settingsStore.nostrSignerType,
           let type = NostrSignerType(rawValue: savedType) {
            self.signerType = type
        }
    }
    
    // MARK: - Key Derivation
    
    /// Derive Nostr keypair from wallet seed
    /// Uses first 32 bytes of seed as private key (same as cashu.me)
    func deriveKeypair(from seed: Data) throws {
        guard seed.count >= 32 else {
            throw NostrError.invalidSeed
        }
        
        // Store seed for later use (switching back to seed-derived key)
        self.currentSeed = seed
        
        // Check if we should use a custom private key
        if signerType == .privateKey, let customKeyHex = try? keychain.loadNostrPrivateKey() {
            try setPrivateKey(fromHex: customKeyHex)
            return
        }
        
        // Use seed-derived key
        signerType = .seed
        let privateKeyBytes = Array(seed.prefix(32))
        try setPrivateKey(fromBytes: privateKeyBytes)
    }
    
    /// Set private key from raw bytes
    private func setPrivateKey(fromBytes privateKeyBytes: [UInt8]) throws {
        do {
            // Create P256K Schnorr private key
            let privKey = try P256K.Schnorr.PrivateKey(dataRepresentation: privateKeyBytes)
            self.privateKey = privKey
            
            // Get x-only public key (32 bytes)
            let xonlyPubKey = privKey.xonly
            let pubKeyBytes = xonlyPubKey.bytes
            
            // Set public key hex
            self.publicKeyHex = pubKeyBytes.map { String(format: "%02x", $0) }.joined()
            
            // Convert to bech32 npub
            self.npub = try Bech32.encode(hrp: "npub", data: Data(pubKeyBytes))
            
            // Convert private key to nsec for display/export
            self.nsec = try Bech32.encode(hrp: "nsec", data: Data(privateKeyBytes))
            
            self.isInitialized = true
            
            print("Nostr keypair initialized (\(signerType.displayName)):")
            print("  pubkey: \(publicKeyHex)")
            print("  npub: \(npub)")
        } catch {
            print("Failed to create Nostr keys: \(error)")
            throw NostrError.keypairCreationFailed
        }
    }
    
    /// Set private key from hex string
    private func setPrivateKey(fromHex hex: String) throws {
        guard let data = Data(hexString: hex), data.count == 32 else {
            throw NostrError.invalidPrivateKey
        }
        try setPrivateKey(fromBytes: Array(data))
    }
    
    // MARK: - Key Management
    
    /// Generate a new random Nostr keypair
    func generateRandomKeypair() throws {
        var randomBytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, 32, &randomBytes)
        guard status == errSecSuccess else {
            throw NostrError.randomGenerationFailed
        }
        
        // Save to keychain
        let hexKey = randomBytes.map { String(format: "%02x", $0) }.joined()
        try keychain.saveNostrPrivateKey(hexKey)
        
        // Set as current key
        signerType = .privateKey
        try setPrivateKey(fromBytes: randomBytes)
        
        print("Generated new random Nostr keypair")
    }
    
    /// Import a private key from nsec (bech32) format
    func importNsec(_ nsecString: String) throws {
        // Decode nsec to get raw private key bytes
        let privateKeyBytes = try Bech32.decode(hrp: "nsec", bech32: nsecString)
        guard privateKeyBytes.count == 32 else {
            throw NostrError.invalidNsec
        }
        
        // Save to keychain
        let hexKey = privateKeyBytes.map { String(format: "%02x", $0) }.joined()
        try keychain.saveNostrPrivateKey(hexKey)
        
        // Set as current key
        signerType = .privateKey
        try setPrivateKey(fromBytes: privateKeyBytes)
        
        print("Imported nsec successfully")
    }
    
    /// Reset to seed-derived key
    func resetToSeedKey() throws {
        guard let seed = currentSeed else {
            throw NostrError.noSeedAvailable
        }
        
        // Delete custom key from keychain
        try? keychain.deleteNostrPrivateKey()
        
        // Switch back to seed
        signerType = .seed
        let privateKeyBytes = Array(seed.prefix(32))
        try setPrivateKey(fromBytes: privateKeyBytes)
        
        print("Reset to seed-derived Nostr key")
    }
    
    /// Switch signer type (called from settings)
    func switchSignerType(to type: NostrSignerType) throws {
        switch type {
        case .seed:
            try resetToSeedKey()
        case .privateKey:
            // Check if we have a custom key stored
            if let customKeyHex = try? keychain.loadNostrPrivateKey() {
                signerType = .privateKey
                try setPrivateKey(fromHex: customKeyHex)
            } else {
                // No custom key exists, generate one
                try generateRandomKeypair()
            }
        }
    }
    
    /// Check if a custom private key is stored
    func hasCustomPrivateKey() -> Bool {
        return keychain.hasNostrPrivateKey()
    }
    
    /// Get the current nsec for copying
    func getNsec() -> String {
        return nsec
    }
    
    /// Get private key hex (for internal use)
    func getPrivateKeyHex() -> String? {
        guard let privKey = privateKey else { return nil }
        // Get raw bytes from the private key
        let bytes = privKey.dataRepresentation
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Get the npub Lightning address for a given domain
    func getLightningAddress(domain: String) -> String {
        guard isInitialized else { return "" }
        return "\(npub)@\(domain)"
    }
    
    // MARK: - NIP-98 HTTP Auth
    
    /// Generate NIP-98 authorization header for HTTP requests
    /// NIP-98 uses kind 27235 events with URL and method tags
    func generateNIP98AuthHeader(url: String, method: String) throws -> String {
        guard let privKey = privateKey else {
            throw NostrError.notInitialized
        }
        
        // Build the NIP-98 event
        let createdAt = Int(Date().timeIntervalSince1970)
        
        // Tags array - method should match exactly what will be sent in HTTP
        let httpMethod = method.uppercased()
        let tags: [[String]] = [["u", url], ["method", httpMethod]]
        
        // Calculate event ID (SHA256 of serialized event array)
        // Format: [0, pubkey, created_at, kind, tags, content]
        let eventId = try calculateEventId(
            pubkey: publicKeyHex,
            createdAt: createdAt,
            kind: 27235,
            tags: tags,
            content: ""
        )
        
        // Sign the event ID using BIP-340 Schnorr
        guard let eventIdData = Data(hexString: eventId), eventIdData.count == 32 else {
            throw NostrError.signingFailed
        }
        
        // Create Schnorr signature using P256K
        var messageBytes = Array(eventIdData)
        
        // Generate auxiliary randomness for signing (32 bytes)
        var auxRand = Array(repeating: UInt8(0), count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, 32, &auxRand)
        if status != errSecSuccess {
            // Fallback: use zeros if random generation fails
            auxRand = Array(repeating: UInt8(0), count: 32)
        }
        
        let signature = try privKey.signature(message: &messageBytes, auxiliaryRand: &auxRand)
        let sigBytes = signature.dataRepresentation
        
        // Signature must be exactly 64 bytes
        guard sigBytes.count == 64 else {
            throw NostrError.signingFailed
        }
        
        let signatureHex = sigBytes.map { String(format: "%02x", $0) }.joined()
        
        // Build the signed event JSON manually to ensure exact field ordering
        // Field order matches NIP-98 spec: id, pubkey, content, kind, created_at, tags, sig
        // Use .withoutEscapingSlashes to prevent URLs from being escaped (https:// not https:\/\/)
        let tagsJson = try JSONSerialization.data(withJSONObject: tags, options: [.withoutEscapingSlashes])
        let tagsString = String(data: tagsJson, encoding: .utf8) ?? "[]"
        
        let jsonString = """
{"id":"\(eventId)","pubkey":"\(publicKeyHex)","content":"","kind":27235,"created_at":\(createdAt),"tags":\(tagsString),"sig":"\(signatureHex)"}
"""
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw NostrError.signingFailed
        }

        return jsonData.base64EncodedString()
    }
    
    // MARK: - Event ID Calculation
    
    /// Calculate Nostr event ID as SHA256 of serialized event array
    /// Format: [0, pubkey, created_at, kind, tags, content]
    /// This MUST match the exact format specified in NIP-01
    private func calculateEventId(
        pubkey: String,
        createdAt: Int,
        kind: Int,
        tags: [[String]],
        content: String
    ) throws -> String {
        // Build the commitment array matching nostr-tools exactly:
        // JSON.stringify([0, evt.pubkey, evt.created_at, evt.kind, evt.tags, evt.content])
        
        // We need to serialize this as a JSON array with the exact format
        let commitment = NostrCommitment(
            zero: 0,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content
        )
        
        // Encode as JSON array
        // CRITICAL: Use .withoutEscapingSlashes to match nostr-tools behavior
        // Without this, URLs like "https://..." become "https:\/\/..." which changes the hash
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let commitmentData = try encoder.encode(commitment)
        
        // SHA256 hash
        let hash = SHA256.hash(data: commitmentData)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Nostr Event Structures

/// Represents a signed Nostr event
/// Field order matches NIP-01/NIP-98: id, pubkey, content, kind, created_at, tags, sig
struct NostrEvent: Encodable {
    let id: String
    let pubkey: String
    let content: String
    let kind: Int
    let createdAt: Int
    let tags: [[String]]
    let sig: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case pubkey
        case content
        case kind
        case createdAt = "created_at"
        case tags
        case sig
    }
    
    // Custom encoding to ensure exact field order
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(pubkey, forKey: .pubkey)
        try container.encode(content, forKey: .content)
        try container.encode(kind, forKey: .kind)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(tags, forKey: .tags)
        try container.encode(sig, forKey: .sig)
    }
}

/// Helper for encoding the commitment array
/// Format: [0, pubkey, created_at, kind, tags, content]
struct NostrCommitment: Encodable {
    let zero: Int
    let pubkey: String
    let createdAt: Int
    let kind: Int
    let tags: [[String]]
    let content: String
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(zero)
        try container.encode(pubkey)
        try container.encode(createdAt)
        try container.encode(kind)
        try container.encode(tags)
        try container.encode(content)
    }
}

// MARK: - Error Types

enum NostrError: LocalizedError {
    case invalidSeed
    case keypairCreationFailed
    case notInitialized
    case signingFailed
    case invalidPrivateKey
    case invalidNsec
    case randomGenerationFailed
    case noSeedAvailable
    case bech32DecodingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidSeed:
            return "Invalid seed data - must be at least 32 bytes"
        case .keypairCreationFailed:
            return "Failed to create Nostr keypair"
        case .notInitialized:
            return "Nostr service not initialized"
        case .signingFailed:
            return "Failed to sign Nostr event"
        case .invalidPrivateKey:
            return "Invalid private key - must be 32 bytes"
        case .invalidNsec:
            return "Invalid nsec format"
        case .randomGenerationFailed:
            return "Failed to generate random bytes"
        case .noSeedAvailable:
            return "No wallet seed available"
        case .bech32DecodingFailed:
            return "Failed to decode bech32 string"
        }
    }
}

// MARK: - Bech32 Encoding

/// Simple Bech32 encoder/decoder for npub/nsec format
enum Bech32 {
    private static let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    
    static func encode(hrp: String, data: Data) throws -> String {
        // Convert 8-bit data to 5-bit groups
        let converted = try convertBits(data: Array(data), fromBits: 8, toBits: 5, pad: true)
        
        // Calculate checksum
        let checksum = createChecksum(hrp: hrp, data: converted)
        
        // Encode data + checksum
        var result = hrp + "1"
        for value in converted + checksum {
            let index = charset.index(charset.startIndex, offsetBy: Int(value))
            result.append(charset[index])
        }
        
        return result
    }
    
    /// Decode a bech32 string to raw bytes
    static func decode(hrp expectedHrp: String, bech32: String) throws -> [UInt8] {
        let lowercased = bech32.lowercased()
        
        // Find the separator (last '1' in the string)
        guard let separatorIndex = lowercased.lastIndex(of: "1") else {
            throw NostrError.bech32DecodingFailed
        }
        
        let hrp = String(lowercased[..<separatorIndex])
        guard hrp == expectedHrp else {
            throw NostrError.bech32DecodingFailed
        }
        
        let dataPartStart = lowercased.index(after: separatorIndex)
        let dataPart = String(lowercased[dataPartStart...])
        
        // Decode characters to 5-bit values
        var values: [UInt8] = []
        for char in dataPart {
            guard let index = charset.firstIndex(of: char) else {
                throw NostrError.bech32DecodingFailed
            }
            values.append(UInt8(charset.distance(from: charset.startIndex, to: index)))
        }
        
        // Verify checksum
        guard verifyChecksum(hrp: hrp, data: values) else {
            throw NostrError.bech32DecodingFailed
        }
        
        // Remove checksum (last 6 bytes)
        let dataWithoutChecksum = Array(values.dropLast(6))
        
        // Convert from 5-bit to 8-bit
        let result = try convertBits(data: dataWithoutChecksum, fromBits: 5, toBits: 8, pad: false)
        
        return result
    }
    
    private static func verifyChecksum(hrp: String, data: [UInt8]) -> Bool {
        let values = hrpExpand(hrp) + data
        return polymod(values) == 1
    }
    
    private static func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) throws -> [UInt8] {
        var acc = 0
        var bits = 0
        var result: [UInt8] = []
        let maxv = (1 << toBits) - 1
        
        for value in data {
            acc = (acc << fromBits) | Int(value)
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }
        
        if pad {
            if bits > 0 {
                result.append(UInt8((acc << (toBits - bits)) & maxv))
            }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
            throw NSError(domain: "Bech32", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid padding"])
        }
        
        return result
    }
    
    private static func polymod(_ values: [UInt8]) -> UInt32 {
        let generator: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk: UInt32 = 1
        
        for value in values {
            let top = chk >> 25
            chk = ((chk & 0x1ffffff) << 5) ^ UInt32(value)
            for i in 0..<5 {
                if ((top >> i) & 1) == 1 {
                    chk ^= generator[i]
                }
            }
        }
        
        return chk
    }
    
    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        var result: [UInt8] = []
        for char in hrp {
            guard let ascii = char.asciiValue else { return [] }
            result.append(UInt8(ascii >> 5))
        }
        result.append(0)
        for char in hrp {
            guard let ascii = char.asciiValue else { return [] }
            result.append(UInt8(ascii & 31))
        }
        return result
    }
    
    private static func createChecksum(hrp: String, data: [UInt8]) -> [UInt8] {
        let values = hrpExpand(hrp) + data + [0, 0, 0, 0, 0, 0]
        let polymod = polymod(values) ^ 1
        var result: [UInt8] = []
        for i in 0..<6 {
            result.append(UInt8((polymod >> (5 * (5 - i))) & 31))
        }
        return result
    }
}

// MARK: - Data Hex Extension

extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
}
