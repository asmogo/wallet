package org.cashu.wallet.Core

import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import org.cashu.wallet.Models.MintInfo

data class MintDiscoveryState(
    val discoveredMints: List<MintInfo> = emptyList(),
    val isDiscovering: Boolean = false,
)

class MintDiscoveryManager(
    private val settingsManager: SettingsManager,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build(),
) {
    private val mutableState = MutableStateFlow(MintDiscoveryState())
    val state: StateFlow<MintDiscoveryState> = mutableState.asStateFlow()
    private val webSockets = CopyOnWriteArrayList<WebSocket>()

    suspend fun discoverMints(): List<MintInfo> {
        if (mutableState.value.isDiscovering) return mutableState.value.discoveredMints
        if (!settingsManager.state.value.useWebsockets) return emptyList()

        closeAllConnections()
        mutableState.value = MintDiscoveryState(isDiscovering = true)
        return try {
            withContext(Dispatchers.IO) {
                configuredRelays()
                    .map { relay -> async { connectAndQuery(relay) } }
                    .awaitAll()
            }
            mutableState.value.discoveredMints
        } finally {
            closeAllConnections()
            mutableState.update { it.copy(isDiscovering = false) }
        }
    }

    private suspend fun connectAndQuery(relay: String) {
        val request = runCatching { Request.Builder().url(relay).build() }.getOrNull() ?: return
        val closed = CompletableDeferred<Unit>()
        val subscriptionId = UUID.randomUUID().toString()
        val listener = object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send("""["REQ","$subscriptionId",{"kinds":[38172],"limit":50}]""")
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handleRelayMessage(text)
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                handleRelayMessage(bytes.utf8())
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(NORMAL_CLOSURE, null)
                closed.complete(Unit)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                webSockets.remove(webSocket)
                closed.complete(Unit)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                webSockets.remove(webSocket)
                closed.complete(Unit)
            }
        }

        val webSocket = client.newWebSocket(request, listener)
        webSockets += webSocket
        withTimeoutOrNull(DISCOVERY_WINDOW_MILLIS) { closed.await() }
        webSocket.close(NORMAL_CLOSURE, "discovery complete")
        webSockets.remove(webSocket)
    }

    private fun handleRelayMessage(message: String) {
        val discovered = NostrMintEventParser.parseRelayMessage(message) ?: return
        mutableState.update { current ->
            if (current.discoveredMints.any { it.url == discovered.url }) {
                current
            } else {
                current.copy(discoveredMints = current.discoveredMints + discovered)
            }
        }
    }

    private fun configuredRelays(): List<String> {
        val configured = settingsManager.state.value.nostrRelays
            .map { it.trim() }
            .filter { relay ->
                relay.startsWith("wss://", ignoreCase = true) || relay.startsWith("ws://", ignoreCase = true)
            }
        return configured.ifEmpty { DEFAULT_RELAYS }
    }

    private fun closeAllConnections() {
        webSockets.forEach { it.close(NORMAL_CLOSURE, "discovery stopped") }
        webSockets.clear()
    }

    private companion object {
        const val DISCOVERY_WINDOW_MILLIS = 3_000L
        const val NORMAL_CLOSURE = 1000
        val DEFAULT_RELAYS = listOf(
            "wss://relay.damus.io",
            "wss://relay.8333.space/",
            "wss://nos.lol",
            "wss://relay.primal.net",
        )
    }
}

object NostrMintEventParser {
    private val json = Json { ignoreUnknownKeys = true }

    fun parseRelayMessage(jsonString: String): MintInfo? = runCatching {
        val envelope = json.parseToJsonElement(jsonString).jsonArray
        if (envelope.size < 3 || envelope[0].jsonPrimitive.contentOrNull != "EVENT") return null
        val event = envelope[2].jsonObject
        val kind = event["kind"]?.jsonPrimitive?.intOrNull
        if (kind != null && kind != 38172) return null

        val mintUrl = event["tags"]?.jsonArray
            ?.firstNotNullOfOrNull { tagElement ->
                val fields = tagElement.jsonArray.mapNotNull { it.jsonPrimitive.contentOrNull }
                fields.getOrNull(1)?.takeIf { fields.firstOrNull() == "u" }
            }
            ?.trim()
            ?.trimEnd('/')
            ?: return null
        if (!mintUrl.startsWith("http://", ignoreCase = true) && !mintUrl.startsWith("https://", ignoreCase = true)) {
            return null
        }

        val content = event["content"]?.jsonPrimitive?.contentOrNull
        val contentJson = content
            ?.let { runCatching { json.parseToJsonElement(it).jsonObject }.getOrNull() }
        MintInfo(
            url = mintUrl,
            name = contentJson?.get("name")?.jsonPrimitive?.contentOrNull ?: "Unknown Mint",
            description = contentJson?.get("description")?.jsonPrimitive?.contentOrNull,
        )
    }.getOrNull()
}
