package com.cashu.me.Core

import java.security.SecureRandom
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import com.cashu.me.Core.Protocols.SecureStorage
import com.cashu.me.Core.Protocols.StorageKeys
import com.cashu.me.Models.P2PKKeyInfo

data class SettingsState(
    val useBitcoinSymbol: Boolean = true,
    val showFiatBalance: Boolean = false,
    val bitcoinPriceCurrency: String = "USD",
    val checkPendingOnStartup: Boolean = true,
    val checkSentTokens: Boolean = true,
    val autoPasteEcashReceive: Boolean = true,
    val useWebsockets: Boolean = true,
    val enablePaymentRequests: Boolean = false,
    val receivePaymentRequestsAutomatically: Boolean = false,
    val showP2PKButtonInDrawer: Boolean = false,
    val amountDisplayPrimary: String = "fiat",
    val homeBalanceUnit: String = "sat",
    val sentryEnabled: Boolean = false,
    val appLockEnabled: Boolean = false,
    val checkIncomingInvoices: Boolean = true,
    val periodicallyCheckIncomingInvoices: Boolean = true,
    val nostrSignerType: String = "SEED",
    val nostrRelays: List<String> = emptyList(),
    val nostrMintBackupEnabled: Boolean = true,
    val p2pkKeys: List<P2PKKeyInfo> = emptyList(),
)

internal data class LegacySettingsSecretMigration(
    val p2pkKeysToPersist: List<P2PKKeyInfo>?,
)

/** The wallet's seed-derived P2PK identity: compressed 02-prefixed pubkey + private hex. */
data class PrimaryP2PKKey(
    val publicKey: String,
    val privateKeyHex: String,
)

internal data class SettingsWalletScopedSnapshot(
    val preferences: PreferenceSnapshot,
    val p2pkKeys: List<P2PKKeyInfo>,
)

internal object LegacySettingsSecretMigrator {
    fun migrate(
        p2pkRecords: List<LegacyP2PKKeyRecord>,
        loadSecret: (String) -> String?,
        saveSecret: (String, String) -> Unit,
    ): LegacySettingsSecretMigration {
        var shouldPersistP2PK = false
        val p2pkMetadata = p2pkRecords.map { record ->
            migrateSecret(
                key = secureP2PKPrivateKey(record.metadata.id),
                legacyValue = record.privateKey,
                loadSecret = loadSecret,
                saveSecret = saveSecret,
            )
            shouldPersistP2PK = shouldPersistP2PK || record.shouldRewriteMetadata || record.hasLegacySecret
            record.metadata
        }

        return LegacySettingsSecretMigration(
            p2pkKeysToPersist = p2pkMetadata.takeIf { shouldPersistP2PK },
        )
    }

    private fun migrateSecret(
        key: String,
        legacyValue: String,
        loadSecret: (String) -> String?,
        saveSecret: (String, String) -> Unit,
    ) {
        if (legacyValue.isBlank() || loadSecret(key) != null) return
        saveSecret(key, legacyValue)
    }

    fun secureP2PKPrivateKey(id: String): String = "settings.p2pk.$id.privateKey"
}

class SettingsManager(
    private val settingsStore: SettingsStore,
    private val secureStorage: SecureStorage,
) {
    private val secureRandom = SecureRandom()

    companion object {
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
        migrateLegacyStoredSecrets()
    }

    private val mutableState = MutableStateFlow(loadState())
    val state: StateFlow<SettingsState> = mutableState.asStateFlow()

    // Wired by AppContainer (same pattern as NPCService.quoteClaimHandler).
    var sentryService: SentryService? = null

    // Wired by AppContainer: the seed-derived primary P2PK key (iOS
    // primaryP2PKPublicKey/PrivateKeyHex). Null until the wallet seed is loaded.
    var primaryP2PKKeyProvider: (() -> PrimaryP2PKKey?)? = null

    private fun primaryP2PKKey(): PrimaryP2PKKey? = primaryP2PKKeyProvider?.invoke()

    /** The seed-derived primary P2PK key, if the wallet seed is loaded (iOS primaryP2PKPublicKey). */
    fun primaryP2PKKeyInfo(): PrimaryP2PKKey? = primaryP2PKKey()

    /** Stored private key hex for a device key — used only for nsec backup/reveal. */
    fun p2pkPrivateKeyHex(id: String): String? =
        secureStorage.loadString(secureP2PKPrivateKey(id))

    /** Rename a device key (iOS setP2PKKeyNickname). */
    fun setP2PKKeyNickname(id: String, label: String) = update {
        settingsStore.p2pkKeys = settingsStore.p2pkKeys.map {
            if (it.id == id) it.copy(label = label.trim()) else it
        }
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
    fun setReceivePaymentRequestsAutomatically(value: Boolean) = update {
        settingsStore.receivePaymentRequestsAutomatically = value
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
    fun setHomeBalanceUnit(unit: String) = update { settingsStore.homeBalanceUnit = unit }

    fun addRelay(relay: String) = update {
        val normalized = relay.trim()
        if (normalized.isNotEmpty() && normalized !in settingsStore.nostrRelays) {
            settingsStore.nostrRelays = settingsStore.nostrRelays + normalized
        }
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
        update { settingsStore.p2pkKeys = settingsStore.p2pkKeys + key }
    }

    fun generateP2PKKey(): Boolean =
        runCatching {
            val privateKey = generateRandomPrivateKey()
            addP2PKPrivateKey(privateKey)
        }.isSuccess

    fun importP2PKNsec(nsec: String) {
        val trimmed = nsec.trim()
        require(trimmed.startsWith("nsec1", ignoreCase = true)) { "Invalid nsec format." }
        val privateKey = Bech32.decode("nsec", trimmed)
        require(privateKey.size == 32) { "Invalid nsec format." }
        addP2PKPrivateKey(privateKey)
    }

    fun removeP2PKKey(id: String) = update {
        secureStorage.delete(secureP2PKPrivateKey(id))
        settingsStore.p2pkKeys = settingsStore.p2pkKeys.filterNot { it.id == id }
    }

    fun p2pkSigningKeysFor(pubkeys: List<String>): List<String> {
        if (pubkeys.isEmpty()) return emptyList()
        val tokenPubkeys = pubkeys.map(::normalizeP2PKForComparison).toSet()
        val primary = primaryP2PKKey()
        val primaryMatches = primary != null &&
            normalizeP2PKForComparison(primary.publicKey) in tokenPubkeys
        val availableKeys = settingsStore.p2pkKeys
        val matching = availableKeys.filter { normalizeP2PKForComparison(it.publicKey) in tokenPubkeys }
        require(primaryMatches || matching.isNotEmpty()) {
            "This token is locked to a P2PK key that is not stored on this device."
        }
        require(primaryMatches || matching.any { secureStorage.loadString(secureP2PKPrivateKey(it.id)) != null }) {
            "Missing encrypted P2PK private key."
        }
        // Pass the full signing set (primary + device keys) and let CDK pick,
        // mirroring iOS allP2PKSigningKeyHexes().
        return allP2PKSigningKeyHexes()
    }

    /** Primary seed-derived key + every device key with a stored secret, deduped (iOS parity). */
    fun allP2PKSigningKeyHexes(): List<String> {
        val stored = settingsStore.p2pkKeys.mapNotNull {
            secureStorage.loadString(secureP2PKPrivateKey(it.id))
        }
        return (listOfNotNull(primaryP2PKKey()?.privateKeyHex) + stored).distinct()
    }

    fun markP2PKKeyUsed(publicKey: String) = update {
        val comparable = normalizeP2PKForComparison(publicKey)
        settingsStore.p2pkKeys = settingsStore.p2pkKeys.map {
            if (normalizeP2PKForComparison(it.publicKey) == comparable) {
                it.copy(used = true, usedCount = it.usedCount + 1)
            } else {
                it
            }
        }
    }

    fun resetWalletScopedData() = update {
        deleteWalletScopedSecrets(snapshotWalletScopedData(), deleteNostrPrivateKey = true)
        settingsStore.clearWalletScopedData()
    }

    internal fun snapshotWalletScopedData(): SettingsWalletScopedSnapshot =
        SettingsWalletScopedSnapshot(
            preferences = settingsStore.snapshotWalletScopedData(),
            p2pkKeys = settingsStore.p2pkKeys,
        )

    internal fun prepareForWalletReplacement() = update {
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
        snapshot.p2pkKeys.forEach { secureStorage.delete(secureP2PKPrivateKey(it.id)) }
        if (deleteNostrPrivateKey) secureStorage.delete(StorageKeys.secureNostrPrivateKey)
    }

    private fun migrateLegacyStoredSecrets() {
        val migration = LegacySettingsSecretMigrator.migrate(
            p2pkRecords = settingsStore.loadP2PKKeysWithLegacySecrets(),
            loadSecret = secureStorage::loadString,
            saveSecret = secureStorage::saveString,
        )
        migration.p2pkKeysToPersist?.let { settingsStore.p2pkKeys = it }
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
        homeBalanceUnit = settingsStore.homeBalanceUnit,
        sentryEnabled = settingsStore.sentryEnabled,
        appLockEnabled = settingsStore.appLockEnabled,
        checkIncomingInvoices = settingsStore.checkIncomingInvoices,
        periodicallyCheckIncomingInvoices = settingsStore.periodicallyCheckIncomingInvoices,
        nostrSignerType = settingsStore.nostrSignerType,
        nostrRelays = settingsStore.nostrRelays,
        nostrMintBackupEnabled = settingsStore.nostrMintBackupEnabled,
        p2pkKeys = settingsStore.p2pkKeys,
    )

    private fun normalizeP2PKForComparison(pubkey: String): String {
        return normalizeP2PKPublicKeyForComparison(pubkey)
    }

    private fun addP2PKPrivateKey(privateKey: ByteArray) {
        require(privateKey.size == 32) { "Invalid nsec format." }
        val privateKeyHex = privateKey.toHex()
        val publicKey = "02${NostrService.publicKeyHex(privateKeyHex)}"
        val comparable = normalizeP2PKForComparison(publicKey)
        require(settingsStore.p2pkKeys.none { normalizeP2PKForComparison(it.publicKey) == comparable }) {
            "Key already exists."
        }
        val id = UUID.randomUUID().toString()
        val key = P2PKKeyInfo(
            id = id,
            publicKey = publicKey,
            label = "P2PK key",
        )
        secureStorage.saveString(secureP2PKPrivateKey(id), privateKeyHex)
        update { settingsStore.p2pkKeys = settingsStore.p2pkKeys + key }
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

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
}
