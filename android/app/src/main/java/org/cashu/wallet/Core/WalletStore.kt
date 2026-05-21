package org.cashu.wallet.Core

import android.content.Context
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import org.cashu.wallet.Core.Protocols.StorageKeys
import org.cashu.wallet.Models.ClaimedToken
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Models.PendingReceiveToken
import org.cashu.wallet.Models.PendingToken
import org.cashu.wallet.Models.WalletTransaction

class WalletStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("wallet_store", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    var activeMintURL: String?
        get() = prefs.getString(StorageKeys.walletActiveMintUrl, null)
        set(value) = prefs.edit().putString(StorageKeys.walletActiveMintUrl, value).apply()

    fun loadMints(): List<MintInfo> = loadList(StorageKeys.walletMints, MintInfo.serializer())
    fun saveMints(mints: List<MintInfo>) = saveList(StorageKeys.walletMints, MintInfo.serializer(), mints)

    fun loadPendingTokens(): List<PendingToken> = loadList(StorageKeys.walletPendingTokens, PendingToken.serializer())
    fun savePendingTokens(tokens: List<PendingToken>) = saveList(StorageKeys.walletPendingTokens, PendingToken.serializer(), tokens)

    fun loadPendingReceiveTokens(): List<PendingReceiveToken> = loadList(StorageKeys.walletPendingReceiveTokens, PendingReceiveToken.serializer())
    fun savePendingReceiveTokens(tokens: List<PendingReceiveToken>) =
        saveList(StorageKeys.walletPendingReceiveTokens, PendingReceiveToken.serializer(), tokens)

    fun loadClaimedTokens(): List<ClaimedToken> = loadList(StorageKeys.walletClaimedTokens, ClaimedToken.serializer())
    fun saveClaimedTokens(tokens: List<ClaimedToken>) = saveList(StorageKeys.walletClaimedTokens, ClaimedToken.serializer(), tokens)

    fun loadTransactions(): List<WalletTransaction> = loadList(StorageKeys.walletTransactions, WalletTransaction.serializer())
    fun saveTransactions(transactions: List<WalletTransaction>) =
        saveList(StorageKeys.walletTransactions, WalletTransaction.serializer(), transactions)

    fun loadPaymentPreimages(): Map<String, String> =
        loadMap(StorageKeys.walletPaymentPreimages, String.serializer())
    fun savePaymentPreimages(preimages: Map<String, String>) =
        saveMap(StorageKeys.walletPaymentPreimages, String.serializer(), preimages)

    fun loadMeltQuoteFees(): Map<String, Long> =
        loadMap(StorageKeys.walletMeltQuoteFees, Long.serializer())
    fun saveMeltQuoteFees(fees: Map<String, Long>) =
        saveMap(StorageKeys.walletMeltQuoteFees, Long.serializer(), fees)

    fun loadMintQuoteTimestamps(): Map<String, Long> =
        loadMap(StorageKeys.walletMintQuoteTimestamps, Long.serializer())
    fun saveMintQuoteTimestamps(timestamps: Map<String, Long>) =
        saveMap(StorageKeys.walletMintQuoteTimestamps, Long.serializer(), timestamps)

    fun loadProcessedNPCQuotes(): List<String> = loadList(StorageKeys.walletProcessedNPCQuotes, String.serializer())
    fun saveProcessedNPCQuotes(quotes: List<String>) =
        saveList(StorageKeys.walletProcessedNPCQuotes, String.serializer(), quotes)

    internal fun snapshotWalletScopedData(): PreferenceSnapshot {
        val prefixKeys = prefs.all.keys.filter {
            it.startsWith(StorageKeys.walletDataPrefix) || it.startsWith(StorageKeys.npcDataPrefix)
        }
        return prefs.snapshot(StorageKeys.walletBoundaryKeys + prefixKeys)
    }

    internal fun restoreWalletScopedData(snapshot: PreferenceSnapshot) {
        prefs.restore(snapshot)
    }

    fun removeAllWalletData() {
        val editor = prefs.edit()
        StorageKeys.walletBoundaryKeys.forEach(editor::remove)
        prefs.all.keys
            .filter { it.startsWith(StorageKeys.walletDataPrefix) || it.startsWith(StorageKeys.npcDataPrefix) }
            .forEach(editor::remove)
        editor.apply()
    }

    private fun <T> loadList(key: String, serializer: KSerializer<T>): List<T> {
        val raw = prefs.getString(key, null) ?: return emptyList()
        return runCatching { json.decodeFromString(ListSerializer(serializer), raw) }.getOrDefault(emptyList())
    }

    private fun <T> saveList(key: String, serializer: KSerializer<T>, values: List<T>) {
        prefs.edit().putString(key, json.encodeToString(ListSerializer(serializer), values)).apply()
    }

    private fun <T> loadMap(key: String, serializer: KSerializer<T>): Map<String, T> {
        val raw = prefs.getString(key, null) ?: return emptyMap()
        return runCatching { json.decodeFromString(MapSerializer(String.serializer(), serializer), raw) }
            .getOrDefault(emptyMap())
    }

    private fun <T> saveMap(key: String, serializer: KSerializer<T>, values: Map<String, T>) {
        prefs.edit().putString(key, json.encodeToString(MapSerializer(String.serializer(), serializer), values)).apply()
    }
}
