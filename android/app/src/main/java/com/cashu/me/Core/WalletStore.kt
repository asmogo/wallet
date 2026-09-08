package com.cashu.me.Core

import android.content.Context
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import com.cashu.me.Core.Protocols.StorageKeys
import com.cashu.me.Models.CashuRequest
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.MintQuoteScheduleRecord
import com.cashu.me.Models.PendingReceiveToken
import com.cashu.me.Models.WalletTransaction

class WalletStore(
    context: Context,
    storeName: String = "wallet_store",
) : CashuRequestPersistence {
    private val store = DataStorePreferenceStore(context.applicationContext, storeName)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    var activeMintURL: String?
        get() = store.string(StorageKeys.walletActiveMintUrl)
        set(value) = store.putString(StorageKeys.walletActiveMintUrl, value)

    fun loadMints(): List<MintInfo> {
        val removed = loadList(StorageKeys.walletRemovedMintUrls, String.serializer())
        return loadList(StorageKeys.walletMints, MintInfo.serializer()).filterNot { mint ->
            removed.any { com.cashu.me.Core.CDK.mintRemovalUrlsMatch(it, mint.url) }
        }
    }
    fun saveMints(mints: List<MintInfo>) = saveList(StorageKeys.walletMints, MintInfo.serializer(), mints)

    /** CDK retains proofs after removal; they must not implicitly reconnect a mint. */
    fun isMintRemoved(url: String): Boolean =
        loadList(StorageKeys.walletRemovedMintUrls, String.serializer())
            .any { com.cashu.me.Core.CDK.mintRemovalUrlsMatch(it, url) }

    @Synchronized
    fun setMintRemoved(url: String, removed: Boolean) {
        val current = loadList(StorageKeys.walletRemovedMintUrls, String.serializer())
        val updated = current.filterNot { com.cashu.me.Core.CDK.mintRemovalUrlsMatch(it, url) } +
            if (removed) listOf(url) else emptyList()
        if (updated != current) saveList(StorageKeys.walletRemovedMintUrls, String.serializer(), updated)
    }

    fun loadBalancesByUnit(): Map<String, Long> =
        loadMap(StorageKeys.walletBalancesByUnit, Long.serializer())
    fun saveBalancesByUnit(balances: Map<String, Long>) =
        saveMap(StorageKeys.walletBalancesByUnit, Long.serializer(), balances)

    fun loadPendingReceiveTokens(): List<PendingReceiveToken> = loadList(StorageKeys.walletPendingReceiveTokens, PendingReceiveToken.serializer())
    fun savePendingReceiveTokens(tokens: List<PendingReceiveToken>) =
        saveList(StorageKeys.walletPendingReceiveTokens, PendingReceiveToken.serializer(), tokens)

    /** txId → encoded token (re-display/reclaim of sent tokens, receive receipts). */
    fun loadSavedTokens(): Map<String, String> =
        loadMap(StorageKeys.walletSavedTokens, String.serializer())
    fun saveSavedTokens(tokens: Map<String, String>) =
        saveMap(StorageKeys.walletSavedTokens, String.serializer(), tokens)

    fun loadTransactions(): List<WalletTransaction> = loadList(StorageKeys.walletTransactions, WalletTransaction.serializer())
    fun saveTransactions(transactions: List<WalletTransaction>) =
        saveList(StorageKeys.walletTransactions, WalletTransaction.serializer(), transactions)

    fun loadPaymentPreimages(): Map<String, String> =
        loadMap(StorageKeys.walletPaymentPreimages, String.serializer())
    fun savePaymentPreimages(preimages: Map<String, String>) =
        saveMap(StorageKeys.walletPaymentPreimages, String.serializer(), preimages)

    fun loadMintQuoteTimestamps(): Map<String, Long> =
        loadMap(StorageKeys.walletMintQuoteTimestamps, Long.serializer())
    fun saveMintQuoteTimestamps(timestamps: Map<String, Long>) =
        saveMap(StorageKeys.walletMintQuoteTimestamps, Long.serializer(), timestamps)

    fun loadMintQuoteSchedules(): Map<String, MintQuoteScheduleRecord> =
        loadMap(StorageKeys.walletMintQuoteSchedules, MintQuoteScheduleRecord.serializer())
    fun saveMintQuoteSchedules(schedules: Map<String, MintQuoteScheduleRecord>) =
        saveMap(StorageKeys.walletMintQuoteSchedules, MintQuoteScheduleRecord.serializer(), schedules)

    fun loadProcessedNPCQuotes(): List<String> = loadList(StorageKeys.walletProcessedNPCQuotes, String.serializer())
    fun saveProcessedNPCQuotes(quotes: List<String>) =
        saveList(StorageKeys.walletProcessedNPCQuotes, String.serializer(), quotes)

    fun loadProcessedCashuRequests(): List<String> =
        loadList(StorageKeys.walletProcessedCashuRequests, String.serializer())
    fun saveProcessedCashuRequests(requestIds: List<String>) =
        saveList(StorageKeys.walletProcessedCashuRequests, String.serializer(), requestIds)

    fun loadProcessedNip17GiftWraps(): List<String> =
        loadList(StorageKeys.walletProcessedNip17GiftWraps, String.serializer())
    fun saveProcessedNip17GiftWraps(eventIds: List<String>) =
        saveList(StorageKeys.walletProcessedNip17GiftWraps, String.serializer(), eventIds)

    override fun loadCashuRequests(): List<CashuRequest> =
        loadList(StorageKeys.cashuRequests, CashuRequest.serializer()).map { it.withLegacyPaymentFallback() }
    override fun saveCashuRequests(requests: List<CashuRequest>) =
        saveList(StorageKeys.cashuRequests, CashuRequest.serializer(), requests.map { it.withLegacyPaymentFallback() })

    override var currentCashuRequestId: String?
        get() = store.string(StorageKeys.cashuRequestsCurrentId)
        set(value) = store.putString(StorageKeys.cashuRequestsCurrentId, value)

    internal fun snapshotWalletScopedData(): PreferenceSnapshot {
        val prefixKeys = store.keys().filter {
            it.startsWith(StorageKeys.walletDataPrefix) || it.startsWith(StorageKeys.npcDataPrefix)
        }
        return store.snapshot(StorageKeys.walletBoundaryKeys + prefixKeys)
    }

    internal fun restoreWalletScopedData(snapshot: PreferenceSnapshot) {
        store.restore(snapshot)
    }

    fun removeAllWalletData() {
        store.removeKeys(StorageKeys.walletBoundaryKeys)
        store.removePrefix(listOf(StorageKeys.walletDataPrefix, StorageKeys.npcDataPrefix))
    }

    /**
     * One-way cleanup for stores obsoleted by the CDK 0.18 transaction
     * lifecycle upgrade (local pending/claimed send records, async-melt
     * tracking, melt fee notes). Idempotent.
     */
    fun purgeRetiredKeys() {
        store.removeKeys(StorageKeys.retiredWalletKeys)
    }

    private fun <T> loadList(key: String, serializer: KSerializer<T>): List<T> {
        val raw = store.string(key) ?: return emptyList()
        return runCatching { json.decodeFromString(ListSerializer(serializer), raw) }.getOrDefault(emptyList())
    }

    private fun <T> saveList(key: String, serializer: KSerializer<T>, values: List<T>) {
        store.putString(key, json.encodeToString(ListSerializer(serializer), values))
    }

    private fun <T> loadMap(key: String, serializer: KSerializer<T>): Map<String, T> {
        val raw = store.string(key) ?: return emptyMap()
        return runCatching { json.decodeFromString(MapSerializer(String.serializer(), serializer), raw) }
            .getOrDefault(emptyMap())
    }

    private fun <T> saveMap(key: String, serializer: KSerializer<T>, values: Map<String, T>) {
        store.putString(key, json.encodeToString(MapSerializer(String.serializer(), serializer), values))
    }
}
