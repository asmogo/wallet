package org.cashu.wallet.Core

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.cashu.wallet.Core.Protocols.StorageKeys

data class NPCQuote(
    val id: String,
    val amount: Long,
    val mintUrl: String?,
    val request: String? = null,
    val state: String?,
    val locked: Boolean,
    val createdAtEpochSeconds: Long?,
    val paidAtEpochSeconds: Long?,
    val expiryEpochSeconds: Long? = null,
) {
    val isPaid: Boolean get() = state.equals("PAID", ignoreCase = true)
}

data class NPCState(
    val isEnabled: Boolean = false,
    val automaticClaim: Boolean = true,
    val selectedMintUrl: String? = null,
    val lastCheckEpochMillis: Long? = null,
    val lightningAddress: String = "",
    val configuredMintUrl: String = "",
    val isInitialized: Boolean = false,
    val isConnected: Boolean = false,
    val isLoading: Boolean = false,
    val isCheckingPayments: Boolean = false,
    val errorMessage: String? = null,
    val pendingPaidQuotes: List<NPCQuote> = emptyList(),
)

interface NPCQuoteClaimHandler {
    fun isNPCQuoteProcessed(quoteId: String): Boolean
    suspend fun claimNPCQuote(quote: NPCQuote, p2pkPubkey: String?): Boolean
}

class NPCService(
    context: Context,
    private val nostrService: NostrService,
    private val settingsManager: SettingsManager,
) {
    private val prefs = context.applicationContext.getSharedPreferences("npc_store", Context.MODE_PRIVATE)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val client = OkHttpClient()
    private val json = Json { ignoreUnknownKeys = true }
    private val baseUrl = "https://npubx.cash"
    private val domain = "npubx.cash"
    private val refreshIntervalMillis = 120_000L
    private var refreshJob: Job? = null
    private var paymentCheckJob: Job? = null
    var quoteClaimHandler: NPCQuoteClaimHandler? = null

    private val mutableState = MutableStateFlow(loadInitialState())
    val state: StateFlow<NPCState> = mutableState.asStateFlow()

    init {
        scope.launch {
            nostrService.state.collect { nostr ->
                val lightningAddress = nostrService.seedDerivedLightningAddress(domain)
                update {
                    copy(
                        lightningAddress = lightningAddress,
                        isInitialized = nostr.isInitialized && nostrService.hasSeedDerivedKey(),
                    )
                }
                if (mutableState.value.isEnabled && nostr.isInitialized) {
                    connect()
                }
            }
        }
        scope.launch {
            settingsManager.state.collect {
                applyPollingPreferences()
            }
        }
    }

    fun setEnabled(value: Boolean) {
        prefs.edit().putBoolean(StorageKeys.npcEnabled, value).apply()
        update { copy(isEnabled = value, errorMessage = null) }
        if (value) {
            scope.launch { connect() }
        } else {
            disconnect()
        }
    }

    fun setAutomaticClaim(value: Boolean) {
        prefs.edit().putBoolean(StorageKeys.npcAutomaticClaim, value).apply()
        update { copy(automaticClaim = value) }
    }

    fun changeMint(mintUrl: String) {
        scope.launch {
            update { copy(isLoading = true, errorMessage = null) }
            val result = runCatching {
                setRemoteMint(mintUrl)
            }
            result.onSuccess { configuredMint ->
                val selected = configuredMint ?: mintUrl
                prefs.edit().putString(StorageKeys.npcSelectedMint, selected).apply()
                update {
                    copy(
                        selectedMintUrl = selected,
                        configuredMintUrl = selected,
                        isLoading = false,
                        isConnected = true,
                        errorMessage = null,
                    )
                }
            }.onFailure { error ->
                update {
                    copy(
                        selectedMintUrl = mintUrl,
                        configuredMintUrl = configuredMintUrl,
                        isLoading = false,
                        errorMessage = error.message ?: "Failed to update npub.cash mint.",
                    )
                }
                prefs.edit().putString(StorageKeys.npcSelectedMint, mintUrl).apply()
            }
        }
    }

    fun checkAndClaimPayments() {
        if (paymentCheckJob?.isActive == true) return
        paymentCheckJob = scope.launch { checkAndClaimPaymentsNow() }
    }

    fun resetForWalletBoundary() {
        stopBackgroundRefresh()
        prefs.edit()
            .remove(StorageKeys.npcEnabled)
            .remove(StorageKeys.npcAutomaticClaim)
            .remove(StorageKeys.npcSelectedMint)
            .remove(StorageKeys.npcLastCheck)
            .apply()
        mutableState.value = NPCState()
    }

    private suspend fun connect() {
        val current = mutableState.value
        if (!current.isEnabled || !current.isInitialized) {
            update {
                copy(
                    isConnected = false,
                    errorMessage = if (current.isEnabled) "Nostr keys are not initialized." else null,
                )
            }
            return
        }
        update { copy(isLoading = true, errorMessage = null) }
        val result = runCatching {
            fetchQuotes()
        }
        result.onSuccess { quotes ->
            val configured = mutableState.value.selectedMintUrl
                ?: quotes.firstNotNullOfOrNull { it.mintUrl }
                ?: ""
            if (configured.isNotBlank()) prefs.edit().putString(StorageKeys.npcSelectedMint, configured).apply()
            update {
                copy(
                    configuredMintUrl = configured,
                    selectedMintUrl = configured.ifBlank { selectedMintUrl },
                    isConnected = true,
                    isLoading = false,
                    errorMessage = null,
                )
            }
            applyPollingPreferences()
        }.onFailure { error ->
            update {
                copy(
                    isConnected = false,
                    isLoading = false,
                    errorMessage = error.message ?: "Not connected to npub.cash.",
                )
            }
        }
    }

    private fun disconnect() {
        stopBackgroundRefresh()
        update { copy(isConnected = false, isLoading = false, pendingPaidQuotes = emptyList()) }
    }

    private suspend fun checkAndClaimPaymentsNow() {
        val settings = settingsManager.state.value
        if (!mutableState.value.isEnabled || !settings.checkIncomingInvoices) return
        if (!mutableState.value.isConnected) connect()
        if (!mutableState.value.isConnected) return

        update { copy(isCheckingPayments = true, errorMessage = null) }
        val result = runCatching { fetchQuotes() }
        result.onSuccess { quotes ->
            val now = System.currentTimeMillis()
            prefs.edit().putLong(StorageKeys.npcLastCheck, now).apply()
            val handler = quoteClaimHandler
            val processedQuoteIds = handler?.let { claimHandler ->
                quotes.mapNotNull { quote -> quote.id.takeIf(claimHandler::isNPCQuoteProcessed) }.toSet()
            }.orEmpty()
            val paidQuotes = paidQuotesForProcessing(
                quotes = quotes,
                processedQuoteIds = processedQuoteIds,
            )
            val claimFailures = if (mutableState.value.automaticClaim) {
                claimPaidQuotes(paidQuotes, handler)
            } else {
                paidQuotes
            }
            update {
                copy(
                    lastCheckEpochMillis = now,
                    isCheckingPayments = false,
                    pendingPaidQuotes = claimFailures,
                    errorMessage = if (claimFailures.isNotEmpty() && mutableState.value.automaticClaim) {
                        "Some paid npub.cash quotes could not be minted automatically."
                    } else {
                        null
                    },
                )
            }
        }.onFailure { error ->
            update {
                copy(
                    isCheckingPayments = false,
                    errorMessage = error.message ?: "Failed to check npub.cash payments.",
                )
            }
        }
    }

    private suspend fun claimPaidQuotes(
        paidQuotes: List<NPCQuote>,
        handler: NPCQuoteClaimHandler?,
    ): List<NPCQuote> {
        if (handler == null) return paidQuotes
        return paidQuotes.filterNot { quote ->
            runCatching { handler.claimNPCQuote(quote, p2pkPublicKeyFor(quote)) }
                .getOrDefault(false) || handler.isNPCQuoteProcessed(quote.id)
        }
    }

    private fun p2pkPublicKeyFor(quote: NPCQuote): String? {
        if (!quote.locked) return null
        val publicKey = nostrService.seedDerivedPublicKeyHex().takeIf { it.length == 64 } ?: return null
        return "02$publicKey"
    }

    private fun applyPollingPreferences() {
        val settings = settingsManager.state.value
        val state = mutableState.value
        if (!state.isEnabled || !state.isConnected || !settings.checkIncomingInvoices) {
            stopBackgroundRefresh()
            return
        }
        if (!settings.periodicallyCheckIncomingInvoices) {
            stopBackgroundRefresh()
            return
        }
        if (refreshJob?.isActive == true) return
        refreshJob = scope.launch {
            while (isActive) {
                checkAndClaimPaymentsNow()
                delay(refreshIntervalMillis)
            }
        }
    }

    private fun stopBackgroundRefresh() {
        refreshJob?.cancel()
        refreshJob = null
    }

    private suspend fun fetchQuotes(): List<NPCQuote> {
        val endpoint = "$baseUrl/api/v2/quote"
        val body = authenticatedRequest(endpoint, "GET")
        return parseQuotesJson(body)
    }

    private suspend fun setRemoteMint(mintUrl: String): String? {
        val endpoint = "$baseUrl/api/v2/settings"
        val body = """{"mint":"${mintUrl.escapeJson()}"}""".toRequestBody("application/json".toMediaType())
        val response = authenticatedRequest(endpoint, "PUT", body)
        val root = json.parseToJsonElement(response).jsonObject
        val data = root["data"]?.jsonObject ?: root
        if (data["error"]?.jsonPrimitive?.booleanOrNull == true) {
            error("Failed to change mint.")
        }
        return data["mint"]?.jsonPrimitive?.contentOrNull
            ?: data["mint_url"]?.jsonPrimitive?.contentOrNull
            ?: data["mintUrl"]?.jsonPrimitive?.contentOrNull
    }

    private suspend fun authenticatedRequest(
        url: String,
        method: String,
        body: okhttp3.RequestBody? = null,
    ): String = withContext(Dispatchers.IO) {
        val token = fetchJwtToken()
        val request = Request.Builder()
            .url(url)
            .method(method, body)
            .header("Authorization", "Bearer $token")
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("npub.cash HTTP ${response.code}.")
            response.body?.string() ?: error("Empty npub.cash response.")
        }
    }

    private fun fetchJwtToken(): String {
        val url = "$baseUrl/api/v2/auth/nip98"
        val auth = nostrService.generateSeedNip98AuthHeader(url, "GET")
        val request = Request.Builder()
            .url(url)
            .get()
            .header("Authorization", "Nostr $auth")
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("npub.cash auth HTTP ${response.code}.")
            val body = response.body?.string() ?: error("Empty npub.cash auth response.")
            val root = json.parseToJsonElement(body).jsonObject
            return root["token"]?.jsonPrimitive?.contentOrNull
                ?: root["data"]?.jsonObject?.get("token")?.jsonPrimitive?.contentOrNull
                ?: error("npub.cash auth token missing.")
        }
    }

    private fun loadInitialState(): NPCState {
        val nostr = nostrService.state.value
        val selectedMint = prefs.getString(StorageKeys.npcSelectedMint, null)
        val lastCheck = prefs.getLong(StorageKeys.npcLastCheck, Long.MIN_VALUE).takeIf { it != Long.MIN_VALUE }
        return NPCState(
            isEnabled = prefs.getBoolean(StorageKeys.npcEnabled, false),
            automaticClaim = prefs.getBoolean(StorageKeys.npcAutomaticClaim, true),
            selectedMintUrl = selectedMint,
            lastCheckEpochMillis = lastCheck,
            lightningAddress = nostrService.seedDerivedLightningAddress(domain),
            configuredMintUrl = selectedMint.orEmpty(),
            isInitialized = nostr.isInitialized && nostrService.hasSeedDerivedKey(),
        )
    }

    private fun update(transform: NPCState.() -> NPCState) {
        mutableState.value = mutableState.value.transform()
    }

    private fun String.escapeJson(): String =
        replace("\\", "\\\\").replace("\"", "\\\"")

    companion object {
        private val parser = Json { ignoreUnknownKeys = true }

        fun parseQuotesJson(body: String): List<NPCQuote> {
            val root = parser.parseToJsonElement(body)
            val quoteElements = quoteElements(root)
            return quoteElements.mapNotNull { parseQuote(it) }
        }

        private fun quoteElements(root: JsonElement): List<JsonElement> {
            if (root is JsonArray) return root
            val objectRoot = root.jsonObject
            val data = objectRoot["data"]
            if (data is JsonArray) return data
            if (data is JsonObject) {
                data["quotes"]?.let { if (it is JsonArray) return it }
                data["items"]?.let { if (it is JsonArray) return it }
            }
            objectRoot["quotes"]?.let { if (it is JsonArray) return it }
            objectRoot["items"]?.let { if (it is JsonArray) return it }
            return emptyList()
        }

        private fun parseQuote(element: JsonElement): NPCQuote? {
            val obj = element.jsonObject
            val id = stringValue(obj, "id", "quote", "quote_id") ?: return null
            val amount = longValue(obj, "amount", "amount_sat", "amount_sats") ?: 0L
            val paid = boolValue(obj, "paid", "is_paid")
            val state = stringValue(obj, "state", "status") ?: if (paid == true) "PAID" else null
            return NPCQuote(
                id = id,
                amount = amount,
                mintUrl = stringValue(obj, "mint", "mint_url", "mintUrl"),
                request = stringValue(obj, "request", "payment_request", "paymentRequest", "invoice"),
                state = state,
                locked = boolValue(obj, "locked", "is_locked") ?: false,
                createdAtEpochSeconds = timestampValue(obj, "created_at", "createdAt", "created"),
                paidAtEpochSeconds = timestampValue(obj, "paid_at", "paidAt"),
                expiryEpochSeconds = timestampValue(obj, "expiry", "expires_at", "expiresAt", "expires"),
            )
        }

        fun paidQuotesForProcessing(
            quotes: List<NPCQuote>,
            processedQuoteIds: Set<String>,
        ): List<NPCQuote> =
            quotes
                .filter { it.isPaid && it.id !in processedQuoteIds }
                .sortedBy { it.paidAtEpochSeconds ?: it.createdAtEpochSeconds ?: Long.MAX_VALUE }

        private fun stringValue(obj: JsonObject, vararg names: String): String? =
            names.firstNotNullOfOrNull { name -> obj[name]?.jsonPrimitive?.contentOrNull }

        private fun boolValue(obj: JsonObject, vararg names: String): Boolean? =
            names.firstNotNullOfOrNull { name -> obj[name]?.jsonPrimitive?.booleanOrNull }

        private fun longValue(obj: JsonObject, vararg names: String): Long? =
            names.firstNotNullOfOrNull { name ->
                obj[name]?.jsonPrimitive?.longOrNull
                    ?: obj[name]?.jsonPrimitive?.contentOrNull?.toLongOrNull()
            }

        private fun timestampValue(obj: JsonObject, vararg names: String): Long? =
            names.firstNotNullOfOrNull { name ->
                val primitive = obj[name]?.jsonPrimitive ?: return@firstNotNullOfOrNull null
                primitive.longOrNull ?: primitive.contentOrNull?.let { content ->
                    content.toLongOrNull()
                        ?: runCatching { java.time.Instant.parse(content).epochSecond }.getOrNull()
                }
            }
    }
}
