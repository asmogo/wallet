package com.cashu.me.Core

import android.content.Context
import androidx.datastore.preferences.preferencesDataStoreFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import com.cashu.me.Core.Platform.AndroidSecureStorage
import com.cashu.me.Core.Protocols.StorageKeys
import com.cashu.me.Models.CashuRequest
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.MintQuoteScheduleRecord
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
    fun restoreBackupBarrierSurvivesReloadAndWalletRollback() {
        val storeName = uniqueStoreName("restore_barrier")
        val store = SettingsStore(context, storeName)
        store.walletRestoreIncomplete = true
        val snapshot = store.snapshotWalletScopedData()
        store.clearWalletScopedData()
        assertFalse(SettingsStore(context, storeName).walletRestoreIncomplete)
        store.restoreWalletScopedData(snapshot)
        assertTrue(SettingsStore(context, storeName).walletRestoreIncomplete)
    }

    @Test
    fun replacementCheckpointPreservesSqliteWalContents() {
        val root = java.io.File(context.cacheDir, "replacement-checkpoint-" + UUID.randomUUID()).apply { mkdirs() }
        val isolatedContext = object : android.content.ContextWrapper(context) {
            override fun getApplicationContext(): Context = this
            override fun getFilesDir(): java.io.File = root
        }
        val paths = com.cashu.me.Core.Platform.WalletDatabasePathManager(isolatedContext)
        try {
            android.database.sqlite.SQLiteDatabase.openOrCreateDatabase(paths.databaseFile, null).use { db ->
                db.enableWriteAheadLogging()
                db.execSQL("CREATE TABLE recovery_test (value TEXT NOT NULL)")
                db.execSQL("INSERT INTO recovery_test VALUES ('proofs before replacement')")
                paths.checkpointBeforeReplacement()
            }
            android.database.sqlite.SQLiteDatabase.openDatabase(paths.databaseFile.path, null, 0).use { reopened ->
                reopened.rawQuery("SELECT value FROM recovery_test", null).use { cursor ->
                    assertTrue(cursor.moveToFirst())
                    assertEquals("proofs before replacement", cursor.getString(0))
                }
            }
        } finally { root.deleteRecursively() }
    }

    @Test
    fun replacementCheckpointNeverDeletesAnUnreadableDatabase() {
        val root = java.io.File(context.cacheDir, "replacement-corrupt-" + UUID.randomUUID()).apply { mkdirs() }
        val isolatedContext = object : android.content.ContextWrapper(context) {
            override fun getApplicationContext(): Context = this
            override fun getFilesDir(): java.io.File = root
        }
        val paths = com.cashu.me.Core.Platform.WalletDatabasePathManager(isolatedContext)
        try {
            paths.databaseFile.writeText("unreadable original database")
            try {
                paths.checkpointBeforeReplacement()
                org.junit.Assert.fail("Unreadable database must block preparation")
            } catch (_: Exception) { }
            assertEquals("unreadable original database", paths.databaseFile.readText())
        } finally { root.deleteRecursively() }
    }

    @Test
    fun walletStoreMigratesSharedPreferencesAndClearsWalletBoundary() {
        val storeName = uniqueStoreName("wallet_store")
        val mint = MintInfo(url = "https://mint.example.com", name = "Example", balance = 21)
        val schedule = MintQuoteScheduleRecord(
            firstObservedAtEpochMillis = 1_000,
            nextAttemptAtEpochMillis = 2_000,
            consecutiveFailures = 2,
            hadOutstandingPayment = true,
            isReusable = true,
        )
        context.seedSharedPreferences(storeName) {
            putString(
                StorageKeys.walletMints,
                json.encodeToString(ListSerializer(MintInfo.serializer()), listOf(mint)),
            )
            putString(StorageKeys.walletActiveMintUrl, mint.url)
            putString(StorageKeys.walletProcessedNPCQuotes, json.encodeToString(ListSerializer(String.serializer()), listOf("quote-1")))
            putString(
                StorageKeys.walletMintQuoteSchedules,
                json.encodeToString(
                    MapSerializer(String.serializer(), MintQuoteScheduleRecord.serializer()),
                    mapOf("quote-1" to schedule),
                ),
            )
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
        assertEquals(mapOf("quote-1" to schedule), store.loadMintQuoteSchedules())
        assertEquals("req-1", store.loadCashuRequests().first().id)
        assertEquals("req-1", store.currentCashuRequestId)

        store.removeAllWalletData()

        assertNull(store.activeMintURL)
        assertEquals(emptyList<MintInfo>(), store.loadMints())
        assertEquals(emptyList<String>(), store.loadProcessedNPCQuotes())
        assertEquals(emptyMap<String, MintQuoteScheduleRecord>(), store.loadMintQuoteSchedules())
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
    fun legacyGlobalPriceCacheMigratesOnceToSelectedCurrency() {
        val storeName = uniqueStoreName("settings_store")
        val rawStore = DataStorePreferenceStore(context, storeName)
        rawStore.putString(StorageKeys.priceCachedBTC, "100000.0")
        rawStore.putLong(StorageKeys.priceCachedBTCDate, 1_234L)
        val store = SettingsStore(context, storeName)

        assertEquals(100_000.0, store.cachedPrice("USD") ?: 0.0, 0.0)
        assertEquals(1_234L, store.cachedPriceDate("USD"))
        assertNull(rawStore.string(StorageKeys.priceCachedBTC))
        assertEquals(Long.MIN_VALUE, rawStore.long(StorageKeys.priceCachedBTCDate, Long.MIN_VALUE))
        assertNull(store.cachedPrice("EUR"))
        assertNull(store.cachedPriceDate("EUR"))

        rawStore.putString(StorageKeys.priceCachedBTC, "95000.0")
        rawStore.putLong(StorageKeys.priceCachedBTCDate, 1_999L)
        assertEquals(100_000.0, store.cachedPrice("USD") ?: 0.0, 0.0)
        assertEquals(1_234L, store.cachedPriceDate("USD"))
        assertNull(rawStore.string(StorageKeys.priceCachedBTC))
        assertEquals(Long.MIN_VALUE, rawStore.long(StorageKeys.priceCachedBTCDate, Long.MIN_VALUE))

        store.setCachedPrice(90_000.0, "EUR")
        store.setCachedPriceDate(2_345L, "EUR")

        assertNull(store.cachedPrice("GBP"))
        assertNull(store.cachedPriceDate("GBP"))
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
