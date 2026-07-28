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
    context: Context,
    private val nostrService: NostrService,
    private val settingsManager: SettingsManager,
    private val walletManager: WalletManager,
    private val cashuRequestStore: CashuRequestStore,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val metadataStore = DataStorePreferenceStore(context.applicationContext, "settings_store")
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val sinceKey = "cashuRequests.nip17.since.v1"
    private var client: NostrInboxClient? = null
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
        val since = metadataStore.long(sinceKey, (System.currentTimeMillis() / 1000) - 48 * 60 * 60)
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
        if (event.kind != 1059) return
        metadataStore.putLong(sinceKey, event.createdAt)
        client?.updateSince(event.createdAt)
        val rumor = runCatching { NIP17.unwrap(event, recipientPrivateKey) }
            .onFailure { AppLogger.wallet.debug("CashuRequestListener: NIP-17 unwrap failed: ${it.message}") }
            .getOrNull() ?: return
        if (rumor.kind != 14) return
        tryClaim(rumor.content, event.id)
    }

    private suspend fun tryClaim(rumorContent: String, eventId: String) {
        val payload = runCatching { paymentPayloadToToken(rumorContent) }
            .onFailure { AppLogger.wallet.debug("CashuRequestListener: malformed PaymentRequestPayload") }
            .getOrNull() ?: return
        val info = TokenInfo.parse(payload.token) ?: return
        val shouldAutoClaim = shouldAutoClaim(
            autoClaimEnabled = settingsManager.state.value.receivePaymentRequestsAutomatically,
            mintKnown = walletManager.isMintKnown(info.mint),
        )
        if (!shouldAutoClaim) {
            holdForApproval(payload, info, eventId)
            return
        }
        runCatching {
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
        }.onFailure { error ->
            AppLogger.wallet.error("CashuRequestListener: redeem failed", error)
            scope.launch {
                mutableState.value = CashuRequestListenerState(
                    isRunning = client != null,
                    lastError = error.userFacingWalletMessage,
                    heldForApproval = mutableState.value.heldForApproval,
                )
            }
        }
    }

    private suspend fun holdForApproval(
        payload: PaymentPayloadToken,
        info: TokenInfo,
        eventId: String,
    ) {
        val existing = walletManager.state.value.pendingReceiveTokens
            .firstOrNull { it.token == payload.token }
        if (existing != null) {
            mutableState.value = mutableState.value.copy(heldForApproval = existing)
            return
        }

        val listenerHeldCount = walletManager.state.value.pendingReceiveTokens.count {
            it.cashuRequestId != null || it.processedId != null
        }
        if (listenerHeldCount >= MaxHeldPayments) {
            AppLogger.wallet.info("CashuRequestListener: approval backlog full; deferring payment")
            return
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
        walletManager.savePendingReceiveToken(pending)
        walletManager.loadTransactions()
        mutableState.value = mutableState.value.copy(
            lastError = null,
            heldForApproval = pending,
        )
        AppLogger.wallet.info("CashuRequestListener: payment held for explicit approval")
    }

    data class PaymentPayloadToken(
        val token: String,
        val requestId: String?,
    )

    companion object {
        private const val MaxHeldPayments = 50
        private val payloadJson = Json { ignoreUnknownKeys = true; encodeDefaults = true }

        internal fun shouldAutoClaim(autoClaimEnabled: Boolean, mintKnown: Boolean): Boolean =
            autoClaimEnabled && mintKnown

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
