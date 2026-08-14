import XCTest
import Cdk
@testable import CashuWallet

/// NIP-44 v2 cryptography tests.
///
/// The implementation lives in the CDK FFI (`cdk-nostr`, Rust `nostr` crate);
/// these tests pin the FFI contract the wallet relies on for NIP-17 inbox
/// unwrapping, using the official NIP-44 vectors.
///
/// Key pairs use the smallest valid secp256k1 scalars so the test vectors are
/// easy to verify against the spec:
///   sec1 = 1  →  pub1 = x-coord of G  (79be667e…)
///   sec2 = 2  →  pub2 = x-coord of 2G (c6047f94…)
final class NIP44Tests: XCTestCase {
    // Scalar 1 (private key for G)
    private let sec1Hex = "0000000000000000000000000000000000000000000000000000000000000001"
    // x-only pubkey for G
    private let pub1Hex = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    // Scalar 2 (private key for 2G)
    private let sec2Hex = "0000000000000000000000000000000000000000000000000000000000000002"
    // x-only pubkey for 2G
    private let pub2Hex = "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"

    // MARK: - key derivation

    func testGetPubkeyDerivesGeneratorPoint() throws {
        XCTAssertEqual(try nostrGetPubkey(nostrSecretKey: sec1Hex), pub1Hex)
        XCTAssertEqual(try nostrGetPubkey(nostrSecretKey: sec2Hex), pub2Hex)
    }

    func testGetPubkeyRejectsInvalidKeys() {
        XCTAssertThrowsError(try nostrGetPubkey(nostrSecretKey: "zzzz"))
        XCTAssertThrowsError(try nostrGetPubkey(nostrSecretKey: "00"))
    }

    // MARK: - official NIP-44 v2 vectors (decrypt)
    // https://github.com/nostr-protocol/nips/blob/master/44.md

    func testDecryptOfficialVector1() throws {
        let payload = "AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABee0G5VSK0/9YypIObAtDKfYEAjD35uVkHyB0F4DwrcNaCXlCWZKaArsGrY6M9wnuTMxWfp1RTN9Xga8no+kF5Vsb"
        let decrypted = try nip44Decrypt(
            nostrSecretKey: sec1Hex,
            senderPubkey: pub2Hex,
            payload: payload
        )
        XCTAssertEqual(decrypted, "a")
    }

    func testDecryptOfficialVector2() throws {
        let payload = "AvAAAAAAAAAAAAAAAAAAAPAAAAAAAAAAAAAAAAAAAAAPSKSK6is9ngkX2+cSq85Th16oRTISAOfhStnixqZziKMDvB0QQzgFZdjLTPicCJaV8nDITO+QfaQ61+KbWQIOO2Yj"
        let decrypted = try nip44Decrypt(
            nostrSecretKey: sec2Hex,
            senderPubkey: pub1Hex,
            payload: payload
        )
        XCTAssertEqual(decrypted, "\u{1F355}\u{1FAC3}")
    }

    func testDecryptOfficialVector3() throws {
        let sec1 = "5c0c523f52a5b6fad39ed2403092df8cebc36318b39383bca6c00808626fab3a"
        let sec2 = "4b22aa260e4acb7021e32f38a6cdf4b673c6a277755bfce287e370c924dc936d"
        let pub2 = try nostrGetPubkey(nostrSecretKey: sec2)
        let payload = "ArY1I2xC2yDwIbuNHN/1ynXdGgzHLqdCrXUPMwELJPc7s7JqlCMJBAIIjfkpHReBPXeoMCyuClwgbT419jUWU1PwaNl4FEQYKCDKVJz+97Mp3K+Q2YGa77B6gpxB/lr1QgoqpDf7wDVrDmOqGoiPjWDqy8KzLueKDcm9BVP8xeTJIxs="
        let decrypted = try nip44Decrypt(
            nostrSecretKey: sec1,
            senderPubkey: pub2,
            payload: payload
        )
        XCTAssertEqual(decrypted, "\u{8868}\u{30dd}\u{3042}A\u{9dd7}\u{152}\u{e9}\u{ff22}\u{900d}\u{dc}\u{df}\u{aa}\u{105}\u{f1}\u{4e02}\u{3400}\u{20000}")
    }

    // MARK: - round-trip encrypt / decrypt

    func testEncryptDecryptRoundTrip() throws {
        let plaintext = "Hello, NIP-44!"
        let ciphertext = try nip44Encrypt(
            nostrSecretKey: sec1Hex,
            recipientPubkey: pub2Hex,
            plaintext: plaintext
        )
        let decrypted = try nip44Decrypt(
            nostrSecretKey: sec2Hex,
            senderPubkey: pub1Hex,
            payload: ciphertext
        )
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptDecryptUnicodeText() throws {
        let plaintext = "こんにちは世界 🌍 emoji test"
        let ciphertext = try nip44Encrypt(
            nostrSecretKey: sec1Hex,
            recipientPubkey: pub2Hex,
            plaintext: plaintext
        )
        let decrypted = try nip44Decrypt(
            nostrSecretKey: sec2Hex,
            senderPubkey: pub1Hex,
            payload: ciphertext
        )
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptDecryptLongMessage() throws {
        let plaintext = String(repeating: "A", count: 2_000)
        let ciphertext = try nip44Encrypt(
            nostrSecretKey: sec1Hex,
            recipientPubkey: pub2Hex,
            plaintext: plaintext
        )
        let decrypted = try nip44Decrypt(
            nostrSecretKey: sec2Hex,
            senderPubkey: pub1Hex,
            payload: ciphertext
        )
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptProducesBase64PayloadWithVersion2() throws {
        let ciphertext = try nip44Encrypt(
            nostrSecretKey: sec1Hex,
            recipientPubkey: pub2Hex,
            plaintext: "hi"
        )
        let raw = try XCTUnwrap(Data(base64Encoded: ciphertext), "Output should be valid base64")
        XCTAssertEqual(raw.first, 0x02, "NIP-44 v2 payloads start with version byte 0x02")
    }

    // MARK: - tamper detection

    func testDecryptTamperedPayloadThrows() throws {
        let ciphertext = try nip44Encrypt(
            nostrSecretKey: sec1Hex,
            recipientPubkey: pub2Hex,
            plaintext: "secret"
        )

        // Flip a byte in the base64 payload (middle of the ciphertext region)
        var raw = try XCTUnwrap(Data(base64Encoded: ciphertext))
        raw[50] ^= 0xFF
        let tampered = raw.base64EncodedString()

        XCTAssertThrowsError(
            try nip44Decrypt(nostrSecretKey: sec2Hex, senderPubkey: pub1Hex, payload: tampered)
        )
    }

    func testDecryptWrongKeyThrows() throws {
        let ciphertext = try nip44Encrypt(
            nostrSecretKey: sec1Hex,
            recipientPubkey: pub2Hex,
            plaintext: "secret"
        )

        let wrongKey = nostrGenerateSecretKey()
        XCTAssertThrowsError(
            try nip44Decrypt(nostrSecretKey: wrongKey, senderPubkey: pub1Hex, payload: ciphertext)
        )
    }

    // MARK: - invalid payloads

    func testDecryptTooShortPayloadThrows() {
        XCTAssertThrowsError(
            try nip44Decrypt(nostrSecretKey: sec1Hex, senderPubkey: pub2Hex, payload: "dG9vc2hvcnQ=")
        )
    }

    func testDecryptWrongVersionByteThrows() throws {
        let ciphertext = try nip44Encrypt(
            nostrSecretKey: sec1Hex,
            recipientPubkey: pub2Hex,
            plaintext: "x"
        )
        var raw = try XCTUnwrap(Data(base64Encoded: ciphertext))
        raw[0] = 0x01  // version byte should be 0x02
        let wrongVersion = raw.base64EncodedString()

        XCTAssertThrowsError(
            try nip44Decrypt(nostrSecretKey: sec2Hex, senderPubkey: pub1Hex, payload: wrongVersion)
        )
    }

    func testDecryptInvalidBase64Throws() {
        XCTAssertThrowsError(
            try nip44Decrypt(nostrSecretKey: sec1Hex, senderPubkey: pub2Hex, payload: "not-base64!!!")
        )
    }
}
