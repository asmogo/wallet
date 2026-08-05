package com.cashu.me.Core

import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
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
        previewFetcher = MintPreviewFetcher { null },
    )

    private class FakeMintDiscoverySettings(
        override var useWebsockets: Boolean,
        override var nostrRelays: List<String>,
    ) : MintDiscoverySettings

}
