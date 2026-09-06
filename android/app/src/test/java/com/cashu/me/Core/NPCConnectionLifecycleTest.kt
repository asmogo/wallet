package com.cashu.me.Core

import com.cashu.me.Core.Protocols.StorageKeys
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.*
import org.junit.Test
import kotlin.coroutines.Continuation
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

class NPCConnectionLifecycleTest {
    @Test(timeout = 10_000)
    fun restoredEnabledAddressConnectsAfterSeedIsAvailable() = runBlocking {
        val fixture = Fixture(this)
        try {
            fixture.service.initializeWithSeed(byteArrayOf(1))
            fixture.awaitRequest()
            val connection = async { fixture.service.connect() }
            fixture.client.complete()
            connection.await()
            assertTrue(fixture.service.state.value.isConnected)
            assertFalse(fixture.service.state.value.isLoading)
            assertEquals(1, fixture.clientsCreated)
        } finally { fixture.close() }
    }

    @Test(timeout = 10_000)
    fun disabledAddressDoesNotConnectOnStartupOrForeground() = runBlocking {
        val fixture = Fixture(this, enabled = false)
        try {
            fixture.service.initializeWithSeed(byteArrayOf(1))
            fixture.service.initializeIfEnabled()
            yield()
            assertEquals(0, fixture.clientsCreated)
            assertFalse(fixture.service.state.value.isConnected)
        } finally { fixture.close() }
    }

    @Test(timeout = 10_000)
    fun enablingBeforeKeySetupConnectsWhenSeedArrives() = runBlocking {
        val fixture = Fixture(this, enabled = false)
        try {
            fixture.service.setEnabled(true)
            yield()
            assertEquals(0, fixture.clientsCreated)
            assertNull(fixture.service.state.value.errorMessage)
            fixture.service.initializeWithSeed(byteArrayOf(1))
            fixture.awaitRequest()
            val connection = async { fixture.service.connect() }
            fixture.client.complete()
            connection.await()
            assertTrue(fixture.service.state.value.isConnected)
        } finally { fixture.close() }
    }

    @Test(timeout = 10_000)
    fun concurrentAndRepeatedRecoveryShareOneConnection() = runBlocking {
        val fixture = Fixture(this)
        try {
            fixture.service.initializeWithSeed(byteArrayOf(1))
            fixture.awaitRequest()
            val first = async { fixture.service.connect() }
            val second = async { fixture.service.connect() }
            yield()
            assertEquals(1, fixture.clientsCreated)
            fixture.client.complete()
            first.await()
            second.await()
            fixture.service.connect()
            assertEquals(1, fixture.clientsCreated)
        } finally { fixture.close() }
    }

    @Test(timeout = 10_000)
    fun failedStartupRecoversWithoutToggling() = runBlocking {
        val fixture = Fixture(this)
        try {
            fixture.service.initializeWithSeed(byteArrayOf(1))
            fixture.awaitRequest()
            val initial = async { fixture.service.connect() }
            yield()
            val failed = fixture.client
            failed.fail()
            initial.await()
            assertFalse(fixture.service.state.value.isConnected)
            assertNotNull(fixture.service.state.value.errorMessage)
            assertTrue(failed.closed)

            fixture.service.initializeIfEnabled()
            val recovered = async { fixture.service.connect() }
            yield()
            fixture.awaitRequest()
            fixture.client.complete()
            recovered.await()
            assertTrue(fixture.service.state.value.isConnected)
            assertTrue(fixture.service.state.value.isEnabled)
            assertNull(fixture.service.state.value.errorMessage)
        } finally { fixture.close() }
    }

    @Test(timeout = 10_000)
    fun lateSuccessCannotReconnectDisabledService() = runBlocking {
        val fixture = Fixture(this)
        try {
            fixture.service.initializeWithSeed(byteArrayOf(1))
            fixture.awaitRequest()
            fixture.service.setEnabled(false)
            fixture.client.complete()
            yield()
            assertFalse(fixture.service.state.value.isConnected)
            assertFalse(fixture.service.state.value.isLoading)
            assertNull(fixture.service.state.value.errorMessage)
            assertTrue(fixture.client.closed)
        } finally { fixture.close() }
    }

    @Test(timeout = 10_000)
    fun lateFailureCannotOverwriteNewWalletConnection() = runBlocking {
        val fixture = Fixture(this)
        try {
            fixture.service.initializeWithSeed(byteArrayOf(1))
            fixture.awaitRequest()
            val old = fixture.client
            fixture.service.resetForWalletBoundary()
            fixture.service.initializeWithSeed(byteArrayOf(2))
            fixture.service.setEnabled(true)
            yield()
            fixture.awaitRequest()
            val connection = async { fixture.service.connect() }
            fixture.client.complete()
            connection.await()
            val address = fixture.service.state.value.lightningAddress
            old.fail()
            yield()
            assertTrue(fixture.service.state.value.isConnected)
            assertFalse(fixture.service.state.value.isLoading)
            assertNull(fixture.service.state.value.errorMessage)
            assertEquals(address, fixture.service.state.value.lightningAddress)
            assertTrue(old.closed)
        } finally { fixture.close() }
    }

    @Test(timeout = 10_000)
    fun disabledAndReenabledSessionIgnoresOldSuccessEvenWithSameKeys() = runBlocking {
        val fixture = Fixture(this)
        try {
            fixture.service.initializeWithSeed(byteArrayOf(1))
            fixture.awaitRequest()
            val old = fixture.client
            fixture.service.setEnabled(false)
            fixture.service.setEnabled(true)
            yield()
            fixture.awaitRequest()
            old.complete()
            yield()
            assertFalse(fixture.service.state.value.isConnected)
            assertTrue(fixture.service.state.value.isLoading)
            val connection = async { fixture.service.connect() }
            fixture.client.complete()
            connection.await()
            assertTrue(fixture.service.state.value.isConnected)
        } finally { fixture.close() }
    }

    @Test(timeout = 10_000)
    fun periodicChecksRetryFailedStartup() = runBlocking {
        val fixture = Fixture(this, periodicChecks = true)
        try {
            fixture.service.initializeWithSeed(byteArrayOf(1))
            fixture.awaitRequest()
            val initial = async { fixture.service.connect() }
            yield()
            fixture.client.fail()
            initial.await()
            assertFalse(fixture.service.state.value.isConnected)

            // No foreground or UI trigger: the periodic job must initiate recovery.
            fixture.awaitRequest()
            val retry = async { fixture.service.connect() }
            fixture.client.complete()
            retry.await()
            assertTrue(fixture.service.state.value.isConnected)
            assertNull(fixture.service.state.value.errorMessage)
        } finally { fixture.close() }
    }

    private class Fixture(parent: CoroutineScope, enabled: Boolean = true, periodicChecks: Boolean = false) {
        private val scope = CoroutineScope(parent.coroutineContext + SupervisorJob(parent.coroutineContext[Job]))
        var client = ControlledClient()
        private val clients = mutableListOf(client)
        private val created = Channel<ControlledClient>(Channel.UNLIMITED)
        var clientsCreated = 0
        val service = NPCService(
            prefs = InMemorySharedPreferences(mutableMapOf(StorageKeys.npcEnabled to enabled)),
            settingsState = MutableStateFlow(SettingsState(checkIncomingInvoices = periodicChecks)),
            refreshIntervalMillis = 10,
            scope = scope,
            makeClient = { _, _ ->
                if (clientsCreated > 0) {
                    client = ControlledClient()
                    clients += client
                }
                clientsCreated += 1
                created.trySend(client)
                client
            },
            deriveKeys = { seed -> seed.first().toString() to "01".repeat(32) },
        )
        suspend fun awaitRequest() {
            created.receive().started.receive()
        }
        suspend fun close() {
            service.resetForWalletBoundary()
            clients.forEach { it.complete() }
            scope.cancel()
        }
    }

    /** Deliberately ignores cancellation, like a late native/network callback. */
    private class ControlledClient : NPCClient {
        val started = Channel<Unit>(Channel.UNLIMITED)
        var closed = false
        private var continuation: Continuation<List<NPCQuote>>? = null
        private var requestCount = 0
        override suspend fun getQuotes(): List<NPCQuote> {
            requestCount += 1
            if (requestCount > 1) return emptyList()
            return suspendCoroutine {
                continuation = it
                started.trySend(Unit)
            }
        }
        fun complete() {
            val pending = continuation
            continuation = null
            pending?.resumeWith(Result.success(emptyList()))
        }
        fun fail() {
            val pending = continuation
            continuation = null
            pending?.resumeWithException(IllegalStateException("Offline"))
        }
        override suspend fun setMintUrl(mintUrl: String): String = mintUrl
        override fun close() { closed = true }
    }
}
