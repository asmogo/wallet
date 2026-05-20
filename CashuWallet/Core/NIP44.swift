import Foundation
import CryptoKit
import P256K

enum NIP44 {
    enum Error: Swift.Error {
        case invalidPubkey
        case invalidVersion
        case invalidPayload
        case macMismatch
        case lengthMismatch
        case plaintextTooLong
    }

    /// Encrypt `plaintext` with NIP-44 v2. Returns base64 payload.
    static func encrypt(
        plaintext: String,
        senderPrivateKey: Data,
        recipientPubkeyHex: String
    ) throws -> String {
        let conversationKey = try conversationKey(privateKey: senderPrivateKey, pubkeyHex: recipientPubkeyHex)
        var nonce = Data(count: 32)
        let status = nonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard status == errSecSuccess else { throw Error.invalidPayload }
        return try encrypt(plaintext: plaintext, conversationKey: conversationKey, nonce: nonce)
    }

    /// Decrypt a NIP-44 v2 base64 payload.
    static func decrypt(
        payload: String,
        recipientPrivateKey: Data,
        senderPubkeyHex: String
    ) throws -> String {
        let conversationKey = try conversationKey(privateKey: recipientPrivateKey, pubkeyHex: senderPubkeyHex)
        return try decrypt(payload: payload, conversationKey: conversationKey)
    }

    // MARK: - Internal

    static func conversationKey(privateKey: Data, pubkeyHex: String) throws -> Data {
        guard let pubkeyBytes = Data(hex: pubkeyHex), pubkeyBytes.count == 32 else {
            throw Error.invalidPubkey
        }
        // x-only -> uncompressed via 0x02 prefix (parity flag — either works for ECDH X).
        var serialized = Data([0x02])
        serialized.append(pubkeyBytes)
        let pub = try P256K.KeyAgreement.PublicKey(dataRepresentation: serialized, format: .compressed)
        let priv = try P256K.KeyAgreement.PrivateKey(dataRepresentation: privateKey)
        let shared = try priv.sharedSecretFromKeyAgreement(with: pub, format: .compressed)
        // libsecp256k1 returns 33 bytes (1 version byte + 32 X). Strip the version.
        let ssBytes = shared.withUnsafeBytes { Data($0) }
        let x = ssBytes.suffix(32)
        let prk = HKDF<CryptoKit.SHA256>.extract(
            inputKeyMaterial: SymmetricKey(data: x),
            salt: Data("nip44-v2".utf8)
        )
        return prk.withUnsafeBytes { Data($0) }
    }

    static func encrypt(plaintext: String, conversationKey: Data, nonce: Data) throws -> String {
        let plaintextBytes = Data(plaintext.utf8)
        guard plaintextBytes.count >= 1, plaintextBytes.count <= 65_535 else {
            throw Error.plaintextTooLong
        }
        let (chachaKey, chachaNonce, hmacKey) = try derive(conversationKey: conversationKey, nonce: nonce)
        let padded = pad(plaintext: plaintextBytes)
        let ciphertext = try chacha20(key: chachaKey, nonce: chachaNonce, data: padded)
        let mac = hmacAAD(key: hmacKey, aad: nonce, message: ciphertext)
        var payload = Data([0x02])
        payload.append(nonce)
        payload.append(ciphertext)
        payload.append(mac)
        return payload.base64EncodedString()
    }

    static func decrypt(payload: String, conversationKey: Data) throws -> String {
        guard let raw = Data(base64Encoded: payload), raw.count >= 1 + 32 + 32 + 32 else {
            throw Error.invalidPayload
        }
        guard raw[0] == 0x02 else { throw Error.invalidVersion }
        let nonce = raw.subdata(in: 1..<33)
        let mac = raw.suffix(32)
        let ciphertext = raw.subdata(in: 33..<(raw.count - 32))
        let (chachaKey, chachaNonce, hmacKey) = try derive(conversationKey: conversationKey, nonce: nonce)
        let expected = hmacAAD(key: hmacKey, aad: nonce, message: ciphertext)
        guard constantTimeEquals(expected, mac) else { throw Error.macMismatch }
        let padded = try chacha20(key: chachaKey, nonce: chachaNonce, data: ciphertext)
        return try unpad(padded: padded)
    }

    // MARK: - HKDF expand → 76 bytes → split

    private static func derive(conversationKey: Data, nonce: Data) throws -> (chachaKey: Data, chachaNonce: Data, hmacKey: Data) {
        let prk = SymmetricKey(data: conversationKey)
        let derived = HKDF<CryptoKit.SHA256>.expand(pseudoRandomKey: prk, info: nonce, outputByteCount: 76)
        let d = derived.withUnsafeBytes { Data($0) }
        return (d.subdata(in: 0..<32), d.subdata(in: 32..<44), d.subdata(in: 44..<76))
    }

    // MARK: - Padding (NIP-44 v2 spec)

    static func pad(plaintext: Data) -> Data {
        let length = plaintext.count
        let paddedLen = paddedLength(for: length)
        var out = Data(capacity: 2 + paddedLen)
        out.append(UInt8((length >> 8) & 0xFF))
        out.append(UInt8(length & 0xFF))
        out.append(plaintext)
        if paddedLen > length {
            out.append(Data(repeating: 0, count: paddedLen - length))
        }
        return out
    }

    static func unpad(padded: Data) throws -> String {
        guard padded.count >= 2 else { throw Error.invalidPayload }
        let len = (Int(padded[0]) << 8) | Int(padded[1])
        guard len >= 1, len <= padded.count - 2 else { throw Error.lengthMismatch }
        let expectedPaddedLen = paddedLength(for: len)
        guard padded.count == 2 + expectedPaddedLen else { throw Error.lengthMismatch }
        let textBytes = padded.subdata(in: 2..<(2 + len))
        guard let s = String(data: textBytes, encoding: .utf8) else { throw Error.invalidPayload }
        return s
    }

    static func paddedLength(for length: Int) -> Int {
        guard length > 32 else { return 32 }
        let nextPower = 1 << (Int(log2(Double(length - 1))) + 1)
        let chunk: Int = nextPower <= 256 ? 32 : nextPower / 8
        return chunk * (((length - 1) / chunk) + 1)
    }

    // MARK: - Crypto primitives

    private static func chacha20(key: Data, nonce: Data, data: Data) throws -> Data {
        // ChaCha20 stream cipher, IETF variant (96-bit nonce, 32-bit counter starting at 0).
        // NIP-44 uses the 12-byte nonce directly with counter=0.
        return try ChaCha20.process(key: key, nonce: nonce, data: data)
    }

    private static func hmacAAD(key: Data, aad: Data, message: Data) -> Data {
        var data = Data()
        data.append(aad)
        data.append(message)
        let mac = HMAC<CryptoKit.SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return mac.withUnsafeBytes { Data($0) }
    }

    private static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}

// MARK: - ChaCha20 (IETF RFC 8439) — pure-Swift implementation

enum ChaCha20 {
    static func process(key: Data, nonce: Data, data: Data) throws -> Data {
        precondition(key.count == 32, "ChaCha20 key must be 32 bytes")
        precondition(nonce.count == 12, "ChaCha20 nonce must be 12 bytes")
        var out = Data(count: data.count)
        var counter: UInt32 = 0
        var offset = 0
        while offset < data.count {
            let block = chacha20Block(key: key, counter: counter, nonce: nonce)
            let remaining = data.count - offset
            let take = min(64, remaining)
            for i in 0..<take {
                out[offset + i] = data[offset + i] ^ block[i]
            }
            offset += take
            counter &+= 1
        }
        return out
    }

    private static func chacha20Block(key: Data, counter: UInt32, nonce: Data) -> [UInt8] {
        var state = [UInt32](repeating: 0, count: 16)
        state[0] = 0x61707865
        state[1] = 0x3320646E
        state[2] = 0x79622D32
        state[3] = 0x6B206574
        for i in 0..<8 {
            state[4 + i] = loadLE32(key, offset: i * 4)
        }
        state[12] = counter
        state[13] = loadLE32(nonce, offset: 0)
        state[14] = loadLE32(nonce, offset: 4)
        state[15] = loadLE32(nonce, offset: 8)

        var working = state
        for _ in 0..<10 {
            quarterRound(&working, 0, 4, 8, 12)
            quarterRound(&working, 1, 5, 9, 13)
            quarterRound(&working, 2, 6, 10, 14)
            quarterRound(&working, 3, 7, 11, 15)
            quarterRound(&working, 0, 5, 10, 15)
            quarterRound(&working, 1, 6, 11, 12)
            quarterRound(&working, 2, 7, 8, 13)
            quarterRound(&working, 3, 4, 9, 14)
        }
        for i in 0..<16 { working[i] &+= state[i] }

        var out = [UInt8](repeating: 0, count: 64)
        for i in 0..<16 {
            let w = working[i]
            out[i * 4] = UInt8(w & 0xFF)
            out[i * 4 + 1] = UInt8((w >> 8) & 0xFF)
            out[i * 4 + 2] = UInt8((w >> 16) & 0xFF)
            out[i * 4 + 3] = UInt8((w >> 24) & 0xFF)
        }
        return out
    }

    private static func loadLE32(_ data: Data, offset: Int) -> UInt32 {
        return UInt32(data[data.startIndex + offset]) |
               (UInt32(data[data.startIndex + offset + 1]) << 8) |
               (UInt32(data[data.startIndex + offset + 2]) << 16) |
               (UInt32(data[data.startIndex + offset + 3]) << 24)
    }

    private static func quarterRound(_ s: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        s[a] = s[a] &+ s[b]; s[d] ^= s[a]; s[d] = rotl(s[d], 16)
        s[c] = s[c] &+ s[d]; s[b] ^= s[c]; s[b] = rotl(s[b], 12)
        s[a] = s[a] &+ s[b]; s[d] ^= s[a]; s[d] = rotl(s[d], 8)
        s[c] = s[c] &+ s[d]; s[b] ^= s[c]; s[b] = rotl(s[b], 7)
    }

    private static func rotl(_ v: UInt32, _ n: UInt32) -> UInt32 {
        (v << n) | (v >> (32 - n))
    }
}
