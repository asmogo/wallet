package com.cashu.me.Core

import java.lang.reflect.Proxy
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import com.cashu.me.Core.CDK.CdkWalletGateway

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
        val manager = discoveryManager()
        manager.discoverMints()
        assertTrue(manager.state.value.hasCompletedDiscovery)

        val retry = async(start = CoroutineStart.UNDISPATCHED) { manager.discoverMints() }

        val retrying = manager.state.value
        assertTrue(retrying.isDiscovering)
        assertFalse(retrying.hasCompletedDiscovery)
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
        relays: List<String> = listOf("ws://127.0.0.1:9"),
    ) = MintDiscoveryManager(
        settings = FakeMintDiscoverySettings(useWebsockets, relays),
        gateway = unusedGateway(),
    )

    private class FakeMintDiscoverySettings(
        override var useWebsockets: Boolean,
        override var nostrRelays: List<String>,
    ) : MintDiscoverySettings

    private fun unusedGateway(): CdkWalletGateway = Proxy.newProxyInstance(
        CdkWalletGateway::class.java.classLoader,
        arrayOf(CdkWalletGateway::class.java),
    ) { _, method, _ -> error("Unexpected gateway call: ${method.name}") } as CdkWalletGateway
}
