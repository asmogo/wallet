package org.cashu.wallet.Core

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

data class CashuRequestListenerState(
    val isRunning: Boolean = false,
    val lastError: String? = null,
)

class CashuRequestListener(
    context: Context,
    private val nostrService: NostrService,
    private val settingsManager: SettingsManager,
    private val walletManager: WalletManager,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val metadataStore = DataStorePreferenceStore(context.applicationContext, "settings_store")
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val sinceKey = "cashuRequests.nip17.since.v1"
    private var client: NostrInboxClient? = null
    private val mutableState = MutableStateFlow(CashuRequestListenerState())
    val state: StateFlow<CashuRequestListenerState> = mutableState.asStateFlow()

    fun start() {
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
        mutableState.value = CashuRequestListenerState(isRunning = true)
        AppLogger.wallet.info("CashuRequestListener: started on ${relays.size} relays since=$since")
    }

    fun stop() {
        client?.stop()
        client = null
        mutableState.value = CashuRequestListenerState(isRunning = false)
    }

    private suspend fun handle(event: NostrIncomingEvent, recipientPrivateKey: ByteArray) {
        if (event.kind != 1059) return
        metadataStore.putLong(sinceKey, event.createdAt)
        client?.updateSince(event.createdAt)
        val rumor = runCatching { NIP17.unwrap(event, recipientPrivateKey) }
            .onFailure { AppLogger.wallet.debug("CashuRequestListener: NIP-17 unwrap failed: ${it.message}") }
            .getOrNull() ?: return
        if (rumor.kind != 14) return
        tryClaim(rumor.content)
    }

    private suspend fun tryClaim(rumorContent: String) {
        val payload = runCatching { paymentPayloadToToken(rumorContent) }
            .onFailure { AppLogger.wallet.debug("CashuRequestListener: malformed PaymentRequestPayload") }
            .getOrNull() ?: return
        runCatching {
            walletManager.receiveCashuRequestPayment(
                tokenString = payload.token,
                requestId = payload.requestId,
            )
        }.onFailure { error ->
            AppLogger.wallet.error("CashuRequestListener: redeem failed", error)
            scope.launch {
                mutableState.value = CashuRequestListenerState(
                    isRunning = client != null,
                    lastError = error.message ?: "Failed to redeem Cashu request payment.",
                )
            }
        }
    }

    data class PaymentPayloadToken(
        val token: String,
        val requestId: String?,
    )

    companion object {
        private val payloadJson = Json { ignoreUnknownKeys = true; encodeDefaults = true }

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
