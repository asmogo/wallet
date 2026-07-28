package com.cashu.me.Core

import android.content.Context
import androidx.datastore.preferences.preferencesDataStoreFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import com.cashu.me.Core.Platform.AndroidSecureStorage
import com.cashu.me.Core.Protocols.StorageKeys
import com.cashu.me.Models.CashuRequest
import com.cashu.me.Models.MintInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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
            putString(
                StorageKeys.cashuRequests,
                json.encodeToString(ListSerializer(CashuRequest.serializer()), listOf(CashuRequest(id = "req-1", encoded = "creqA-test"))),
            )
            putString(StorageKeys.cashuRequestsCurrentId, "req-1")
        }

        val store = WalletStore(context, storeName)

        assertEquals(mint.url, store.activeMintURL)
        assertEquals(listOf(mint), store.loadMints())
        assertEquals(listOf("quote-1"), store.loadProcessedNPCQuotes())
        assertEquals("req-1", store.loadCashuRequests().first().id)
        assertEquals("req-1", store.currentCashuRequestId)

        store.removeAllWalletData()

        assertNull(store.activeMintURL)
        assertEquals(emptyList<MintInfo>(), store.loadMints())
        assertEquals(emptyList<String>(), store.loadProcessedNPCQuotes())
        assertEquals(emptyList<CashuRequest>(), store.loadCashuRequests())
        assertNull(store.currentCashuRequestId)
    }

    @Test
    fun settingsStoreMigratesSharedPreferencesAndClearsOnlyWalletScopedData() {
        val storeName = uniqueStoreName("settings_store")
        context.seedSharedPreferences(storeName) {
            putBoolean(StorageKeys.settingsUseBitcoinSymbol, true)
            putBoolean(StorageKeys.settingsEnablePaymentRequests, false)
            putBoolean(StorageKeys.settingsReceivePaymentRequestsAutomatically, false)
            putString(StorageKeys.settingsBitcoinPriceCurrency, "EUR")
            putString(StorageKeys.settingsNostrRelays, json.encodeToString(ListSerializer(String.serializer()), listOf("wss://relay.example")))
            putString(
                StorageKeys.cashuRequestsProcessedNip17Ids,
                json.encodeToString(ListSerializer(String.serializer()), listOf("event-1")),
            )
            putString(
                StorageKeys.settingsP2PKKeys,
                """[{"id":"p2pk-1","publicKey":"02${"a".repeat(64)}","label":"P2PK key","createdAtEpochMillis":1,"used":false,"usedCount":0}]""",
            )
        }

        val store = SettingsStore(context, storeName)

        assertEquals(true, store.useBitcoinSymbol)
        assertFalse(store.enablePaymentRequests)
        assertFalse(store.receivePaymentRequestsAutomatically)
        assertEquals("EUR", store.bitcoinPriceCurrency)
        assertEquals(listOf("wss://relay.example"), store.nostrRelays)
        assertEquals(1, store.p2pkKeys.size)
        assertEquals(
            """["event-1"]""",
            DataStorePreferenceStore(context, storeName)
                .string(StorageKeys.cashuRequestsProcessedNip17Ids),
        )

        store.clearWalletScopedData()

        assertEquals(true, store.useBitcoinSymbol)
        assertTrue(store.enablePaymentRequests)
        assertTrue(store.receivePaymentRequestsAutomatically)
        assertEquals("EUR", store.bitcoinPriceCurrency)
        assertEquals(emptyList<Any>(), store.p2pkKeys)
        assertNull(
            DataStorePreferenceStore(context, storeName)
                .string(StorageKeys.cashuRequestsProcessedNip17Ids),
        )
    }

    @Test
    fun cashuRequestPrivacyDefaultsMatchIos() {
        val store = SettingsStore(context, uniqueStoreName("settings_store"))

        assertTrue(store.enablePaymentRequests)
        assertTrue(store.receivePaymentRequestsAutomatically)
    }

    @Test
    fun enablingAutomaticCashuRequestClaimsDrainsEligibleHeldPaymentsOnce() {
        val store = SettingsStore(context, uniqueStoreName("settings_store"))
        store.receivePaymentRequestsAutomatically = false
        val manager = SettingsManager(store, AndroidSecureStorage(context))
        var drainCount = 0
        manager.claimEligibleHeldPayments = { drainCount += 1 }

        manager.setReceivePaymentRequestsAutomatically(true)
        manager.setReceivePaymentRequestsAutomatically(true)

        assertEquals(1, drainCount)
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
