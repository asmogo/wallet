package com.cashu.me.Core

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
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
import com.cashu.me.Core.Protocols.StorageKeys
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

class NPCService internal constructor(
    private val prefs: SharedPreferences,
    private val settingsState: StateFlow<SettingsState>,
    private val scope: CoroutineScope,
    private val refreshIntervalMillis: Long = 120_000L,
    private val makeClient: (String, String) -> NPCClient = ::CdkNPCClient,
    private val deriveKeys: (ByteArray) -> Pair<String, String> = { seed ->
        val secret = npubcashDeriveSecretKeyFromSeed(seed)
        secret to npubcashGetPubkey(secret)
    },
) {
    constructor(context: Context, settingsManager: SettingsManager) : this(
        prefs = context.applicationContext.getSharedPreferences("npc_store", Context.MODE_PRIVATE),
        settingsState = settingsManager.state,
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
    )
    private val baseUrl = "https://npubx.cash"
    private val domain = "npubx.cash"
    private var refreshJob: Job? = null
    private var paymentCheckJob: Job? = null
    private var connectionAttempt: Deferred<Unit>? = null
    private var sessionGeneration = 0L
    private var client: NPCClient? = null
    private var nostrSecretKey: String? = null
    private var nostrPublicKey: String? = null
    var quoteClaimHandler: NPCQuoteClaimHandler? = null

    private val mutableState = MutableStateFlow(loadInitialState())
    val state: StateFlow<NPCState> = mutableState.asStateFlow()

    init {
        scope.launch {
            settingsState.collect {
                applyPollingPreferences()
            }
        }
    }

    /**
     * Initializes the npub.cash identity exactly as CDK does on iOS: derive the
     * NIP-06 key from the 64-byte BIP39 seed, not from the wallet's legacy
     * Nostr/P2PK key.
     */
    // Wallet setup also calls this from IO; publish keys and session changes
    // on the same dispatcher that owns connection and polling jobs.
    suspend fun initializeWithSeed(seed: ByteArray) = withContext(scope.coroutineContext.minusKey(Job)) {
        val (secretKey, publicKey) = deriveKeys(seed)
        val npub = Bech32.encode("npub", NostrService.hexToBytes(publicKey))

        if (nostrSecretKey != secretKey) disconnect()
        nostrSecretKey = secretKey
        nostrPublicKey = publicKey
        update {
            copy(
                lightningAddress = "$npub@$domain",
                isInitialized = true,
                errorMessage = null,
            )
        }
        initializeIfEnabled()
    }

    fun setEnabled(value: Boolean) {
        if (mutableState.value.isEnabled == value) return
        prefs.edit().putBoolean(StorageKeys.npcEnabled, value).apply()
        update { copy(isEnabled = value, errorMessage = null) }
        if (value) {
            initializeIfEnabled()
        } else {
            disconnect()
        }
    }

    /** Recover an enabled address on startup, foreground, or settings entry. */
    fun initializeIfEnabled() {
        scope.launch {
            connect()
            applyPollingPreferences()
        }
    }

    fun setAutomaticClaim(value: Boolean) {
        prefs.edit().putBoolean(StorageKeys.npcAutomaticClaim, value).apply()
        update { copy(automaticClaim = value) }
    }

    fun changeMint(mintUrl: String) {
        scope.launch {
            if (!mutableState.value.isEnabled) return@launch
            val session = sessionGeneration
            update { copy(isLoading = true, errorMessage = null) }
            val result = runCatching {
                connect()
                if (!isCurrentSession(session)) throw CancellationException()
                setRemoteMint(mintUrl)
            }
            if (!isCurrentSession(session)) return@launch
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
                if (error is CancellationException) throw error
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

    suspend fun resetForWalletBoundary() = withContext(scope.coroutineContext.minusKey(Job)) {
        disconnect()
        prefs.edit()
            .remove(StorageKeys.npcEnabled)
            .remove(StorageKeys.npcAutomaticClaim)
            .remove(StorageKeys.npcSelectedMint)
            .remove(StorageKeys.npcLastCheck)
            .apply()
        mutableState.value = NPCState()
        nostrSecretKey = null
        nostrPublicKey = null
    }

    internal suspend fun connect() {
        val current = mutableState.value
        val secretKey = nostrSecretKey
        if (!current.isEnabled || !current.isInitialized || secretKey == null) return
        if (current.isConnected && client != null) return
        connectionAttempt?.let { it.await(); return }

        val session = sessionGeneration
        update { copy(isConnected = false, isLoading = true, errorMessage = null) }
        // Install the handle before execution, including on Main.immediate.
        val attempt = scope.async(start = CoroutineStart.LAZY) {
            establishConnection(secretKey, session)
        }
        connectionAttempt = attempt
        attempt.await()
    }

    private suspend fun establishConnection(secretKey: String, session: Long) {
        var candidate: NPCClient? = null
        try {
            val connectedClient = makeClient(baseUrl, secretKey)
            candidate = connectedClient
            val quotes = connectedClient.getQuotes()
            currentCoroutineContext().ensureActive()
            if (!isCurrentSession(session)) return
            val selected = mutableState.value.selectedMintUrl
            val configured = if (selected != null) {
                try {
                    connectedClient.setMintUrl(selected)
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Exception) {
                    selected
                }
            } else {
                quotes.firstNotNullOfOrNull { it.mintUrl }.orEmpty()
            }
            currentCoroutineContext().ensureActive()
            if (!isCurrentSession(session)) return
            client = connectedClient
            candidate = null // Ownership passes to the active session.
            update {
                copy(configuredMintUrl = configured, isConnected = true, errorMessage = null)
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            if (!isCurrentSession(session)) return
            update {
                copy(isConnected = false, errorMessage = error.message ?: "Not connected to npub.cash.")
            }
        } finally {
            candidate?.close()
            if (isCurrentSession(session)) {
                connectionAttempt = null
                update { copy(isLoading = false) }
                applyPollingPreferences()
            }
        }
    }

    private fun isCurrentSession(session: Long): Boolean =
        mutableState.value.isEnabled && sessionGeneration == session

    private fun disconnect() {
        sessionGeneration += 1
        connectionAttempt?.cancel()
        connectionAttempt = null
        paymentCheckJob?.cancel()
        paymentCheckJob = null
        stopBackgroundRefresh()
        client?.close()
        client = null
        update {
            copy(
                isConnected = false,
                isLoading = false,
                isCheckingPayments = false,
                errorMessage = null,
                pendingPaidQuotes = emptyList(),
            )
        }
    }

    private suspend fun checkAndClaimPaymentsNow() {
        val settings = settingsState.value
        if (!mutableState.value.isEnabled || !settings.checkIncomingInvoices) return
        val session = sessionGeneration
        if (!mutableState.value.isConnected) connect()
        if (!isCurrentSession(session) || !mutableState.value.isConnected) return

        update { copy(isCheckingPayments = true, errorMessage = null) }
        val result = runCatching { fetchQuotes() }
        if (!isCurrentSession(session)) return
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
                claimPaidQuotes(paidQuotes, handler, session)
            } else {
                paidQuotes
            }
            if (!isCurrentSession(session)) return
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
            if (error is CancellationException) {
                update { copy(isCheckingPayments = false) }
                throw error
            }
            client?.close()
            client = null
            update {
                copy(
                    isConnected = false,
                    isCheckingPayments = false,
                    errorMessage = error.message ?: "Failed to check npub.cash payments.",
                )
            }
        }
    }

    private suspend fun claimPaidQuotes(
        paidQuotes: List<NPCQuote>,
        handler: NPCQuoteClaimHandler?,
        session: Long,
    ): List<NPCQuote> {
        if (handler == null) return paidQuotes
        return paidQuotes.filterNot { quote ->
            currentCoroutineContext().ensureActive()
            if (!isCurrentSession(session)) return emptyList()
            val claimed = try {
                handler.claimNPCQuote(quote, p2pkPublicKeyFor(quote))
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                false
            }
            claimed || handler.isNPCQuoteProcessed(quote.id)
        }
    }

    private fun p2pkPublicKeyFor(quote: NPCQuote): String? {
        if (!quote.locked) return null
        val publicKey = nostrPublicKey?.takeIf { it.length == 64 } ?: return null
        return "02$publicKey"
    }

    private fun applyPollingPreferences() {
        val settings = settingsState.value
        val state = mutableState.value
        val shouldRun = shouldRunPeriodicInvoiceChecks(
            isEnabled = state.isEnabled,
            isInitialized = state.isInitialized,
            checkIncomingInvoices = settings.checkIncomingInvoices,
            periodicallyCheckIncomingInvoices = settings.periodicallyCheckIncomingInvoices,
        )
        if (!shouldRun) {
            stopBackgroundRefresh()
            return
        }
        if (refreshJob?.isActive == true) return
        refreshJob = scope.launch {
            // Delay after failure so recovery never recursively retries.
            if (mutableState.value.isConnected) checkAndClaimPayments()
            while (isActive) {
                delay(refreshIntervalMillis)
                checkAndClaimPayments()
            }
        }
    }

    private fun stopBackgroundRefresh() {
        refreshJob?.cancel()
        refreshJob = null
    }

    private suspend fun fetchQuotes(): List<NPCQuote> {
        val connectedClient = client ?: error("Not connected to npub.cash.")
        return connectedClient.getQuotes()
    }

    private suspend fun setRemoteMint(mintUrl: String): String {
        val connectedClient = client ?: error("Not connected to npub.cash.")
        return connectedClient.setMintUrl(mintUrl)
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
            isInitialized: Boolean,
            checkIncomingInvoices: Boolean,
            periodicallyCheckIncomingInvoices: Boolean,
        ): Boolean = isEnabled && isInitialized && checkIncomingInvoices && periodicallyCheckIncomingInvoices

    }
}
