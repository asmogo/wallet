package com.cashu.me.Core

import android.content.Context
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import com.cashu.me.Core.Protocols.StorageKeys
import com.cashu.me.Models.P2PKKeyInfo

class SettingsStore(
    context: Context,
    storeName: String = "settings_store",
) {
    companion object {
        val defaultNostrRelays = listOf(
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://relay.primal.net",
        )
    }

    private val store = DataStorePreferenceStore(context.applicationContext, storeName)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    var useBitcoinSymbol: Boolean
        get() = store.boolean(StorageKeys.settingsUseBitcoinSymbol, true)
        set(value) = store.putBoolean(StorageKeys.settingsUseBitcoinSymbol, value)

    var showFiatBalance: Boolean
        get() = store.boolean(StorageKeys.settingsShowFiatBalance, false)
        set(value) = store.putBoolean(StorageKeys.settingsShowFiatBalance, value)

    var bitcoinPriceCurrency: String
        get() = store.string(StorageKeys.settingsBitcoinPriceCurrency) ?: "USD"
        set(value) = store.putString(StorageKeys.settingsBitcoinPriceCurrency, value)

    var checkPendingOnStartup: Boolean
        get() = store.boolean(StorageKeys.settingsCheckPendingOnStartup, true)
        set(value) = store.putBoolean(StorageKeys.settingsCheckPendingOnStartup, value)

    var checkSentTokens: Boolean
        get() = store.boolean(StorageKeys.settingsCheckSentTokens, true)
        set(value) = store.putBoolean(StorageKeys.settingsCheckSentTokens, value)

    var autoPasteEcashReceive: Boolean
        get() = store.boolean(StorageKeys.settingsAutoPasteEcashReceive, true)
        set(value) = store.putBoolean(StorageKeys.settingsAutoPasteEcashReceive, value)

    var useWebsockets: Boolean
        get() = store.boolean(StorageKeys.settingsUseWebsockets, true)
        set(value) = store.putBoolean(StorageKeys.settingsUseWebsockets, value)

    var enablePaymentRequests: Boolean
        get() = store.boolean(StorageKeys.settingsEnablePaymentRequests, true)
        set(value) = store.putBoolean(StorageKeys.settingsEnablePaymentRequests, value)

    var receivePaymentRequestsAutomatically: Boolean
        get() = store.boolean(StorageKeys.settingsReceivePaymentRequestsAutomatically, true)
        set(value) = store.putBoolean(StorageKeys.settingsReceivePaymentRequestsAutomatically, value)

    var showP2PKButtonInDrawer: Boolean
        get() = store.boolean(StorageKeys.settingsShowP2PKButtonInDrawer, false)
        set(value) = store.putBoolean(StorageKeys.settingsShowP2PKButtonInDrawer, value)

    var amountDisplayPrimary: String
        get() = store.string(StorageKeys.settingsAmountDisplayPrimary) ?: "fiat"
        set(value) = store.putString(StorageKeys.settingsAmountDisplayPrimary, value)

    var homeBalanceUnit: String
        get() = store.string(StorageKeys.settingsHomeBalanceUnit) ?: "sat"
        set(value) = store.putString(StorageKeys.settingsHomeBalanceUnit, value)

    var sentryEnabled: Boolean
        get() = store.boolean(StorageKeys.settingsSentryEnabled, false)
        set(value) = store.putBoolean(StorageKeys.settingsSentryEnabled, value)

    var appLockEnabled: Boolean
        get() = store.boolean(StorageKeys.settingsAppLockEnabled, false)
        set(value) = store.putBoolean(StorageKeys.settingsAppLockEnabled, value)

    var checkIncomingInvoices: Boolean
        get() = store.boolean(StorageKeys.settingsCheckIncomingInvoices, true)
        set(value) = store.putBoolean(StorageKeys.settingsCheckIncomingInvoices, value)

    var periodicallyCheckIncomingInvoices: Boolean
        get() = store.boolean(StorageKeys.settingsPeriodicallyCheckIncomingInvoices, true)
        set(value) = store.putBoolean(StorageKeys.settingsPeriodicallyCheckIncomingInvoices, value)

    var nostrSignerType: String
        get() = store.string(StorageKeys.settingsNostrSignerType) ?: "SEED"
        set(value) = store.putString(StorageKeys.settingsNostrSignerType, value)

    var nostrRelays: List<String>
        get() = loadList(StorageKeys.settingsNostrRelays, String.serializer()).ifEmpty { defaultNostrRelays }
        set(value) = saveList(StorageKeys.settingsNostrRelays, String.serializer(), value)

    var nostrMintBackupEnabled: Boolean
        get() = store.boolean(StorageKeys.settingsNostrMintBackupEnabled, true)
        set(value) = store.putBoolean(StorageKeys.settingsNostrMintBackupEnabled, value)

    var nostrMintBackupLastBackupDate: Long?
        get() = store.long(StorageKeys.walletNostrMintBackupLastBackupDate, Long.MIN_VALUE)
            .takeIf { it != Long.MIN_VALUE }
        set(value) = if (value == null) {
            store.remove(StorageKeys.walletNostrMintBackupLastBackupDate)
        } else {
            store.putLong(StorageKeys.walletNostrMintBackupLastBackupDate, value)
        }

    var nwcEnabled: Boolean
        get() = store.boolean(StorageKeys.nwcEnabled, false)
        set(value) = store.putBoolean(StorageKeys.nwcEnabled, value)

    var nwcSelectedMint: String?
        get() = store.string(StorageKeys.nwcSelectedMint)
        set(value) = store.putString(StorageKeys.nwcSelectedMint, value)

    var nwcBudgetSats: Long?
        get() = store.long(StorageKeys.nwcBudgetSats, Long.MIN_VALUE)
            .takeIf { it != Long.MIN_VALUE }
        set(value) = if (value == null) {
            store.putLong(StorageKeys.nwcBudgetSats, Long.MIN_VALUE)
        } else {
            store.putLong(StorageKeys.nwcBudgetSats, value)
        }

    var p2pkKeys: List<P2PKKeyInfo>
        get() = loadList(StorageKeys.settingsP2PKKeys, P2PKKeyInfo.serializer())
        set(value) = saveList(StorageKeys.settingsP2PKKeys, P2PKKeyInfo.serializer(), value)

    internal fun loadP2PKKeysWithLegacySecrets(): List<LegacyP2PKKeyRecord> =
        LegacySettingsSecretParser.p2pkKeys(store.string(StorageKeys.settingsP2PKKeys))

    internal fun clearLegacyNwcPrototypeSettings() {
        store.removeKeys(
            listOf(
                StorageKeys.legacySettingsEnableNwc,
                StorageKeys.legacySettingsNwcConnections,
            ),
        )
    }

    internal fun snapshotWalletScopedData(): PreferenceSnapshot {
        val prefixKeys = store.keys().filter { it.startsWith(StorageKeys.npcDataPrefix) }
        return store.snapshot(walletScopedKeys + prefixKeys)
    }

    internal fun restoreWalletScopedData(snapshot: PreferenceSnapshot) {
        store.restore(snapshot)
    }

    fun clearWalletScopedData() {
        store.removeKeys(walletScopedKeys)
        store.removePrefix(listOf(StorageKeys.npcDataPrefix, StorageKeys.nwcDataPrefix))
    }

    fun resetNostrRelaysToDefault() {
        nostrRelays = defaultNostrRelays
    }

    var priceEnabled: Boolean
        get() = store.boolean(StorageKeys.priceEnabled, showFiatBalance)
        set(value) = store.putBoolean(StorageKeys.priceEnabled, value)

    var priceCurrencyCode: String
        get() = store.string(StorageKeys.priceCurrencyCode) ?: bitcoinPriceCurrency
        set(value) = store.putString(StorageKeys.priceCurrencyCode, value.uppercase())

    fun cachedPrice(currency: String): Double? {
        val normalized = currency.uppercase()
        return store.string(StorageKeys.priceCachedBTC(normalized))?.toDoubleOrNull()
            ?: store.string(StorageKeys.priceCachedBTC)?.toDoubleOrNull()
    }

    fun setCachedPrice(price: Double, currency: String) {
        val normalized = currency.uppercase()
        store.putString(StorageKeys.priceCachedBTC(normalized), price.toString())
        store.putString(StorageKeys.priceCachedBTC, price.toString())
    }

    fun cachedPriceDate(currency: String): Long? {
        val normalized = currency.uppercase()
        val dated = store.long(StorageKeys.priceCachedBTCDate(normalized), Long.MIN_VALUE)
        if (dated != Long.MIN_VALUE) return dated
        val legacy = store.long(StorageKeys.priceCachedBTCDate, Long.MIN_VALUE)
        return legacy.takeIf { it != Long.MIN_VALUE }
    }

    fun setCachedPriceDate(epochMillis: Long, currency: String) {
        val normalized = currency.uppercase()
        store.putLong(StorageKeys.priceCachedBTCDate(normalized), epochMillis)
        store.putLong(StorageKeys.priceCachedBTCDate, epochMillis)
    }

    private fun <T> loadList(key: String, serializer: KSerializer<T>): List<T> {
        val raw = store.string(key) ?: return emptyList()
        return runCatching { json.decodeFromString(ListSerializer(serializer), raw) }.getOrDefault(emptyList())
    }

    private fun <T> saveList(key: String, serializer: KSerializer<T>, values: List<T>) {
        store.putString(key, json.encodeToString(ListSerializer(serializer), values))
    }

    private val walletScopedKeys = setOf(
        StorageKeys.settingsEnablePaymentRequests,
        StorageKeys.settingsReceivePaymentRequestsAutomatically,
        StorageKeys.settingsP2PKKeys,
        StorageKeys.settingsNostrSignerType,
        StorageKeys.settingsNostrMintBackupEnabled,
        StorageKeys.cashuRequestsProcessedNip17Ids,
        StorageKeys.walletNostrMintBackupLastBackupDate,
        StorageKeys.npcEnabled,
        StorageKeys.npcAutomaticClaim,
        StorageKeys.npcSelectedMint,
        StorageKeys.npcLastCheck,
        StorageKeys.nwcEnabled,
        StorageKeys.nwcSelectedMint,
        StorageKeys.nwcBudgetSats,
    )
}

internal data class LegacyP2PKKeyRecord(
    val metadata: P2PKKeyInfo,
    val privateKey: String,
    val shouldRewriteMetadata: Boolean,
) {
    val hasLegacySecret: Boolean get() = privateKey.isNotBlank()
}

internal object LegacySettingsSecretParser {
    private val json = Json { ignoreUnknownKeys = true }

    fun p2pkKeys(raw: String?): List<LegacyP2PKKeyRecord> {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching {
            json.parseToJsonElement(raw).jsonArray.mapNotNull { element ->
                val fields = element.jsonObject
                val publicKey = fields.string("publicKey") ?: return@mapNotNull null
                val id = fields.string("id") ?: java.util.UUID.randomUUID().toString()
                val hasLabel = "label" in fields
                val hasCreatedAt = "createdAtEpochMillis" in fields
                val metadata = P2PKKeyInfo(
                    id = id,
                    publicKey = publicKey,
                    label = fields.string("label") ?: "P2PK key",
                    createdAtEpochMillis = fields.long("createdAtEpochMillis") ?: System.currentTimeMillis(),
                    used = fields.boolean("used") ?: false,
                    usedCount = fields.long("usedCount")?.toInt() ?: 0,
                )
                LegacyP2PKKeyRecord(
                    metadata = metadata,
                    privateKey = fields.string("privateKey").orEmpty(),
                    shouldRewriteMetadata = !hasLabel || !hasCreatedAt || "privateKey" in fields,
                )
            }
        }.getOrDefault(emptyList())
    }

    private fun Map<String, JsonElement>.string(key: String): String? =
        get(key)?.jsonPrimitive?.contentOrNull

    private fun Map<String, JsonElement>.long(key: String): Long? =
        get(key)?.jsonPrimitive?.longOrNull

    private fun Map<String, JsonElement>.boolean(key: String): Boolean? =
        get(key)?.jsonPrimitive?.booleanOrNull
}
