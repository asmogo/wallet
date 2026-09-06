package com.cashu.me.Core

import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import com.cashu.me.Models.PaymentMethodKind

class MintDiscoveryManagerTest {
    @Test
    fun parsesKind38172MintEvent() {
        val message = """
            ["EVENT","sub-1",{
              "kind":38172,
              "pubkey":"abcdef",
              "tags":[["u","https://mint.example.com/"]],
              "content":"{\"name\":\"Example Mint\",\"description\":\"Demo mint\",\"icon_url\":\"https://mint.example.com/icon.png\"}"
            }]
        """.trimIndent()

        val mint = NostrMintEventParser.parseRelayMessage(message)

        assertEquals("https://mint.example.com", mint?.url)
        assertEquals("Example Mint", mint?.name)
        assertEquals("Demo mint", mint?.description)
        assertEquals("https://mint.example.com/icon.png", mint?.iconUrl)
    }

    @Test
    fun rejectsNonMintEventKinds() {
        val message = """
            ["EVENT","sub-1",{
              "kind":1,
              "tags":[["u","https://mint.example.com"]],
              "content":"{}"
            }]
        """.trimIndent()

        assertNull(NostrMintEventParser.parseRelayMessage(message))
    }

    @Test
    fun rejectsMintEventsWithoutHttpUrl() {
        val message = """
            ["EVENT","sub-1",{
              "kind":38172,
              "tags":[["u","not-a-url"]],
              "content":"{}"
            }]
        """.trimIndent()

        assertNull(NostrMintEventParser.parseRelayMessage(message))
    }

    @Test
    fun rejectsCleartextMintAnnouncements() {
        val message = """
            ["EVENT","sub-1",{
              "kind":38172,
              "tags":[["u","http://mint.example.com"]],
              "content":"{}"
            }]
        """.trimIndent()

        assertNull(NostrMintEventParser.parseRelayMessage(message))
    }

    @Test
    fun canonicalizesHttpsMintAnnouncements() {
        assertEquals(
            "https://mint.example.com:8443/path",
            canonicalDiscoveredMintUrl(" HTTPS://MINT.EXAMPLE.COM:8443/path/ "),
        )
        assertNull(canonicalDiscoveredMintUrl("https://user:secret@mint.example.com"))
        assertNull(canonicalDiscoveredMintUrl("https://mint.example.com?network=test"))
        assertNull(canonicalDiscoveredMintUrl("https://mint.example.com/#fragment"))
    }

    @Test
    fun parsesNut06PreviewWithoutPreparingCdkWallet() {
        val preview = MintPreviewParser.parse(
            mintUrl = "https://mint.example.com",
            jsonString = """
                {
                  "name":"Live Mint",
                  "description":"Ready",
                  "icon_url":"https://mint.example.com/icon.png",
                  "nuts":{
                    "4":{"methods":[
                      {"method":"bolt11","unit":"sat"},
                      {"method":"bolt12","unit":"usd"}
                    ]},
                    "5":{"methods":[
                      {"method":"onchain","unit":"sat"}
                    ]}
                  }
                }
            """.trimIndent(),
        )

        assertEquals("Live Mint", preview?.name)
        assertEquals(listOf("sat", "usd"), preview?.units)
        assertEquals(listOf("sat", "usd"), preview?.mintUnits)
        assertEquals(listOf(PaymentMethodKind.Bolt11, PaymentMethodKind.Bolt12), preview?.supportedMintMethods)
        assertEquals(listOf(PaymentMethodKind.Onchain), preview?.supportedMeltMethods)
        assertEquals(false, preview?.supportsBolt12MintDescription)
    }

    @Test
    fun parsesNut04Bolt12DescriptionAdvertisement() {
        val advertised = MintPreviewParser.parse(
            mintUrl = "https://mint.example.com",
            jsonString = """
                {
                  "name":"Live Mint",
                  "nuts":{
                    "4":{"methods":[
                      {"method":"bolt12","unit":"sat","options":{"description":true}}
                    ]}
                  }
                }
            """.trimIndent(),
        )
        val omitted = MintPreviewParser.parse(
            mintUrl = "https://mint.example.com",
            jsonString = """
                {
                  "name":"Live Mint",
                  "nuts":{
                    "4":{"methods":[
                      {"method":"bolt12","unit":"sat"}
                    ]}
                  }
                }
            """.trimIndent(),
        )

        assertEquals(true, advertised?.supportsBolt12MintDescription)
        assertEquals(false, omitted?.supportsBolt12MintDescription)
    }

    @Test
    fun discoveryCycleWithZeroResultsCompletesExhausted() = runBlocking {
        val manager = discoveryManager()

        manager.discoverMints()

        val state = manager.state.value
        assertFalse(state.isDiscovering)
        assertTrue(state.hasCompletedDiscovery)
        assertTrue(state.discoveredMints.isEmpty())
    }

    @Test
    fun retryResetsExhaustedStateWhileDiscovering() = runBlocking {
        val isRetry = AtomicBoolean(false)
        val retryStarted = CompletableDeferred<Unit>()
        val finishRetry = CountDownLatch(1)
        val manager = discoveryManager(client = FailedRelayClient {
            if (isRetry.get()) {
                retryStarted.complete(Unit)
                check(finishRetry.await(5, TimeUnit.SECONDS)) { "Retry was not released by the test" }
            }
        })
        manager.discoverMints()
        assertTrue(manager.state.value.hasCompletedDiscovery)

        isRetry.set(true)
        val retry = async(start = CoroutineStart.UNDISPATCHED) { manager.discoverMints() }

        try {
            // Hold the relay request until the in-progress state is inspected.
            // A real refused connection can finish before these assertions run.
            withTimeout(5_000) { retryStarted.await() }
            val retrying = manager.state.value
            assertTrue(retrying.isDiscovering)
            assertFalse(retrying.hasCompletedDiscovery)
        } finally {
            finishRetry.countDown()
        }
        retry.await()
        assertTrue(manager.state.value.hasCompletedDiscovery)
        assertFalse(manager.state.value.isDiscovering)
    }

    @Test
    fun discoveryStaysIdleWhenWebsocketsDisabled() = runBlocking {
        val manager = discoveryManager(useWebsockets = false)

        val result = manager.discoverMints()

        assertTrue(result.isEmpty())
        val state = manager.state.value
        assertFalse(state.isDiscovering)
        assertFalse(state.hasCompletedDiscovery)
    }

    @Test
    fun clearDiscoveredMintsResetsToFreshState() = runBlocking {
        val manager = discoveryManager()
        manager.discoverMints()
        assertTrue(manager.state.value.hasCompletedDiscovery)

        manager.clearDiscoveredMints()

        val state = manager.state.value
        assertFalse(state.isDiscovering)
        assertFalse(state.hasCompletedDiscovery)
        assertTrue(state.discoveredMints.isEmpty())
    }

    private fun discoveryManager(
        useWebsockets: Boolean = true,
        relays: List<String> = listOf("wss://relay.example"),
        client: OkHttpClient = FailedRelayClient(),
    ) = MintDiscoveryManager(
        settings = FakeMintDiscoverySettings(useWebsockets, relays),
        client = client,
        previewFetcher = MintPreviewFetcher { null },
    )

    /** Completes empty discovery without opening sockets or depending on network timing. */
    private class FailedRelayClient(
        private val beforeConnect: () -> Unit = {},
    ) : OkHttpClient() {
        override fun newWebSocket(request: Request, listener: WebSocketListener): WebSocket {
            beforeConnect()
            val socket = object : WebSocket {
                override fun request(): Request = request
                override fun queueSize(): Long = 0
                override fun send(text: String): Boolean = false
                override fun send(bytes: ByteString): Boolean = false
                override fun close(code: Int, reason: String?): Boolean = true
                override fun cancel() = Unit
            }
            listener.onFailure(socket, IOException("Simulated unavailable relay"), null)
            return socket
        }
    }

    private class FakeMintDiscoverySettings(
        override var useWebsockets: Boolean,
        override var nostrRelays: List<String>,
    ) : MintDiscoverySettings

}
