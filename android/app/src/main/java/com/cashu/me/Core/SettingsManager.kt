package com.cashu.me.Core

import java.security.SecureRandom
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import com.cashu.me.Core.Protocols.SecureStorage
import com.cashu.me.Core.Protocols.StorageKeys
import com.cashu.me.Models.P2PKKeyInfo

/** Why [SettingsManager.addRelay] accepted or rejected a relay URL. */
sealed interface RelayAddResult {
    /** Accepted; [relay] is the trimmed value that was stored. */
    data class Added(val relay: String) : RelayAddResult

    /** Rejected; [message] is user-facing. */
    data class Rejected(val message: String) : RelayAddResult

    companion object {
        const val InvalidScheme = "Relay URL must start with ws:// or wss://"
        const val Duplicate = "Relay already added"
    }
}

/** Nostr speaks over WebSockets only; anything else can never connect. */
fun isSupportedRelayScheme(relay: String): Boolean {
    val trimmed = relay.trim()
    return trimmed.startsWith("wss://", ignoreCase = true) ||
        trimmed.startsWith("ws://", ignoreCase = true)
}

/**
 * Decides whether a typed relay can join [existing]. Free-standing so it is
 * unit-testable without a `Context` — mirrors iOS `NostrRelaysSettingsSection.addRelay`
 * plus `SettingsManager.addNostrRelay`'s case-insensitive duplicate rule.
 *
 * Returns null for blank input, which the submit control already disables.
 */
fun validateNostrRelay(candidate: String, existing: List<String>): RelayAddResult? {
    val trimmed = candidate.trim()
    if (trimmed.isEmpty()) return null
    if (!isSupportedRelayScheme(trimmed)) return RelayAddResult.Rejected(RelayAddResult.InvalidScheme)
    if (existing.any { it.equals(trimmed, ignoreCase = true) }) {
        return RelayAddResult.Rejected(RelayAddResult.Duplicate)
    }
    return RelayAddResult.Added(trimmed)
}

data class SettingsState(
    val useBitcoinSymbol: Boolean = true,
    val showFiatBalance: Boolean = false,
    val bitcoinPriceCurrency: String = "USD",
    val checkPendingOnStartup: Boolean = true,
    val checkSentTokens: Boolean = true,
    val autoPasteEcashReceive: Boolean = true,
    val useWebsockets: Boolean = true,
    val enablePaymentRequests: Boolean = true,
    val receivePaymentRequestsAutomatically: Boolean = true,
    val showP2PKButtonInDrawer: Boolean = false,
    val amountDisplayPrimary: String = "fiat",
    val homeBalancePrimary: String = "sats",
    val homeBalanceUnit: String = "sat",
    val sentryEnabled: Boolean = false,
    val appLockEnabled: Boolean = false,
    val checkIncomingInvoices: Boolean = true,
    val periodicallyCheckIncomingInvoices: Boolean = true,
    val nostrSignerType: String = "SEED",
    val nostrRelays: List<String> = emptyList(),
    val nostrMintBackupEnabled: Boolean = true,
    val p2pkKeys: List<P2PKKeyInfo> = emptyList(),
    val p2pkUnavailableKeyIds: Set<String> = emptySet(),
)

internal data class LegacySettingsSecretMigration(
    val p2pkKeysToPersist: List<P2PKKeyInfo>?,
    val pendingLegacySecrets: Map<String, String>,
)

internal interface P2PKMetadataStore {
    val keys: List<P2PKKeyInfo>
    var pendingDeletionIds: Set<String>
    fun saveKeys(keys: List<P2PKKeyInfo>, preservingLegacySecrets: Map<String, String> = emptyMap())
}

private class SettingsP2PKMetadataStore(
    private val settingsStore: SettingsStore,
) : P2PKMetadataStore {
    override val keys: List<P2PKKeyInfo> get() = settingsStore.p2pkKeys
    override var pendingDeletionIds: Set<String>
        get() = settingsStore.p2pkPendingDeletionIds
        set(value) { settingsStore.p2pkPendingDeletionIds = value }

    override fun saveKeys(
        keys: List<P2PKKeyInfo>,
        preservingLegacySecrets: Map<String, String>,
    ) {
        settingsStore.saveP2PKKeys(keys, preservingLegacySecrets)
    }
}

private class P2PKStorageException(message: String, cause: Throwable? = null) :
    IllegalStateException(message, cause)

/** The wallet's seed-derived P2PK identity: compressed 02-prefixed pubkey + private hex. */
data class PrimaryP2PKKey(
    val publicKey: String,
    val privateKeyHex: String,
)

internal data class SettingsWalletScopedSnapshot(
    val preferences: PreferenceSnapshot,
    val p2pkKeys: List<P2PKKeyInfo>,
    val pendingP2PKDeletionIds: Set<String> = emptySet(),
)

internal object LegacySettingsSecretMigrator {
    fun migrate(
        p2pkRecords: List<LegacyP2PKKeyRecord>,
        loadSecret: (String) -> String?,
        saveSecret: (String, String) -> Unit,
        isUsableSecret: (P2PKKeyInfo, String) -> Boolean,
    ): LegacySettingsSecretMigration {
        var shouldPersistP2PK = false
        val pendingLegacySecrets = mutableMapOf<String, String>()
        val p2pkMetadata = p2pkRecords.map { record ->
            val storageKey = secureP2PKPrivateKey(record.metadata.id)
            val storedSecret = runCatching { loadSecret(storageKey) }.getOrNull()
            val hasUsableStoredSecret = storedSecret != null &&
                isUsableSecret(record.metadata, storedSecret)

            if (!hasUsableStoredSecret && record.privateKey.isNotBlank()) {
                if (isUsableSecret(record.metadata, record.privateKey)) {
                    runCatching { saveSecret(storageKey, record.privateKey) }
                        .onFailure {
                            pendingLegacySecrets[record.metadata.id] = record.privateKey
                        }
                }
            }
            shouldPersistP2PK = shouldPersistP2PK || record.shouldRewriteMetadata || record.hasLegacySecret
            record.metadata
        }

        return LegacySettingsSecretMigration(
            p2pkKeysToPersist = p2pkMetadata.takeIf { shouldPersistP2PK },
            pendingLegacySecrets = pendingLegacySecrets,
        )
    }

    fun secureP2PKPrivateKey(id: String): String = "settings.p2pk.$id.privateKey"
}

class SettingsManager internal constructor(
    private val settingsStore: SettingsStore,
    private val secureStorage: SecureStorage,
    private val p2pkStore: P2PKMetadataStore,
) : MintDiscoverySettings {
    private val secureRandom = SecureRandom()
    private val pendingLegacyP2PKSecrets = mutableMapOf<String, String>()

    constructor(settingsStore: SettingsStore, secureStorage: SecureStorage) : this(
        settingsStore = settingsStore,
        secureStorage = secureStorage,
        p2pkStore = SettingsP2PKMetadataStore(settingsStore),
    )

    companion object {
        /** The relay list a fresh install starts with, and what "reset" restores. */
        val defaultNostrRelays: List<String> get() = SettingsStore.defaultNostrRelays

        val supportedFiatCurrencies = listOf(
            "USD", "EUR", "AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "GBP",
            "HKD", "HUF", "ILS", "INR", "JPY", "KRW", "MXN", "NZD", "NOK", "PLN",
            "RUB", "SEK", "SGD", "THB", "TRY", "ZAR",
        )

        fun normalizeP2PKPublicKeyForSend(pubkey: String?): String? {
            val trimmed = pubkey?.trim()?.lowercase().orEmpty()
            if (trimmed.isEmpty()) return null

            val isHex = trimmed.all { it in '0'..'9' || it in 'a'..'f' }
            if (trimmed.length == 64 && isHex) {
                return "02$trimmed"
            }

            require(
                trimmed.length == 66 &&
                    (trimmed.startsWith("02") || trimmed.startsWith("03")) &&
                    isHex,
            ) {
                "Invalid P2PK pubkey. Use a 66-character hex key with 02/03 prefix."
            }
            return trimmed
        }

        fun normalizeP2PKPublicKeyForComparison(pubkey: String): String {
            val trimmed = pubkey.trim().lowercase()
            return if (trimmed.length == 66 && (trimmed.startsWith("02") || trimmed.startsWith("03"))) {
                trimmed.drop(2)
            } else {
                trimmed
            }
        }
    }

    init {
        recoverInterruptedP2PKRemovals()
        migrateLegacyStoredSecrets()
    }

    private val mutableState = MutableStateFlow(loadState())
    val state: StateFlow<SettingsState> = mutableState.asStateFlow()

    override val useWebsockets: Boolean get() = state.value.useWebsockets
    override val nostrRelays: List<String> get() = state.value.nostrRelays

    // Wired by AppContainer (same pattern as NPCService.quoteClaimHandler).
    var sentryService: SentryService? = null
    var claimEligibleHeldPayments: (() -> Unit)? = null

    // Wired by AppContainer: the seed-derived primary P2PK key (iOS
    // primaryP2PKPublicKey/PrivateKeyHex). Null until the wallet seed is loaded.
    var primaryP2PKKeyProvider: (() -> PrimaryP2PKKey?)? = null

    private fun primaryP2PKKey(): PrimaryP2PKKey? = primaryP2PKKeyProvider?.invoke()

    /** The seed-derived primary P2PK key, if the wallet seed is loaded (iOS primaryP2PKPublicKey). */
    fun primaryP2PKKeyInfo(): PrimaryP2PKKey? = primaryP2PKKey()

    /** Stored private key hex for a device key — used only for nsec backup/reveal. */
    fun p2pkPrivateKeyHex(id: String): String? {
        val key = p2pkStore.keys.firstOrNull { it.id == id } ?: return null
        return availableP2PKPrivateKey(key)
    }

    /** Rename a device key (iOS setP2PKKeyNickname). */
    fun setP2PKKeyNickname(id: String, label: String) {
        val updated = p2pkStore.keys.map {
            if (it.id == id) it.copy(label = label.trim()) else it
        }
        persistP2PKMetadata(updated)
    }

    fun setUseBitcoinSymbol(value: Boolean) = update { settingsStore.useBitcoinSymbol = value }
    fun setShowFiatBalance(value: Boolean) = update {
        settingsStore.showFiatBalance = value
        settingsStore.priceEnabled = value
    }
    fun setUseWebsockets(value: Boolean) = update { settingsStore.useWebsockets = value }
    fun setCheckIncomingInvoices(value: Boolean) = update { settingsStore.checkIncomingInvoices = value }
    // TODO(runtime-parity): Keep this storage-only until Swift wires matching startup processors.
    fun setCheckPendingOnStartup(value: Boolean) = update { settingsStore.checkPendingOnStartup = value }
    fun setPeriodicallyCheckIncomingInvoices(value: Boolean) = update {
        settingsStore.periodicallyCheckIncomingInvoices = value
    }
    fun setCheckSentTokens(value: Boolean) = update { settingsStore.checkSentTokens = value }
    fun setAutoPasteEcashReceive(value: Boolean) = update { settingsStore.autoPasteEcashReceive = value }
    fun setEnablePaymentRequests(value: Boolean) = update { settingsStore.enablePaymentRequests = value }
    fun setReceivePaymentRequestsAutomatically(value: Boolean) {
        val previous = state.value.receivePaymentRequestsAutomatically
        update {
            settingsStore.receivePaymentRequestsAutomatically = value
        }
        if (value && !previous) {
            claimEligibleHeldPayments?.invoke()
        }
    }
    fun setShowP2PKButtonInDrawer(value: Boolean) = update { settingsStore.showP2PKButtonInDrawer = value }
    // Mirrors Swift SettingsManager.sentryEnabled didSet: persist, then start/stop the SDK on change.
    fun setSentryEnabled(value: Boolean) {
        val previous = settingsStore.sentryEnabled
        update { settingsStore.sentryEnabled = value }
        if (value == previous) return
        if (value) sentryService?.initialize() else sentryService?.shutdown()
    }
    fun setAppLockEnabled(value: Boolean) = update { settingsStore.appLockEnabled = value }
    fun setBitcoinPriceCurrency(value: String) = update {
        val normalized = value.uppercase()
        if (normalized in supportedFiatCurrencies) {
            settingsStore.bitcoinPriceCurrency = normalized
            settingsStore.priceCurrencyCode = normalized
        }
    }
    fun setAmountDisplayPrimary(value: String) = update {
        settingsStore.amountDisplayPrimary = AmountDisplayPrimary.fromRaw(value).rawValue
    }
    /** Shared Home balance and history-row ordering; payment entry stays independent. */
    fun setHomeBalancePrimary(value: String) = update {
        settingsStore.homeBalancePrimary = AmountDisplayPrimary.fromRaw(value).rawValue
    }
    fun setHomeBalanceUnit(unit: String) = update { settingsStore.homeBalanceUnit = unit }

    /**
     * Adds a relay, reporting why it was rejected instead of silently no-opping.
     * Null means the input was blank and nothing happened.
     */
    fun addRelay(relay: String): RelayAddResult? {
        val result = validateNostrRelay(relay, settingsStore.nostrRelays)
        if (result is RelayAddResult.Added) {
            update { settingsStore.nostrRelays = settingsStore.nostrRelays + result.relay }
        }
        return result
    }

    fun removeRelay(relay: String) = update {
        settingsStore.nostrRelays = settingsStore.nostrRelays.filterNot { it == relay }
    }

    fun resetNostrRelaysToDefault() = update {
        settingsStore.resetNostrRelaysToDefault()
    }

    fun setNostrMintBackupEnabled(value: Boolean) = update {
        settingsStore.nostrMintBackupEnabled = value
    }

    fun importP2PKPublicKey(publicKey: String, label: String = "P2PK key") {
        val normalized = normalizeP2PKForComparison(publicKey)
        val key = P2PKKeyInfo(
            id = UUID.randomUUID().toString(),
            publicKey = normalized,
            label = label,
        )
        persistP2PKMetadata(p2pkStore.keys + key)
    }

    fun generateP2PKKey(): P2PKKeyInfo = addP2PKPrivateKey(generateRandomPrivateKey())

    fun importP2PKNsec(nsec: String) {
        val trimmed = nsec.trim()
        require(trimmed.startsWith("nsec1", ignoreCase = true)) { "Invalid nsec format." }
        val privateKey = Bech32.decode("nsec", trimmed)
        require(privateKey.size == 32) { "Invalid nsec format." }
        addP2PKPrivateKey(privateKey)
    }

    fun removeP2PKKey(id: String) {
        val key = p2pkStore.keys.firstOrNull { it.id == id } ?: return
        val privateKey = availableP2PKPrivateKey(key)
        val primaryStorageKey = secureP2PKPrivateKey(id)
        val fallbackStorageKey = secureP2PKRemovalFallback(id)
        val previousPendingIds = p2pkStore.pendingDeletionIds
        val pendingIdsAfterCleanup = previousPendingIds - id
        val pendingIds = previousPendingIds + id

        try {
            p2pkStore.pendingDeletionIds = pendingIds
        } catch (error: Throwable) {
            throw P2PKStorageException("Could not prepare the key removal.", error)
        }

        try {
            if (privateKey != null) {
                secureStorage.saveString(fallbackStorageKey, privateKey)
            }
            secureStorage.delete(primaryStorageKey)
        } catch (error: Throwable) {
            val fallbackWasRemoved = runCatching { secureStorage.delete(fallbackStorageKey) }.isSuccess
            if (fallbackWasRemoved) {
                runCatching { p2pkStore.pendingDeletionIds = pendingIdsAfterCleanup }
            }
            throw P2PKStorageException("Could not remove the encrypted key.", error)
        }

        val previousLegacySecret = pendingLegacyP2PKSecrets.remove(id)
        try {
            p2pkStore.saveKeys(
                keys = p2pkStore.keys.filterNot { it.id == id },
                preservingLegacySecrets = pendingLegacyP2PKSecrets,
            )
            mutableState.value = loadState()
        } catch (error: Throwable) {
            if (previousLegacySecret != null) pendingLegacyP2PKSecrets[id] = previousLegacySecret
            val primaryWasRestored = privateKey == null || runCatching {
                secureStorage.saveString(primaryStorageKey, privateKey)
            }.isSuccess
            if (primaryWasRestored) {
                val fallbackWasRemoved = runCatching { secureStorage.delete(fallbackStorageKey) }.isSuccess
                if (fallbackWasRemoved) {
                    runCatching { p2pkStore.pendingDeletionIds = pendingIdsAfterCleanup }
                }
            }
            throw P2PKStorageException("Could not save the key removal.", error)
        }

        val fallbackWasRemoved = runCatching { secureStorage.delete(fallbackStorageKey) }.isSuccess
        if (fallbackWasRemoved) {
            runCatching { p2pkStore.pendingDeletionIds = pendingIdsAfterCleanup }
        }
    }

    fun p2pkSigningKeysFor(pubkeys: List<String>): List<String> {
        if (pubkeys.isEmpty()) return emptyList()
        val tokenPubkeys = pubkeys.map(::normalizeP2PKForComparison).toSet()
        val primary = primaryP2PKKey()
        val primaryMatches = primary != null &&
            normalizeP2PKForComparison(primary.publicKey) in tokenPubkeys
        val availableKeys = p2pkStore.keys
        val matching = availableKeys.filter { normalizeP2PKForComparison(it.publicKey) in tokenPubkeys }
        require(primaryMatches || matching.isNotEmpty()) {
            "This token is locked to a P2PK key that is not stored on this device."
        }
        require(primaryMatches || matching.any { availableP2PKPrivateKey(it) != null }) {
            "Missing encrypted P2PK private key."
        }
        // Pass the full signing set (primary + device keys) and let CDK pick,
        // mirroring iOS allP2PKSigningKeyHexes().
        return allP2PKSigningKeyHexes()
    }

    /** Primary seed-derived key + every device key with a stored secret, deduped (iOS parity). */
    fun allP2PKSigningKeyHexes(): List<String> {
        val stored = p2pkStore.keys.mapNotNull(::availableP2PKPrivateKey)
        return (listOfNotNull(primaryP2PKKey()?.privateKeyHex) + stored).distinct()
    }

    fun markP2PKKeyUsed(publicKey: String) {
        val comparable = normalizeP2PKForComparison(publicKey)
        val updated = p2pkStore.keys.map {
            if (availableP2PKPrivateKey(it) != null &&
                normalizeP2PKForComparison(it.publicKey) == comparable
            ) {
                it.copy(used = true, usedCount = it.usedCount + 1)
            } else {
                it
            }
        }
        persistP2PKMetadata(updated)
    }

    fun resetWalletScopedData() = update {
        deleteWalletScopedSecrets(snapshotWalletScopedData(), deleteNostrPrivateKey = true)
        pendingLegacyP2PKSecrets.clear()
        settingsStore.clearWalletScopedData()
    }

    var onboardingCompleted: Boolean
        get() = settingsStore.onboardingCompleted
        set(value) {
            settingsStore.onboardingCompleted = value
        }

    val hasOnboardingCompletionMarker: Boolean
        get() = settingsStore.hasOnboardingCompletionMarker

    internal fun snapshotWalletScopedData(): SettingsWalletScopedSnapshot =
        SettingsWalletScopedSnapshot(
            preferences = settingsStore.snapshotWalletScopedData(),
            p2pkKeys = p2pkStore.keys,
            pendingP2PKDeletionIds = p2pkStore.pendingDeletionIds,
        )

    internal fun prepareForWalletReplacement() = update {
        pendingLegacyP2PKSecrets.clear()
        settingsStore.clearWalletScopedData()
        settingsStore.nostrSignerType = NostrSignerType.Seed.rawValue
    }

    internal fun restoreWalletScopedData(snapshot: SettingsWalletScopedSnapshot) {
        settingsStore.restoreWalletScopedData(snapshot.preferences)
        mutableState.value = loadState()
    }

    internal fun deleteWalletScopedSecrets(
        snapshot: SettingsWalletScopedSnapshot,
        deleteNostrPrivateKey: Boolean,
    ) {
        val p2pkIds = snapshot.p2pkKeys.mapTo(mutableSetOf()) { it.id }
            .apply { addAll(snapshot.pendingP2PKDeletionIds) }
        p2pkIds.forEach {
            secureStorage.delete(secureP2PKPrivateKey(it))
            secureStorage.delete(secureP2PKRemovalFallback(it))
        }
        if (deleteNostrPrivateKey) secureStorage.delete(StorageKeys.secureNostrPrivateKey)
    }

    private fun migrateLegacyStoredSecrets() {
        val migration = LegacySettingsSecretMigrator.migrate(
            p2pkRecords = settingsStore.loadP2PKKeysWithLegacySecrets(),
            loadSecret = secureStorage::loadString,
            saveSecret = secureStorage::saveString,
            isUsableSecret = ::isUsableP2PKSecret,
        )
        pendingLegacyP2PKSecrets.clear()
        pendingLegacyP2PKSecrets.putAll(migration.pendingLegacySecrets)
        migration.p2pkKeysToPersist?.let { keys ->
            runCatching {
                p2pkStore.saveKeys(keys, pendingLegacyP2PKSecrets)
            }.onFailure {
                AppLogger.security.error("Failed to sanitize legacy P2PK metadata", it)
            }
        }
    }

    private fun update(block: () -> Unit) {
        block()
        mutableState.value = loadState()
    }

    private fun loadState(): SettingsState = SettingsState(
        useBitcoinSymbol = settingsStore.useBitcoinSymbol,
        showFiatBalance = settingsStore.showFiatBalance,
        bitcoinPriceCurrency = settingsStore.bitcoinPriceCurrency,
        checkPendingOnStartup = settingsStore.checkPendingOnStartup,
        checkSentTokens = settingsStore.checkSentTokens,
        autoPasteEcashReceive = settingsStore.autoPasteEcashReceive,
        useWebsockets = settingsStore.useWebsockets,
        enablePaymentRequests = settingsStore.enablePaymentRequests,
        receivePaymentRequestsAutomatically = settingsStore.receivePaymentRequestsAutomatically,
        showP2PKButtonInDrawer = settingsStore.showP2PKButtonInDrawer,
        amountDisplayPrimary = AmountDisplayPrimary.fromRaw(settingsStore.amountDisplayPrimary).rawValue,
        homeBalancePrimary = AmountDisplayPrimary.fromRaw(settingsStore.homeBalancePrimary).rawValue,
        homeBalanceUnit = settingsStore.homeBalanceUnit,
        sentryEnabled = settingsStore.sentryEnabled,
        appLockEnabled = settingsStore.appLockEnabled,
        checkIncomingInvoices = settingsStore.checkIncomingInvoices,
        periodicallyCheckIncomingInvoices = settingsStore.periodicallyCheckIncomingInvoices,
        nostrSignerType = settingsStore.nostrSignerType,
        nostrRelays = settingsStore.nostrRelays,
        nostrMintBackupEnabled = settingsStore.nostrMintBackupEnabled,
        p2pkKeys = p2pkStore.keys,
        p2pkUnavailableKeyIds = p2pkStore.keys
            .filter { availableP2PKPrivateKey(it) == null }
            .mapTo(mutableSetOf()) { it.id },
    )

    private fun normalizeP2PKForComparison(pubkey: String): String {
        return normalizeP2PKPublicKeyForComparison(pubkey)
    }

    private fun addP2PKPrivateKey(privateKey: ByteArray): P2PKKeyInfo {
        require(privateKey.size == 32) { "Invalid nsec format." }
        val privateKeyHex = privateKey.toHex()
        val publicKey = "02${NostrService.publicKeyHex(privateKeyHex)}"
        val comparable = normalizeP2PKForComparison(publicKey)
        val existingKey = p2pkStore.keys.firstOrNull {
            normalizeP2PKForComparison(it.publicKey) == comparable
        }
        require(existingKey == null || availableP2PKPrivateKey(existingKey) == null) {
            "Key already exists."
        }
        val key = existingKey ?: P2PKKeyInfo(
            id = UUID.randomUUID().toString(),
            publicKey = publicKey,
            label = "P2PK key",
        )
        val isRepair = existingKey != null

        try {
            secureStorage.saveString(secureP2PKPrivateKey(key.id), privateKeyHex)
        } catch (error: Throwable) {
            throw P2PKStorageException("Could not save the encrypted key.", error)
        }

        try {
            if (isRepair) {
                persistP2PKMetadata(p2pkStore.keys)
            } else {
                persistP2PKMetadata(p2pkStore.keys + key)
            }
        } catch (error: Throwable) {
            if (!isRepair) {
                runCatching { secureStorage.delete(secureP2PKPrivateKey(key.id)) }
            }
            throw P2PKStorageException("Could not save the key metadata.", error)
        }
        return key
    }

    private fun persistP2PKMetadata(keys: List<P2PKKeyInfo>) {
        retryPendingLegacyP2PKSecrets(keys)
        p2pkStore.saveKeys(keys, pendingLegacyP2PKSecrets)
        mutableState.value = loadState()
    }

    private fun retryPendingLegacyP2PKSecrets(keys: List<P2PKKeyInfo>) {
        val metadataById = keys.associateBy { it.id }
        val iterator = pendingLegacyP2PKSecrets.iterator()
        while (iterator.hasNext()) {
            val (id, secret) = iterator.next()
            val metadata = metadataById[id]
            if (metadata == null || !isUsableP2PKSecret(metadata, secret)) {
                iterator.remove()
                continue
            }
            if (runCatching { secureStorage.saveString(secureP2PKPrivateKey(id), secret) }.isSuccess) {
                iterator.remove()
            }
        }
    }

    private fun availableP2PKPrivateKey(key: P2PKKeyInfo): String? {
        val secureSecret = runCatching {
            secureStorage.loadString(secureP2PKPrivateKey(key.id))
        }.getOrNull()
        if (secureSecret != null && isUsableP2PKSecret(key, secureSecret)) return secureSecret

        pendingLegacyP2PKSecrets[key.id]?.let { legacySecret ->
            if (isUsableP2PKSecret(key, legacySecret)) return legacySecret
        }

        if (key.id in runCatching { p2pkStore.pendingDeletionIds }.getOrDefault(emptySet())) {
            val fallbackSecret = runCatching {
                secureStorage.loadString(secureP2PKRemovalFallback(key.id))
            }.getOrNull()
            if (fallbackSecret != null && isUsableP2PKSecret(key, fallbackSecret)) return fallbackSecret
        }
        return null
    }

    private fun isUsableP2PKSecret(key: P2PKKeyInfo, secret: String): Boolean {
        val normalizedSecret = secret.trim().lowercase()
        if (normalizedSecret.length != 64 || normalizedSecret.any { it !in '0'..'9' && it !in 'a'..'f' }) {
            return false
        }
        val derivedPublicKey = runCatching {
            "02${NostrService.publicKeyHex(normalizedSecret)}"
        }.getOrNull() ?: return false
        return normalizeP2PKForComparison(derivedPublicKey) ==
            normalizeP2PKForComparison(key.publicKey)
    }

    private fun recoverInterruptedP2PKRemovals() {
        val pendingIds = runCatching { p2pkStore.pendingDeletionIds }.getOrDefault(emptySet())
        if (pendingIds.isEmpty()) return
        val metadataById = p2pkStore.keys.associateBy { it.id }
        val unresolvedIds = pendingIds.toMutableSet()

        pendingIds.forEach { id ->
            val key = metadataById[id]
            val primaryStorageKey = secureP2PKPrivateKey(id)
            val fallbackStorageKey = secureP2PKRemovalFallback(id)
            if (key == null) {
                val primaryRemoved = runCatching { secureStorage.delete(primaryStorageKey) }.isSuccess
                val fallbackRemoved = runCatching { secureStorage.delete(fallbackStorageKey) }.isSuccess
                if (primaryRemoved && fallbackRemoved) unresolvedIds.remove(id)
                return@forEach
            }

            val primarySecret = runCatching { secureStorage.loadString(primaryStorageKey) }.getOrNull()
            val primaryIsUsable = primarySecret != null && isUsableP2PKSecret(key, primarySecret)
            val fallbackSecret = runCatching { secureStorage.loadString(fallbackStorageKey) }.getOrNull()
            val fallbackIsUsable = fallbackSecret != null && isUsableP2PKSecret(key, fallbackSecret)
            val restored = primaryIsUsable || (fallbackIsUsable && runCatching {
                secureStorage.saveString(primaryStorageKey, fallbackSecret)
            }.isSuccess)
            if (restored && runCatching { secureStorage.delete(fallbackStorageKey) }.isSuccess) {
                unresolvedIds.remove(id)
            }
        }

        if (unresolvedIds != pendingIds) {
            runCatching { p2pkStore.pendingDeletionIds = unresolvedIds }
        }
    }

    private fun generateRandomPrivateKey(): ByteArray {
        repeat(10) {
            val key = ByteArray(32).also(secureRandom::nextBytes)
            if (runCatching { NostrService.schnorrSign(ByteArray(32), key) }.isSuccess) {
                return key
            }
        }
        error("Failed to generate secure key.")
    }

    private fun secureP2PKPrivateKey(id: String): String =
        LegacySettingsSecretMigrator.secureP2PKPrivateKey(id)

    private fun secureP2PKRemovalFallback(id: String): String =
        "${secureP2PKPrivateKey(id)}.removalFallback"

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
}
