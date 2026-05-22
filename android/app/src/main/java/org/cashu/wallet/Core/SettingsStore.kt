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

class SettingsStore(
    context: Context,
    storeName: String = "settings_store",
) {
    companion object {
        val defaultNostrRelays = listOf(
            "wss://relay.damus.io",
            "wss://relay.8333.space/",
            "wss://nos.lol",
            "wss://relay.primal.net",
        )
    }

    private val store = DataStorePreferenceStore(context.applicationContext, storeName)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    var useBitcoinSymbol: Boolean
        get() = store.boolean(StorageKeys.settingsUseBitcoinSymbol, false)
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
        get() = store.boolean(StorageKeys.settingsEnablePaymentRequests, false)
        set(value) = store.putBoolean(StorageKeys.settingsEnablePaymentRequests, value)

    var receivePaymentRequestsAutomatically: Boolean
        get() = store.boolean(StorageKeys.settingsReceivePaymentRequestsAutomatically, false)
        set(value) = store.putBoolean(StorageKeys.settingsReceivePaymentRequestsAutomatically, value)

    var enableNWC: Boolean
        get() = store.boolean(StorageKeys.settingsEnableNWC, false)
        set(value) = store.putBoolean(StorageKeys.settingsEnableNWC, value)

    var showP2PKButtonInDrawer: Boolean
        get() = store.boolean(StorageKeys.settingsShowP2PKButtonInDrawer, false)
        set(value) = store.putBoolean(StorageKeys.settingsShowP2PKButtonInDrawer, value)

    var amountDisplayPrimary: String
        get() = store.string(StorageKeys.settingsAmountDisplayPrimary) ?: "fiat"
        set(value) = store.putString(StorageKeys.settingsAmountDisplayPrimary, value)

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

    var nwcConnections: List<NwcConnection>
        get() = loadList(StorageKeys.settingsNwcConnections, NwcConnection.serializer())
        set(value) = saveList(StorageKeys.settingsNwcConnections, NwcConnection.serializer(), value)

    var p2pkKeys: List<P2PKKeyInfo>
        get() = loadList(StorageKeys.settingsP2PKKeys, P2PKKeyInfo.serializer())
        set(value) = saveList(StorageKeys.settingsP2PKKeys, P2PKKeyInfo.serializer(), value)

    internal fun loadNwcConnectionsWithLegacySecrets(): List<LegacyNwcConnectionRecord> =
        LegacySettingsSecretParser.nwcConnections(store.string(StorageKeys.settingsNwcConnections))

    internal fun loadP2PKKeysWithLegacySecrets(): List<LegacyP2PKKeyRecord> =
        LegacySettingsSecretParser.p2pkKeys(store.string(StorageKeys.settingsP2PKKeys))

    internal fun snapshotWalletScopedData(): PreferenceSnapshot {
        val prefixKeys = store.keys().filter { it.startsWith(StorageKeys.npcDataPrefix) }
        return store.snapshot(walletScopedKeys + prefixKeys)
    }

    internal fun restoreWalletScopedData(snapshot: PreferenceSnapshot) {
        store.restore(snapshot)
    }

    fun clearWalletScopedData() {
        store.removeKeys(walletScopedKeys)
        store.removePrefix(listOf(StorageKeys.npcDataPrefix))
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
