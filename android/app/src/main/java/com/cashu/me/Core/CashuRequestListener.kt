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
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
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
import com.cashu.me.Models.PendingReceiveToken
import com.cashu.me.Models.TokenInfo

data class CashuRequestListenerState(
    val isRunning: Boolean = false,
    val lastError: String? = null,
    val heldForApproval: PendingReceiveToken? = null,
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
    private val eventMutex = Mutex()
    private val heldClaimMutex = Mutex()
    private val mutableState = MutableStateFlow(CashuRequestListenerState())
    val state: StateFlow<CashuRequestListenerState> = mutableState.asStateFlow()

    @Synchronized
    fun start() {
        if (!settingsManager.state.value.enablePaymentRequests) {
            stop()
            return
        }
        if (client != null || pausedForWalletBoundary) return
        if (retiringClients.isNotEmpty()) {
            startAfterRetirement = true
            return
        }
        val nostr = nostrService.state.value
        val privateKeyHex = nostrService.currentPrivateKey()
        if (!nostr.isInitialized || nostr.publicKeyHex.isBlank() || privateKeyHex.isNullOrBlank()) {
            mutableState.value = mutableState.value.copy(
                isRunning = false,
                lastError = "Nostr key is not initialized.",
            )
            return
        }
        val relays = CashuRequestNostrReadiness.normalizedRelays(
            settingsManager.state.value.nostrRelays,
        )
        if (relays.isEmpty()) {
            mutableState.value = mutableState.value.copy(
                isRunning = false,
                lastError = "No Nostr relays configured.",
            )
            return
        }
        processedEvents.reload()
        val since = lookbackSince(System.currentTimeMillis() / 1000)
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
        mutableState.value = mutableState.value.copy(isRunning = true, lastError = null)
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
        mutableState.value = CashuRequestListenerState()
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
        mutableState.value = mutableState.value.copy(isRunning = false)
        return detached
    }

    private fun isCurrentGeneration(generation: Long): Boolean =
        listenerGeneration.get() == generation

    fun dismissHeldPayment() {
        mutableState.value = mutableState.value.copy(heldForApproval = null)
    }

    private suspend fun handle(
        event: NostrIncomingEvent,
        recipientPrivateKey: ByteArray,
        generation: Long,
    ) {
        if (!isCurrentGeneration(generation)) return
        eventMutex.withLock {
            if (!isCurrentGeneration(generation)) return@withLock
            if (event.kind != 1059) return@withLock
            if (!processedEvents.begin(event.id)) return@withLock

            var terminalOutcome = false
            try {
                if (!isCurrentGeneration(generation)) return@withLock
                val rumor = runCatching { NIP17.unwrap(event, recipientPrivateKey) }
                    .onFailure {
                        AppLogger.wallet.debug(
                            "CashuRequestListener: NIP-17 unwrap failed: ${it.message}",
                        )
                    }
                    .getOrNull()
                if (rumor == null || rumor.kind != 14) {
                    terminalOutcome = true
                    return@withLock
                }
                if (!isCurrentGeneration(generation)) return@withLock
                terminalOutcome = shouldMarkProcessed(
                    tryClaim(rumor.content, event.id, generation),
                )
            } finally {
                processedEvents.finish(
                    eventId = event.id,
                    terminalOutcome = terminalOutcome && isCurrentGeneration(generation),
                )
            }
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
        val info = TokenInfo.parse(payload.token) ?: return ClaimOutcome.Unclaimable
        val shouldAutoClaim = shouldAutoClaim(
            autoClaimEnabled = settingsManager.state.value.receivePaymentRequestsAutomatically,
            mintKnown = walletManager.isMintKnown(info.mint),
        )
        if (!shouldAutoClaim) {
            return holdForApproval(payload, info, eventId, generation)
        }
        return runCatching {
            val amount = walletManager.receiveCashuRequestPayment(
                tokenString = payload.token,
                requestId = payload.requestId,
                processedId = eventId,
                confirmationOwner = ReceiveConfirmationOwner.Home,
            )
            if (amount > 0 && !payload.requestId.isNullOrBlank()) {
                cashuRequestStore.attachPayment(
                    requestId = payload.requestId,
                    transactionId = eventId,
                    amount = amount,
                )
            }
            ClaimOutcome.Claimed
        }.getOrElse { error ->
            AppLogger.wallet.error(
                "CashuRequestListener: redeem failed; payment remains retryable",
                error,
            )
            if (isCurrentGeneration(generation)) {
                scope.launch(Dispatchers.Main.immediate) {
                    if (isCurrentGeneration(generation)) {
                        mutableState.value = mutableState.value.copy(
                            lastError = error.userFacingWalletMessage,
                        )
                    }
                }
            }
            ClaimOutcome.TransientFailure
        }
    }

    private suspend fun holdForApproval(
        payload: PaymentPayloadToken,
        info: TokenInfo,
        eventId: String,
        generation: Long,
    ): ClaimOutcome {
        val existing = walletManager.state.value.pendingReceiveTokens
            .firstOrNull { it.token == payload.token }
        if (existing != null) {
            if (isCurrentGeneration(generation)) {
                mutableState.value = mutableState.value.copy(heldForApproval = existing)
            }
            return ClaimOutcome.Held
        }

        val listenerHeldCount = walletManager.state.value.pendingReceiveTokens.count {
            it.isCashuRequestPayment
        }
        if (listenerHeldCount >= MaxHeldPayments) {
            AppLogger.wallet.info("CashuRequestListener: approval backlog full; deferring payment")
            return ClaimOutcome.TransientFailure
        }

        val pending = PendingReceiveToken(
            tokenId = payload.token.take(64),
            token = payload.token,
            amount = info.amount,
            dateEpochMillis = System.currentTimeMillis(),
            mintUrl = info.mint,
            unit = info.unit,
            cashuRequestId = payload.requestId,
            processedId = eventId,
            memo = info.memo,
        )
        return runCatching {
            walletManager.savePendingReceiveToken(pending)
            walletManager.loadTransactions()
            if (isCurrentGeneration(generation)) {
                mutableState.value = mutableState.value.copy(
                    lastError = null,
                    heldForApproval = pending,
                )
            }
            AppLogger.wallet.info("CashuRequestListener: payment held for explicit approval")
            ClaimOutcome.Held
        }.getOrElse { error ->
            AppLogger.wallet.error("CashuRequestListener: failed to persist held payment", error)
            ClaimOutcome.TransientFailure
        }
    }

    suspend fun claimHeldPayment(pending: PendingReceiveToken): Long {
        val amount = heldClaimMutex.withLock {
            walletManager.claimPendingReceiveToken(pending)
        }
        if (mutableState.value.heldForApproval?.tokenId == pending.tokenId) {
            mutableState.value = mutableState.value.copy(heldForApproval = null)
        }
        claimEligibleHeldPayments()
        return amount
    }

    fun declineHeldPayment(pending: PendingReceiveToken) {
        walletManager.removePendingReceiveToken(pending.tokenId)
        if (mutableState.value.heldForApproval?.tokenId == pending.tokenId) {
            mutableState.value = mutableState.value.copy(heldForApproval = null)
        }
        scope.launch { walletManager.loadTransactions() }
    }

    suspend fun claimEligibleHeldPayments() {
        if (!settingsManager.state.value.receivePaymentRequestsAutomatically) return
        heldClaimMutex.withLock {
            val eligible = walletManager.state.value.pendingReceiveTokens.filter { pending ->
                shouldClaimHeldPayment(
                    autoClaimEnabled = settingsManager.state.value.receivePaymentRequestsAutomatically,
                    listenerHeld = pending.isCashuRequestPayment,
                    mintKnown = walletManager.isMintKnown(pending.mintUrl),
                )
            }
            for (pending in eligible) {
                runCatching { walletManager.claimPendingReceiveToken(pending) }
                    .onSuccess {
                        if (mutableState.value.heldForApproval?.tokenId == pending.tokenId) {
                            mutableState.value = mutableState.value.copy(heldForApproval = null)
                        }
                    }
                    .onFailure {
                        AppLogger.wallet.error(
                            "CashuRequestListener: held-payment claim failed; leaving it in History",
                            it,
                        )
                    }
            }
        }
    }

    fun claimEligibleHeldPaymentsAsync() {
        scope.launch { claimEligibleHeldPayments() }
    }

    data class PaymentPayloadToken(
        val token: String,
        val requestId: String?,
    )

    internal enum class ClaimOutcome {
        Claimed,
        Unclaimable,
        TransientFailure,
        Held,
    }

    companion object {
        internal const val MaxHeldPayments = 50
        internal const val LookbackWindowSeconds = 7 * 24 * 60 * 60L
        private val payloadJson = Json { ignoreUnknownKeys = true; encodeDefaults = true }

        internal fun shouldAutoClaim(autoClaimEnabled: Boolean, mintKnown: Boolean): Boolean =
            autoClaimEnabled && mintKnown

        internal fun shouldClaimHeldPayment(
            autoClaimEnabled: Boolean,
            listenerHeld: Boolean,
            mintKnown: Boolean,
        ): Boolean = autoClaimEnabled && listenerHeld && mintKnown

        internal fun shouldMarkProcessed(outcome: ClaimOutcome): Boolean =
            outcome != ClaimOutcome.TransientFailure

        internal fun lookbackSince(nowEpochSeconds: Long): Long =
            nowEpochSeconds - LookbackWindowSeconds

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
