package com.cashu.me.Core

import java.util.Base64
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import com.cashu.me.Core.Wallet.userFacingWalletMessage

data class CashuRequestListenerState(
    val isRunning: Boolean = false,
    val lastError: String? = null,
)

class CashuRequestListener(
    private val nostrService: NostrService,
    private val settingsManager: SettingsManager,
    private val walletManager: WalletManager,
    private val cashuRequestStore: CashuRequestStore,
    private val walletStore: WalletStore,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val processedEvents = ProcessedNip17EventTracker(
        load = walletStore::loadProcessedNip17GiftWraps,
        save = walletStore::saveProcessedNip17GiftWraps,
    )
    private var client: NostrInboxClient? = null
    private val retiringClients = mutableSetOf<NostrInboxClient>()
    private val listenerGeneration = AtomicLong()
    private var pausedForWalletBoundary = false
    private var startAfterRetirement = false
    private val mutableState = MutableStateFlow(CashuRequestListenerState())
    val state: StateFlow<CashuRequestListenerState> = mutableState.asStateFlow()

    @Synchronized
    fun start() {
        if (client != null || pausedForWalletBoundary) return
        if (retiringClients.isNotEmpty()) {
            startAfterRetirement = true
            return
        }
        val nostr = nostrService.state.value
        val privateKeyHex = nostrService.currentPrivateKey()
        if (!nostr.isInitialized || nostr.publicKeyHex.isBlank() || privateKeyHex.isNullOrBlank()) {
            mutableState.value = CashuRequestListenerState(lastError = "Nostr key is not initialized.")
            return
        }
        val relays = settingsManager.state.value.nostrRelays
            .map(String::trim)
            .filter { it.startsWith("ws://") || it.startsWith("wss://") }
            .distinct()
        if (relays.isEmpty()) {
            mutableState.value = CashuRequestListenerState(lastError = "No Nostr relays configured.")
            return
        }
        reloadProcessedIds()
        val since = subscriptionSince(System.currentTimeMillis() / 1000)
        val recipientPrivateKey = NIP44.hexToBytes(privateKeyHex)
        val generation = listenerGeneration.incrementAndGet()
        val newClient = NostrInboxClient(
            pubkeyHex = nostr.publicKeyHex,
            relays = relays,
            since = since,
        ) { event ->
            handle(event, recipientPrivateKey, generation)
        }
        client = newClient
        newClient.start()
        mutableState.value = CashuRequestListenerState(isRunning = true)
        AppLogger.wallet.info("CashuRequestListener: started on ${relays.size} relays since=$since")
    }

    fun stop() {
        val detached = synchronized(this) {
            startAfterRetirement = false
            detachClient()?.also { retiringClients += it }
        } ?: return
        detached.stop()
        scope.launch {
            detached.stopAndJoin()
            val shouldRestart = synchronized(this@CashuRequestListener) {
                retiringClients -= detached
                val requested = startAfterRetirement &&
                    retiringClients.isEmpty() &&
                    !pausedForWalletBoundary
                if (requested) startAfterRetirement = false
                requested
            }
            if (shouldRestart) start()
        }
    }

    suspend fun pauseForWalletBoundary() {
        quiesceForWalletBoundary()
    }

    suspend fun resetForWalletBoundary(restart: Boolean) {
        quiesceForWalletBoundary()
        processedEvents.clear()
        synchronized(this) {
            pausedForWalletBoundary = false
        }
        if (restart) start()
    }

    private suspend fun quiesceForWalletBoundary() {
        val clients = synchronized(this) {
            pausedForWalletBoundary = true
            startAfterRetirement = false
            detachClient()?.let { retiringClients += it }
            retiringClients.toList()
        }
        clients.forEach { it.stop() }
        clients.forEach { it.stopAndJoin() }
        synchronized(this) {
            retiringClients.removeAll(clients.toSet())
        }
    }

    /** Must be called while holding this listener's monitor. */
    private fun detachClient(): NostrInboxClient? {
        listenerGeneration.incrementAndGet()
        val detached = client
        client = null
        mutableState.value = CashuRequestListenerState(isRunning = false)
        return detached
    }

    private fun isCurrentGeneration(generation: Long): Boolean =
        listenerGeneration.get() == generation

    private suspend fun handle(
        event: NostrIncomingEvent,
        recipientPrivateKey: ByteArray,
        generation: Long,
    ) {
        if (!isCurrentGeneration(generation)) return
        if (event.kind != 1059) return
        if (!processedEvents.begin(event.id)) return

        var terminalOutcome = false
        try {
            if (!isCurrentGeneration(generation)) return
            val rumor = runCatching { NIP17.unwrap(event, recipientPrivateKey) }
                .onFailure { AppLogger.wallet.debug("CashuRequestListener: NIP-17 unwrap failed: ${it.message}") }
                .getOrNull()
            if (rumor == null || rumor.kind != 14) {
                terminalOutcome = true
                return
            }
            if (!isCurrentGeneration(generation)) return
            terminalOutcome = tryClaim(rumor.content, event.id, generation) != ClaimOutcome.TransientFailure
        } finally {
            processedEvents.finish(
                eventId = event.id,
                terminalOutcome = terminalOutcome && isCurrentGeneration(generation),
            )
        }
    }

    private suspend fun tryClaim(
        rumorContent: String,
        eventId: String,
        generation: Long,
    ): ClaimOutcome {
        val payload = runCatching { paymentPayloadToToken(rumorContent) }
            .onFailure { AppLogger.wallet.debug("CashuRequestListener: malformed PaymentRequestPayload") }
            .getOrNull() ?: return ClaimOutcome.Unclaimable
        return runCatching {
            val amount = walletManager.receiveCashuRequestPayment(
                tokenString = payload.token,
                requestId = payload.requestId,
                processedId = eventId,
            )
            if (amount > 0 && !payload.requestId.isNullOrBlank()) {
                cashuRequestStore.attachPayment(
                    requestId = payload.requestId,
                    transactionId = eventId,
                    amount = amount,
                )
            }
            ClaimOutcome.Claimed
        }.onFailure { error ->
            AppLogger.wallet.error("CashuRequestListener: redeem failed", error)
            if (isCurrentGeneration(generation)) {
                scope.launch {
                    if (isCurrentGeneration(generation)) {
                        mutableState.value = CashuRequestListenerState(
                            isRunning = mutableState.value.isRunning,
                            lastError = error.userFacingWalletMessage,
                        )
                    }
                }
            }
        }.getOrElse { ClaimOutcome.TransientFailure }
    }

    private fun reloadProcessedIds() {
        processedEvents.reload()
    }

    private enum class ClaimOutcome { Claimed, Unclaimable, TransientFailure }

    data class PaymentPayloadToken(
        val token: String,
        val requestId: String?,
    )

    companion object {
        internal const val LookbackSeconds = 7L * 24 * 60 * 60
        private val payloadJson = Json { ignoreUnknownKeys = true; encodeDefaults = true }

        internal fun subscriptionSince(nowEpochSeconds: Long): Long =
            nowEpochSeconds - LookbackSeconds

        fun paymentPayloadToToken(content: String): PaymentPayloadToken {
            val fields = payloadJson.parseToJsonElement(content).jsonObject
            val mintUrl = fields["mint"]?.jsonPrimitive?.contentOrNull
                ?: throw IllegalArgumentException("Payment payload mint missing.")
            val proofs = fields["proofs"]?.jsonArray
                ?: throw IllegalArgumentException("Payment payload proofs missing.")
            val unit = fields["unit"]?.jsonPrimitive?.contentOrNull ?: "sat"
            val memo = fields["memo"]?.jsonPrimitive?.contentOrNull
            val token = JsonObject(
                buildMap {
                    put(
                        "token",
                        JsonArray(
                            listOf(
                                JsonObject(
                                    mapOf(
                                        "mint" to JsonPrimitive(mintUrl),
                                        "proofs" to proofs,
                                    ),
                                ),
                            ),
                        ),
                    )
                    put("unit", JsonPrimitive(unit))
                    if (!memo.isNullOrBlank()) put("memo", JsonPrimitive(memo))
                },
            )
            val encoded = Base64.getUrlEncoder()
                .withoutPadding()
                .encodeToString(payloadJson.encodeToString(token).toByteArray(Charsets.UTF_8))
            return PaymentPayloadToken(
                token = "cashuA$encoded",
                requestId = fields["id"]?.jsonPrimitive?.contentOrNull,
            )
        }
    }
}

internal class ProcessedNip17EventTracker(
    private val load: () -> List<String>,
    private val save: (List<String>) -> Unit,
    private val maxProcessedIds: Int = 1_000,
) {
    private val lock = Any()
    private val processedIds = mutableSetOf<String>()
    private val processedOrder = mutableListOf<String>()
    private val inFlightIds = mutableSetOf<String>()

    init {
        require(maxProcessedIds > 0) { "maxProcessedIds must be positive." }
    }

    fun reload() {
        val stored = load().distinct().takeLast(maxProcessedIds)
        synchronized(lock) {
            processedOrder.clear()
            processedOrder.addAll(stored)
            processedIds.clear()
            processedIds.addAll(stored)
            inFlightIds.clear()
        }
    }

    fun clear() {
        synchronized(lock) {
            processedIds.clear()
            processedOrder.clear()
            inFlightIds.clear()
        }
    }

    fun begin(eventId: String): Boolean = synchronized(lock) {
        if (eventId in processedIds || eventId in inFlightIds) {
            false
        } else {
            inFlightIds += eventId
            true
        }
    }

    fun finish(eventId: String, terminalOutcome: Boolean) {
        synchronized(lock) {
            inFlightIds -= eventId
            if (!terminalOutcome || !processedIds.add(eventId)) return
            processedOrder += eventId
            if (processedOrder.size > maxProcessedIds) {
                val removed = processedOrder.removeAt(0)
                processedIds -= removed
            }
            save(processedOrder.toList())
        }
    }
}
