import Foundation
import CryptoKit
import P256K
import Security
#if canImport(CommonCrypto)
import CommonCrypto
#endif

struct NostrRelayEvent: Codable, Sendable {
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

    init(id: String, pubkey: String, content: String, kind: Int, createdAt: Int, tags: [[String]], sig: String) {
        self.id = id
        self.pubkey = pubkey
        self.content = content
        self.kind = kind
        self.createdAt = createdAt
        self.tags = tags
        self.sig = sig
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.pubkey = try container.decode(String.self, forKey: .pubkey)
        self.content = try container.decode(String.self, forKey: .content)
        self.kind = try container.decode(Int.self, forKey: .kind)
        self.createdAt = try container.decode(Int.self, forKey: .createdAt)
        self.tags = try container.decode([[String]].self, forKey: .tags)
        self.sig = try container.decode(String.self, forKey: .sig)
    }

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

struct NostrDirectMessageEvent: Codable, Sendable {
    let id: String
    let pubkey: String
    let content: String
    let kind: Int
    let createdAt: Int
    let tags: [[String]]

    enum CodingKeys: String, CodingKey {
        case id
        case pubkey
        case content
        case kind
        case createdAt = "created_at"
        case tags
    }

    init(id: String, pubkey: String, content: String, kind: Int, createdAt: Int, tags: [[String]]) {
        self.id = id
        self.pubkey = pubkey
        self.content = content
        self.kind = kind
        self.createdAt = createdAt
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.pubkey = try container.decode(String.self, forKey: .pubkey)
        self.content = try container.decode(String.self, forKey: .content)
        self.kind = try container.decode(Int.self, forKey: .kind)
        self.createdAt = try container.decode(Int.self, forKey: .createdAt)
        self.tags = try container.decode([[String]].self, forKey: .tags)
    }
}

struct NostrFilter: Sendable {
    var kinds: [Int]? = nil
    var authors: [String]? = nil
    var since: Int? = nil
    var limit: Int? = nil
    var tags: [String: [String]] = [:]

    func asJSONObject() -> [String: Any] {
        var object: [String: Any] = [:]
        if let kinds {
            object["kinds"] = kinds
        }
        if let authors {
            object["authors"] = authors
        }
        if let since {
            object["since"] = since
        }
        if let limit {
            object["limit"] = limit
        }
        for (tag, values) in tags where !values.isEmpty {
            object["#\(tag)"] = values
        }
        return object
    }
}

enum NostrEncryptionMode: String, Sendable {
    case nip04 = "nip04"
    case nip44v2 = "nip44_v2"
}

enum NostrSupportError: LocalizedError {
    case missingPrivateKey
    case invalidHexKey
    case invalidPublicKey
    case invalidCiphertext
    case invalidPayload
    case invalidPadding
    case unsupportedVersion
    case invalidUTF8
    case commonCryptoUnavailable
    case pbkdfFailed
    case noRelayAcknowledged

    var errorDescription: String? {
        switch self {
        case .missingPrivateKey:
            return "Missing Nostr private key"
        case .invalidHexKey:
            return "Invalid Nostr hex key"
        case .invalidPublicKey:
            return "Invalid Nostr public key"
        case .invalidCiphertext:
            return "Invalid encrypted payload"
        case .invalidPayload:
            return "Invalid Nostr payload"
        case .invalidPadding:
            return "Invalid payload padding"
        case .unsupportedVersion:
            return "Unsupported encryption version"
        case .invalidUTF8:
            return "Payload is not valid UTF-8"
        case .commonCryptoUnavailable:
            return "Required cryptography support is unavailable"
        case .pbkdfFailed:
            return "Failed to derive wallet seed"
        case .noRelayAcknowledged:
            return "No relay accepted the event"
        }
    }
}

enum NostrProfilePointer {
    private enum TLVType: UInt8 {
        case special = 0
        case relay = 1
    }

    static func encodeNprofile(pubkeyHex: String, relays: [String]) throws -> String {
        guard let pubkeyData = Data(hexString: pubkeyHex), pubkeyData.count == 32 else {
            throw NostrSupportError.invalidPublicKey
        }

        var payload = Data()
        payload.append(TLVType.special.rawValue)
        payload.append(UInt8(pubkeyData.count))
        payload.append(pubkeyData)

        for relay in relays {
            let normalizedRelay = relay.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedRelay.isEmpty, let relayData = normalizedRelay.data(using: .utf8), relayData.count <= Int(UInt8.max) else {
                continue
            }
            payload.append(TLVType.relay.rawValue)
            payload.append(UInt8(relayData.count))
            payload.append(relayData)
        }

        return try Bech32.encode(hrp: "nprofile", data: payload)
    }
}

enum NostrCrypto {
    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return encoder
    }()

    static func bip39Seed(from mnemonic: String, passphrase: String = "") throws -> Data {
        #if canImport(CommonCrypto)
        let normalizedMnemonic = mnemonic.decomposedStringWithCompatibilityMapping
        let normalizedSalt = ("mnemonic" + passphrase).decomposedStringWithCompatibilityMapping

        guard let passwordData = normalizedMnemonic.data(using: .utf8),
              let saltData = normalizedSalt.data(using: .utf8) else {
            throw NostrSupportError.pbkdfFailed
        }

        var derived = Data(repeating: 0, count: 64)
        let derivedCount = derived.count
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            passwordData.withUnsafeBytes { passwordBytes in
                saltData.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                        2048,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        derivedCount
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw NostrSupportError.pbkdfFailed
        }

        return derived
        #else
        throw NostrSupportError.commonCryptoUnavailable
        #endif
    }

    static func publicKeyHex(for privateKeyHex: String) throws -> String {
        guard let privateKeyData = Data(hexString: privateKeyHex), privateKeyData.count == 32 else {
            throw NostrSupportError.invalidHexKey
        }
        let privateKey = try P256K.Schnorr.PrivateKey(dataRepresentation: privateKeyData)
        return hexString(privateKey.xonly.bytes)
    }

    static func signEvent(
        privateKeyHex: String,
        kind: Int,
        tags: [[String]],
        content: String,
        createdAt: Int = Int(Date().timeIntervalSince1970)
    ) throws -> NostrRelayEvent {
        guard let privateKeyData = Data(hexString: privateKeyHex), privateKeyData.count == 32 else {
            throw NostrSupportError.invalidHexKey
        }

        let privateKey = try P256K.Schnorr.PrivateKey(dataRepresentation: privateKeyData)
        let pubkeyHex = hexString(privateKey.xonly.bytes)
        let eventId = try calculateEventId(pubkey: pubkeyHex, createdAt: createdAt, kind: kind, tags: tags, content: content)

        guard let eventIdData = Data(hexString: eventId) else {
            throw NostrError.signingFailed
        }

        var messageBytes = Array(eventIdData)
        var auxRand = secureRandomBytes(count: 32)
        let signature = try privateKey.signature(message: &messageBytes, auxiliaryRand: &auxRand)
        let signatureHex = hexString(signature.dataRepresentation)

        return NostrRelayEvent(
            id: eventId,
            pubkey: pubkeyHex,
            content: content,
            kind: kind,
            createdAt: createdAt,
            tags: tags,
            sig: signatureHex
        )
    }

    static func verifyEvent(_ event: NostrRelayEvent) -> Bool {
        guard let eventIdData = Data(hexString: event.id),
              let signatureData = Data(hexString: event.sig),
              let pubkeyData = Data(hexString: event.pubkey),
              eventIdData.count == 32,
              signatureData.count == 64,
              pubkeyData.count == 32 else {
            return false
        }

        do {
            let expectedEventId = try calculateEventId(
                pubkey: event.pubkey,
                createdAt: event.createdAt,
                kind: event.kind,
                tags: event.tags,
                content: event.content
            )
            guard expectedEventId == event.id else {
                return false
            }

            let xonlyKey = P256K.Schnorr.XonlyKey(dataRepresentation: pubkeyData, keyParity: 0)
            let signature = try P256K.Schnorr.SchnorrSignature(dataRepresentation: signatureData)
            var messageBytes = Array(eventIdData)
            return xonlyKey.isValid(signature, for: &messageBytes)
        } catch {
            return false
        }
    }

    static func nip04Encrypt(plaintext: String, privateKeyHex: String, publicKeyHex: String) throws -> String {
        guard let plaintextData = plaintext.data(using: .utf8) else {
            throw NostrSupportError.invalidUTF8
        }
        let sharedX = try sharedXCoordinate(privateKeyHex: privateKeyHex, publicKeyHex: publicKeyHex)
        let key = SymmetricKey(data: sharedX)
        let iv = Data(secureRandomBytes(count: kCCBlockSizeAES128))
        let encrypted = try aesCBCEncrypt(data: plaintextData, key: key, iv: iv)
        return encrypted.base64EncodedString() + "?iv=" + iv.base64EncodedString()
    }

    static func nip04Decrypt(payload: String, privateKeyHex: String, publicKeyHex: String) throws -> String {
        let parts = payload.components(separatedBy: "?iv=")
        guard parts.count == 2,
              let cipherData = Data(base64Encoded: parts[0]),
              let iv = Data(base64Encoded: parts[1]) else {
            throw NostrSupportError.invalidCiphertext
        }

        let sharedX = try sharedXCoordinate(privateKeyHex: privateKeyHex, publicKeyHex: publicKeyHex)
        let key = SymmetricKey(data: sharedX)
        let decrypted = try aesCBCDecrypt(data: cipherData, key: key, iv: iv)
        guard let plaintext = String(data: decrypted, encoding: .utf8) else {
            throw NostrSupportError.invalidUTF8
        }
        return plaintext
    }

    static func nip44Encrypt(plaintext: String, privateKeyHex: String, publicKeyHex: String) throws -> String {
        let conversationKey = try conversationKey(privateKeyHex: privateKeyHex, publicKeyHex: publicKeyHex)
        let nonce = Data(secureRandomBytes(count: 32))
        let (chachaKey, chachaNonce, hmacKey) = try messageKeys(conversationKey: conversationKey, nonce: nonce)
        let padded = try padNip44(plaintext)
        let ciphertext = Data(try ChaCha20.xor(data: padded, key: chachaKey, nonce: chachaNonce, counter: 0))
        let mac = hmacSHA256(key: hmacKey, message: nonce + ciphertext)
        var payload = Data([2])
        payload.append(nonce)
        payload.append(ciphertext)
        payload.append(mac)
        return payload.base64EncodedString()
    }

    static func nip44Decrypt(payload: String, privateKeyHex: String, publicKeyHex: String) throws -> String {
        guard !payload.isEmpty else {
            throw NostrSupportError.invalidPayload
        }
        if payload.first == "#" {
            throw NostrSupportError.unsupportedVersion
        }
        guard payload.count >= 132, payload.count <= 87472,
              let data = Data(base64Encoded: payload) else {
            throw NostrSupportError.invalidPayload
        }
        guard data.count >= 99, data.count <= 65603 else {
            throw NostrSupportError.invalidPayload
        }
        guard data.first == 2 else {
            throw NostrSupportError.unsupportedVersion
        }

        let nonce = data.subdata(in: 1..<33)
        let mac = data.suffix(32)
        let ciphertext = data.subdata(in: 33..<(data.count - 32))
        let conversationKey = try conversationKey(privateKeyHex: privateKeyHex, publicKeyHex: publicKeyHex)
        let (chachaKey, chachaNonce, hmacKey) = try messageKeys(conversationKey: conversationKey, nonce: nonce)
        let expectedMac = hmacSHA256(key: hmacKey, message: nonce + ciphertext)
        guard constantTimeEqual(expectedMac, Data(mac)) else {
            throw NostrSupportError.invalidCiphertext
        }

        let paddedPlaintext = Data(try ChaCha20.xor(data: ciphertext, key: chachaKey, nonce: chachaNonce, counter: 0))
        return try unpadNip44(paddedPlaintext)
    }

    private static func calculateEventId(
        pubkey: String,
        createdAt: Int,
        kind: Int,
        tags: [[String]],
        content: String
    ) throws -> String {
        let commitment = NostrCommitment(
            zero: 0,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content
        )
        let data = try jsonEncoder.encode(commitment)
        return hexString(CryptoKit.SHA256.hash(data: data))
    }

    private static func conversationKey(privateKeyHex: String, publicKeyHex: String) throws -> Data {
        let sharedX = try sharedXCoordinate(privateKeyHex: privateKeyHex, publicKeyHex: publicKeyHex)
        let salt = Data("nip44-v2".utf8)
        return hkdfExtract(salt: salt, inputKeyMaterial: sharedX)
    }

    private static func sharedXCoordinate(privateKeyHex: String, publicKeyHex: String) throws -> Data {
        guard let privateKeyData = Data(hexString: privateKeyHex), privateKeyData.count == 32 else {
            throw NostrSupportError.invalidHexKey
        }
        guard let publicKeyData = Data(hexString: publicKeyHex), publicKeyData.count == 32 else {
            throw NostrSupportError.invalidPublicKey
        }

        let privateKey = try P256K.KeyAgreement.PrivateKey(dataRepresentation: privateKeyData, format: .compressed)
        let compressedPublicKey = Data([0x02]) + publicKeyData
        let publicKey = try P256K.KeyAgreement.PublicKey(dataRepresentation: compressedPublicKey, format: .compressed)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        let sharedData = sharedSecret.withUnsafeBytes { Data($0) }
        guard sharedData.count == 33 else {
            throw NostrSupportError.invalidPayload
        }
        return sharedData.dropFirst()
    }

    private static func messageKeys(conversationKey: Data, nonce: Data) throws -> (key: Data, nonce: Data, hmacKey: Data) {
        guard conversationKey.count == 32, nonce.count == 32 else {
            throw NostrSupportError.invalidPayload
        }
        let expanded = hkdfExpand(pseudoRandomKey: conversationKey, info: nonce, outputLength: 76)
        return (
            expanded.subdata(in: 0..<32),
            expanded.subdata(in: 32..<44),
            expanded.subdata(in: 44..<76)
        )
    }

    private static func padNip44(_ plaintext: String) throws -> Data {
        guard let plaintextData = plaintext.data(using: .utf8) else {
            throw NostrSupportError.invalidUTF8
        }
        let length = plaintextData.count
        guard length >= 1, length <= 65_535 else {
            throw NostrSupportError.invalidPayload
        }
        let paddedLength = calcPaddedLength(length)
        var data = Data()
        data.append(contentsOf: UInt16(length).bigEndianBytes)
        data.append(plaintextData)
        data.append(Data(repeating: 0, count: paddedLength - length))
        return data
    }

    private static func unpadNip44(_ padded: Data) throws -> String {
        guard padded.count >= 34 else {
            throw NostrSupportError.invalidPadding
        }
        let length = Int(UInt16(bigEndianBytes: Array(padded.prefix(2))))
        guard length > 0 else {
            throw NostrSupportError.invalidPadding
        }
        let expectedLength = 2 + calcPaddedLength(length)
        guard padded.count == expectedLength else {
            throw NostrSupportError.invalidPadding
        }
        let plaintextData = padded.subdata(in: 2..<(2 + length))
        let suffix = padded.suffix(from: 2 + length)
        guard suffix.allSatisfy({ $0 == 0 }) else {
            throw NostrSupportError.invalidPadding
        }
        guard let plaintext = String(data: plaintextData, encoding: .utf8) else {
            throw NostrSupportError.invalidUTF8
        }
        return plaintext
    }

    private static func calcPaddedLength(_ unpaddedLength: Int) -> Int {
        guard unpaddedLength > 32 else {
            return 32
        }

        let nextPower = 1 << (Int(log2(Double(unpaddedLength - 1))) + 1)
        let chunk = nextPower <= 256 ? 32 : nextPower / 8
        return chunk * (((unpaddedLength - 1) / chunk) + 1)
    }

    private static func hkdfExtract(salt: Data, inputKeyMaterial: Data) -> Data {
        Data(HMAC<CryptoKit.SHA256>.authenticationCode(for: inputKeyMaterial, using: SymmetricKey(data: salt)))
    }

    private static func hkdfExpand(pseudoRandomKey: Data, info: Data, outputLength: Int) -> Data {
        var output = Data()
        var previous = Data()
        var counter: UInt8 = 1
        while output.count < outputLength {
            var blockInput = Data()
            blockInput.append(previous)
            blockInput.append(info)
            blockInput.append(counter)
            previous = Data(HMAC<CryptoKit.SHA256>.authenticationCode(for: blockInput, using: SymmetricKey(data: pseudoRandomKey)))
            output.append(previous)
            counter &+= 1
        }
        return output.prefix(outputLength)
    }

    private static func hmacSHA256(key: Data, message: Data) -> Data {
        Data(HMAC<CryptoKit.SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            diff |= left ^ right
        }
        return diff == 0
    }

    private static func secureRandomBytes(count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if status == errSecSuccess {
            return bytes
        }
        return [UInt8](repeating: 0, count: count)
    }

    private static func aesCBCEncrypt(data: Data, key: SymmetricKey, iv: Data) throws -> Data {
        #if canImport(CommonCrypto)
        let keyData = key.withUnsafeBytes { Data($0) }
        return try crypt(operation: CCOperation(kCCEncrypt), data: data, key: keyData, iv: iv)
        #else
        throw NostrSupportError.commonCryptoUnavailable
        #endif
    }

    private static func aesCBCDecrypt(data: Data, key: SymmetricKey, iv: Data) throws -> Data {
        #if canImport(CommonCrypto)
        let keyData = key.withUnsafeBytes { Data($0) }
        return try crypt(operation: CCOperation(kCCDecrypt), data: data, key: keyData, iv: iv)
        #else
        throw NostrSupportError.commonCryptoUnavailable
        #endif
    }

    #if canImport(CommonCrypto)
    private static func crypt(operation: CCOperation, data: Data, key: Data, iv: Data) throws -> Data {
        var output = Data(repeating: 0, count: data.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress,
                            data.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw NostrSupportError.invalidCiphertext
        }
        output.removeSubrange(outputLength..<output.count)
        return output
    }
    #endif
}

enum NostrRelayClient {
    static func publish(event: NostrRelayEvent, to relays: [String]) async throws {
        let normalizedRelays = normalizeRelays(relays)
        guard !normalizedRelays.isEmpty else {
            throw NostrSupportError.noRelayAcknowledged
        }

        let eventData = try JSONEncoder().encode(event)
        let eventObject = try JSONSerialization.jsonObject(with: eventData)
        let messageData = try JSONSerialization.data(withJSONObject: ["EVENT", eventObject], options: [.withoutEscapingSlashes])
        let messageString = String(decoding: messageData, as: UTF8.self)

        let successCount = await withTaskGroup(of: Bool.self) { group in
            for relay in normalizedRelays {
                group.addTask {
                    do {
                        try await publishToRelay(relay: relay, message: messageString)
                        return true
                    } catch {
                        return false
                    }
                }
            }

            var successes = 0
            for await success in group {
                if success {
                    successes += 1
                }
            }
            return successes
        }

        guard successCount > 0 else {
            throw NostrSupportError.noRelayAcknowledged
        }
    }

    static func fetchEvents(from relays: [String], filter: NostrFilter, timeout: TimeInterval = 4) async -> [NostrRelayEvent] {
        let normalizedRelays = normalizeRelays(relays)
        let results = await withTaskGroup(of: [NostrRelayEvent].self) { group in
            for relay in normalizedRelays {
                group.addTask {
                    await fetchFromRelay(relay: relay, filter: filter, timeout: timeout)
                }
            }

            var merged: [NostrRelayEvent] = []
            for await events in group {
                merged.append(contentsOf: events)
            }
            return merged
        }

        var seenIds = Set<String>()
        return results.filter { event in
            seenIds.insert(event.id).inserted
        }
    }

    private static func publishToRelay(relay: String, message: String) async throws {
        let (session, task) = try makeConnection(relay: relay)
        defer {
            task.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }

        task.resume()
        try await task.send(.string(message))
    }

    private static func fetchFromRelay(relay: String, filter: NostrFilter, timeout: TimeInterval) async -> [NostrRelayEvent] {
        do {
            let (session, task) = try makeConnection(relay: relay)
            defer {
                task.cancel(with: .normalClosure, reason: nil)
                session.invalidateAndCancel()
            }

            let subscriptionId = UUID().uuidString
            let requestData = try JSONSerialization.data(
                withJSONObject: ["REQ", subscriptionId, filter.asJSONObject()],
                options: [.withoutEscapingSlashes]
            )
            let requestString = String(decoding: requestData, as: UTF8.self)

            task.resume()
            try await task.send(.string(requestString))

            var events: [NostrRelayEvent] = []
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                guard let message = try await receiveMessage(task: task, timeout: 0.75) else {
                    break
                }
                switch parseRelayMessage(message) {
                case .event(let event):
                    events.append(event)
                case .eose:
                    return events
                case .other:
                    continue
                }
            }
            return events
        } catch {
            return []
        }
    }

    fileprivate static func normalizeRelays(_ relays: [String]) -> [String] {
        Array(
            Set(
                relays
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { relay in
                        let lower = relay.lowercased()
                        return lower.hasPrefix("wss://") || lower.hasPrefix("ws://")
                    }
            )
        )
    }

    fileprivate static func makeConnection(relay: String) throws -> (URLSession, URLSessionWebSocketTask) {
        guard let url = URL(string: relay) else {
            throw URLError(.badURL)
        }
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration)
        let task = session.webSocketTask(with: url)
        return (session, task)
    }

    fileprivate static func receiveMessage(task: URLSessionWebSocketTask, timeout: TimeInterval) async throws -> URLSessionWebSocketTask.Message? {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message?.self) { group in
            group.addTask {
                try await task.receive()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let result = try await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    fileprivate enum ParsedRelayMessage {
        case event(NostrRelayEvent)
        case eose
        case other
    }

    fileprivate static func parseRelayMessage(_ message: URLSessionWebSocketTask.Message) -> ParsedRelayMessage {
        let text: String
        switch message {
        case .string(let string):
            text = string
        case .data(let data):
            text = String(decoding: data, as: UTF8.self)
        @unknown default:
            return .other
        }

        guard let data = text.data(using: .utf8),
              let rawArray = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let type = rawArray.first as? String else {
            return .other
        }

        if type == "EOSE" {
            return .eose
        }

        guard type == "EVENT", rawArray.count >= 3,
              JSONSerialization.isValidJSONObject(rawArray[2]),
              let eventData = try? JSONSerialization.data(withJSONObject: rawArray[2]),
              let event = try? JSONDecoder().decode(NostrRelayEvent.self, from: eventData) else {
            return .other
        }

        return .event(event)
    }
}

final class NostrRelaySubscription {
    typealias EventHandler = @Sendable (NostrRelayEvent) async -> Void

    private let relays: [String]
    private let filter: NostrFilter
    private let onEvent: EventHandler
    private let lock = NSLock()

    private var receiveTasks: [Task<Void, Never>] = []
    private var websocketTasks: [URLSessionWebSocketTask] = []
    private var sessions: [URLSession] = []
    private var active = false

    init(relays: [String], filter: NostrFilter, onEvent: @escaping EventHandler) {
        self.relays = NostrRelayClient.normalizeRelays(relays)
        self.filter = filter
        self.onEvent = onEvent
    }

    func start() {
        lock.lock()
        guard !active else {
            lock.unlock()
            return
        }
        active = true
        lock.unlock()

        for relay in relays {
            let task: Task<Void, Never> = Task.detached(priority: .background) { [weak self] in
                guard let self else { return }
                await self.listen(to: relay)
            }
            lock.lock()
            receiveTasks.append(task)
            lock.unlock()
        }
    }

    func stop() {
        lock.lock()
        active = false
        let tasks = receiveTasks
        let webSockets = websocketTasks
        let sessions = sessions
        receiveTasks.removeAll()
        websocketTasks.removeAll()
        self.sessions.removeAll()
        lock.unlock()

        tasks.forEach { $0.cancel() }
        webSockets.forEach { $0.cancel(with: .normalClosure, reason: nil) }
        sessions.forEach { $0.invalidateAndCancel() }
    }

    private func listen(to relay: String) async {
        while isActive {
            do {
                let (session, task) = try NostrRelayClient.makeConnection(relay: relay)
                register(session: session, task: task)
                defer { unregister(session: session, task: task) }

                let subscriptionId = UUID().uuidString
                let requestData = try JSONSerialization.data(
                    withJSONObject: ["REQ", subscriptionId, filter.asJSONObject()],
                    options: [.withoutEscapingSlashes]
                )
                let requestString = String(decoding: requestData, as: UTF8.self)

                task.resume()
                try await task.send(.string(requestString))

                while isActive && !Task.isCancelled {
                    let message = try await task.receive()
                    switch NostrRelayClient.parseRelayMessage(message) {
                    case .event(let event):
                        await onEvent(event)
                    case .eose, .other:
                        continue
                    }
                }
            } catch {
                if !isActive || Task.isCancelled {
                    return
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    private func register(session: URLSession, task: URLSessionWebSocketTask) {
        lock.lock()
        sessions.append(session)
        websocketTasks.append(task)
        lock.unlock()
    }

    private func unregister(session: URLSession, task: URLSessionWebSocketTask) {
        lock.lock()
        sessions.removeAll { ObjectIdentifier($0) == ObjectIdentifier(session) }
        websocketTasks.removeAll { ObjectIdentifier($0) == ObjectIdentifier(task) }
        lock.unlock()
    }
}

private enum ChaCha20 {
    private static let constants: [UInt32] = [
        0x6170_7865,
        0x3320_646E,
        0x7962_2D32,
        0x6B20_6574,
    ]

    static func xor(data: Data, key: Data, nonce: Data, counter: UInt32) throws -> [UInt8] {
        guard key.count == 32, nonce.count == 12 else {
            throw NostrSupportError.invalidPayload
        }

        var output = [UInt8](repeating: 0, count: data.count)
        let input = [UInt8](data)
        let keyWords = Array(key).chunked(into: 4).map { UInt32(littleEndianBytes: Array($0)) }
        let nonceWords = Array(nonce).chunked(into: 4).map { UInt32(littleEndianBytes: Array($0)) }

        var blockCounter = counter
        var index = 0
        while index < input.count {
            let block = block(keyWords: keyWords, nonceWords: nonceWords, counter: blockCounter)
            let blockEnd = min(index + 64, input.count)
            for byteIndex in index..<blockEnd {
                output[byteIndex] = input[byteIndex] ^ block[byteIndex - index]
            }
            index += 64
            blockCounter &+= 1
        }
        return output
    }

    private static func block(keyWords: [UInt32], nonceWords: [UInt32], counter: UInt32) -> [UInt8] {
        var state = constants + keyWords + [counter] + nonceWords
        let original = state

        for _ in 0..<10 {
            quarterRound(&state, 0, 4, 8, 12)
            quarterRound(&state, 1, 5, 9, 13)
            quarterRound(&state, 2, 6, 10, 14)
            quarterRound(&state, 3, 7, 11, 15)
            quarterRound(&state, 0, 5, 10, 15)
            quarterRound(&state, 1, 6, 11, 12)
            quarterRound(&state, 2, 7, 8, 13)
            quarterRound(&state, 3, 4, 9, 14)
        }

        for index in 0..<16 {
            state[index] = state[index] &+ original[index]
        }

        return state.flatMap { $0.littleEndianBytes }
    }

    private static func quarterRound(_ state: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        state[a] &+= state[b]
        state[d] ^= state[a]
        state[d] = rotateLeft(state[d], by: 16)

        state[c] &+= state[d]
        state[b] ^= state[c]
        state[b] = rotateLeft(state[b], by: 12)

        state[a] &+= state[b]
        state[d] ^= state[a]
        state[d] = rotateLeft(state[d], by: 8)

        state[c] &+= state[d]
        state[b] ^= state[c]
        state[b] = rotateLeft(state[b], by: 7)
    }

    private static func rotateLeft(_ value: UInt32, by bits: UInt32) -> UInt32 {
        (value << bits) | (value >> (32 - bits))
    }
}

private extension UInt16 {
    var bigEndianBytes: [UInt8] {
        let value = bigEndian
        return [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    init(bigEndianBytes bytes: [UInt8]) {
        self = bytes.reduce(0) { ($0 << 8) | UInt16($1) }
    }
}

private func hexString<T: Sequence>(_ bytes: T) -> String where T.Element == UInt8 {
    bytes.map { String(format: "%02x", $0) }.joined()
}

private extension UInt32 {
    init(littleEndianBytes bytes: [UInt8]) {
        self = bytes.enumerated().reduce(0) { partialResult, element in
            partialResult | (UInt32(element.element) << (UInt32(element.offset) * 8))
        }
    }

    var littleEndianBytes: [UInt8] {
        let value = littleEndian
        return [
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24),
        ]
    }
}

private extension Array where Element == UInt8 {
    func chunked(into size: Int) -> [ArraySlice<UInt8>] {
        stride(from: 0, to: count, by: size).map {
            self[$0..<Swift.min($0 + size, count)]
        }
    }
}
