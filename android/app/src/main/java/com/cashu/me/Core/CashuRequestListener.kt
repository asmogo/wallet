package com.cashu.me.Core

import android.content.Context
import java.util.Base64
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import com.cashu.me.Core.Protocols.StorageKeys
import com.cashu.me.Core.Wallet.userFacingWalletMessage
import com.cashu.me.Models.PendingReceiveToken
import com.cashu.me.Models.TokenInfo

data class CashuRequestListenerState(
    val isRunning: Boolean = false,
    val lastError: String? = null,
    val heldForApproval: PendingReceiveToken? = null,
)

class CashuRequestListener(
    context: Context,
    private val nostrService: NostrService,
    private val settingsManager: SettingsManager,
    private val walletManager: WalletManager,
    private val cashuRequestStore: CashuRequestStore,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val metadataStore = DataStorePreferenceStore(context.applicationContext, "settings_store")
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private var client: NostrInboxClient? = null
    private val eventMutex = Mutex()
    private val heldClaimMutex = Mutex()
    private var processedIds: Set<String> = emptySet()
    private var processedOrder: List<String> = emptyList()
    private val mutableState = MutableStateFlow(CashuRequestListenerState())
    val state: StateFlow<CashuRequestListenerState> = mutableState.asStateFlow()

    fun start() {
        if (!settingsManager.state.value.enablePaymentRequests) {
            stop()
            return
        }
        if (client != null) return
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
        loadProcessedIds()
        // The old moving cursor is unsafe for NIP-59 gift wraps because their
        // created_at values are deliberately backdated. Always re-scan a fixed
        // window and de-duplicate by event id instead.
        metadataStore.removeKeys(listOf(LegacySinceKey))
        val since = lookbackSince(System.currentTimeMillis() / 1000)
        val recipientPrivateKey = NIP44.hexToBytes(privateKeyHex)
        client = NostrInboxClient(
            pubkeyHex = nostr.publicKeyHex,
            relays = relays,
            since = since,
        ) { event ->
            handle(event, recipientPrivateKey)
        }.also { it.start() }
        mutableState.value = mutableState.value.copy(isRunning = true, lastError = null)
        AppLogger.wallet.info("CashuRequestListener: started on ${relays.size} relays since=$since")
    }

    fun stop() {
        client?.stop()
        client = null
        mutableState.value = mutableState.value.copy(isRunning = false)
    }

    fun dismissHeldPayment() {
        mutableState.value = mutableState.value.copy(heldForApproval = null)
    }

    private suspend fun handle(event: NostrIncomingEvent, recipientPrivateKey: ByteArray) {
        eventMutex.withLock {
            if (event.kind != 1059) return
            if (event.id in processedIds) return
            val rumor = runCatching { NIP17.unwrap(event, recipientPrivateKey) }
                .onFailure { AppLogger.wallet.debug("CashuRequestListener: NIP-17 unwrap failed: ${it.message}") }
                .getOrNull()
            if (rumor == null || rumor.kind != 14) {
                markProcessed(event.id)
                return
            }
            if (shouldMarkProcessed(tryClaim(rumor.content, event.id))) {
                markProcessed(event.id)
            }
        }
    }

    private suspend fun tryClaim(rumorContent: String, eventId: String): ClaimOutcome {
        val payload = runCatching { paymentPayloadToToken(rumorContent) }
            .onFailure { AppLogger.wallet.debug("CashuRequestListener: malformed PaymentRequestPayload") }
            .getOrNull() ?: return ClaimOutcome.Unclaimable
        val info = TokenInfo.parse(payload.token) ?: return ClaimOutcome.Unclaimable
        val shouldAutoClaim = shouldAutoClaim(
            autoClaimEnabled = settingsManager.state.value.receivePaymentRequestsAutomatically,
            mintKnown = walletManager.isMintKnown(info.mint),
        )
        if (!shouldAutoClaim) {
            return holdForApproval(payload, info, eventId)
        }
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
        }.getOrElse { error ->
            AppLogger.wallet.error("CashuRequestListener: redeem failed; payment remains retryable", error)
            scope.launch(Dispatchers.Main.immediate) {
                mutableState.value = CashuRequestListenerState(
                    isRunning = client != null,
                    lastError = error.userFacingWalletMessage,
                    heldForApproval = mutableState.value.heldForApproval,
                )
            }
            ClaimOutcome.TransientFailure
        }
    }

    private suspend fun holdForApproval(
        payload: PaymentPayloadToken,
        info: TokenInfo,
        eventId: String,
    ): ClaimOutcome {
        val existing = walletManager.state.value.pendingReceiveTokens
            .firstOrNull { it.token == payload.token }
        if (existing != null) {
            mutableState.value = mutableState.value.copy(heldForApproval = existing)
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
        )
        return runCatching {
            walletManager.savePendingReceiveToken(pending)
            walletManager.loadTransactions()
            mutableState.value = mutableState.value.copy(
                lastError = null,
                heldForApproval = pending,
            )
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

    private fun loadProcessedIds() {
        val stored = metadataStore.string(StorageKeys.cashuRequestsProcessedNip17Ids)
            ?.let { raw -> runCatching { json.decodeFromString<List<String>>(raw) }.getOrNull() }
            .orEmpty()
            .takeLast(MaxProcessedIds)
        processedOrder = stored.distinct()
        processedIds = processedOrder.toSet()
    }

    private fun markProcessed(id: String) {
        processedOrder = appendProcessedId(processedOrder, id, MaxProcessedIds)
        processedIds = processedOrder.toSet()
        metadataStore.putString(
            StorageKeys.cashuRequestsProcessedNip17Ids,
            json.encodeToString(processedOrder),
        )
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
        internal const val MaxProcessedIds = 1_000
        internal const val LookbackWindowSeconds = 7 * 24 * 60 * 60L
        private const val LegacySinceKey = "cashuRequests.nip17.since.v1"
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

        internal fun appendProcessedId(
            current: List<String>,
            id: String,
            limit: Int,
        ): List<String> {
            if (id in current) return current
            return (current + id).takeLast(limit)
        }

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
