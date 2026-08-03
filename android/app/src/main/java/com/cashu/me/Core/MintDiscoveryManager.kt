package com.cashu.me.Core

import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
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
import com.cashu.me.Core.CDK.CdkWalletGateway
import com.cashu.me.Models.MintInfo

data class MintDiscoveryState(
    val discoveredMints: List<MintInfo> = emptyList(),
    val isDiscovering: Boolean = false,
    val hasCompletedDiscovery: Boolean = false,
)

interface MintDiscoverySettings {
    val useWebsockets: Boolean
    val nostrRelays: List<String>
}

class MintDiscoveryManager(
    private val settings: MintDiscoverySettings,
    private val gateway: CdkWalletGateway,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build(),
) {
    private val mutableState = MutableStateFlow(MintDiscoveryState())
    val state: StateFlow<MintDiscoveryState> = mutableState.asStateFlow()
    private val webSockets = CopyOnWriteArrayList<WebSocket>()
    private val metadataScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val discoveryGeneration = AtomicLong(0)
    private val relayDiscoveryActive = AtomicBoolean(false)
    private val pendingValidations = ConcurrentHashMap.newKeySet<ValidationKey>()

    suspend fun discoverMints(): List<MintInfo> {
        if (mutableState.value.isDiscovering) return mutableState.value.discoveredMints
        if (!settings.useWebsockets) return emptyList()

        val generation = discoveryGeneration.incrementAndGet()
        pendingValidations.clear()
        relayDiscoveryActive.set(true)
        closeAllConnections()
        mutableState.value = MintDiscoveryState(isDiscovering = true)
        return try {
            withContext(Dispatchers.IO) {
                configuredRelays()
                    .map { relay -> async { connectAndQuery(relay, generation) } }
                    .awaitAll()
            }
            mutableState.value.discoveredMints
        } finally {
            closeAllConnections()
            if (discoveryGeneration.get() == generation) {
                relayDiscoveryActive.set(false)
                mutableState.update {
                    it.copy(
                        isDiscovering = pendingValidations.any { pending -> pending.generation == generation },
                        hasCompletedDiscovery = true,
                    )
                }
            }
        }
    }

    fun clearDiscoveredMints() {
        discoveryGeneration.incrementAndGet()
        relayDiscoveryActive.set(false)
        pendingValidations.clear()
        closeAllConnections()
        mutableState.value = MintDiscoveryState()
    }

    private suspend fun connectAndQuery(relay: String, generation: Long) {
        val request = runCatching { Request.Builder().url(relay).build() }.getOrNull() ?: return
        val closed = CompletableDeferred<Unit>()
        val subscriptionId = UUID.randomUUID().toString()
        val listener = object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                webSocket.send("""["REQ","$subscriptionId",{"kinds":[38172],"limit":50}]""")
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handleRelayMessage(text, generation)
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                handleRelayMessage(bytes.utf8(), generation)
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

    private fun handleRelayMessage(message: String, generation: Long) {
        if (discoveryGeneration.get() != generation) return
        val discovered = NostrMintEventParser.parseRelayMessage(message) ?: return
        val validation = ValidationKey(generation, discovered.url)
        if (mutableState.value.discoveredMints.any { it.url == discovered.url }) return
        if (!pendingValidations.add(validation)) return

        mutableState.update { it.copy(isDiscovering = true) }
        fetchMintPreview(discovered, validation)
    }

    private fun fetchMintPreview(discovered: MintInfo, validation: ValidationKey) {
        metadataScope.launch {
            try {
                val fetched = runCatching {
                    gateway.ensureWallet(discovered.url)
                    gateway.fetchMintInfo(discovered.url)
                }.onFailure {
                    AppLogger.wallet.error(
                        "Mint info validation failed for discovered mint ${discovered.url}",
                        it,
                    )
                }.getOrNull() ?: return@launch

                if (discoveryGeneration.get() != validation.generation) return@launch
                mutableState.update { current ->
                    if (current.discoveredMints.any { it.url == discovered.url }) {
                        current
                    } else {
                        current.copy(
                            discoveredMints = current.discoveredMints + discovered.mergedWithPreview(fetched),
                        )
                    }
                }
            } finally {
                pendingValidations.remove(validation)
                if (discoveryGeneration.get() == validation.generation &&
                    !relayDiscoveryActive.get() &&
                    pendingValidations.none { it.generation == validation.generation }
                ) {
                    mutableState.update { it.copy(isDiscovering = false) }
                }
            }
        }
    }

    private fun configuredRelays(): List<String> {
        val configured = settings.nostrRelays
            .map { it.trim() }
            .filter(::isSupportedRelayScheme)
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
            "wss://nos.lol",
            "wss://relay.primal.net",
        )
    }

    private data class ValidationKey(val generation: Long, val url: String)
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
            iconUrl = contentJson?.get("icon_url")?.jsonPrimitive?.contentOrNull
                ?: contentJson?.get("iconUrl")?.jsonPrimitive?.contentOrNull,
        )
    }.getOrNull()
}

private fun MintInfo.mergedWithPreview(preview: MintInfo): MintInfo = copy(
    name = preview.name.takeIf { it.isNotBlank() } ?: name,
    description = preview.description ?: description,
    iconUrl = preview.iconUrl?.takeIf { it.isNotBlank() } ?: iconUrl,
    units = preview.units,
    mintUnits = preview.mintUnits,
    supportedMintMethods = preview.supportedMintMethods,
    supportedMeltMethods = preview.supportedMeltMethods,
    onchainMintConfirmations = preview.onchainMintConfirmations,
    lastUpdatedEpochMillis = preview.lastUpdatedEpochMillis,
)
