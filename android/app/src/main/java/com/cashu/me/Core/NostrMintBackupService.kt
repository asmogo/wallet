package com.cashu.me.Core

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import com.cashu.me.Core.CDK.CdkWalletGateway

data class NostrMintBackupState(
    val isBackingUp: Boolean = false,
    val isSearching: Boolean = false,
    val lastBackupDateEpochMillis: Long? = null,
)

sealed class NostrMintBackupException(message: String) : IllegalStateException(message) {
    class WebSocketsDisabled : NostrMintBackupException("Websocket connections are disabled.")
    class NoRelays : NostrMintBackupException("No Nostr relays are configured.")
    class NothingToBackUp : NostrMintBackupException("There are no mints to back up yet.")
    class RestoreIncomplete : NostrMintBackupException("Finish restoring the wallet before replacing its backup.")
}

/**
 * Publishes the wallet's mint list as an encrypted NUT-27 backup on Nostr and
 * finds existing backups during restore. All protocol work (key derivation,
 * encryption, relay publishing) happens inside cdk via the wallet repository;
 * this service only adds settings gating, relay hygiene, and UI-facing state.
 * Mirrors iOS `NostrMintBackupService`.
 */
class NostrMintBackupService(
    private val settingsManager: SettingsManager,
    private val settingsStore: SettingsStore,
    private val gateway: CdkWalletGateway,
) {
    private val mutableState = MutableStateFlow(
        NostrMintBackupState(lastBackupDateEpochMillis = settingsStore.nostrMintBackupLastBackupDate),
    )
    val state: StateFlow<NostrMintBackupState> = mutableState.asStateFlow()

    /**
     * Fire-and-forget trigger after mint-list changes — the Nostr twin of the
     * iCloud backup on iOS. Failures only log; the mint operation that
     * triggered the backup must not surface a relay error.
     */
    suspend fun backupCurrentMintsIfEnabled() {
        if (settingsStore.walletRestoreIncomplete) return
        if (!settingsManager.state.value.nostrMintBackupEnabled) return
        try {
            backupMints()
        } catch (_: NostrMintBackupException.NothingToBackUp) {
            // Empty wallet — nothing worth publishing, not a failure.
        } catch (t: Throwable) {
            AppLogger.wallet.error("Nostr mint backup failed", t)
        }
    }

    suspend fun backupMints() {
        if (settingsStore.walletRestoreIncomplete) throw NostrMintBackupException.RestoreIncomplete()
        val relays = requireBackupPreconditions()

        // NUT-27 backups are addressable events: publishing replaces the
        // previous backup for this seed on the relay. Never push an empty
        // list — a freshly initialized wallet (e.g. mid-restore) would
        // otherwise wipe the backup it is about to read.
        if (!gateway.hasWallets()) throw NostrMintBackupException.NothingToBackUp()

        mutableState.value = mutableState.value.copy(isBackingUp = true)
        try {
            gateway.backupMints(relays, client = BACKUP_CLIENT)
            val now = System.currentTimeMillis()
            settingsStore.nostrMintBackupLastBackupDate = now
            mutableState.value = mutableState.value.copy(lastBackupDateEpochMillis = now)
        } finally {
            mutableState.value = mutableState.value.copy(isBackingUp = false)
        }
    }

    /**
     * Fetch the newest mint-list backup for the currently opened wallet seed.
     * Returns the backed-up mint URLs (empty when the relays have no backup).
     */
    suspend fun fetchBackedUpMintUrls(): List<String> {
        val relays = requireBackupPreconditions()
        mutableState.value = mutableState.value.copy(isSearching = true)
        return try {
            gateway.fetchMintBackup(relays, timeoutSecs = RESTORE_TIMEOUT_SECS)
        } catch (t: Throwable) {
            // CDK reports "no backup published for this seed" as an error
            // rather than an empty result. Fold it into the documented empty
            // return so call sites keep a single friendly "nothing found"
            // path instead of surfacing a raw FFI dump.
            if (t.message?.contains("no backup event found", ignoreCase = true) == true) {
                emptyList()
            } else {
                throw t
            }
        } finally {
            mutableState.value = mutableState.value.copy(isSearching = false)
        }
    }

    fun resetForWalletBoundary() {
        settingsStore.nostrMintBackupLastBackupDate = null
        mutableState.value = NostrMintBackupState()
    }

    fun reloadStoredState() {
        mutableState.value = NostrMintBackupState(
            lastBackupDateEpochMillis = settingsStore.nostrMintBackupLastBackupDate,
        )
    }

    private fun requireBackupPreconditions(): List<String> {
        val settings = settingsManager.state.value
        if (!settings.useWebsockets) throw NostrMintBackupException.WebSocketsDisabled()
        val relays = normalizedNostrBackupRelays(settings.nostrRelays)
        if (relays.isEmpty()) throw NostrMintBackupException.NoRelays()
        return relays
    }

    companion object {
        private const val BACKUP_CLIENT = "cashu.me"
        private val RESTORE_TIMEOUT_SECS = 4uL

        /** Trim, keep only ws(s):// relays, dedupe preserving order (iOS normalizedRelays). */
        fun normalizedNostrBackupRelays(relays: List<String>): List<String> = relays
            .map(String::trim)
            .filter { it.startsWith("wss://", ignoreCase = true) || it.startsWith("ws://", ignoreCase = true) }
            .distinct()
    }
}
