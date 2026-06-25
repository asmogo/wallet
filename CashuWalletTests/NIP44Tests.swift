import XCTest
@testable import CashuWallet

/// NIP-44 v2 cryptography tests.
///
/// Key pairs use the smallest valid secp256k1 scalars so the test vectors are
/// easy to verify against the spec:
///   sec1 = 1  →  pub1 = x-coord of G  (79be667e…)
///   sec2 = 2  →  pub2 = x-coord of 2G (c6047f94…)
///
/// ECDH is symmetric: conversationKey(sec1, pub2) == conversationKey(sec2, pub1).
final class NIP44Tests: XCTestCase {
    // Scalar 1 (private key for G)
    private let sec1Hex = "0000000000000000000000000000000000000000000000000000000000000001"
    // x-only compressed pubkey for G
    private let pub1Hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    // Scalar 2 (private key for 2G)
    private let sec2Hex = "0000000000000000000000000000000000000000000000000000000000000002"
    // x-only compressed pubkey for 2G
    private let pub2Hex = "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"

    private var sec1: Data { Data(hexString: sec1Hex)! }
    private var sec2: Data { Data(hexString: sec2Hex)! }

    // MARK: - conversationKey symmetry

    func testConversationKeyIsSymmetric() throws {
        let ck1 = try NIP44.conversationKey(privateKey: sec1, pubkeyHex: pub2Hex)
        let ck2 = try NIP44.conversationKey(privateKey: sec2, pubkeyHex: pub1Hex)
        XCTAssertEqual(ck1, ck2, "ECDH must be commutative: sec1+pub2 == sec2+pub1")
    }

    func testConversationKeyIs32Bytes() throws {
        let ck = try NIP44.conversationKey(privateKey: sec1, pubkeyHex: pub2Hex)
        XCTAssertEqual(ck.count, 32)
    }

    // MARK: - invalid pubkey

    func testConversationKeyThrowsOnTooShortPubkey() {
        XCTAssertThrowsError(
            try NIP44.conversationKey(privateKey: sec1, pubkeyHex: "79be667e")
        ) { error in
            guard case NIP44.Error.invalidPubkey = error else {
                XCTFail("Expected .invalidPubkey, got \(error)"); return
            }
        }
    }

    func testConversationKeyThrowsOnEmptyPubkey() {
        XCTAssertThrowsError(
            try NIP44.conversationKey(privateKey: sec1, pubkeyHex: "")
        ) { error in
            guard case NIP44.Error.invalidPubkey = error else {
                XCTFail("Expected .invalidPubkey, got \(error)"); return
            }
        }
    }

    func testConversationKeyThrowsOnOddLengthHex() {
        XCTAssertThrowsError(
            try NIP44.conversationKey(privateKey: sec1, pubkeyHex: "79be")
        )
    }

    // MARK: - round-trip encrypt / decrypt (random nonce)

    func testEncryptDecryptRoundTrip() throws {
        let plaintext = "Hello, NIP-44!"
        let ciphertext = try NIP44.encrypt(
            plaintext: plaintext,
            senderPrivateKey: sec1,
            recipientPubkeyHex: pub2Hex
        )
        let decrypted = try NIP44.decrypt(
            payload: ciphertext,
            recipientPrivateKey: sec2,
            senderPubkeyHex: pub1Hex
        )
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptDecryptEmptyString() throws {
        let plaintext = " "
        let ciphertext = try NIP44.encrypt(
            plaintext: plaintext,
            senderPrivateKey: sec1,
            recipientPubkeyHex: pub2Hex
        )
        let decrypted = try NIP44.decrypt(
            payload: ciphertext,
            recipientPrivateKey: sec2,
            senderPubkeyHex: pub1Hex
        )
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptDecryptUnicodeText() throws {
        let plaintext = "こんにちは世界 🌍 emoji test"
        let ciphertext = try NIP44.encrypt(
            plaintext: plaintext,
            senderPrivateKey: sec1,
            recipientPubkeyHex: pub2Hex
        )
        let decrypted = try NIP44.decrypt(
            payload: ciphertext,
            recipientPrivateKey: sec2,
            senderPubkeyHex: pub1Hex
        )
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptDecryptLongMessage() throws {
        let plaintext = String(repeating: "A", count: 2_000)
        let ciphertext = try NIP44.encrypt(
            plaintext: plaintext,
            senderPrivateKey: sec1,
            recipientPubkeyHex: pub2Hex
        )
        let decrypted = try NIP44.decrypt(
            payload: ciphertext,
            recipientPrivateKey: sec2,
            senderPubkeyHex: pub1Hex
        )
        XCTAssertEqual(decrypted, plaintext)
    }

    // MARK: - deterministic encrypt with fixed nonce

    func testEncryptWithFixedNonceIsIdempotent() throws {
        let ck = try NIP44.conversationKey(privateKey: sec1, pubkeyHex: pub2Hex)
        let nonce = Data(repeating: 0xAB, count: 32)
        let enc1 = try NIP44.encrypt(plaintext: "test", conversationKey: ck, nonce: nonce)
        let enc2 = try NIP44.encrypt(plaintext: "test", conversationKey: ck, nonce: nonce)
        XCTAssertEqual(enc1, enc2)
    }

    func testEncryptProducesBase64Output() throws {
        let ck = try NIP44.conversationKey(privateKey: sec1, pubkeyHex: pub2Hex)
        let nonce = Data(repeating: 0x00, count: 32)
        let enc = try NIP44.encrypt(plaintext: "hi", conversationKey: ck, nonce: nonce)
        XCTAssertNotNil(Data(base64Encoded: enc), "Output should be valid base64")
    }

    func testDecryptFixedNonceRoundTrip() throws {
        let ck = try NIP44.conversationKey(privateKey: sec1, pubkeyHex: pub2Hex)
        let nonce = Data(count: 32)
        let plaintext = "deterministic test"
        let enc = try NIP44.encrypt(plaintext: plaintext, conversationKey: ck, nonce: nonce)
        let dec = try NIP44.decrypt(payload: enc, conversationKey: ck)
        XCTAssertEqual(dec, plaintext)
    }

    // MARK: - tamper detection

    func testDecryptTamperedPayloadThrowsMACMismatch() throws {
        let ck = try NIP44.conversationKey(privateKey: sec1, pubkeyHex: pub2Hex)
        let nonce = Data(count: 32)
        var enc = try NIP44.encrypt(plaintext: "secret", conversationKey: ck, nonce: nonce)

        // Flip a byte in the base64 payload (middle of the ciphertext region)
        var raw = Data(base64Encoded: enc)!
        raw[50] ^= 0xFF
        enc = raw.base64EncodedString()

        XCTAssertThrowsError(try NIP44.decrypt(payload: enc, conversationKey: ck)) { error in
            guard case NIP44.Error.macMismatch = error else {
                XCTFail("Expected .macMismatch, got \(error)"); return
            }
        }
    }

    func testDecryptWrongKeyThrowsMACMismatch() throws {
        let ck = try NIP44.conversationKey(privateKey: sec1, pubkeyHex: pub2Hex)
        let nonce = Data(count: 32)
        let enc = try NIP44.encrypt(plaintext: "secret", conversationKey: ck, nonce: nonce)

        let wrongKey = Data(repeating: 0xFF, count: 32)
        XCTAssertThrowsError(try NIP44.decrypt(payload: enc, conversationKey: wrongKey)) { error in
            guard case NIP44.Error.macMismatch = error else {
                XCTFail("Expected .macMismatch, got \(error)"); return
            }
        }
    }

    // MARK: - invalid payloads

    func testDecryptTooShortPayloadThrows() {
        let ck = Data(count: 32)
        XCTAssertThrowsError(try NIP44.decrypt(payload: "dG9vc2hvcnQ=", conversationKey: ck)) { error in
            guard case NIP44.Error.invalidPayload = error else {
                XCTFail("Expected .invalidPayload, got \(error)"); return
            }
        }
    }

    func testDecryptWrongVersionByteThrows() throws {
        let ck = try NIP44.conversationKey(privateKey: sec1, pubkeyHex: pub2Hex)
        let nonce = Data(count: 32)
        var enc = try NIP44.encrypt(plaintext: "x", conversationKey: ck, nonce: nonce)
        var raw = Data(base64Encoded: enc)!
        raw[0] = 0x01  // version byte should be 0x02
        enc = raw.base64EncodedString()

        XCTAssertThrowsError(try NIP44.decrypt(payload: enc, conversationKey: ck)) { error in
            guard case NIP44.Error.invalidVersion = error else {
                XCTFail("Expected .invalidVersion, got \(error)"); return
            }
        }
    }

    func testDecryptInvalidBase64Throws() {
        let ck = Data(count: 32)
        XCTAssertThrowsError(try NIP44.decrypt(payload: "not-base64!!!", conversationKey: ck))
    }
}
