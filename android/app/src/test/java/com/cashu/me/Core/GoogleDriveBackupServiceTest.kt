package com.cashu.me.Core

import android.content.Intent
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import com.cashu.me.Core.Platform.BlockStoreFacade
import com.cashu.me.Core.Platform.DriveAppDataApi
import com.cashu.me.Core.Platform.DriveAuthClient
import com.cashu.me.Core.Platform.DriveAuthorization
import com.cashu.me.Core.Platform.DriveFileRef

class GoogleDriveBackupServiceTest {
    // ------------------------------------------------------------------ policy

    @Test
    fun writeBarrierDefersBackupsWhileRestoreIncomplete() {
        assertTrue(DriveRestorePolicy.shouldPerformBackup(restoreIncomplete = false))
        assertFalse(DriveRestorePolicy.shouldPerformBackup(restoreIncomplete = true))
    }

    @Test
    fun onboardingRequiredWithoutSeedOrWithIncompleteRestore() {
        assertTrue(DriveRestorePolicy.needsOnboarding(hasStoredMnemonic = false, restoreIncomplete = false))
        assertTrue(DriveRestorePolicy.needsOnboarding(hasStoredMnemonic = false, restoreIncomplete = true))
        assertTrue(DriveRestorePolicy.needsOnboarding(hasStoredMnemonic = true, restoreIncomplete = true))
        assertFalse(DriveRestorePolicy.needsOnboarding(hasStoredMnemonic = true, restoreIncomplete = false))
    }

    // ------------------------------------------------------------------ backup

    @Test
    fun backupUploadsPayloadToDriveAndBlockStore() = runBlocking {
        val host = FakeHost()
        val api = FakeDriveApi()
        val blockStore = FakeBlockStore()
        val service = service(host = host, api = api, blockStore = blockStore)

        val outcome = service.performBackup()

        assertEquals(DriveBackupOutcome.Success(mintCount = 2), outcome)
        val stored = decode(api.files.single().bytes)
        assertEquals(MNEMONIC, stored.mnemonic)
        assertEquals(host.mintUrls, stored.mintUrls)
        assertEquals(stored, decode(blockStore.stored!!))
        assertEquals(stored.updatedAt, host.lastBackupEpochMillis)
        assertEquals(stored.updatedAt, service.state.value.lastBackupEpochMillis)
    }

    @Test
    fun backupGuardOrderDeferredBeatsUnavailableBeatsNoSeed() = runBlocking {
        val host = FakeHost(mnemonic = null).apply { restoreIncomplete = true }
        val auth = FakeAuth(available = false)
        val api = FakeDriveApi()
        val service = service(host = host, auth = auth, api = api)

        assertEquals(DriveBackupOutcome.Deferred, service.performBackup())

        host.restoreIncomplete = false
        assertEquals(DriveBackupOutcome.Unavailable, service.performBackup())

        auth.available = true
        assertEquals(DriveBackupOutcome.NoSeed, service.performBackup())
        assertTrue(api.files.isEmpty())
    }

    @Test
    fun backgroundBackupReportsNeedsConsentWithoutLaunchingUi() = runBlocking {
        val service = service(auth = FakeAuth(defaultResult = needsResolution()))

        assertEquals(DriveBackupOutcome.NeedsConsent, service.performBackup())
        assertEquals(DriveBackupOutcome.NeedsConsent, service.state.value.lastOutcome)
    }

    @Test
    fun backupUpdatesNewestFileAndDeletesStragglers() = runBlocking {
        val api = FakeDriveApi()
        api.seedFile("newest", "old".encodeToByteArray())
        api.seedFile("stale", "older".encodeToByteArray())
        val service = service(api = api)

        val outcome = service.performBackup()

        assertEquals(DriveBackupOutcome.Success(mintCount = 2), outcome)
        assertEquals(listOf("newest"), api.files.map { it.id })
        assertEquals(MNEMONIC, decode(api.files.single().bytes).mnemonic)
    }

    @Test
    fun backupRetriesOnceAfterExpiredToken() = runBlocking {
        val auth = FakeAuth(
            results = mutableListOf(
                DriveAuthorization.Ready("expired"),
                DriveAuthorization.Ready("fresh"),
            ),
        )
        val api = FakeDriveApi(unauthorizedTokens = setOf("expired"))
        val service = service(auth = auth, api = api)

        assertEquals(DriveBackupOutcome.Success(mintCount = 2), service.performBackup())
        assertEquals(2, auth.authorizeCalls)
    }

    @Test
    fun blockStoreFailureDoesNotFailTheBackup() = runBlocking {
        val api = FakeDriveApi()
        val blockStore = FakeBlockStore(failStore = true)
        val service = service(api = api, blockStore = blockStore)

        assertEquals(DriveBackupOutcome.Success(mintCount = 2), service.performBackup())
        assertEquals(1, api.files.size)
    }

    @Test
    fun blockStoreCopyTrimsMintsButKeepsSeedWithinLimit() = runBlocking {
        val host = FakeHost(mintUrls = List(200) { "https://very-long-mint-url-$it.example.com/api/v1/cashu" })
        val blockStore = FakeBlockStore()
        val service = service(host = host, blockStore = blockStore)

        assertEquals(DriveBackupOutcome.Success(mintCount = 200), service.performBackup())

        val trimmed = decode(blockStore.stored!!)
        assertTrue(blockStore.stored!!.size <= 4096)
        assertEquals(MNEMONIC, trimmed.mnemonic)
        assertTrue(trimmed.mintUrls.size < 200)
    }

    // ------------------------------------------------------------------ detect

    @Test
    fun detectPrefersBlockStoreAndSkipsSignIn() = runBlocking {
        val auth = FakeAuth()
        val blockStore = FakeBlockStore(stored = encode(payload()))
        val service = service(auth = auth, blockStore = blockStore)

        val result = service.detectBackup()

        assertEquals(DriveDetectResult.Found(payload(), DriveBackupSource.BlockStore), result)
        assertEquals(0, auth.authorizeCalls)
    }

    @Test
    fun detectFallsThroughCorruptBlockStoreToDrive() = runBlocking {
        val api = FakeDriveApi()
        api.seedFile("f1", encode(payload()))
        val blockStore = FakeBlockStore(stored = "not json".encodeToByteArray())
        val service = service(api = api, blockStore = blockStore)

        assertEquals(DriveDetectResult.Found(payload(), DriveBackupSource.Drive), service.detectBackup())
    }

    @Test
    fun detectAcceptsNewerPayloadVersionsWithUnknownFields() = runBlocking {
        val futurePayload =
            """{"version":99,"mnemonic":"$MNEMONIC","mintUrls":["https://m.example"],"updatedAt":123,"future":"x"}"""
        val blockStore = FakeBlockStore(stored = futurePayload.encodeToByteArray())
        val service = service(blockStore = blockStore)

        val result = service.detectBackup() as DriveDetectResult.Found
        assertEquals(MNEMONIC, result.payload.mnemonic)
        assertEquals(listOf("https://m.example"), result.payload.mintUrls)
    }

    @Test
    fun detectRejectsPayloadWithInvalidMnemonic() = runBlocking {
        val blockStore = FakeBlockStore(stored = encode(payload(mnemonic = "not a seed")))
        val service = service(blockStore = blockStore)

        assertEquals(DriveDetectResult.NotFound, service.detectBackup())
    }

    @Test
    fun detectReportsNotFoundAndConsentDeclined() = runBlocking {
        assertEquals(DriveDetectResult.NotFound, service().detectBackup())

        val declined = service(auth = FakeAuth(defaultResult = needsResolution(), intentToken = null))
        assertEquals(DriveDetectResult.ConsentDeclined, declined.detectBackup())

        val unavailable = service(auth = FakeAuth(available = false))
        assertEquals(DriveDetectResult.Unavailable, unavailable.detectBackup())
    }

    // ------------------------------------------------------------------ toggle

    @Test
    fun enableWithGrantedConsentBacksUpAndStaysEnabled() = runBlocking {
        val host = FakeHost(enabled = false)
        val auth = FakeAuth(
            results = mutableListOf(needsResolution()),
            defaultResult = DriveAuthorization.Ready("granted"),
            intentToken = "granted",
        )
        val service = service(host = host, auth = auth)

        val outcome = service.setEnabled(true)

        assertEquals(DriveBackupOutcome.Success(mintCount = 2), outcome)
        assertTrue(host.backupEnabled)
    }

    @Test
    fun enableRollsBackWhenConsentIsDeclined() = runBlocking {
        val host = FakeHost(enabled = false)
        val service = service(
            host = host,
            auth = FakeAuth(defaultResult = needsResolution(), intentToken = null),
        )

        assertEquals(DriveBackupOutcome.ConsentDeclined, service.setEnabled(true))
        assertFalse(host.backupEnabled)
    }

    @Test
    fun disableClearsDriveFileBlockStoreAndTimestamp() = runBlocking {
        val host = FakeHost()
        val api = FakeDriveApi()
        val blockStore = FakeBlockStore()
        val service = service(host = host, api = api, blockStore = blockStore)
        service.performBackup()
        assertNotNull(host.lastBackupEpochMillis)

        service.setEnabled(false)

        assertFalse(host.backupEnabled)
        assertTrue(api.files.isEmpty())
        assertNull(blockStore.stored)
        assertNull(host.lastBackupEpochMillis)
        assertNull(service.state.value.lastBackupEpochMillis)
    }

    // ------------------------------------------------------- wallet boundaries

    @Test
    fun walletBoundaryResetKeepsRemoteBackupIntact() = runBlocking {
        val host = FakeHost()
        val api = FakeDriveApi()
        val blockStore = FakeBlockStore()
        val service = service(host = host, api = api, blockStore = blockStore)
        service.performBackup()

        service.resetForWalletBoundary()

        assertNull(host.lastBackupEpochMillis)
        assertNull(service.state.value.lastBackupEpochMillis)
        assertEquals(1, api.files.size)
        assertNotNull(blockStore.stored)
    }

    @Test
    fun backupIfEnabledHonoursTheToggle() = runBlocking {
        val host = FakeHost(enabled = false)
        val api = FakeDriveApi()
        val service = service(host = host, api = api)

        service.backupIfEnabled()
        assertTrue(api.files.isEmpty())

        host.setBackupEnabled(true)
        service.backupIfEnabled()
        assertEquals(1, api.files.size)
    }

    // ------------------------------------------------------------------ fakes

    private companion object {
        const val MNEMONIC =
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

        val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

        fun payload(mnemonic: String = MNEMONIC) = DriveBackupPayload(
            mnemonic = mnemonic,
            mintUrls = listOf("https://mint-a.example", "https://mint-b.example"),
            updatedAt = 1_722_000_000_000,
        )

        fun encode(payload: DriveBackupPayload): ByteArray =
            json.encodeToString(DriveBackupPayload.serializer(), payload).encodeToByteArray()

        fun decode(bytes: ByteArray): DriveBackupPayload =
            json.decodeFromString(DriveBackupPayload.serializer(), bytes.decodeToString())

        fun needsResolution() = DriveAuthorization.NeedsResolution {
            error("Consent resolution must not be unwrapped in unit tests.")
        }

        fun service(
            host: FakeHost = FakeHost(),
            auth: FakeAuth = FakeAuth(),
            api: FakeDriveApi = FakeDriveApi(),
            blockStore: FakeBlockStore = FakeBlockStore(),
        ) = GoogleDriveBackupService(
            host = host,
            authClient = auth,
            driveApi = api,
            blockStore = blockStore,
        )
    }

    private class FakeHost(
        private var enabled: Boolean = true,
        var mnemonic: String? = MNEMONIC,
        var mintUrls: List<String> = listOf("https://mint-a.example", "https://mint-b.example"),
    ) : GoogleDriveBackupService.Host {
        override val backupEnabled: Boolean get() = enabled

        override fun setBackupEnabled(value: Boolean) {
            enabled = value
        }

        override var lastBackupEpochMillis: Long? = null
        override var restoreIncomplete: Boolean = false

        override fun loadMnemonic(): String? = mnemonic

        override fun loadMintUrls(): List<String> = mintUrls
    }

    private class FakeAuth(
        var available: Boolean = true,
        val results: MutableList<DriveAuthorization> = mutableListOf(),
        var defaultResult: DriveAuthorization = DriveAuthorization.Ready("token"),
        var intentToken: String? = null,
    ) : DriveAuthClient {
        var authorizeCalls = 0

        override fun isPlayServicesAvailable(): Boolean = available

        override suspend fun authorize(): DriveAuthorization {
            authorizeCalls++
            return if (results.isNotEmpty()) results.removeAt(0) else defaultResult
        }

        override fun resultFromIntent(intent: Intent?): String? = intentToken
    }

    private class FakeDriveApi(
        private val unauthorizedTokens: Set<String> = emptySet(),
    ) : DriveAppDataApi {
        class StoredFile(val id: String, var bytes: ByteArray)

        val files = mutableListOf<StoredFile>()
        private var nextId = 1

        fun seedFile(id: String, bytes: ByteArray) {
            files.add(StoredFile(id, bytes))
        }

        private fun requireAuthorized(token: String) {
            if (token in unauthorizedTokens) throw DriveBackupException.Http(401)
        }

        override suspend fun findBackupFiles(accessToken: String, fileName: String): List<DriveFileRef> {
            requireAuthorized(accessToken)
            return files.map { DriveFileRef(id = it.id, modifiedTime = null) }
        }

        override suspend fun createFile(accessToken: String, fileName: String, content: ByteArray): String {
            requireAuthorized(accessToken)
            val id = "file-${nextId++}"
            files.add(StoredFile(id, content))
            return id
        }

        override suspend fun updateFile(accessToken: String, fileId: String, content: ByteArray) {
            requireAuthorized(accessToken)
            files.first { it.id == fileId }.bytes = content
        }

        override suspend fun downloadFile(accessToken: String, fileId: String): ByteArray {
            requireAuthorized(accessToken)
            return files.first { it.id == fileId }.bytes
        }

        override suspend fun deleteFile(accessToken: String, fileId: String) {
            requireAuthorized(accessToken)
            files.removeAll { it.id == fileId }
        }

        override suspend fun accountEmail(accessToken: String): String? {
            requireAuthorized(accessToken)
            return "backup@example.com"
        }
    }

    private class FakeBlockStore(
        var stored: ByteArray? = null,
        var failStore: Boolean = false,
    ) : BlockStoreFacade {
        override suspend fun store(bytes: ByteArray) {
            check(!failStore) { "Block Store is unavailable." }
            stored = bytes
        }

        override suspend fun retrieve(): ByteArray? = stored

        override suspend fun deleteAll() {
            stored = null
        }
    }
}
