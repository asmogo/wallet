package org.cashu.wallet.Core

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NostrServiceTest {
    @Test
    fun bech32RoundTripsNsecPayload() {
        val key = ByteArray(32) { index -> (index + 1).toByte() }
        val encoded = Bech32.encode("nsec", key)

        assertTrue(encoded.startsWith("nsec1"))
        assertArrayEquals(key, Bech32.decode("nsec", encoded))
    }

    @Test
    fun secp256k1PrivateKeyOneProducesGeneratorXOnlyPublicKey() {
        val publicKey = NostrService.publicKeyHex(
            "0000000000000000000000000000000000000000000000000000000000000001",
        )

        assertEquals(
            "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
            publicKey,
        )
    }

    @Test
    fun schnorrSignatureVerifiesAgainstDerivedPublicKey() {
        val privateKey = NostrService.hexToBytes("0000000000000000000000000000000000000000000000000000000000000003")
        val publicKey = NostrService.publicKeyXOnly(privateKey)
        val message = ByteArray(32) { index -> index.toByte() }
        val signature = NostrService.schnorrSign(message, privateKey, auxRand = ByteArray(32))

        assertTrue(NostrService.verifySchnorr(message, publicKey, signature))
    }

    @Test
    fun nip98CommitmentJsonMatchesSwiftFieldOrderAndSlashEscaping() {
        val publicKey = "a".repeat(64)
        val tags = NostrService.nip98Tags("https://mint.example.com/api/v1?x=1", "post")

        val commitment = NostrService.eventCommitmentJson(
            pubkey = publicKey,
            createdAt = 1_710_000_000,
            kind = 27235,
            tags = tags,
            content = "",
        )

        assertEquals(
            """[0,"$publicKey",1710000000,27235,[["u","https://mint.example.com/api/v1?x=1"],["method","POST"]],""]""",
            commitment,
        )
        assertFalse(commitment.contains("""\/"""))
    }

    @Test
    fun signedNip98EventJsonMatchesSwiftFieldOrderAndEscapesQuotesOnly() {
        val eventId = "b".repeat(64)
        val publicKey = "a".repeat(64)
        val signature = "c".repeat(128)
        val tags = NostrService.nip98Tags("""https://mint.example.com/a"b""", "get")

        val json = NostrService.signedNip98EventJson(
            eventId = eventId,
            publicKey = publicKey,
            createdAt = 1_710_000_001,
            tags = tags,
            signature = signature,
        )

        assertEquals(
            """{"id":"$eventId","pubkey":"$publicKey","content":"","kind":27235,"created_at":1710000001,"tags":[["u","https://mint.example.com/a\"b"],["method","GET"]],"sig":"$signature"}""",
            json,
        )
        assertFalse(json.contains("""\/"""))
    }
}
