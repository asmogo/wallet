package com.cashu.me.Core

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import com.cashu.me.Core.Protocols.SecureStorage
import com.cashu.me.Models.P2PKKeyInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class P2PKStorageTransactionInstrumentedTest {
    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val privateKeyHex = "0".repeat(63) + "1"
    private val publicKeyHex =
        "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

    @Test
    fun importSecureFailureDoesNotPublishMetadata() {
        val metadata = FakeP2PKMetadataStore()
        val secureStorage = FakeP2PKSecureStorage().apply { failSaves = true }
        val manager = manager(metadata, secureStorage)

        assertThrows(IllegalStateException::class.java) {
            manager.importP2PKNsec(nsecForPrivateKeyOne())
        }

        assertTrue(metadata.keys.isEmpty())
        assertTrue(secureStorage.values.isEmpty())
        assertTrue(manager.state.value.p2pkKeys.isEmpty())
    }

    @Test
    fun importMetadataFailureRollsBackNewSecureSecretAndPublishedState() {
        val metadata = FakeP2PKMetadataStore().apply { failKeySaves = true }
        val secureStorage = FakeP2PKSecureStorage()
        val manager = manager(metadata, secureStorage)

        assertThrows(IllegalStateException::class.java) {
            manager.importP2PKNsec(nsecForPrivateKeyOne())
        }

        assertTrue(metadata.keys.isEmpty())
        assertTrue(secureStorage.values.isEmpty())
        assertTrue(manager.state.value.p2pkKeys.isEmpty())
    }

    @Test
    fun removalMetadataFailureRestoresEncryptedSecret() {
        val key = storedKey()
        val metadata = FakeP2PKMetadataStore(listOf(key))
        val secureStorage = FakeP2PKSecureStorage(
            mutableMapOf(primaryStorageKey(key.id) to privateKeyHex),
        )
        val manager = manager(metadata, secureStorage)
        metadata.failKeySaves = true

        assertThrows(IllegalStateException::class.java) {
            manager.removeP2PKKey(key.id)
        }

        assertEquals(listOf(key), metadata.keys)
        assertEquals(privateKeyHex, secureStorage.values[primaryStorageKey(key.id)])
        assertFalse(secureStorage.values.containsKey(fallbackStorageKey(key.id)))
        assertTrue(metadata.pendingDeletionIds.isEmpty())
        assertEquals(listOf(key), manager.state.value.p2pkKeys)
    }

    @Test
    fun interruptedRemovalRestoresEncryptedSecretWithoutMetadataSecret() {
        val key = storedKey()
        val metadata = FakeP2PKMetadataStore(listOf(key)).apply {
            pendingDeletionIds = setOf(key.id)
        }
        val secureStorage = FakeP2PKSecureStorage(
            mutableMapOf(fallbackStorageKey(key.id) to privateKeyHex),
        )

        val manager = manager(metadata, secureStorage)

        assertEquals(privateKeyHex, secureStorage.values[primaryStorageKey(key.id)])
        assertFalse(secureStorage.values.containsKey(fallbackStorageKey(key.id)))
        assertTrue(metadata.pendingDeletionIds.isEmpty())
        assertTrue(manager.state.value.p2pkUnavailableKeyIds.isEmpty())
    }

    @Test
    fun metadataOnlyKeyIsUnavailableUntilMatchingNsecRepairsIt() {
        val key = storedKey()
        val metadata = FakeP2PKMetadataStore(listOf(key))
        val secureStorage = FakeP2PKSecureStorage()
        val manager = manager(metadata, secureStorage)

        assertEquals(setOf(key.id), manager.state.value.p2pkUnavailableKeyIds)

        manager.importP2PKNsec(nsecForPrivateKeyOne())

        assertEquals(listOf(key), metadata.keys)
        assertTrue(manager.state.value.p2pkUnavailableKeyIds.isEmpty())
        assertEquals(privateKeyHex, secureStorage.values[primaryStorageKey(key.id)])
    }

    @Test
    fun metadataOnlyKeyCanBeRemovedWithoutASecret() {
        val key = storedKey()
        val metadata = FakeP2PKMetadataStore(listOf(key))
        val secureStorage = FakeP2PKSecureStorage()
        val manager = manager(metadata, secureStorage)

        manager.removeP2PKKey(key.id)

        assertTrue(metadata.keys.isEmpty())
        assertTrue(metadata.pendingDeletionIds.isEmpty())
        assertTrue(secureStorage.values.isEmpty())
        assertTrue(manager.state.value.p2pkKeys.isEmpty())
    }

    private fun manager(
        metadata: FakeP2PKMetadataStore,
        secureStorage: FakeP2PKSecureStorage,
    ): SettingsManager = SettingsManager(
        settingsStore = SettingsStore(context, "p2pk-test.${UUID.randomUUID()}"),
        secureStorage = secureStorage,
        p2pkStore = metadata,
    )

    private fun storedKey() = P2PKKeyInfo(
        id = UUID.randomUUID().toString(),
        publicKey = publicKeyHex,
        label = "Stored key",
    )

    private fun nsecForPrivateKeyOne(): String = Bech32.encode(
        "nsec",
        ByteArray(32).also { it[31] = 1 },
    )

    private fun primaryStorageKey(id: String) = "settings.p2pk.$id.privateKey"

    private fun fallbackStorageKey(id: String) = "${primaryStorageKey(id)}.removalFallback"
}

private class FakeP2PKMetadataStore(
    initialKeys: List<P2PKKeyInfo> = emptyList(),
) : P2PKMetadataStore {
    private var storedKeys = initialKeys
    private var storedPendingDeletionIds = emptySet<String>()
    var failKeySaves = false
    var failPendingSaves = false

    override val keys: List<P2PKKeyInfo>
        get() = storedKeys

    override var pendingDeletionIds: Set<String>
        get() = storedPendingDeletionIds
        set(value) {
            if (failPendingSaves) error("metadata unavailable")
            storedPendingDeletionIds = value
        }

    override fun saveKeys(
        keys: List<P2PKKeyInfo>,
        preservingLegacySecrets: Map<String, String>,
    ) {
        if (failKeySaves) error("metadata unavailable")
        check(preservingLegacySecrets.isEmpty()) {
            "Tests must not persist private keys in metadata."
        }
        storedKeys = keys
    }
}

private class FakeP2PKSecureStorage(
    val values: MutableMap<String, String> = mutableMapOf(),
) : SecureStorage {
    var failSaves = false
    var failDeletes = false

    override fun loadString(key: String): String? = values[key]

    override fun saveString(key: String, value: String) {
        if (failSaves) error("secure storage unavailable")
        values[key] = value
    }

    override fun delete(key: String) {
        if (failDeletes) error("secure storage unavailable")
        values.remove(key)
    }

    override fun contains(key: String): Boolean = key in values
}
