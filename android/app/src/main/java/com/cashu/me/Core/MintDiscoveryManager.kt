package com.cashu.me.Core

import java.io.IOException
import java.net.URL
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.PaymentMethodKind

data class MintDiscoveryState(
    val discoveredMints: List<MintInfo> = emptyList(),
    val isDiscovering: Boolean = false,
    val hasCompletedDiscovery: Boolean = false,
)

interface MintDiscoverySettings {
    val useWebsockets: Boolean
    val nostrRelays: List<String>
}

fun interface MintPreviewFetcher {
    suspend fun fetch(mintUrl: String): MintInfo?
}

/**
 * Lightweight NUT-06 probe used only by discovery. It deliberately avoids CDK:
 * previewing an attacker-announced URL must not create a wallet or occupy the
 * repository's single serialized operation lane.
 */
class HttpMintPreviewFetcher(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(PREVIEW_TIMEOUT_MILLIS, TimeUnit.MILLISECONDS)
        .readTimeout(PREVIEW_TIMEOUT_MILLIS, TimeUnit.MILLISECONDS)
        .callTimeout(PREVIEW_TIMEOUT_MILLIS, TimeUnit.MILLISECONDS)
        .build(),
) : MintPreviewFetcher {
    override suspend fun fetch(mintUrl: String): MintInfo? {
        val request = runCatching {
            Request.Builder().url("${mintUrl.trimEnd('/')}/v1/info").get().build()
        }.getOrNull() ?: return null
        val result = CompletableDeferred<MintInfo?>()
        val call = client.newCall(request)
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                result.complete(null)
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    val preview = if (response.isSuccessful) {
                        response.body?.string()?.let { MintPreviewParser.parse(mintUrl, it) }
                    } else {
                        null
                    }
                    result.complete(preview)
                }
            }
        })
        return try {
            result.await()
        } finally {
            if (!result.isCompleted) call.cancel()
        }
    }

    private companion object {
        const val PREVIEW_TIMEOUT_MILLIS = 5_000L
    }
}

class MintDiscoveryManager(
    private val settings: MintDiscoverySettings,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build(),
    private val previewFetcher: MintPreviewFetcher = HttpMintPreviewFetcher(),
) {
    private val mutableState = MutableStateFlow(MintDiscoveryState())
    val state: StateFlow<MintDiscoveryState> = mutableState.asStateFlow()
    private val webSockets = CopyOnWriteArrayList<WebSocket>()
    private val metadataScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val discoveryGeneration = AtomicLong(0)
    private val relayDiscoveryActive = AtomicBoolean(false)
    private val pendingValidations = ConcurrentHashMap.newKeySet<ValidationKey>()
    private val validationJobs = ConcurrentHashMap<ValidationKey, Job>()
    private val previewPermits = Semaphore(PREVIEW_CONCURRENCY)

    suspend fun discoverMints(): List<MintInfo> {
        if (mutableState.value.isDiscovering) return mutableState.value.discoveredMints
        if (!settings.useWebsockets) return emptyList()

        val generation = discoveryGeneration.incrementAndGet()
        cancelPendingValidations()
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
        cancelPendingValidations()
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
        val job = metadataScope.launch(start = CoroutineStart.LAZY) {
            try {
                val fetched = previewPermits.withPermit {
                    runCatching { previewFetcher.fetch(discovered.url) }.onFailure {
                        AppLogger.wallet.error(
                            "Mint info validation failed for discovered mint ${discovered.url}",
                            it,
                        )
                    }.getOrNull()
                } ?: return@launch

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
                validationJobs.remove(validation)
                pendingValidations.remove(validation)
                if (discoveryGeneration.get() == validation.generation &&
                    !relayDiscoveryActive.get() &&
                    pendingValidations.none { it.generation == validation.generation }
                ) {
                    mutableState.update { it.copy(isDiscovering = false) }
                }
            }
        }
        validationJobs[validation] = job
        job.start()
    }

    private fun cancelPendingValidations() {
        validationJobs.values.forEach(Job::cancel)
        validationJobs.clear()
        pendingValidations.clear()
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
        const val PREVIEW_CONCURRENCY = 4
        val DEFAULT_RELAYS = listOf(
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://relay.primal.net",
        )
    }

    private data class ValidationKey(val generation: Long, val url: String)
}

internal object MintPreviewParser {
    private val json = Json { ignoreUnknownKeys = true }

    fun parse(mintUrl: String, jsonString: String): MintInfo? = runCatching {
        val root = json.parseToJsonElement(jsonString).jsonObject
        val mintSettings = root.nutMethods("4")
        val meltSettings = root.nutMethods("5")
        val mintMethods = mintSettings.mapNotNull { setting ->
            PaymentMethodKind.fromRaw(setting["method"]?.jsonPrimitive?.contentOrNull)
        }.distinctBy(PaymentMethodKind::rawValue)
        val meltMethods = meltSettings.mapNotNull { setting ->
            PaymentMethodKind.fromRaw(setting["method"]?.jsonPrimitive?.contentOrNull)
        }.distinctBy(PaymentMethodKind::rawValue)
        val mintUnits = mintSettings.map { setting ->
            setting["unit"]?.jsonPrimitive?.contentOrNull ?: "sat"
        }.distinct().sorted().ifEmpty { listOf("sat") }
        val units = (mintSettings + meltSettings).map { setting ->
            setting["unit"]?.jsonPrimitive?.contentOrNull ?: "sat"
        }.distinct().sorted().ifEmpty { listOf("sat") }

        MintInfo(
            url = mintUrl,
            name = root["name"]?.jsonPrimitive?.contentOrNull?.trim()?.takeIf(String::isNotBlank)
                ?: "Unknown Mint",
            description = root["description"]?.jsonPrimitive?.contentOrNull,
            iconUrl = root["icon_url"]?.jsonPrimitive?.contentOrNull
                ?: root["iconUrl"]?.jsonPrimitive?.contentOrNull,
            units = units,
            mintUnits = mintUnits,
            supportedMintMethods = mintMethods,
            supportedMeltMethods = meltMethods,
            supportsBolt12MintDescription = mintSettings.any { setting ->
                PaymentMethodKind.fromRaw(setting["method"]?.jsonPrimitive?.contentOrNull) ==
                    PaymentMethodKind.Bolt12 &&
                    (setting["options"]?.jsonObject?.get("description")
                        ?: setting["description"])?.jsonPrimitive?.booleanOrNull == true
            },
        )
    }.getOrNull()

    private fun JsonObject.nutMethods(number: String): List<JsonObject> {
        val nut = this["nuts"]?.jsonObject?.get(number)?.jsonObject ?: return emptyList()
        if (nut["disabled"]?.jsonPrimitive?.booleanOrNull == true) return emptyList()
        return nut["methods"]?.jsonArray.orEmpty().mapNotNull { element ->
            runCatching { element.jsonObject }.getOrNull()
        }
    }
}

internal fun canonicalDiscoveredMintUrl(rawUrl: String): String? {
    val trimmed = rawUrl.trim().trimEnd('/')
    val parsed = runCatching { URL(trimmed) }.getOrNull() ?: return null
    if (!parsed.protocol.equals("https", ignoreCase = true) || parsed.host.isNullOrBlank()) return null
    if (parsed.userInfo != null || parsed.query != null || parsed.ref != null) return null
    val port = parsed.port.takeIf { it != -1 }?.let { ":$it" }.orEmpty()
    val path = parsed.path.orEmpty().trimEnd('/')
    return "https://${parsed.host.lowercase()}$port$path"
}

object NostrMintEventParser {
    private val json = Json { ignoreUnknownKeys = true }

    fun parseRelayMessage(jsonString: String): MintInfo? = runCatching {
        val envelope = json.parseToJsonElement(jsonString).jsonArray
        if (envelope.size < 3 || envelope[0].jsonPrimitive.contentOrNull != "EVENT") return null
        val event = envelope[2].jsonObject
        if (event["kind"]?.jsonPrimitive?.intOrNull != 38172) return null

        val mintUrl = event["tags"]?.jsonArray
            ?.firstNotNullOfOrNull { tagElement ->
                val fields = tagElement.jsonArray.mapNotNull { it.jsonPrimitive.contentOrNull }
                fields.getOrNull(1)?.takeIf { fields.firstOrNull() == "u" }
            }
            ?.let(::canonicalDiscoveredMintUrl)
            ?: return null

        val content = event["content"]?.jsonPrimitive?.contentOrNull
        val contentJson = content
            ?.let { runCatching { json.parseToJsonElement(it).jsonObject }.getOrNull() }
        MintInfo(
            url = mintUrl,
            name = contentJson?.get("name")?.jsonPrimitive?.contentOrNull
                ?.trim()?.takeIf(String::isNotBlank) ?: "Unknown Mint",
            description = contentJson?.get("description")?.jsonPrimitive?.contentOrNull,
            iconUrl = contentJson?.get("icon_url")?.jsonPrimitive?.contentOrNull
                ?: contentJson?.get("iconUrl")?.jsonPrimitive?.contentOrNull,
        )
    }.getOrNull()
}

private fun MintInfo.mergedWithPreview(preview: MintInfo): MintInfo = copy(
    name = preview.name.takeIf { it.isNotBlank() && it != "Unknown Mint" } ?: name,
    description = preview.description ?: description,
    iconUrl = preview.iconUrl?.takeIf { it.isNotBlank() } ?: iconUrl,
    units = preview.units,
    mintUnits = preview.mintUnits,
    supportedMintMethods = preview.supportedMintMethods,
    supportedMeltMethods = preview.supportedMeltMethods,
    supportsBolt12MintDescription = preview.supportsBolt12MintDescription,
    onchainMintConfirmations = preview.onchainMintConfirmations,
    lastUpdatedEpochMillis = preview.lastUpdatedEpochMillis,
)
