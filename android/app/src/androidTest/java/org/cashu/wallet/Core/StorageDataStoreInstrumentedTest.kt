package org.cashu.wallet.Core

import android.content.Context
import androidx.datastore.preferences.preferencesDataStoreFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import org.cashu.wallet.Core.Platform.AndroidSecureStorage
import org.cashu.wallet.Core.Protocols.StorageKeys
import org.cashu.wallet.Models.MintInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class StorageDataStoreInstrumentedTest {
    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val json = Json { encodeDefaults = true }

    @Test
    fun walletStoreMigratesSharedPreferencesAndClearsWalletBoundary() {
        val storeName = uniqueStoreName("wallet_store")
        val mint = MintInfo(url = "https://mint.example.com", name = "Example", balance = 21)
        context.seedSharedPreferences(storeName) {
            putString(
                StorageKeys.walletMints,
                json.encodeToString(ListSerializer(MintInfo.serializer()), listOf(mint)),
            )
            putString(StorageKeys.walletActiveMintUrl, mint.url)
            putString(StorageKeys.walletProcessedNPCQuotes, json.encodeToString(ListSerializer(String.serializer()), listOf("quote-1")))
        }

        val store = WalletStore(context, storeName)

        assertEquals(mint.url, store.activeMintURL)
        assertEquals(listOf(mint), store.loadMints())
        assertEquals(listOf("quote-1"), store.loadProcessedNPCQuotes())

        store.removeAllWalletData()

        assertNull(store.activeMintURL)
        assertEquals(emptyList<MintInfo>(), store.loadMints())
        assertEquals(emptyList<String>(), store.loadProcessedNPCQuotes())
    }

    @Test
    fun settingsStoreMigratesSharedPreferencesAndClearsOnlyWalletScopedData() {
        val storeName = uniqueStoreName("settings_store")
        context.seedSharedPreferences(storeName) {
            putBoolean(StorageKeys.settingsUseBitcoinSymbol, true)
            putString(StorageKeys.settingsBitcoinPriceCurrency, "EUR")
            putString(StorageKeys.settingsNostrRelays, json.encodeToString(ListSerializer(String.serializer()), listOf("wss://relay.example")))
            putString(
                StorageKeys.settingsNwcConnections,
                """[{"id":"nwc-1","name":"Wallet connection","walletPublicKey":"wallet-pub","connectionPublicKey":"conn-pub","allowanceSats":1000}]""",
            )
            putString(
                StorageKeys.settingsP2PKKeys,
                """[{"id":"p2pk-1","publicKey":"02${"a".repeat(64)}","label":"P2PK key","createdAtEpochMillis":1,"used":false,"usedCount":0}]""",
            )
        }

        val store = SettingsStore(context, storeName)

        assertEquals(true, store.useBitcoinSymbol)
        assertEquals("EUR", store.bitcoinPriceCurrency)
        assertEquals(listOf("wss://relay.example"), store.nostrRelays)
        assertEquals(1, store.nwcConnections.size)
        assertEquals(1, store.p2pkKeys.size)

        store.clearWalletScopedData()

        assertEquals(true, store.useBitcoinSymbol)
        assertEquals("EUR", store.bitcoinPriceCurrency)
        assertEquals(emptyList<Any>(), store.nwcConnections)
        assertEquals(emptyList<Any>(), store.p2pkKeys)
    }

    @Test
    fun androidSecureStorageDeletesStoredSecrets() {
        val storage = AndroidSecureStorage(context)
        val key = "instrumented.secret.${UUID.randomUUID()}"

        storage.saveString(key, "secret-value")

        assertEquals("secret-value", storage.loadString(key))

        storage.delete(key)

        assertFalse(storage.contains(key))
        assertNull(storage.loadString(key))
    }

    private fun uniqueStoreName(prefix: String): String = "$prefix.${UUID.randomUUID()}"

    private fun Context.seedSharedPreferences(
        name: String,
        block: android.content.SharedPreferences.Editor.() -> Unit,
    ) {
        preferencesDataStoreFile(name).delete()
        getSharedPreferences(name, Context.MODE_PRIVATE).edit().clear().apply()
        getSharedPreferences(name, Context.MODE_PRIVATE).edit().apply {
            block()
            apply()
        }
    }
}
