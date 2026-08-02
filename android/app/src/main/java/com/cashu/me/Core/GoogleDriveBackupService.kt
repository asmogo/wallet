package com.cashu.me.Core

import android.content.Intent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import com.cashu.me.Core.Platform.BlockStoreFacade
import com.cashu.me.Core.Platform.DriveAppDataApi
import com.cashu.me.Core.Platform.DriveAuthClient
import com.cashu.me.Core.Platform.DriveAuthorization
import com.cashu.me.Core.Platform.DriveConsentResolution

/**
 * Everything the backup contains. Seed presence alone makes a backup valid —
 * the mint list is a convenience that may be empty (iOS `ICloudBackupInfo`
 * semantics: "Seed backup — add mints after"). `version` only changes when a
 * field's meaning changes; readers ignore unknown fields and never reject
 * newer versions, because the seed is the product.
 */
@Serializable
data class DriveBackupPayload(
    val version: Int = 1,
    val mnemonic: String,
    val mintUrls: List<String> = emptyList(),
    val updatedAt: Long,
)

enum class DriveAvailability { Unknown, Available, NoPlayServices }

/**
 * Fires an authorization consent resolution through a UI activity-result
 * launcher and returns the result intent (null = declined/cancelled).
 * Background callers pass nothing and get the no-UI default.
 */
typealias DriveConsentLauncher = suspend (DriveConsentResolution) -> Intent?

enum class DriveBackupSource { BlockStore, Drive }

/** Mirror of iOS `ICloudBackupOutcome`, plus the consent cases Android's OAuth reality adds. */
sealed interface DriveBackupOutcome {
    data class Success(val mintCount: Int) : DriveBackupOutcome
    data object Deferred : DriveBackupOutcome
    data object Unavailable : DriveBackupOutcome
    data object NoSeed : DriveBackupOutcome

    /** A background trigger needed the consent sheet it cannot show. */
    data object NeedsConsent : DriveBackupOutcome

    /** The user dismissed or declined the consent sheet. */
    data object ConsentDeclined : DriveBackupOutcome
    data class Failed(val message: String) : DriveBackupOutcome
}

sealed interface DriveDetectResult {
    data class Found(val payload: DriveBackupPayload, val source: DriveBackupSource) : DriveDetectResult
    data object NotFound : DriveDetectResult
    data object Unavailable : DriveDetectResult
    data object ConsentDeclined : DriveDetectResult
}

sealed class DriveBackupException(message: String) : IllegalStateException(message) {
    class Network(cause: Throwable) :
        DriveBackupException("Couldn't reach Google Drive. Check your connection.") {
        init {
            initCause(cause)
        }
    }

    class Http(val code: Int) : DriveBackupException("Google Drive returned an error ($code).")
}

/**
 * Mirror of iOS `ICloudRestorePolicy`. While a restore is incomplete, backups
 * defer (the write barrier that stops a half-restored mint list from
 * clobbering the good remote backup) and the app is forced back into
 * onboarding so the restore resumes.
 */
object DriveRestorePolicy {
    fun shouldPerformBackup(restoreIncomplete: Boolean): Boolean = !restoreIncomplete

    fun needsOnboarding(hasStoredMnemonic: Boolean, restoreIncomplete: Boolean): Boolean =
        !hasStoredMnemonic || restoreIncomplete
}

data class DriveBackupState(
    val availability: DriveAvailability = DriveAvailability.Unknown,
    val isBackingUp: Boolean = false,
    val isDetecting: Boolean = false,
    val lastBackupEpochMillis: Long? = null,
    val lastOutcome: DriveBackupOutcome? = null,
    val accountEmail: String? = null,
)

/**
 * Google Drive backup of the wallet seed and mint list — the Android twin of
 * iOS iCloud backup (`WalletManager+Backup.swift`), with two storage legs:
 *
 * 1. A plaintext JSON file in Drive's hidden appDataFolder — always reachable
 *    after sign-in, but only encrypted at rest by Google (NOT end-to-end).
 * 2. A Block Store copy — end-to-end encrypted when the device has a screen
 *    lock, restored silently during Android device-setup migration, but
 *    unreachable after a fresh setup.
 *
 * One user-facing toggle drives both. Restore checks Block Store first (no
 * sign-in), then Drive. Mirrors `NostrMintBackupService` in shape.
 */
class GoogleDriveBackupService(
    private val host: Host,
    private val authClient: DriveAuthClient,
    private val driveApi: DriveAppDataApi,
    private val blockStore: BlockStoreFacade,
    private val validateMnemonic: (String) -> Boolean = {
        MnemonicInput.hasSupportedWordCount(MnemonicInput.normalize(it))
    },
) {
    /**
     * What the service needs from the app's stores (SettingsManager,
     * SettingsStore, SecureStorage, WalletStore) — narrowed to an interface
     * so the money-critical logic is testable on the JVM (NwcStore pattern).
     * The production adapter lives in AppContainer.
     */
    interface Host {
        val backupEnabled: Boolean
        fun setBackupEnabled(value: Boolean)
        var lastBackupEpochMillis: Long?
        var restoreIncomplete: Boolean
        fun loadMnemonic(): String?
        fun loadMintUrls(): List<String>
    }

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val backupMutex = Mutex()

    private val mutableState = MutableStateFlow(
        DriveBackupState(lastBackupEpochMillis = host.lastBackupEpochMillis),
    )
    val state: StateFlow<DriveBackupState> = mutableState.asStateFlow()

    /** iOS `hasIncompleteICloudRestore` twin — see [DriveRestorePolicy]. */
    var restoreIncomplete: Boolean
        get() = host.restoreIncomplete
        set(value) {
            host.restoreIncomplete = value
        }

    fun refreshAvailability(): DriveAvailability {
        val availability = if (authClient.isPlayServicesAvailable()) {
            DriveAvailability.Available
        } else {
            DriveAvailability.NoPlayServices
        }
        mutableState.update { it.copy(availability = availability) }
        return availability
    }

    /**
     * Fire-and-forget trigger after mint-list and wallet-boundary changes —
     * the Drive twin of `NostrMintBackupService.backupCurrentMintsIfEnabled`.
     * Failures only log; the wallet operation that triggered the backup must
     * not surface a Drive error.
     */
    suspend fun backupIfEnabled() {
        if (!host.backupEnabled) return
        runCatching { performBackup() }
            .onFailure { AppLogger.wallet.error("Google Drive backup failed", it) }
    }

    /**
     * iOS `performICloudBackup()` twin, same guard order. Background callers
     * leave [allowResolution] false and get [DriveBackupOutcome.NeedsConsent]
     * when the token needs a consent sheet; UI callers pass a launcher that
     * fires the PendingIntent and returns the result intent.
     */
    suspend fun performBackup(
        allowResolution: Boolean = false,
        launchResolution: DriveConsentLauncher = { null },
    ): DriveBackupOutcome = backupMutex.withLock {
        if (!DriveRestorePolicy.shouldPerformBackup(restoreIncomplete)) {
            return recordOutcome(DriveBackupOutcome.Deferred)
        }
        if (refreshAvailability() != DriveAvailability.Available) {
            return recordOutcome(DriveBackupOutcome.Unavailable)
        }
        val mnemonic = host.loadMnemonic()
            ?: return recordOutcome(DriveBackupOutcome.NoSeed)

        mutableState.update { it.copy(isBackingUp = true) }
        try {
            val token = when (val acquired = acquireToken(allowResolution, launchResolution)) {
                is TokenResult.Token -> acquired.value
                is TokenResult.Outcome -> return recordOutcome(acquired.value)
            }
            val payload = DriveBackupPayload(
                mnemonic = mnemonic,
                mintUrls = host.loadMintUrls(),
                updatedAt = System.currentTimeMillis(),
            )
            val bytes = json.encodeToString(DriveBackupPayload.serializer(), payload).encodeToByteArray()

            withTokenRetry(token) { fresh ->
                val existing = driveApi.findBackupFiles(fresh, BACKUP_FILE_NAME)
                if (existing.isEmpty()) {
                    driveApi.createFile(fresh, BACKUP_FILE_NAME, bytes)
                } else {
                    driveApi.updateFile(fresh, existing.first().id, bytes)
                    existing.drop(1).forEach { driveApi.deleteFile(fresh, it.id) }
                }
            }

            // Best-effort second leg: Block Store must never fail the backup.
            runCatching { blockStore.store(blockStoreBytes(payload)) }
                .onFailure { AppLogger.wallet.error("Block Store backup failed", it) }

            host.lastBackupEpochMillis = payload.updatedAt
            mutableState.update { it.copy(lastBackupEpochMillis = payload.updatedAt) }
            refreshAccountEmail(token)
            recordOutcome(DriveBackupOutcome.Success(mintCount = payload.mintUrls.size))
        } catch (e: DriveBackupException) {
            recordOutcome(DriveBackupOutcome.Failed(e.message ?: "Google Drive backup failed."))
        } finally {
            mutableState.update { it.copy(isBackingUp = false) }
        }
    }

    /**
     * Restore-time discovery: Block Store first (silent — present when this
     * device was set up from the old phone's backup), then Drive (sign-in).
     */
    suspend fun detectBackup(
        launchResolution: DriveConsentLauncher = { null },
    ): DriveDetectResult {
        if (refreshAvailability() != DriveAvailability.Available) {
            return DriveDetectResult.Unavailable
        }
        mutableState.update { it.copy(isDetecting = true) }
        try {
            runCatching { blockStore.retrieve() }
                .getOrNull()
                ?.let(::parsePayload)
                ?.let { return DriveDetectResult.Found(it, DriveBackupSource.BlockStore) }

            val token = when (val acquired = acquireToken(allowResolution = true, launchResolution)) {
                is TokenResult.Token -> acquired.value
                is TokenResult.Outcome -> return when (acquired.value) {
                    DriveBackupOutcome.ConsentDeclined -> DriveDetectResult.ConsentDeclined
                    else -> DriveDetectResult.Unavailable
                }
            }
            refreshAccountEmail(token)
            val payload = withTokenRetry(token) { fresh ->
                driveApi.findBackupFiles(fresh, BACKUP_FILE_NAME)
                    .firstNotNullOfOrNull { parsePayload(driveApi.downloadFile(fresh, it.id)) }
            }
            return payload
                ?.let { DriveDetectResult.Found(it, DriveBackupSource.Drive) }
                ?: DriveDetectResult.NotFound
        } catch (e: DriveBackupException) {
            AppLogger.wallet.error("Google Drive backup detection failed", e)
            return DriveDetectResult.NotFound
        } finally {
            mutableState.update { it.copy(isDetecting = false) }
        }
    }

    /**
     * Toggle handler. Enabling runs an immediate backup (iOS setter parity)
     * and rolls the flag back when access never materialized, so the toggle
     * always reflects reality. Disabling clears the remote data.
     */
    suspend fun setEnabled(
        value: Boolean,
        launchResolution: DriveConsentLauncher = { null },
    ): DriveBackupOutcome? {
        if (!value) {
            host.setBackupEnabled(false)
            clearBackupData()
            return null
        }
        host.setBackupEnabled(true)
        val outcome = performBackup(allowResolution = true, launchResolution = launchResolution)
        val accessNeverGranted = outcome is DriveBackupOutcome.Unavailable ||
            outcome is DriveBackupOutcome.NeedsConsent ||
            outcome is DriveBackupOutcome.ConsentDeclined
        if (accessNeverGranted) {
            host.setBackupEnabled(false)
        }
        return outcome
    }

    /**
     * iOS `clearICloudBackupData()` twin: removes the Drive file (best effort
     * — consent may be gone) and the Block Store entry. Never touches the
     * local wallet.
     */
    suspend fun clearBackupData() {
        runCatching {
            val auth = authClient.authorize()
            if (auth is DriveAuthorization.Ready) {
                driveApi.findBackupFiles(auth.accessToken, BACKUP_FILE_NAME)
                    .forEach { driveApi.deleteFile(auth.accessToken, it.id) }
            }
        }.onFailure { AppLogger.wallet.error("Removing Google Drive backup failed", it) }
        runCatching { blockStore.deleteAll() }
            .onFailure { AppLogger.wallet.error("Removing Block Store backup failed", it) }
        host.lastBackupEpochMillis = null
        mutableState.update {
            it.copy(lastBackupEpochMillis = null, lastOutcome = null, accountEmail = null)
        }
    }

    /** Wallet delete/replace: local state only — the remote backup survives (iOS parity). */
    fun resetForWalletBoundary() {
        host.lastBackupEpochMillis = null
        mutableState.update {
            DriveBackupState(availability = it.availability)
        }
    }

    fun reloadStoredState() {
        mutableState.update {
            DriveBackupState(
                availability = it.availability,
                lastBackupEpochMillis = host.lastBackupEpochMillis,
            )
        }
    }

    private sealed interface TokenResult {
        data class Token(val value: String) : TokenResult
        data class Outcome(val value: DriveBackupOutcome) : TokenResult
    }

    private suspend fun acquireToken(
        allowResolution: Boolean,
        launchResolution: DriveConsentLauncher,
    ): TokenResult = when (val auth = authClient.authorize()) {
        is DriveAuthorization.Ready -> TokenResult.Token(auth.accessToken)
        is DriveAuthorization.NeedsResolution -> {
            if (!allowResolution) {
                TokenResult.Outcome(DriveBackupOutcome.NeedsConsent)
            } else {
                val token = authClient.resultFromIntent(launchResolution(auth.consent))
                if (token != null) {
                    TokenResult.Token(token)
                } else {
                    TokenResult.Outcome(DriveBackupOutcome.ConsentDeclined)
                }
            }
        }
        DriveAuthorization.Unavailable -> TokenResult.Outcome(DriveBackupOutcome.Unavailable)
    }

    /** Access tokens expire (~1 h): on a 401, re-authorize silently once and retry. */
    private suspend fun <T> withTokenRetry(token: String, block: suspend (String) -> T): T =
        try {
            block(token)
        } catch (e: DriveBackupException.Http) {
            if (e.code != 401) throw e
            val fresh = (authClient.authorize() as? DriveAuthorization.Ready)?.accessToken ?: throw e
            block(fresh)
        }

    private fun parsePayload(bytes: ByteArray?): DriveBackupPayload? {
        bytes ?: return null
        return runCatching {
            json.decodeFromString(DriveBackupPayload.serializer(), bytes.decodeToString())
        }.getOrNull()?.takeIf { it.mnemonic.isNotBlank() && validateMnemonic(it.mnemonic) }
    }

    /**
     * Block Store entries cap at 4 KB. A seed plus a normal mint list is a few
     * hundred bytes; in the degenerate case, drop trailing mint URLs — a
     * seed-only backup is still a valid backup.
     */
    private fun blockStoreBytes(payload: DriveBackupPayload): ByteArray {
        var candidate = payload
        while (true) {
            val bytes = json.encodeToString(DriveBackupPayload.serializer(), candidate).encodeToByteArray()
            if (bytes.size <= BLOCK_STORE_MAX_BYTES || candidate.mintUrls.isEmpty()) {
                if (candidate.mintUrls.size != payload.mintUrls.size) {
                    AppLogger.wallet.info(
                        "Block Store backup trimmed to ${candidate.mintUrls.size} of ${payload.mintUrls.size} mints",
                    )
                }
                return bytes
            }
            candidate = candidate.copy(mintUrls = candidate.mintUrls.dropLast(1))
        }
    }

    private suspend fun refreshAccountEmail(token: String) {
        if (mutableState.value.accountEmail != null) return
        runCatching { driveApi.accountEmail(token) }
            .getOrNull()
            ?.let { email -> mutableState.update { it.copy(accountEmail = email) } }
    }

    private fun recordOutcome(outcome: DriveBackupOutcome): DriveBackupOutcome {
        mutableState.update { it.copy(lastOutcome = outcome) }
        return outcome
    }

    companion object {
        const val BACKUP_FILE_NAME = "cashu_wallet_backup.json"
        private const val BLOCK_STORE_MAX_BYTES = 4096
    }
}
