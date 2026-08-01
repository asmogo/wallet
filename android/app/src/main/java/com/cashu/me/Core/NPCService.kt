package com.cashu.me.Core

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
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import com.cashu.me.Core.Protocols.StorageKeys
import org.cashudevkit.NpubCashClient
import org.cashudevkit.NpubCashQuote
import org.cashudevkit.npubcashDeriveSecretKeyFromSeed
import org.cashudevkit.npubcashGetPubkey

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
    private val settingsManager: SettingsManager,
) {
    private val prefs = context.applicationContext.getSharedPreferences("npc_store", Context.MODE_PRIVATE)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val baseUrl = "https://npubx.cash"
    private val domain = "npubx.cash"
    private val refreshIntervalMillis = 120_000L
    private var refreshJob: Job? = null
    private var paymentCheckJob: Job? = null
    private val connectionMutex = Mutex()
    private var client: NpubCashClient? = null
    private var nostrSecretKey: String? = null
    private var nostrPublicKey: String? = null
    var quoteClaimHandler: NPCQuoteClaimHandler? = null

    private val mutableState = MutableStateFlow(loadInitialState())
    val state: StateFlow<NPCState> = mutableState.asStateFlow()

    init {
        scope.launch {
            settingsManager.state.collect {
                applyPollingPreferences()
            }
        }
    }

    /**
     * Initializes the npub.cash identity exactly as CDK does on iOS: derive the
     * NIP-06 key from the 64-byte BIP39 seed, not from the wallet's legacy
     * Nostr/P2PK key.
     */
    fun initializeWithSeed(seed: ByteArray) {
        val secretKey = npubcashDeriveSecretKeyFromSeed(seed)
        val publicKey = npubcashGetPubkey(secretKey)
        val npub = Bech32.encode("npub", NostrService.hexToBytes(publicKey))

        nostrSecretKey = secretKey
        nostrPublicKey = publicKey
        update {
            copy(
                lightningAddress = "$npub@$domain",
                isInitialized = true,
                errorMessage = null,
            )
        }
        if (mutableState.value.isEnabled) scope.launch { connect() }
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
                if (client == null) connect()
                setRemoteMint(mintUrl)
            }
            result.onSuccess { selected ->
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
                        isLoading = false,
                        errorMessage = error.message ?: "Failed to update npub.cash mint.",
                    )
                }
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
        client?.close()
        client = null
        nostrSecretKey = null
        nostrPublicKey = null
    }

    private suspend fun connect() {
        connectionMutex.withLock {
            val current = mutableState.value
            val secretKey = nostrSecretKey
            if (!current.isEnabled || !current.isInitialized || secretKey == null) {
                update {
                    copy(
                        isConnected = false,
                        // Key setup follows wallet-runtime initialization. This is a
                        // readiness state, not a connection failure; the settings UI
                        // can distinguish active setup from a setup that needs retrying.
                        errorMessage = null,
                    )
                }
                return@withLock
            }
            client?.close()
            client = null
            update { copy(isConnected = false, isLoading = true, errorMessage = null) }
            val result = runCatching {
                val connectedClient = NpubCashClient(baseUrl = baseUrl, nostrSecretKey = secretKey)
                try {
                    val quotes = connectedClient.getQuotes(since = null).map(::fromCdkQuote)
                    val selected = mutableState.value.selectedMintUrl
                    val configured = if (selected != null) {
                        runCatching { connectedClient.setMintUrl(mintUrl = selected) }
                            .getOrNull()
                            ?.takeUnless { it.error }
                            ?.mintUrl
                            ?: selected
                    } else {
                        quotes.firstNotNullOfOrNull { it.mintUrl }.orEmpty()
                    }
                    ConnectedNPCClient(connectedClient, configured)
                } catch (error: Throwable) {
                    connectedClient.close()
                    throw error
                }
            }
            val connected = result.getOrElse { error ->
                update {
                    copy(
                        isConnected = false,
                        isLoading = false,
                        errorMessage = error.message ?: "Not connected to npub.cash.",
                    )
                }
                return@withLock
            }
            if (!mutableState.value.isEnabled || nostrSecretKey != secretKey) {
                connected.client.close()
                update { copy(isConnected = false, isLoading = false) }
                return@withLock
            }
            client = connected.client
            update {
                copy(
                    configuredMintUrl = connected.configuredMintUrl,
                    isConnected = true,
                    isLoading = false,
                    errorMessage = null,
                )
            }
            applyPollingPreferences()
        }
    }

    private fun disconnect() {
        stopBackgroundRefresh()
        client?.close()
        client = null
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
        val publicKey = nostrPublicKey?.takeIf { it.length == 64 } ?: return null
        return "02$publicKey"
    }

    private fun applyPollingPreferences() {
        val settings = settingsManager.state.value
        val state = mutableState.value
        val shouldRun = shouldRunPeriodicInvoiceChecks(
            isEnabled = state.isEnabled,
            isConnected = state.isConnected,
            checkIncomingInvoices = settings.checkIncomingInvoices,
            periodicallyCheckIncomingInvoices = settings.periodicallyCheckIncomingInvoices,
        )
        if (!shouldRun) {
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
        val connectedClient = client ?: error("Not connected to npub.cash.")
        return connectedClient.getQuotes(since = null).map(::fromCdkQuote)
    }

    private suspend fun setRemoteMint(mintUrl: String): String {
        val connectedClient = client ?: error("Not connected to npub.cash.")
        val response = connectedClient.setMintUrl(mintUrl = mintUrl)
        if (response.error) error("Failed to change mint.")
        return response.mintUrl ?: mintUrl
    }

    private fun loadInitialState(): NPCState {
        val selectedMint = prefs.getString(StorageKeys.npcSelectedMint, null)
        val lastCheck = prefs.getLong(StorageKeys.npcLastCheck, Long.MIN_VALUE).takeIf { it != Long.MIN_VALUE }
        return NPCState(
            isEnabled = prefs.getBoolean(StorageKeys.npcEnabled, false),
            automaticClaim = prefs.getBoolean(StorageKeys.npcAutomaticClaim, true),
            selectedMintUrl = selectedMint,
            lastCheckEpochMillis = lastCheck,
            configuredMintUrl = selectedMint.orEmpty(),
        )
    }

    private fun update(transform: NPCState.() -> NPCState) {
        mutableState.value = mutableState.value.transform()
    }

    companion object {
        internal fun fromCdkQuote(quote: NpubCashQuote): NPCQuote = NPCQuote(
            id = quote.id,
            amount = quote.amount.toLong(),
            mintUrl = quote.mintUrl,
            request = quote.request,
            state = quote.state,
            locked = quote.locked == true,
            createdAtEpochSeconds = quote.createdAt.toLong(),
            paidAtEpochSeconds = quote.paidAt?.toLong(),
            expiryEpochSeconds = quote.expiresAt?.toLong(),
        )

        fun paidQuotesForProcessing(
            quotes: List<NPCQuote>,
            processedQuoteIds: Set<String>,
        ): List<NPCQuote> =
            quotes
                .filter { it.isPaid && it.id !in processedQuoteIds }
                .sortedBy { it.paidAtEpochSeconds ?: it.createdAtEpochSeconds ?: Long.MAX_VALUE }

        internal fun shouldRunPeriodicInvoiceChecks(
            isEnabled: Boolean,
            isConnected: Boolean,
            checkIncomingInvoices: Boolean,
            periodicallyCheckIncomingInvoices: Boolean,
        ): Boolean = isEnabled && isConnected && checkIncomingInvoices && periodicallyCheckIncomingInvoices

    }

    private data class ConnectedNPCClient(
        val client: NpubCashClient,
        val configuredMintUrl: String,
    )
}
