package com.cashu.me.Core

import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import com.cashu.me.Core.CDK.NwcServiceGateway
import com.cashu.me.Core.CDK.NwcServiceHandle
import com.cashu.me.Core.Protocols.SecureStorage
import com.cashu.me.Core.Protocols.StorageKeys

data class NwcState(
    val isEnabled: Boolean = false,
    val selectedMintUrl: String? = null,
    val budgetSats: Long? = null,
    val connectionUri: String? = null,
    val isRunning: Boolean = false,
    val isBusy: Boolean = false,
    val errorMessage: String? = null,
)

@kotlinx.serialization.Serializable
internal data class NwcStoredSettings(
    val isEnabled: Boolean = false,
    val selectedMintUrl: String? = null,
    val budgetSats: Long? = null,
    val connectionUri: String? = null,
)

internal interface NwcStore {
    fun load(): NwcStoredSettings
    fun saveEnabled(value: Boolean)
    fun saveSelectedMint(value: String?)
    fun saveBudgetSats(value: Long?)
    fun saveConnectionUri(value: String?)
    fun clear()
}

internal class SecureNwcStore(
    private val settingsStore: SettingsStore,
    private val secureStorage: SecureStorage,
) : NwcStore {
    init {
        // The removed Android prototype generated unrelated random keys and
        // never ran a wallet service. They cannot preserve a CDK connection.
        settingsStore.clearLegacyNwcPrototypeSettings()
        secureStorage.deletePrefix(StorageKeys.legacySecureNwcPrefix)
    }

    override fun load(): NwcStoredSettings = NwcStoredSettings(
        isEnabled = settingsStore.nwcEnabled,
        selectedMintUrl = settingsStore.nwcSelectedMint,
        budgetSats = settingsStore.nwcBudgetSats,
        connectionUri = secureStorage.loadString(StorageKeys.secureNwcConnectionUri),
    )

    override fun saveEnabled(value: Boolean) {
        settingsStore.nwcEnabled = value
    }

    override fun saveSelectedMint(value: String?) {
        settingsStore.nwcSelectedMint = value
    }

    override fun saveBudgetSats(value: Long?) {
        settingsStore.nwcBudgetSats = value
    }

    override fun saveConnectionUri(value: String?) {
        if (value == null) {
            secureStorage.delete(StorageKeys.secureNwcConnectionUri)
        } else {
            secureStorage.saveString(StorageKeys.secureNwcConnectionUri, value)
        }
    }

    override fun clear() {
        settingsStore.nwcEnabled = false
        settingsStore.nwcSelectedMint = null
        settingsStore.nwcBudgetSats = null
        secureStorage.delete(StorageKeys.secureNwcConnectionUri)
    }
}

@kotlinx.serialization.Serializable
internal data class NwcWalletScopedSnapshot(val settings: NwcStoredSettings)

/**
 * Owns the lifecycle of CDK's Nostr Wallet Connect service.
 *
 * The service key is derived by CDK from the same deterministic 64-byte seed
 * material as iOS. The client secret remains stable across launches by
 * restoring it from the encrypted connection URI; resetting the connection is
 * the only action that intentionally rotates that secret.
 */
class NwcManager internal constructor(
    private val store: NwcStore,
    private val gateway: NwcServiceGateway,
    private val seedProvider: () -> ByteArray?,
    private val relayProvider: () -> List<String>,
) {
    constructor(
        settingsStore: SettingsStore,
        secureStorage: SecureStorage,
        gateway: NwcServiceGateway,
        seedProvider: () -> ByteArray?,
        relayProvider: () -> List<String>,
    ) : this(
        store = SecureNwcStore(settingsStore, secureStorage),
        gateway = gateway,
        seedProvider = seedProvider,
        relayProvider = relayProvider,
    )

    private val lifecycleMutex = Mutex()
    private var service: NwcServiceHandle? = null
    private val mutableState = MutableStateFlow(store.load().toRuntimeState())
    val state: StateFlow<NwcState> = mutableState.asStateFlow()

    suspend fun startIfEnabled() = lifecycleMutex.withLock {
        if (mutableState.value.isEnabled && !mutableState.value.isRunning) {
            withBusy { startServiceLocked() }
        }
    }

    internal suspend fun stop() = lifecycleMutex.withLock { stopServiceLocked() }

    suspend fun setEnabled(value: Boolean, defaultMintUrl: String? = null) = lifecycleMutex.withLock {
        if (value && mutableState.value.selectedMintUrl == null) {
            normalizedMintUrl(defaultMintUrl)?.let(::setSelectedMintPersisted)
        }
        setEnabledPersisted(value)
        withBusy {
            if (value) startServiceLocked() else stopServiceLocked()
        }
    }

    suspend fun setSelectedMintUrl(value: String?) = lifecycleMutex.withLock {
        val normalized = normalizedMintUrl(value)
        if (normalized == mutableState.value.selectedMintUrl) return@withLock
        setSelectedMintPersisted(normalized)
        if (mutableState.value.isEnabled) withBusy { startServiceLocked() }
    }

    suspend fun setBudgetSats(value: Long?) = lifecycleMutex.withLock {
        require(value == null || value in 1..MaxBudgetSats) {
            "Payment limit must be between 1 and $MaxBudgetSats sats."
        }
        if (value == mutableState.value.budgetSats) return@withLock
        store.saveBudgetSats(value)
        mutableState.value = mutableState.value.copy(budgetSats = value)
        if (mutableState.value.isEnabled) withBusy { startServiceLocked() }
    }

    suspend fun regenerateConnection() = lifecycleMutex.withLock {
        withBusy {
            stopServiceLocked()
            setConnectionUriPersisted(null)
            if (mutableState.value.isEnabled) startServiceLocked()
        }
    }

    internal fun snapshotWalletScopedData(): NwcWalletScopedSnapshot =
        NwcWalletScopedSnapshot(mutableState.value.toStoredSettings())

    internal suspend fun resetForWalletBoundary() = lifecycleMutex.withLock {
        mutableState.value = mutableState.value.copy(isBusy = true)
        stopServiceLocked()
        store.clear()
        mutableState.value = NwcState()
    }

    internal suspend fun restoreWalletScopedData(snapshot: NwcWalletScopedSnapshot) = lifecycleMutex.withLock {
        stopServiceLocked()
        store.saveEnabled(snapshot.settings.isEnabled)
        store.saveSelectedMint(snapshot.settings.selectedMintUrl)
        store.saveBudgetSats(snapshot.settings.budgetSats)
        store.saveConnectionUri(snapshot.settings.connectionUri)
        mutableState.value = snapshot.settings.toRuntimeState()
    }

    private suspend fun startServiceLocked() {
        mutableState.value = mutableState.value.copy(errorMessage = null)
        val mintUrl = mutableState.value.selectedMintUrl
        if (mintUrl.isNullOrBlank()) {
            setEnabledPersisted(false)
            mutableState.value = mutableState.value.copy(
                errorMessage = "Select a mint to use with Nostr Wallet Connect.",
            )
            return
        }

        val seed = seedProvider()
        if (seed == null || seed.size < 64) {
            mutableState.value = mutableState.value.copy(
                errorMessage = "Wallet seed is not available yet. Try again in a moment.",
            )
            return
        }

        val relays = relayProvider().map(String::trim).filter(String::isNotEmpty).distinct()
        if (relays.isEmpty()) {
            setEnabledPersisted(false)
            mutableState.value = mutableState.value.copy(
                errorMessage = "Add at least one Nostr relay before enabling Wallet Connect.",
            )
            return
        }

        stopServiceLocked()
        var createdService: NwcServiceHandle? = null
        try {
            val existingUri = mutableState.value.connectionUri
            createdService = gateway.createOrRestoreNwcService(
                mintUrl = mintUrl,
                relays = relays,
                seed = seed,
                clientSecretKey = existingUri?.let(::clientSecretFromConnectionUri),
                maxPaymentMsat = mutableState.value.budgetSats?.toULong()?.times(1_000uL),
            )
            if (existingUri == null || clientSecretFromConnectionUri(existingUri) == null) {
                setConnectionUriPersisted(createdService.connectionUri)
            }
            createdService.start()
            service = createdService
            mutableState.value = mutableState.value.copy(isRunning = createdService.isRunning())
        } catch (error: Throwable) {
            withContext(NonCancellable) {
                runCatching { createdService?.stop() }
                runCatching { createdService?.close() }
            }
            service = null
            if (error is CancellationException) throw error
            mutableState.value = mutableState.value.copy(
                isRunning = false,
                errorMessage = error.message?.takeIf(String::isNotBlank)
                    ?: "Could not start Nostr Wallet Connect.",
            )
            AppLogger.wallet.error("Failed to start Nostr Wallet Connect", error)
        }
    }

    private suspend fun stopServiceLocked() {
        val current = service
        service = null
        if (current != null) {
            withContext(NonCancellable) {
                runCatching { current.stop() }
                    .onFailure { AppLogger.wallet.error("Failed to stop Nostr Wallet Connect", it) }
                runCatching { current.close() }
                    .onFailure { AppLogger.wallet.error("Failed to close Nostr Wallet Connect", it) }
            }
        }
        mutableState.value = mutableState.value.copy(isRunning = false)
    }

    private suspend fun withBusy(block: suspend () -> Unit) {
        mutableState.value = mutableState.value.copy(isBusy = true)
        try {
            block()
        } finally {
            mutableState.value = mutableState.value.copy(isBusy = false)
        }
    }

    private fun setEnabledPersisted(value: Boolean) {
        store.saveEnabled(value)
        mutableState.value = mutableState.value.copy(isEnabled = value)
    }

    private fun setSelectedMintPersisted(value: String?) {
        store.saveSelectedMint(value)
        mutableState.value = mutableState.value.copy(selectedMintUrl = value)
    }

    private fun setConnectionUriPersisted(value: String?) {
        store.saveConnectionUri(value)
        mutableState.value = mutableState.value.copy(connectionUri = value)
    }

    private fun normalizedMintUrl(value: String?): String? =
        value?.trim()?.trimEnd('/')?.takeIf(String::isNotEmpty)

    companion object {
        internal const val MaxBudgetSats = 999_999_999_999L

        internal fun clientSecretFromConnectionUri(uri: String): String? {
            val query = runCatching { URI(uri).rawQuery }.getOrNull()
                ?: uri.substringAfter('?', missingDelimiterValue = "").takeIf(String::isNotEmpty)
                ?: return null
            return query.split('&')
                .asSequence()
                .mapNotNull { pair ->
                    val parts = pair.split('=', limit = 2)
                    if (parts.size != 2 || parts[0] != "secret") return@mapNotNull null
                    runCatching { URLDecoder.decode(parts[1], StandardCharsets.UTF_8.name()) }
                        .getOrDefault(parts[1])
                        .takeIf(String::isNotEmpty)
                }
                .firstOrNull()
        }
    }
}

private fun NwcStoredSettings.toRuntimeState(): NwcState = NwcState(
    isEnabled = isEnabled,
    selectedMintUrl = selectedMintUrl,
    budgetSats = budgetSats,
    connectionUri = connectionUri,
)

private fun NwcState.toStoredSettings(): NwcStoredSettings = NwcStoredSettings(
    isEnabled = isEnabled,
    selectedMintUrl = selectedMintUrl,
    budgetSats = budgetSats,
    connectionUri = connectionUri,
)
