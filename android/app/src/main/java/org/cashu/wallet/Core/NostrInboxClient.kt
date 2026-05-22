package org.cashu.wallet.Core

import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

class NostrInboxClient(
    private val pubkeyHex: String,
    private val relays: List<String>,
    since: Long,
    private val onEvent: suspend (NostrIncomingEvent) -> Unit,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS)
        .build()
    private val json = Json { ignoreUnknownKeys = true }
    private val subId = "cashu-inbox-${UUID.randomUUID().toString().take(8).lowercase()}"
    private val sockets = mutableSetOf<WebSocket>()
    @Volatile
    private var running = false
    @Volatile
    private var sinceTimestamp = since

    fun start() {
        if (running) return
        running = true
        relays.distinct().forEach { relay ->
            scope.launch { connectLoop(relay) }
        }
    }

    fun stop() {
        running = false
        scope.coroutineContext.cancelChildren()
        synchronized(sockets) {
            sockets.forEach { it.close(1000, "closed") }
            sockets.clear()
        }
    }

    fun updateSince(timestamp: Long) {
        if (timestamp > sinceTimestamp) sinceTimestamp = timestamp
    }

    private suspend fun connectLoop(relay: String) {
        var attempt = 0
        while (running) {
            connect(relay)
            if (!running) break
            attempt += 1
            delay(minOf(30, 1 shl minOf(attempt, 5)) * 1_000L)
        }
    }

    private suspend fun connect(relay: String) {
        val request = runCatching { Request.Builder().url(relay).build() }.getOrNull() ?: return
        val listener = InboxWebSocketListener()
        val socket = client.newWebSocket(request, listener)
        synchronized(sockets) { sockets += socket }
        listener.awaitClosed()
        synchronized(sockets) { sockets -= socket }
    }

    private fun subscribe(socket: WebSocket) {
        val requestJson = """["REQ","$subId",{"kinds":[1059],"#p":["$pubkeyHex"],"since":$sinceTimestamp}]"""
        socket.send(requestJson)
    }

    private suspend fun handleMessage(text: String) {
        val array = runCatching { json.parseToJsonElement(text).jsonArray }.getOrNull() ?: return
        val messageType = array.firstOrNull()?.jsonPrimitive?.content ?: return
        if (messageType != "EVENT" || array.size < 3) return
        val event = runCatching {
            json.decodeFromJsonElement<NostrIncomingEvent>(array[2].jsonObject)
        }.getOrNull() ?: return
        updateSince(event.createdAt)
        onEvent(event)
    }

    private inner class InboxWebSocketListener : WebSocketListener() {
        private val closed = kotlinx.coroutines.CompletableDeferred<Unit>()

        override fun onOpen(webSocket: WebSocket, response: Response) {
            subscribe(webSocket)
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            scope.launch { handleMessage(text) }
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            closed.complete(Unit)
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            AppLogger.network.error("Nostr inbox relay failed", t)
            closed.complete(Unit)
        }

        suspend fun awaitClosed() {
            closed.await()
        }
    }
}
