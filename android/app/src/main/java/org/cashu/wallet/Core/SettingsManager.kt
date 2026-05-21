package org.cashu.wallet.Core

import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.security.SecureRandom
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.cashu.wallet.Core.Protocols.SecureStorage
import org.cashu.wallet.Core.Protocols.StorageKeys
import org.cashu.wallet.Models.NwcConnection
import org.cashu.wallet.Models.P2PKKeyInfo

data class SettingsState(
    val useBitcoinSymbol: Boolean = false,
    val showFiatBalance: Boolean = false,
    val bitcoinPriceCurrency: String = "USD",
    val checkPendingOnStartup: Boolean = true,
    val checkSentTokens: Boolean = true,
    val autoPasteEcashReceive: Boolean = true,
    val useWebsockets: Boolean = true,
    val enablePaymentRequests: Boolean = false,
    val receivePaymentRequestsAutomatically: Boolean = false,
    val enableNWC: Boolean = false,
    val showP2PKButtonInDrawer: Boolean = false,
    val amountDisplayPrimary: String = "fiat",
    val checkIncomingInvoices: Boolean = true,
    val periodicallyCheckIncomingInvoices: Boolean = true,
    val nostrSignerType: String = "SEED",
    val nostrRelays: List<String> = emptyList(),
    val nwcConnections: List<NwcConnection> = emptyList(),
    val p2pkKeys: List<P2PKKeyInfo> = emptyList(),
)

internal data class LegacySettingsSecretMigration(
    val nwcConnectionsToPersist: List<NwcConnection>?,
    val p2pkKeysToPersist: List<P2PKKeyInfo>?,
)

internal data class SettingsWalletScopedSnapshot(
    val preferences: PreferenceSnapshot,
    val nwcConnections: List<NwcConnection>,
    val p2pkKeys: List<P2PKKeyInfo>,
)

internal object LegacySettingsSecretMigrator {
    fun migrate(
        nwcRecords: List<LegacyNwcConnectionRecord>,
        p2pkRecords: List<LegacyP2PKKeyRecord>,
        loadSecret: (String) -> String?,
        saveSecret: (String, String) -> Unit,
    ): LegacySettingsSecretMigration {
        var shouldPersistNwc = false
        val nwcMetadata = nwcRecords.map { record ->
            migrateSecret(
                key = secureNWCWalletPrivateKey(record.metadata.id),
                legacyValue = record.walletPrivateKey,
                loadSecret = loadSecret,
                saveSecret = saveSecret,
            )
            migrateSecret(
                key = secureNWCConnectionSecret(record.metadata.id),
                legacyValue = record.connectionSecret,
                loadSecret = loadSecret,
                saveSecret = saveSecret,
            )
            shouldPersistNwc = shouldPersistNwc || record.shouldRewriteMetadata || record.hasLegacySecret
            record.metadata
        }

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
            nwcConnectionsToPersist = nwcMetadata.takeIf { shouldPersistNwc },
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

    fun secureNWCWalletPrivateKey(id: String): String = "settings.nwc.$id.walletPrivateKey"
    fun secureNWCConnectionSecret(id: String): String = "settings.nwc.$id.connectionSecret"
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
    // TODO(runtime-parity): Payment request processing is not started from these Swift parity toggles yet.
    fun setEnablePaymentRequests(value: Boolean) = update { settingsStore.enablePaymentRequests = value }
    fun setReceivePaymentRequestsAutomatically(value: Boolean) = update {
        settingsStore.receivePaymentRequestsAutomatically = value
    }
    // TODO(runtime-parity): Enabling NWC creates persisted connection metadata only, not a runtime listener.
    fun setEnableNWC(value: Boolean) {
        update { settingsStore.enableNWC = value }
        if (value && settingsStore.nwcConnections.isEmpty()) {
            createNwcConnection(name = "Wallet connection", relay = "", allowanceSats = defaultNWCAllowance)
        }
    }
    fun setShowP2PKButtonInDrawer(value: Boolean) = update { settingsStore.showP2PKButtonInDrawer = value }
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

    fun createNwcConnection(name: String, relay: String, allowanceSats: Long?): NwcConnection {
        settingsStore.nwcConnections.firstOrNull()?.let { return it }
        val id = UUID.randomUUID().toString()
        val walletKeypair = generateKeypairHex()
        val connectionKeypair = generateKeypairHex()
        secureStorage.saveString(secureNWCWalletPrivateKey(id), walletKeypair.first)
        secureStorage.saveString(secureNWCConnectionSecret(id), connectionKeypair.first)
        val connection = NwcConnection(
            id = id,
            name = name.ifBlank { "Wallet connection" },
            walletPublicKey = walletKeypair.second,
            connectionPublicKey = connectionKeypair.second,
            allowanceSats = allowanceSats ?: defaultNWCAllowance,
        )
        update { settingsStore.nwcConnections = settingsStore.nwcConnections + connection }
        return connection
    }

    fun removeNwcConnection(id: String) = update {
        secureStorage.delete(secureNWCWalletPrivateKey(id))
        secureStorage.delete(secureNWCConnectionSecret(id))
        settingsStore.nwcConnections = settingsStore.nwcConnections.filterNot { it.id == id }
    }

    fun updateNwcAllowance(id: String, allowanceSats: Long) = update {
        settingsStore.nwcConnections = settingsStore.nwcConnections.map {
            if (it.id == id) it.copy(allowanceSats = allowanceSats.coerceAtLeast(0)) else it
        }
    }

    fun nwcConnectionString(connection: NwcConnection): String {
        val secret = secureStorage.loadString(secureNWCConnectionSecret(connection.id)).orEmpty()
        val relayParams = settingsStore.nostrRelays.joinToString("&") { relay ->
            "relay=${URLEncoder.encode(relay, StandardCharsets.UTF_8.toString())}"
        }
        val secretParam = "secret=$secret"
        val query = listOf(relayParams.takeIf { it.isNotBlank() }, secretParam).filterNotNull().joinToString("&")
        return "nostr+walletconnect://${connection.walletPublicKey}?$query"
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
        val availableKeys = settingsStore.p2pkKeys
        val matching = availableKeys.filter { normalizeP2PKForComparison(it.publicKey) in tokenPubkeys }
        require(matching.isNotEmpty()) {
            "This token is locked to a P2PK key that is not stored on this device."
        }
        require(matching.any { secureStorage.loadString(secureP2PKPrivateKey(it.id)) != null }) {
            "Missing encrypted P2PK private key."
        }
        return availableKeys.mapNotNull { secureStorage.loadString(secureP2PKPrivateKey(it.id)) }
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
            nwcConnections = settingsStore.nwcConnections,
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
        snapshot.nwcConnections.forEach {
            secureStorage.delete(secureNWCWalletPrivateKey(it.id))
            secureStorage.delete(secureNWCConnectionSecret(it.id))
        }
        snapshot.p2pkKeys.forEach { secureStorage.delete(secureP2PKPrivateKey(it.id)) }
        if (deleteNostrPrivateKey) secureStorage.delete(StorageKeys.secureNostrPrivateKey)
    }

    private fun migrateLegacyStoredSecrets() {
        val migration = LegacySettingsSecretMigrator.migrate(
            nwcRecords = settingsStore.loadNwcConnectionsWithLegacySecrets(),
            p2pkRecords = settingsStore.loadP2PKKeysWithLegacySecrets(),
            loadSecret = secureStorage::loadString,
            saveSecret = secureStorage::saveString,
        )
        migration.nwcConnectionsToPersist?.let { settingsStore.nwcConnections = it }
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
        enableNWC = settingsStore.enableNWC,
        showP2PKButtonInDrawer = settingsStore.showP2PKButtonInDrawer,
        amountDisplayPrimary = AmountDisplayPrimary.fromRaw(settingsStore.amountDisplayPrimary).rawValue,
        checkIncomingInvoices = settingsStore.checkIncomingInvoices,
        periodicallyCheckIncomingInvoices = settingsStore.periodicallyCheckIncomingInvoices,
        nostrSignerType = settingsStore.nostrSignerType,
        nostrRelays = settingsStore.nostrRelays,
        nwcConnections = settingsStore.nwcConnections,
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

    private fun generateKeypairHex(): Pair<String, String> {
        val privateKey = generateRandomPrivateKey()
        val privateKeyHex = privateKey.toHex()
        return privateKeyHex to NostrService.publicKeyHex(privateKeyHex)
    }

    private fun secureNWCWalletPrivateKey(id: String): String =
        LegacySettingsSecretMigrator.secureNWCWalletPrivateKey(id)
    private fun secureNWCConnectionSecret(id: String): String =
        LegacySettingsSecretMigrator.secureNWCConnectionSecret(id)
    private fun secureP2PKPrivateKey(id: String): String =
        LegacySettingsSecretMigrator.secureP2PKPrivateKey(id)

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

    private val defaultNWCAllowance: Long = 1_000
}
