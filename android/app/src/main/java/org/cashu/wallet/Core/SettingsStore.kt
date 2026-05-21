package org.cashu.wallet.Core

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
import org.cashu.wallet.Core.Protocols.StorageKeys
import org.cashu.wallet.Models.NwcConnection
import org.cashu.wallet.Models.P2PKKeyInfo

class SettingsStore(context: Context) {
    companion object {
        val defaultNostrRelays = listOf(
            "wss://relay.damus.io",
            "wss://relay.8333.space/",
            "wss://nos.lol",
            "wss://relay.primal.net",
        )
    }

    private val prefs = context.applicationContext.getSharedPreferences("settings_store", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    var useBitcoinSymbol: Boolean
        get() = prefs.getBoolean(StorageKeys.settingsUseBitcoinSymbol, false)
        set(value) = prefs.edit().putBoolean(StorageKeys.settingsUseBitcoinSymbol, value).apply()

    var showFiatBalance: Boolean
        get() = prefs.getBoolean(StorageKeys.settingsShowFiatBalance, false)
        set(value) = prefs.edit().putBoolean(StorageKeys.settingsShowFiatBalance, value).apply()

    var bitcoinPriceCurrency: String
        get() = prefs.getString(StorageKeys.settingsBitcoinPriceCurrency, "USD") ?: "USD"
        set(value) = prefs.edit().putString(StorageKeys.settingsBitcoinPriceCurrency, value).apply()

    var checkPendingOnStartup: Boolean
        get() = prefs.getBoolean(StorageKeys.settingsCheckPendingOnStartup, true)
        set(value) = prefs.edit().putBoolean(StorageKeys.settingsCheckPendingOnStartup, value).apply()

    var checkSentTokens: Boolean
        get() = prefs.getBoolean(StorageKeys.settingsCheckSentTokens, true)
        set(value) = prefs.edit().putBoolean(StorageKeys.settingsCheckSentTokens, value).apply()

    var autoPasteEcashReceive: Boolean
        get() = prefs.getBoolean(StorageKeys.settingsAutoPasteEcashReceive, true)
        set(value) = prefs.edit().putBoolean(StorageKeys.settingsAutoPasteEcashReceive, value).apply()

    var useWebsockets: Boolean
        get() = prefs.getBoolean(StorageKeys.settingsUseWebsockets, true)
        set(value) = prefs.edit().putBoolean(StorageKeys.settingsUseWebsockets, value).apply()

    var enablePaymentRequests: Boolean
        get() = prefs.getBoolean(StorageKeys.settingsEnablePaymentRequests, false)
        set(value) = prefs.edit().putBoolean(StorageKeys.settingsEnablePaymentRequests, value).apply()

    var receivePaymentRequestsAutomatically: Boolean
        get() = prefs.getBoolean(StorageKeys.settingsReceivePaymentRequestsAutomatically, false)
        set(value) = prefs.edit().putBoolean(StorageKeys.settingsReceivePaymentRequestsAutomatically, value).apply()

    var enableNWC: Boolean
        get() = prefs.getBoolean(StorageKeys.settingsEnableNWC, false)
        set(value) = prefs.edit().putBoolean(StorageKeys.settingsEnableNWC, value).apply()

    var showP2PKButtonInDrawer: Boolean
        get() = prefs.getBoolean(StorageKeys.settingsShowP2PKButtonInDrawer, false)
        set(value) = prefs.edit().putBoolean(StorageKeys.settingsShowP2PKButtonInDrawer, value).apply()

    var amountDisplayPrimary: String
        get() = prefs.getString(StorageKeys.settingsAmountDisplayPrimary, "fiat") ?: "fiat"
        set(value) = prefs.edit().putString(StorageKeys.settingsAmountDisplayPrimary, value).apply()

    var checkIncomingInvoices: Boolean
        get() = prefs.getBoolean(StorageKeys.settingsCheckIncomingInvoices, true)
        set(value) = prefs.edit().putBoolean(StorageKeys.settingsCheckIncomingInvoices, value).apply()

    var periodicallyCheckIncomingInvoices: Boolean
        get() = prefs.getBoolean(StorageKeys.settingsPeriodicallyCheckIncomingInvoices, true)
        set(value) = prefs.edit().putBoolean(StorageKeys.settingsPeriodicallyCheckIncomingInvoices, value).apply()

    var nostrSignerType: String
        get() = prefs.getString(StorageKeys.settingsNostrSignerType, "SEED") ?: "SEED"
        set(value) = prefs.edit().putString(StorageKeys.settingsNostrSignerType, value).apply()

    var nostrRelays: List<String>
        get() = loadList(StorageKeys.settingsNostrRelays, String.serializer()).ifEmpty { defaultNostrRelays }
        set(value) = saveList(StorageKeys.settingsNostrRelays, String.serializer(), value)

    var nwcConnections: List<NwcConnection>
        get() = loadList(StorageKeys.settingsNwcConnections, NwcConnection.serializer())
        set(value) = saveList(StorageKeys.settingsNwcConnections, NwcConnection.serializer(), value)

    var p2pkKeys: List<P2PKKeyInfo>
        get() = loadList(StorageKeys.settingsP2PKKeys, P2PKKeyInfo.serializer())
        set(value) = saveList(StorageKeys.settingsP2PKKeys, P2PKKeyInfo.serializer(), value)

    internal fun loadNwcConnectionsWithLegacySecrets(): List<LegacyNwcConnectionRecord> =
        LegacySettingsSecretParser.nwcConnections(prefs.getString(StorageKeys.settingsNwcConnections, null))

    internal fun loadP2PKKeysWithLegacySecrets(): List<LegacyP2PKKeyRecord> =
        LegacySettingsSecretParser.p2pkKeys(prefs.getString(StorageKeys.settingsP2PKKeys, null))

    internal fun snapshotWalletScopedData(): PreferenceSnapshot {
        val prefixKeys = prefs.all.keys.filter { it.startsWith(StorageKeys.npcDataPrefix) }
        return prefs.snapshot(walletScopedKeys + prefixKeys)
    }

    internal fun restoreWalletScopedData(snapshot: PreferenceSnapshot) {
        prefs.restore(snapshot)
    }

    fun clearWalletScopedData() {
        val editor = prefs.edit()
        walletScopedKeys.forEach(editor::remove)
        prefs.all.keys
            .filter { it.startsWith(StorageKeys.npcDataPrefix) }
            .forEach(editor::remove)
        editor.apply()
    }

    fun resetNostrRelaysToDefault() {
        nostrRelays = defaultNostrRelays
    }

    var priceEnabled: Boolean
        get() = prefs.getBoolean(StorageKeys.priceEnabled, showFiatBalance)
        set(value) = prefs.edit().putBoolean(StorageKeys.priceEnabled, value).apply()

    var priceCurrencyCode: String
        get() = prefs.getString(StorageKeys.priceCurrencyCode, bitcoinPriceCurrency) ?: bitcoinPriceCurrency
        set(value) = prefs.edit().putString(StorageKeys.priceCurrencyCode, value.uppercase()).apply()

    fun cachedPrice(currency: String): Double? {
        val normalized = currency.uppercase()
        return prefs.getString(StorageKeys.priceCachedBTC(normalized), null)?.toDoubleOrNull()
            ?: prefs.getString(StorageKeys.priceCachedBTC, null)?.toDoubleOrNull()
    }

    fun setCachedPrice(price: Double, currency: String) {
        val normalized = currency.uppercase()
        prefs.edit()
            .putString(StorageKeys.priceCachedBTC(normalized), price.toString())
            .putString(StorageKeys.priceCachedBTC, price.toString())
            .apply()
    }

    fun cachedPriceDate(currency: String): Long? {
        val normalized = currency.uppercase()
        val dated = prefs.getLong(StorageKeys.priceCachedBTCDate(normalized), Long.MIN_VALUE)
        if (dated != Long.MIN_VALUE) return dated
        val legacy = prefs.getLong(StorageKeys.priceCachedBTCDate, Long.MIN_VALUE)
        return legacy.takeIf { it != Long.MIN_VALUE }
    }

    fun setCachedPriceDate(epochMillis: Long, currency: String) {
        val normalized = currency.uppercase()
        prefs.edit()
            .putLong(StorageKeys.priceCachedBTCDate(normalized), epochMillis)
            .putLong(StorageKeys.priceCachedBTCDate, epochMillis)
            .apply()
    }

    private fun <T> loadList(key: String, serializer: KSerializer<T>): List<T> {
        val raw = prefs.getString(key, null) ?: return emptyList()
        return runCatching { json.decodeFromString(ListSerializer(serializer), raw) }.getOrDefault(emptyList())
    }

    private fun <T> saveList(key: String, serializer: KSerializer<T>, values: List<T>) {
        prefs.edit().putString(key, json.encodeToString(ListSerializer(serializer), values)).apply()
    }

    private val walletScopedKeys = setOf(
        StorageKeys.settingsNwcConnections,
        StorageKeys.settingsP2PKKeys,
        StorageKeys.settingsNostrSignerType,
        StorageKeys.npcEnabled,
        StorageKeys.npcAutomaticClaim,
        StorageKeys.npcSelectedMint,
        StorageKeys.npcLastCheck,
    )
}

internal data class LegacyNwcConnectionRecord(
    val metadata: NwcConnection,
    val walletPrivateKey: String,
    val connectionSecret: String,
    val shouldRewriteMetadata: Boolean,
) {
    val hasLegacySecret: Boolean get() = walletPrivateKey.isNotBlank() || connectionSecret.isNotBlank()
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

    fun nwcConnections(raw: String?): List<LegacyNwcConnectionRecord> {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching {
            json.parseToJsonElement(raw).jsonArray.mapNotNull { element ->
                val fields = element.jsonObject
                val walletPublicKey = fields.string("walletPublicKey") ?: return@mapNotNull null
                val connectionPublicKey = fields.string("connectionPublicKey") ?: return@mapNotNull null
                val id = fields.string("id") ?: java.util.UUID.randomUUID().toString()
                val hasName = "name" in fields
                val hasCreatedAt = "createdAtEpochMillis" in fields
                val hasAndroidAllowance = "allowanceSats" in fields
                val hasSwiftAllowance = "allowanceLeft" in fields
                val metadata = NwcConnection(
                    id = id,
                    name = fields.string("name") ?: "Wallet connection",
                    walletPublicKey = walletPublicKey,
                    connectionPublicKey = connectionPublicKey,
                    allowanceSats = fields.long("allowanceSats") ?: fields.long("allowanceLeft"),
                    createdAtEpochMillis = fields.long("createdAtEpochMillis") ?: System.currentTimeMillis(),
                )
                LegacyNwcConnectionRecord(
                    metadata = metadata,
                    walletPrivateKey = fields.string("walletPrivateKey").orEmpty(),
                    connectionSecret = fields.string("connectionSecret").orEmpty(),
                    shouldRewriteMetadata = !hasName || !hasCreatedAt || !hasAndroidAllowance || hasSwiftAllowance ||
                        "walletPrivateKey" in fields || "connectionSecret" in fields,
                )
            }
        }.getOrDefault(emptyList())
    }

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
