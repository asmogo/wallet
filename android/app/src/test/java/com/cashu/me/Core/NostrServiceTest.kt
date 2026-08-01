package com.cashu.me.Core

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Assert.fail
import org.junit.Test
import com.cashu.me.Core.Protocols.SecureStorage
import com.cashu.me.Core.Protocols.StorageKeys

class NostrServiceTest {
    @Test
    fun selectingMissingCustomKeyRequestsAChoiceWithoutSwitching() {
        assertEquals(
            NostrSignerSelectionAction.ChooseCustomKey,
            nostrSignerSelectionAction(
                current = NostrSignerType.Seed,
                requested = NostrSignerType.PrivateKey,
                hasCustomKey = false,
            ),
        )
    }

    @Test
    fun selectingStoredCustomKeySwitchesSigner() {
        assertEquals(
            NostrSignerSelectionAction.Switch,
            nostrSignerSelectionAction(
                current = NostrSignerType.Seed,
                requested = NostrSignerType.PrivateKey,
                hasCustomKey = true,
            ),
        )
    }

    @Test
    fun switchingToMissingCustomKeyRequiresExplicitSetup() {
        val error = assertThrows(IllegalStateException::class.java) {
            NostrService.requireStoredCustomKey(null)
        }

        assertEquals(
            "Generate or import a custom key before switching key sources.",
            error.message,
        )
    }

    @Test
    fun switchingToExistingCustomKeyUsesStoredIdentity() {
        val storedKey = "01".repeat(32)

        assertEquals(storedKey, NostrService.requireStoredCustomKey(storedKey))
    }

    @Test
    fun failedGenerationRestoresStoredKeySignerAndObservableIdentity() {
        val storage = FailingSecureStorage()
        val settings = FakeNostrSignerSettings()
        val service = NostrService(storage, settings)
        val initial = service.deriveKeypairFromSeed(privateKey(1))
        storage.failAfterNextSave = true

        assertFails { service.generateRandomKeypair() }

        assertEquals(initial, service.state.value)
        assertEquals(initial.nsec, Bech32.encode("nsec", NostrService.hexToBytes(service.currentPrivateKey()!!)))
        assertEquals(NostrSignerType.Seed.rawValue, settings.nostrSignerType)
        assertNull(storage.loadString(StorageKeys.secureNostrPrivateKey))
    }

    @Test
    fun failedResetRestoresCustomKeySignerAndObservableIdentity() {
        val storage = FailingSecureStorage()
        val settings = FakeNostrSignerSettings()
        val service = NostrService(storage, settings)
        service.deriveKeypairFromSeed(privateKey(1))
        val customNsec = Bech32.encode("nsec", privateKey(2))
        val initial = service.importNsec(customNsec)
        val storedCustomKey = storage.loadString(StorageKeys.secureNostrPrivateKey)
        storage.failAfterNextDelete = true

        assertFails { service.resetToSeedKey() }

        assertEquals(initial, service.state.value)
        assertEquals(NostrSignerType.PrivateKey.rawValue, settings.nostrSignerType)
        assertEquals(storedCustomKey, storage.loadString(StorageKeys.secureNostrPrivateKey))
    }

    @Test
    fun failedSignerChangeRestoresSignerAndObservableIdentity() {
        val storage = FailingSecureStorage(
            mutableMapOf(StorageKeys.secureNostrPrivateKey to privateKey(2).toHexString()),
        )
        val settings = FakeNostrSignerSettings()
        val service = NostrService(storage, settings)
        val initial = service.deriveKeypairFromSeed(privateKey(1))
        settings.failAfterNextSet = true

        assertFails { service.switchSignerType(NostrSignerType.PrivateKey) }

        assertEquals(initial, service.state.value)
        assertEquals(NostrSignerType.Seed.rawValue, settings.nostrSignerType)
        assertEquals(privateKey(2).toHexString(), storage.loadString(StorageKeys.secureNostrPrivateKey))
    }

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

    private fun privateKey(value: Int): ByteArray = ByteArray(32).also { it[31] = value.toByte() }

    private fun ByteArray.toHexString(): String = joinToString("") { "%02x".format(it) }

    private fun assertFails(block: () -> Unit) {
        try {
            block()
            fail("Expected operation to fail")
        } catch (_: IllegalStateException) {
            // Expected injected persistence failure.
        }
    }

    private class FakeNostrSignerSettings : NostrSignerSettings {
        private var value = NostrSignerType.Seed.rawValue
        var failAfterNextSet = false

        override var nostrSignerType: String
            get() = value
            set(newValue) {
                value = newValue
                if (failAfterNextSet) {
                    failAfterNextSet = false
                    throw IllegalStateException("Signer settings unavailable")
                }
            }
    }

    private class FailingSecureStorage(
        private val values: MutableMap<String, String> = mutableMapOf(),
    ) : SecureStorage {
        var failAfterNextSave = false
        var failAfterNextDelete = false

        override fun loadString(key: String): String? = values[key]

        override fun saveString(key: String, value: String) {
            values[key] = value
            if (failAfterNextSave) {
                failAfterNextSave = false
                throw IllegalStateException("Secure storage write failed")
            }
        }

        override fun delete(key: String) {
            values.remove(key)
            if (failAfterNextDelete) {
                failAfterNextDelete = false
                throw IllegalStateException("Secure storage delete failed")
            }
        }

        override fun contains(key: String): Boolean = values.containsKey(key)
    }
}
