package com.cashu.me.Core

import java.net.URL
import java.text.Normalizer
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.yield
import org.cashudevkit.PendingMelt
import org.cashudevkit.QuoteState as CdkQuoteState
import org.cashudevkit.npubcashDeriveSecretKeyFromSeed
import com.cashu.me.Core.CDK.CdkWalletGateway
import com.cashu.me.Core.Platform.WalletDatabasePathManager
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import com.cashu.me.Core.Protocols.SecureStorage
import com.cashu.me.Core.Protocols.StorageKeys
import com.cashu.me.Core.Protocols.WalletServiceProtocol
import com.cashu.me.Core.Wallet.isInsufficientBalance
import com.cashu.me.Models.MeltPaymentResult
import com.cashu.me.Models.MeltQuoteInfo
import com.cashu.me.Models.MeltQuoteState
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.Models.MintQuoteState
import com.cashu.me.Models.PaymentMethodKind
import com.cashu.me.Models.PendingReceiveToken
import com.cashu.me.Models.RestoreMintResult
import com.cashu.me.Models.SagaTransactionId
import com.cashu.me.Models.SendTokenResult
import com.cashu.me.Models.WalletTransaction
import org.bouncycastle.crypto.digests.SHA512Digest
import org.bouncycastle.crypto.generators.PKCS5S2ParametersGenerator
import org.bouncycastle.crypto.params.KeyParameter

class WalletManager(
    private val secureStorage: SecureStorage,
    private val walletStore: WalletStore,
    private val cashuRequestStore: CashuRequestStore,
    private val settingsManager: SettingsManager,
    private val nostrService: NostrService,
    private val npcService: NPCService,
    private val nwcManager: NwcManager,
    private val nostrMintBackupService: NostrMintBackupService,
    private val databasePathManager: WalletDatabasePathManager,
    private val gateway: CdkWalletGateway,
    private val runStartupMaintenance: Boolean = true,
    private val startNwc: Boolean = true,
    private val pollQuotesInForeground: Boolean = true,
    private val externalServicesEnabled: Boolean = true,
    private val allowCleartextLocalTestMints: Boolean = false,
) : WalletServiceProtocol, NPCQuoteClaimHandler {
    @Serializable
    private data class WalletReplacementSnapshot(
        val mnemonic: String?,
        val nostrPrivateKey: String?,
        val wallet: PreferenceSnapshot,
        val settings: SettingsWalletScopedSnapshot,
        val nwc: NwcWalletScopedSnapshot,
        val npc: PreferenceSnapshot,
    )

    internal var cashuRequestListener: CashuRequestListener? = null

    private val exceptionHandler = CoroutineExceptionHandler { _, error ->
        AppLogger.wallet.error("Unhandled wallet coroutine error", error)
        update { copy(isLoading = false, errorMessage = error.message ?: error::class.simpleName) }
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate + exceptionHandler)
    private val mutableState = MutableStateFlow(WalletState())
    val state: StateFlow<WalletState> = mutableState.asStateFlow()
    private val mutableReceivedPayments = MutableSharedFlow<ReceivedPaymentEvent>(
        extraBufferCapacity = 1,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val receivedPayments: SharedFlow<ReceivedPaymentEvent> = mutableReceivedPayments.asSharedFlow()
    private val initializationMutex = Mutex()
    private val replacement = DurableWalletReplacement(secureStorage, databasePathManager.replacementBoundaryFiles())
    private val mintMetadataFetcher = WalletMintMetadataFetcher(allowCleartextLocalTestMints)
    private val mintQuoteSyncService = WalletMintQuoteSyncService(gateway, walletStore)
    private val focusedMintQuoteMonitor = FocusedMintQuoteMonitor()
    private val transactionLoader = WalletTransactionLoader(walletStore, gateway)
    private val npcQuotesInFlight = mutableSetOf<String>()
    private var processedNPCQuotes = walletStore.loadProcessedNPCQuotes().toMutableSet()

    // Throttle state for passive mint-quote syncs (app start, resume, History
    // open, the foreground poll). Collapses overlapping triggers and
    // rate-limits how often we re-poll the mint so reusable BOLT12 offers
    // don't hammer it (iOS WalletManager+MintQuoteSync parity). Pull-to-refresh
    // calls [syncPendingMintQuotes] directly to bypass the cooldown.
    // Atomic: startup maintenance runs on Dispatchers.IO while the foreground
    // poll runs on the main-scoped job.
    private val mintQuoteSweepMutex = Mutex()
    // 0 = never synced. Written/read across the IO + Main poll jobs.
    private val lastMintQuoteSyncAtMs = AtomicLong(0L)

    // In-process waiters for melts a mint accepted asynchronously (NUT-05),
    // keyed by quote ID. These die with the process; CDK's durable melt sagas
    // plus [syncPendingMeltQuotes] are the relaunch backstop (iOS
    // WalletManager+PendingMelts parity).
    private val pendingMeltWaiters = mutableMapOf<String, Job>()

    // Foreground quote poll (started/stopped on ProcessLifecycle ON_START/ON_STOP
    // so M3 ModalBottomSheet dialog windows don't kill it). Re-checks pending
    // mint + melt quotes while the app is active so a payment lands without
    // pull-to-refresh (iOS parity).
    private var pendingQuotePollJob: Job? = null
    private var startupMaintenanceJob: Job? = null

    override suspend fun initialize() {
        initializationMutex.withLock {
            if (mutableState.value.isRuntimeReady) return@withLock

            withContext(Dispatchers.IO) {
                try {
                    recoverWalletReplacement()
                } catch (error: Exception) {
                    AppLogger.wallet.error("Wallet replacement recovery failed", error)
                    update { copy(isInitialized = true, isRuntimeReady = false, isLoading = false,
                        startupFailure = walletStartupFailure(true),
                        errorMessage = "Wallet recovery could not finish. Restart to try again.") }
                    return@withContext
                }
                val hasStoredWallet = secureStorage.contains(StorageKeys.secureWalletMnemonic)

                // Publish the complete cached home model before opening SQLite,
                // decrypting the seed, deriving keys, or starting background services.
                // This is the same cache-first boundary used by iOS.
                if (hasStoredWallet) {
                    // Wallets installed before the completion marker existed
                    // are treated as fully onboarded; only installs from this
                    // version on can be incomplete (e.g. process death before
                    // the first-mint step was passed).
                    if (!settingsManager.hasOnboardingCompletionMarker) {
                        settingsManager.onboardingCompleted = true
                    }
                    loadCachedState(needsOnboarding = !settingsManager.onboardingCompleted || settingsManager.walletRestoreIncomplete)
                } else {
                    update {
                        copy(
                            isInitialized = true,
                            isLoading = false,
                            needsOnboarding = true,
                            canExitOnboarding = false,
                            mints = walletStore.loadMints(),
                        )
                    }
                }

                runCatching {
                    gateway.initializeLogging()
                    if (hasStoredWallet) {
                        val mnemonic = checkNotNull(secureStorage.loadString(StorageKeys.secureWalletMnemonic)) {
                            "Stored wallet seed could not be decrypted."
                        }
                        walletStore.purgeRetiredKeys()
                        openWalletRepositoryWithRecovery(mnemonic)
                        deriveNostrKey(mnemonic)
                    }
                    update {
                        copy(
                            isRuntimeReady = true,
                            errorMessage = null,
                            startupFailure = null,
                        )
                    }
                    if (runStartupMaintenance) {
                        startDeferredStartupMaintenance(hasStoredWallet)
                    }
                }.onFailure { error ->
                    AppLogger.wallet.error("Wallet runtime initialization failed", error)
                    val startupFailure = walletStartupFailure(hasStoredWallet)
                    update {
                        copy(
                            isInitialized = true,
                            isRuntimeReady = false,
                            isLoading = false,
                            errorMessage = startupFailure.message,
                            startupFailure = startupFailure,
                        )
                    }
                }
            }
        }
    }

    /**
     * Retries only the prerequisites needed by Lightning-address settings.
     *
     * A wallet runtime startup failure is retried first. If the runtime is
     * already healthy but npub.cash key derivation previously failed, avoid
     * reopening the repository and derive that identity again from the stored
     * wallet seed.
     */
    suspend fun retryLightningAddressSetup() {
        if (!mutableState.value.isRuntimeReady) initialize()
        check(mutableState.value.isRuntimeReady) { "Wallet runtime is not ready." }
        if (npcService.state.value.isInitialized) return

        val mnemonic = withContext(Dispatchers.IO) {
            checkNotNull(secureStorage.loadString(StorageKeys.secureWalletMnemonic)) {
                "Stored wallet seed could not be decrypted."
            }
        }
        withContext(Dispatchers.IO) {
            npcService.initializeWithSeed(walletBip39Seed(mnemonic))
        }
    }

    private fun startDeferredStartupMaintenance(hasStoredWallet: Boolean) {
        startupMaintenanceJob?.cancel()
        startupMaintenanceJob = scope.launch(Dispatchers.IO) {
            // Give Compose a scheduling opportunity to render cached state before
            // background maintenance contends for CDK's operation mutex.
            kotlinx.coroutines.yield()
            if (hasStoredWallet) {
                runCatching { refreshBalance() }
                    .onFailure { AppLogger.wallet.error("Deferred balance refresh failed", it) }

                // iOS startup maintenance parity: complete/compensate wallet
                // sagas interrupted by a process death (e.g. mid-melt), then
                // settle any melt/mint quotes that moved while the app was gone.
                mutableState.value.mints.forEach { mint ->
                    runCatching { gateway.recoverIncompleteSagas(mint.url) }
                        .onSuccess { report ->
                            if (report.hasActivity) {
                                AppLogger.wallet.info(
                                    "Recovered wallet sagas for mint ${mint.url}: " +
                                        "recovered=${report.recovered} compensated=${report.compensated} " +
                                        "skipped=${report.skipped} failed=${report.failed}",
                                )
                            }
                        }
                        .onFailure { AppLogger.wallet.error("Wallet saga recovery failed for mint ${mint.url}", it) }
                }
                runCatching { syncPendingMeltQuotes() }
                    .onFailure { AppLogger.wallet.error("Startup pending melt sync failed", it) }
                runCatching { syncPendingMintQuotes() }
                    .onFailure { AppLogger.wallet.error("Startup pending mint quote sync failed", it) }
            }
            if (startNwc) {
                runCatching { nwcManager.startIfEnabled() }
                    .onFailure { AppLogger.wallet.error("Deferred NWC startup failed", it) }
            }

            // Arm quote detection from the runtime-ready path as well: Process
            // lifecycle ON_START may have already fired before isRuntimeReady
            // flipped true. Guard-protected — no-op if the poll is running.
            onAppEnteredForeground()
        }
    }

    override suspend fun createNewWallet() {
        withLoading {
            val mnemonic = gateway.generateMnemonic()
            installCleanWallet(mnemonic, needsOnboarding = false)
        }
    }

    suspend fun generateMnemonicForOnboarding(): String =
        withLoadingResult { gateway.generateMnemonic() }

    /**
     * BIP-39 checksum check, without installing anything. Seed entry needs to
     * ask *before* committing to a restore so a mistyped word lands on the
     * review grid rather than on an install failure. iOS twin:
     * `WalletManager.validateMnemonic`.
     */
    suspend fun validateMnemonic(mnemonic: String): Boolean {
        val normalized = MnemonicInput.normalize(mnemonic)
        if (!MnemonicInput.hasSupportedWordCount(normalized)) return false
        return gateway.validateMnemonic(normalized)
    }

    suspend fun createNewWalletFromMnemonic(mnemonic: String) {
        val normalized = MnemonicInput.normalize(mnemonic)
        require(MnemonicInput.hasSupportedWordCount(normalized)) {
            "Seed phrase must be ${MnemonicInput.supportedWordCountLabel} words."
        }
        require(gateway.validateMnemonic(normalized)) { "Invalid seed phrase." }
        withLoading { installCleanWallet(normalized, needsOnboarding = false) }
    }

    suspend fun initializeNewWalletForOnboarding(mnemonic: String) {
        val normalized = MnemonicInput.normalize(mnemonic)
        require(MnemonicInput.hasSupportedWordCount(normalized)) {
            "Seed phrase must be ${MnemonicInput.supportedWordCountLabel} words."
        }
        require(gateway.validateMnemonic(normalized)) { "Invalid seed phrase." }
        // Onboarding resumed after process death: the same seed is already
        // installed — reinstalling would wipe its partially added mints.
        if (mutableState.value.isRuntimeReady &&
            secureStorage.loadString(StorageKeys.secureWalletMnemonic) == normalized
        ) {
            return
        }
        withLoading { installCleanWallet(normalized, needsOnboarding = true) }
    }

    /**
     * Seed persisted by an onboarding run that never completed (process death
     * before the first-mint step was passed). A resumed onboarding must re-show
     * these same words — the user may have written them down already — instead
     * of silently regenerating a new seed.
     */
    suspend fun persistedOnboardingMnemonic(): String? = withContext(Dispatchers.IO) {
        if (settingsManager.onboardingCompleted) {
            null
        } else {
            secureStorage.loadString(StorageKeys.secureWalletMnemonic)
        }
    }

    /**
     * Phase 1 of seed restore (iOS `initializeRestoredWallet`): install the
     * repository for this mnemonic. Does **not** force first-launch onboarding
     * — [needsOnboarding] is preserved so:
     *   - first-launch onboarding stays on its restore faces, and
     *   - Settings → Restore keeps the in-app shell (mint staging) instead of
     *     cross-fading to the welcome splash.
     * Phase 3 [completeRestore] clears onboarding when finishing first launch.
     */
    suspend fun initializeRestoredWallet(mnemonic: String) {
        val normalized = MnemonicInput.normalize(mnemonic)
        require(MnemonicInput.hasSupportedWordCount(normalized)) {
            "Seed phrase must be ${MnemonicInput.supportedWordCountLabel} words."
        }
        require(gateway.validateMnemonic(normalized)) { "Invalid seed phrase." }
        val keepOnboarding = mutableState.value.needsOnboarding
        withLoading { installCleanWallet(normalized, needsOnboarding = keepOnboarding, restoring = true) }
    }

    override suspend fun restoreWallet(mnemonic: String) {
        initializeRestoredWallet(mnemonic)
    }

    override suspend fun deleteWallet() {
        withLoading {
            cashuRequestListener?.pauseForWalletBoundary()
            nwcManager.stop()
            gateway.closeWalletRepository()
            recoverWalletReplacement()
            nwcManager.resetForWalletBoundary()
            secureStorage.delete(StorageKeys.secureWalletMnemonic)
            secureStorage.delete(StorageKeys.secureNostrPrivateKey)
            databasePathManager.removeWalletDatabaseFiles()
            cashuRequestStore.resetForWalletBoundary()
            walletStore.removeAllWalletData()
            settingsManager.resetWalletScopedData()
            npcService.resetForWalletBoundary()
            nostrMintBackupService.resetForWalletBoundary()
            cashuRequestListener?.resetForWalletBoundary(restart = false)
            MintLogoBitmapCache.clear()
            update {
                WalletState(
                    isInitialized = true,
                    isRuntimeReady = true,
                    needsOnboarding = true,
                    canExitOnboarding = false,
                )
            }
        }
    }

    override suspend fun addMint(url: String) {
        var addedMintUrl: String? = null
        withLoading {
            val normalized = mintMetadataFetcher.normalizeMintUrl(url)
            mintMetadataFetcher.validateMintUrl(normalized)?.let { throw IllegalArgumentException(it) }
            if (mutableState.value.mints.any { it.url == normalized }) {
                throw IllegalArgumentException("Mint already exists.")
            }
            // Connect and commit first so the Mints view responds promptly.
            // NUT-09 recovery starts below on the app-lifetime scope and
            // refreshes balances/history after it completes.
            gateway.ensureWallet(normalized)
            val fetched = gateway.fetchMintInfo(normalized)
                ?: throw IllegalStateException("Mint did not return info via CDK.")
            val updated = mutableState.value.mints + fetched
            walletStore.saveMints(updated)
            if (mutableState.value.activeMint == null) walletStore.activeMintURL = fetched.url
            loadCachedState(needsOnboarding = false)
            addedMintUrl = fetched.url
        }

        addedMintUrl?.let { mintUrl ->
            scope.launch {
                if (mutableState.value.mints.none { it.url == mintUrl }) return@launch

                runCatching {
                    restoreProofsForAddedMint(
                        mintUrl = mintUrl,
                        restoreMint = { withContext(Dispatchers.IO) { gateway.restoreMint(it) } },
                    )
                    if (mutableState.value.mints.none { it.url == mintUrl }) return@runCatching
                    refreshBalance()
                    loadTransactions()
                }.onSuccess {
                    AppLogger.wallet.info("Background restore completed for added mint $mintUrl")
                }.onFailure { error ->
                    AppLogger.wallet.error("Background restore failed for added mint $mintUrl", error)
                }
            }
        }
        if (externalServicesEnabled) {
            scope.launch { nostrMintBackupService.backupCurrentMintsIfEnabled() }
        }
    }

    override suspend fun removeMint(mint: MintInfo) {
        withLoading {
            val trackedMint = mutableState.value.mints.firstOrNull { it.url == mint.url }
                ?: throw IllegalArgumentException("Mint is no longer tracked.")
            removeMintWalletBeforeCommit(
                mintUrl = trackedMint.url,
                removeWalletIfSingleUnit = gateway::removeWalletIfSingleUnit,
            ) {
                val updated = mutableState.value.mints.filterNot { it.url == trackedMint.url }
                walletStore.saveMints(updated)
                if (walletStore.activeMintURL == trackedMint.url) {
                    walletStore.activeMintURL = updated.firstOrNull()?.url
                }
                loadCachedState(needsOnboarding = false)
            }
            refreshBalance()
        }
        if (externalServicesEnabled) {
            scope.launch { nostrMintBackupService.backupCurrentMintsIfEnabled() }
        }
    }

    override suspend fun setActiveMint(mint: MintInfo) {
        walletStore.activeMintURL = mint.url
        loadCachedState(needsOnboarding = false)
    }

    override suspend fun restoreFromMint(url: String): RestoreMintResult =
        withLoadingResult {
            val normalized = mintMetadataFetcher.normalizeMintUrl(url)
            mintMetadataFetcher.validateMintUrl(normalized)?.let { throw IllegalArgumentException(it) }
            val trackedMintUrl = ensureMintTracked(normalized)
            val result = withContext(Dispatchers.IO) { gateway.restoreMint(trackedMintUrl) }
            refreshBalance()
            loadTransactions()
            result
        }

    suspend fun refreshBalance() {
        val mints = mutableState.value.mints
        var total = 0L
        val unitTotals = mutableMapOf<String, Long>()
        val updated = mints.map { mint ->
            val balance = runCatching { gateway.totalBalance(mint.url) }.getOrDefault(mint.balance)
            total += balance
            // Only sum unit wallets that already exist — never register a unit
            // wallet just because the mint advertises the unit.
            mint.units.filter { !it.equals("sat", ignoreCase = true) }.forEach { unit ->
                runCatching { gateway.unitBalanceIfExists(mint.url, unit) }.getOrNull()?.let {
                    unitTotals[unit] = (unitTotals[unit] ?: 0L) + it
                }
            }
            mint.copy(balance = balance)
        }
        unitTotals["sat"] = total
        walletStore.saveMints(updated)
        walletStore.saveBalancesByUnit(unitTotals)
        update {
            copy(
                balance = total,
                balancesByUnit = unitTotals.toMap(),
                mints = updated,
                activeMint = activeMintFrom(updated),
            )
        }
    }

    /**
     * Refresh NUT-06 mint metadata for every tracked mint. Does not toggle
     * [WalletState.isLoading] — call from the Mints screen so the list stays
     * interactive while names/icons update in place (iOS `refreshMintInfo`).
     */
    suspend fun refreshMintInfo() {
        val current = mutableState.value.mints
        if (current.isEmpty()) return

        var changed = false
        val updated = current.map { mint ->
            val fetched = runCatching {
                gateway.ensureWallet(mint.url)
                gateway.fetchMintInfo(mint.url)
            }.onFailure {
                AppLogger.wallet.error("Failed to refresh mint info for ${mint.url}", it)
            }.getOrNull() ?: return@map mint

            val merged = mint.copy(
                name = fetched.name.takeUnless { it == "Unknown Mint" } ?: mint.name,
                description = fetched.description ?: mint.description,
                iconUrl = fetched.iconUrl ?: mint.iconUrl,
                units = fetched.units.ifEmpty { mint.units },
                mintUnits = fetched.mintUnits.ifEmpty { mint.mintUnits },
                // A live report is authoritative — including a reported-empty
                // list (the mint dropped a rail); only an unknown (unfetched)
                // value keeps the previously stored one.
                supportedMintMethods = fetched.supportedMintMethods ?: mint.supportedMintMethods,
                supportedMeltMethods = fetched.supportedMeltMethods ?: mint.supportedMeltMethods,
                // Live NUT-04 advertisement is authoritative, including false
                // (the mint dropped description support).
                supportsBolt12MintDescription = fetched.supportsBolt12MintDescription,
                lastUpdatedEpochMillis = System.currentTimeMillis(),
                balance = mint.balance,
                isActive = mint.isActive,
            )
            if (merged != mint) {
                changed = true
                merged
            } else {
                mint
            }
        }

        if (!changed) return
        walletStore.saveMints(updated)
        update {
            copy(
                mints = updated,
                activeMint = activeMintFrom(updated),
            )
        }
    }

    /**
     * Balance of one (mint, unit). Sat answers from the cached mint balance;
     * non-sat registers the unit wallet on demand. Null when unavailable.
     */
    suspend fun unitBalance(mintUrl: String, unit: String): Long? {
        if (unit.equals("sat", ignoreCase = true)) {
            return mutableState.value.mints.firstOrNull { it.url == mintUrl }?.balance
        }
        return runCatching {
            withContext(Dispatchers.IO) { gateway.unitBalance(mintUrl, unit) }
        }.getOrNull()
    }

    /**
     * Best-effort mint identity for staging / discovery (iOS `fetchMintPreviewInfo`
     * / detail reachability). Creates a CDK wallet entry if needed so logos and
     * names can load, but does not add the mint to the app's saved list.
     * Throws when the mint is unreachable so callers can map Checking → Offline.
     */
    suspend fun fetchLiveMintInfo(mintUrl: String): MintInfo? {
        val normalized = mintMetadataFetcher.normalizeMintUrl(mintUrl)
        return gateway.fetchMintInfo(normalized)
    }

    override suspend fun createMintQuote(amount: Long?, method: PaymentMethodKind, unit: String, description: String?): MintQuoteInfo {
        val active = mutableState.value.activeMint ?: throw IllegalStateException("No active mint.")
        val offerDescription = normalizedOfferDescription(description)
        return withLoadingResult {
            gateway.createMintQuote(
                amount, method, active.url, unit,
                if (method == PaymentMethodKind.Bolt12) offerDescription else description,
            ).also {
                mintQuoteSyncService.rememberMintQuoteTimestamp(it.id)
            }.let { quote ->
                // CDK drops the description from the returned quote (write-only),
                // so re-attach it for callers that persist or display it (iOS
                // `info.description` parity). Offers are immutable, so this
                // matches what was embedded.
                if (method == PaymentMethodKind.Bolt12) quote.copy(description = offerDescription) else quote
            }
        }
    }

    /**
     * Returns the active mint's reusable amountless BOLT12 offer matching
     * [description] (null → the plain, description-less offer). CDK never
     * returns the offer description, so the match joins quotes with the
     * locally stored quote-intent memos keyed by quote id.
     */
    suspend fun existingAmountlessBolt12Offer(unit: String, description: String? = null): MintQuoteInfo? {
        val activeMint = mutableState.value.activeMint ?: return null
        val memosByQuoteId = LinkedHashMap<String, String?>()
        cashuRequestStore.state.value.requests.forEach { request ->
            // First-wins matches offer immutability (iOS `uniquingKeysWith`
            // parity) — a quote's memo is set once and never changes.
            request.quoteId?.let { memosByQuoteId.putIfAbsent(it, request.memo) }
        }
        val quotes = gateway.listUnissuedMintQuotes().map { quote ->
            if (quote.paymentMethod == PaymentMethodKind.Bolt12) {
                quote.copy(description = memosByQuoteId[quote.id])
            } else {
                quote
            }
        }
        return findExistingAmountlessBolt12Offer(
            quotes = quotes,
            mintUrl = activeMint.url,
            unit = unit,
            description = description,
        )
    }

    suspend fun createMintQuoteForMint(
        mintUrl: String,
        amount: Long?,
        method: PaymentMethodKind = PaymentMethodKind.Bolt11,
        unit: String = "sat",
    ): MintQuoteInfo =
        withLoadingResult {
            val trackedMintUrl = ensureMintTracked(mintUrl)
            gateway.createMintQuote(amount, method, trackedMintUrl, unit).also {
                mintQuoteSyncService.rememberMintQuoteTimestamp(it.id)
            }
        }

    suspend fun checkMintQuote(quoteId: String): MintQuoteInfo =
        withLoadingResult {
            gateway.checkMintQuote(quoteId).also {
                mintQuoteSyncService.rememberMintQuoteTimestamp(it.id)
            }
        }

    suspend fun pollMintQuote(quoteId: String): MintQuoteInfo =
        gateway.checkMintQuote(quoteId).also {
            mintQuoteSyncService.rememberMintQuoteTimestamp(it.id)
        }

    fun subscribeToMintQuote(quoteId: String): Flow<MintQuoteInfo> =
        gateway.subscribeToMintQuote(quoteId) { mintQuoteSyncService.shouldAttempt(quoteId) }

    override suspend fun mintTokens(quoteId: String): Long =
        mintTokens(
            quoteId = quoteId,
            unit = "sat",
            confirmationOwner = ReceiveConfirmationOwner.InFlow,
        )

    suspend fun mintTokens(
        quoteId: String,
        unit: String,
        confirmationOwner: ReceiveConfirmationOwner,
    ): Long {
        val amount = withLoadingResult {
            gateway.mintTokens(quoteId).also {
                refreshBalance()
                loadTransactions()
            }
        }
        publishReceivedPayment(amount, unit, confirmationOwner)
        return amount
    }

    /**
     * Silent single-quote check + mint if paid. Used by Receive (per-quote
     * poll) and transaction detail open — must not flip the global loading
     * flag (passive UX).
     */
    internal suspend fun refreshPendingMintQuote(
        quoteId: String,
        confirmationOwner: ReceiveConfirmationOwner,
        force: Boolean = false,
        observingQuoteId: String? = null,
    ): MintQuoteSyncResult {
        val result = mintQuoteSyncService.syncPendingMintQuote(quoteId, force)
        // A prior status poll or websocket check may already have recovered
        // the issue saga. Re-read balances for an already-settled receive too.
        if (result.minted || result.hasSettledPayment) refreshBalance()
        loadTransactions(observingQuoteId = observingQuoteId)
        result.receivedAmount?.let { amount ->
            publishReceivedPayment(amount, result.unit, confirmationOwner)
        }
        return result
    }

    /** The detail's lifecycle owns this job; every tick reconciles only its quote. */
    internal suspend fun monitorDisplayedMintQuote(
        quoteId: String,
        confirmationOwner: ReceiveConfirmationOwner,
    ) {
        focusedMintQuoteMonitor.monitor(quoteId, refresh = { id ->
            try {
                refreshPendingMintQuote(
                    id,
                    confirmationOwner = confirmationOwner,
                    observingQuoteId = id,
                ).quote
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                AppLogger.wallet.error("Displayed mint quote sync failed", error)
                null
            }
        })
    }

    /** Advisory UI state only; NUT-25 paid/issued counters remain authoritative. */
    internal fun mintQuoteRetryStatus(quoteId: String) =
        mintQuoteSyncService.retryStatus(quoteId)

    internal fun shouldAttemptMintQuote(quoteId: String): Boolean =
        mintQuoteSyncService.shouldAttempt(quoteId)

    /**
     * Cooldown-gated sync for passive triggers (app start, resume, History
     * open, the foreground poll). Skips when a sync ran within
     * [MINT_QUOTE_SYNC_COOLDOWN_MS]. Pull-to-refresh calls
     * [syncPendingMintQuotes] with `force = true` (explicit user intent).
     * iOS `syncPendingMintQuotesIfStale` parity.
     */
    suspend fun syncPendingMintQuotesIfStale() {
        val last = lastMintQuoteSyncAtMs.get()
        if (last != 0L && System.currentTimeMillis() - last < MINT_QUOTE_SYNC_COOLDOWN_MS) return
        syncPendingMintQuotes(force = false)
    }

    /**
     * Reconcile every persisted mint quote individually. CDK's unissued list
     * deliberately retains all BOLT12 quotes forever, so a reusable offer is
     * checked after dismissal, suspension, and relaunch as well as while its QR
     * is visible. Every path uses [WalletMintQuoteSyncService]'s single lane and
     * verifies `amountPaid` against `amountIssued` before reporting success.
     * Silent by design (iOS parity): must never flip the global loading flag.
     *
     * @param force when false (poll / startup / History open), the pass only
     *   runs when the gateway lane is idle enough; when true (pull-to-refresh),
     *   it preempts cooldown gating (explicit user intent).
     */
    suspend fun syncPendingMintQuotes(force: Boolean = false): Int {
        if (!force && focusedMintQuoteMonitor.isActive) return 0
        // Passive triggers collapse while an existing pass is active. An
        // explicit user refresh waits its turn instead of being silently
        // discarded — this makes `force` real rather than a documentation-only
        // parameter and matches iOS's coordinated forced lane.
        if (force) {
            mintQuoteSweepMutex.lock()
        } else if (!mintQuoteSweepMutex.tryLock()) {
            return 0
        }
        lastMintQuoteSyncAtMs.set(System.currentTimeMillis())
        try {
            val databaseQuotes = runCatching { gateway.listUnissuedMintQuotes() }
                .onFailure { AppLogger.wallet.error("Mint quote ledger scan failed", it) }
                .getOrDefault(emptyList())
            // App intents are a second durable index. Usually these IDs are
            // already in CDK's list; the union also surfaces a missing local
            // quote instead of silently dropping an older/migrated offer.
            val intentQuoteIds = cashuRequestStore.state.value.requests.mapNotNull { it.quoteId }
            val quoteIds = (databaseQuotes.map { it.id } + intentQuoteIds).distinct().sorted()
            if (!force && focusedMintQuoteMonitor.isActive) return 0
            val selectedQuoteIds = mintQuoteSyncService.selectQuoteIdsForSync(
                quoteIds,
                force,
                unsettledOnchainQuoteIds = databaseQuotes.filter {
                    it.paymentMethod == PaymentMethodKind.Onchain && it.amountIssued == 0L
                }.map { it.id }.toSet(),
            )
            if (selectedQuoteIds.isEmpty()) return 0

            var mintedQuotes = 0
            for (quoteId in selectedQuoteIds) {
                if (!force && focusedMintQuoteMonitor.isActive) break
                val result = mintQuoteSyncService.syncPendingMintQuote(quoteId, force)
                result.receivedAmount?.let { amount ->
                    mintedQuotes += 1
                    publishReceivedPayment(
                        amount = amount,
                        unit = result.unit,
                        confirmationOwner = ReceiveConfirmationOwner.Home,
                    )
                }
                // Each gateway call releases its native mutex. Yield between
                // rows so foreground user work can acquire it before the next
                // maintenance quote; the passive batch itself is capped at two.
                if (!force) yield()
            }
            if (mintedQuotes > 0) refreshBalance()
            loadTransactions(includeRemoteObservations = !focusedMintQuoteMonitor.isActive)
            return mintedQuotes
        } finally {
            mintQuoteSweepMutex.unlock()
        }
    }

    override fun isNPCQuoteProcessed(quoteId: String): Boolean =
        quoteId in processedNPCQuotes || quoteId in walletStore.loadProcessedNPCQuotes()

    override suspend fun claimNPCQuote(quote: NPCQuote, p2pkPubkey: String?): Boolean {
        if (isNPCQuoteProcessed(quote.id) || quote.id in npcQuotesInFlight) return true
        npcQuotesInFlight += quote.id
        return try {
            val mintUrl = quote.mintUrl ?: mutableState.value.activeMint?.url
                ?: throw IllegalStateException("npub.cash quote ${quote.id} has no mint URL.")
            val normalizedMintUrl = ensureMintTracked(mintUrl)
            val amount = gateway.mintNPCQuote(quote.copy(mintUrl = normalizedMintUrl), p2pkPubkey)
            markNPCQuoteProcessed(quote.id)
            p2pkPubkey?.let(settingsManager::markP2PKKeyUsed)
            refreshBalance()
            loadTransactions()
            publishReceivedPayment(
                amount = amount,
                unit = "sat",
                confirmationOwner = ReceiveConfirmationOwner.Home,
            )
            amount > 0 || isNPCQuoteProcessed(quote.id)
        } catch (error: Throwable) {
            if (mintQuoteSyncService.isAlreadyIssuedMintError(error)) {
                markNPCQuoteProcessed(quote.id)
                true
            } else {
                AppLogger.wallet.error("Failed to mint NPC quote ${quote.id}", error)
                false
            }
        } finally {
            npcQuotesInFlight -= quote.id
        }
    }

    override suspend fun createMeltQuote(request: String, amountSats: Long?, preferredMintURL: String?): MeltQuoteInfo =
        withLoadingResult { gateway.createMeltQuote(request, amountSats, preferredMintURL) }

    override suspend fun meltTokens(quoteId: String, mintUrl: String?): MeltPaymentResult =
        withLoadingResult {
            val confirmation = try {
                gateway.meltTokens(quoteId, mintUrl)
            } catch (failure: com.cashu.me.Core.CDK.MeltPaymentRecoveryException) {
                refreshBalance()
                loadTransactions()
                throw failure
            }
            val result = confirmation.result
            val pendingMelt = confirmation.pendingMelt
            if (pendingMelt != null) {
                // Mint accepted the payment for asynchronous NUT-05 settlement
                // (the usual case for on-chain melts). CDK persists the melt as
                // a Pending transaction backed by a durable saga, so no local
                // bookkeeping is needed; the in-process waiter below completes
                // the fast path and startup/foreground recovery the slow one.
                watchPendingMelt(pendingMelt, quoteId)
            }
            refreshBalance()
            loadTransactions()
            result
        }

    // MARK: - Asynchronous melt settlement (NUT-05, iOS WalletManager+PendingMelts parity)

    /**
     * Wait in the background for an async-accepted melt that is still pending
     * after the gateway's in-lane lightning wait gave up (or is on-chain,
     * which never waits in-lane). Re-`wait()`ing the same handle creates a
     * fresh Rust future, so re-arming after the capped wait is sound. One
     * waiter per quote; the waiter dies with the process and
     * [syncPendingMeltQuotes] takes over after relaunch. Settlement facts
     * (preimage, actual fee) persist on the CDK transaction itself — no
     * app-side metadata to write.
     */
    private fun watchPendingMelt(pendingMelt: PendingMelt, quoteId: String) {
        if (pendingMeltWaiters[quoteId]?.isActive == true) return
        pendingMeltWaiters[quoteId] = scope.launch {
            try {
                withContext(Dispatchers.IO) { pendingMelt.wait() }
                refreshBalance()
                loadTransactions()
            } catch (error: Throwable) {
                // Recovery polling retries the reconciliation later.
                AppLogger.wallet.error("Pending melt wait failed for quote $quoteId", error)
            } finally {
                pendingMeltWaiters.remove(quoteId)
            }
        }
    }

    /**
     * Reconcile melts still recorded as pending — e.g. after a relaunch killed
     * the in-process waiter. CDK's saga recovery re-checks in-flight melts
     * with their mints and flips the transactions to completed/failed when
     * settlement resolves. Cheap no-op when no saga is incomplete.
     */
    suspend fun syncPendingMeltQuotes() {
        if (!mutableState.value.isRuntimeReady) return

        var settledAny = false
        mutableState.value.mints.forEach { mint ->
            runCatching { gateway.recoverIncompleteSagas(mint.url) }
                .onSuccess { report ->
                    if (report.recovered > 0 || report.compensated > 0) settledAny = true
                }
                .onFailure { AppLogger.wallet.error("Pending melt reconciliation failed for ${mint.url}", it) }
        }

        if (settledAny) {
            refreshBalance()
            loadTransactions()
        }
    }

    // MARK: - Foreground quote polling

    /**
     * iOS `scenePhase == .active` parity: one-shot stale mint/melt sync, then
     * arm the repeating poll. Safe to call repeatedly (poll start is
     * idempotent; mint sync is cooldown-gated).
     */
    fun onAppEnteredForeground() {
        if (!pollQuotesInForeground) return
        startPendingQuoteForegroundPolling()
        if (!mutableState.value.isRuntimeReady) return
        npcService.initializeIfEnabled()
        scope.launch {
            try {
                syncPendingMintQuotesIfStale()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                AppLogger.wallet.error("Foreground mint quote sync failed", error)
            }
            try {
                syncPendingMeltQuotes()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                AppLogger.wallet.error("Foreground melt quote sync failed", error)
            }
        }
    }

    /**
     * While the app is active, re-check pending quotes every
     * [PENDING_QUOTE_POLL_INTERVAL_MS] so a payment lands on its own — e.g. a
     * BOLT12 offer paid from another wallet while Home sits open — instead of
     * waiting for pull-to-refresh. The mint sync stays cooldown-gated (the
     * poll interval equals [MINT_QUOTE_SYNC_COOLDOWN_MS], so this never
     * exceeds one pass per interval); the melt sync is a cheap no-op unless a
     * NUT-05 async melt is tracked and its in-process waiter died.
     * Started/stopped from `CashuApp` via [ProcessLifecycleOwner] ON_START /
     * ON_STOP (not the Activity — ModalBottomSheet dialogs must not stop it).
     */
    fun startPendingQuoteForegroundPolling() {
        if (!pollQuotesInForeground) return
        if (pendingQuotePollJob?.isActive == true) return
        pendingQuotePollJob = scope.launch {
            while (isActive) {
                // Delay first: [onAppEnteredForeground] already did the immediate
                // pass (iOS poll-loop + scenePhase one-shot shape).
                delay(PENDING_QUOTE_POLL_INTERVAL_MS)
                if (!isActive) break
                if (!mutableState.value.isRuntimeReady) continue
                try {
                    syncPendingMintQuotesIfStale()
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Throwable) {
                    AppLogger.wallet.error("Foreground mint quote sync failed", error)
                }
                try {
                    syncPendingMeltQuotes()
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Throwable) {
                    AppLogger.wallet.error("Foreground melt quote sync failed", error)
                }
            }
        }
    }

    fun stopPendingQuoteForegroundPolling() {
        pendingQuotePollJob?.cancel()
        pendingQuotePollJob = null
    }

    override suspend fun sendTokens(amount: Long, memo: String?, p2pkPubkey: String?, mintUrl: String?, unit: String): SendTokenResult {
        val selectedMint = mintUrl ?: mutableState.value.activeMint?.url ?: throw IllegalStateException("No active mint.")
        val normalizedP2PKPubkey = SettingsManager.normalizeP2PKPublicKeyForSend(p2pkPubkey)
        return withLoadingResult {
            val result = gateway.sendEcashToken(
                amount,
                memo,
                normalizedP2PKPubkey,
                selectedMint,
                unit,
                // Full signing set so proofs already locked to our keys can be
                // swapped into the outgoing token (iOS TokenService parity).
                settingsManager.allP2PKSigningKeyHexes(),
            )
            // Keep the token string under its (stable, saga-derived) CDK
            // transaction id so History can re-display it and claim checks can
            // resolve the send operation. Lifecycle state lives in CDK itself.
            result.transactionId?.let { transactionId ->
                walletStore.saveSavedTokens(walletStore.loadSavedTokens() + (transactionId to result.token))
            }
            normalizedP2PKPubkey?.let(settingsManager::markP2PKKeyUsed)
            refreshBalance()
            loadTransactions()
            result
        }
    }

    override suspend fun receiveTokens(tokenString: String): Long =
        receiveTokens(
            tokenString = tokenString,
            confirmationOwner = ReceiveConfirmationOwner.InFlow,
        )

    private suspend fun receiveTokens(
        tokenString: String,
        confirmationOwner: ReceiveConfirmationOwner?,
    ): Long {
        val unit = com.cashu.me.Models.TokenInfo.parse(tokenString)?.unit ?: "sat"
        val amount = withLoadingResult {
            val p2pkPubkeys = TokenParser.p2pkPubkeys(tokenString)
            val signingKeys = settingsManager.p2pkSigningKeysFor(p2pkPubkeys)
            gateway.receiveEcashToken(tokenString, signingKeys).also {
                p2pkPubkeys.forEach(settingsManager::markP2PKKeyUsed)
                // iOS parity (WalletManager+Tokens.receiveTokens): track the
                // token's mint only after a successful receive, so an
                // unredeemed token never adds the mint. Without this,
                // refreshBalance/loadTransactions skip the unknown mint and
                // the claimed funds stay invisible.
                trackMintForReceivedToken(
                    tokenString = tokenString,
                    onTrackingFailed = {
                        AppLogger.wallet.error("Failed to track mint for received token", it)
                    },
                    ensureMintTracked = { ensureMintTracked(it) },
                )
                refreshBalance()
                loadTransactions()
            }
        }
        confirmationOwner?.let { publishReceivedPayment(amount, unit, it) }
        return amount
    }

    suspend fun receiveCashuRequestPayment(
        tokenString: String,
        requestId: String?,
        processedId: String? = requestId,
        confirmationOwner: ReceiveConfirmationOwner = ReceiveConfirmationOwner.InFlow,
    ): Long {
        val normalizedProcessedId = processedId?.trim()?.takeIf { it.isNotEmpty() }
        if (normalizedProcessedId != null && normalizedProcessedId in walletStore.loadProcessedCashuRequests()) {
            return 0
        }
        val amount = receiveTokens(tokenString, confirmationOwner)
        normalizedProcessedId?.let { id ->
            walletStore.saveProcessedCashuRequests((walletStore.loadProcessedCashuRequests() + id).distinct().sorted())
        }
        return amount
    }

    fun isMintKnown(url: String): Boolean {
        val normalized = normalizedMintUrlForSelection(url) ?: return false
        return state.value.mints.any {
            normalizedMintUrlForSelection(it.url) == normalized
        }
    }

    suspend fun receiveNfcCashuRequestPayment(
        tokenString: String,
        processedId: String,
    ): com.cashu.me.Core.CDK.NfcReceiveReceipt {
        val unit = com.cashu.me.Models.TokenInfo.parse(tokenString)?.unit ?: "sat"
        val receipt = withLoadingResult {
            require(processedId !in walletStore.loadProcessedCashuRequests()) { "This payment was already received." }
            val p2pkPubkeys = TokenParser.p2pkPubkeys(tokenString)
            val signingKeys = settingsManager.p2pkSigningKeysFor(p2pkPubkeys)
            gateway.receiveNfcEcashToken(tokenString, signingKeys).also {
                p2pkPubkeys.forEach(settingsManager::markP2PKKeyUsed)
                trackMintForReceivedToken(
                    tokenString = tokenString,
                    onTrackingFailed = { AppLogger.wallet.error("Failed to track mint for received NFC token", it) },
                    ensureMintTracked = { ensureMintTracked(it) },
                )
                walletStore.saveProcessedCashuRequests(
                    (walletStore.loadProcessedCashuRequests() + processedId).distinct().sorted(),
                )
                refreshBalance()
                loadTransactions()
            }
        }
        publishReceivedPayment(
            receipt.amountReceived,
            unit,
            ReceiveConfirmationOwner.InFlow,
        )
        return receipt
    }

    suspend fun settleForeignNfcToken(
        tokenString: String,
        settlementMintUrl: String,
        processedId: String,
    ): com.cashu.me.Core.CDK.ForeignNfcSettlement {
        val unit = com.cashu.me.Models.TokenInfo.parse(tokenString)?.unit ?: "sat"
        val settlement = withLoadingResult {
            require(processedId !in walletStore.loadProcessedCashuRequests()) { "This payment was already received." }
            val source = requireNotNull(com.cashu.me.Models.TokenInfo.parse(tokenString)) { "Invalid token." }
            // Persist discovery before CDK may consume proofs. Source change and
            // compensated funds must remain visible and participate in startup recovery.
            ensureMintTracked(source.mint)
            ensureMintTracked(settlementMintUrl)
            try {
                gateway.settleForeignNfcToken(tokenString, settlementMintUrl).also {
                    walletStore.saveProcessedCashuRequests(
                        (walletStore.loadProcessedCashuRequests() + processedId).distinct().sorted(),
                    )
                }
            } finally {
                refreshBalance()
                loadTransactions()
            }
        }
        publishReceivedPayment(
            settlement.amountReceived,
            unit,
            ReceiveConfirmationOwner.InFlow,
        )
        return settlement
    }

    fun savePendingReceiveToken(token: PendingReceiveToken) {
        val current = walletStore.loadPendingReceiveTokens()
        val updated = PendingReceiveToken.upsert(current, token)
        walletStore.savePendingReceiveTokens(updated)
        update { copy(pendingReceiveTokens = updated) }
    }

    fun removePendingReceiveToken(tokenId: String) {
        val updated = walletStore.loadPendingReceiveTokens().filterNot { it.tokenId == tokenId }
        walletStore.savePendingReceiveTokens(updated)
        update { copy(pendingReceiveTokens = updated) }
    }

    suspend fun claimPendingReceiveToken(token: PendingReceiveToken): Long {
        val amount = if (token.cashuRequestId != null || token.processedId != null) {
            receiveCashuRequestPayment(
                tokenString = token.token,
                requestId = token.cashuRequestId,
                processedId = token.processedId,
            ).also { received ->
                if (received > 0 && !token.cashuRequestId.isNullOrBlank()) {
                    cashuRequestStore.attachPayment(
                        requestId = token.cashuRequestId,
                        transactionId = token.processedId ?: token.cashuRequestId,
                        amount = received,
                    )
                }
            }
        } else {
            receiveTokens(token.token, ReceiveConfirmationOwner.InFlow)
        }
        removePendingReceiveToken(token.tokenId)
        return amount
    }

    suspend fun checkPendingTokenStatus(transaction: WalletTransaction): Boolean =
        withLoadingResult {
            val claimed = checkPendingSendClaimInternal(transaction)
            if (claimed) {
                refreshBalance()
                loadTransactions()
            }
            claimed
        }

    private suspend fun checkPendingSendClaimInternal(transaction: WalletTransaction): Boolean {
        val mintUrl = transaction.mintUrl ?: return false
        val sagaId = transaction.sagaId
        if (sagaId != null) {
            return gateway.checkPendingSendClaimed(mintUrl, sagaId, transaction.unit)
        }
        // App-synthesized rows carry no operation; fall back to a direct
        // proof-state probe against the mint.
        val token = transaction.token ?: return false
        return gateway.checkTokenSpendable(token, mintUrl)
    }

    /** Manual claim check for a just-created send, where the caller only holds
     * the token string (Send flow success screen). iOS parity. */
    suspend fun checkSentTokenClaim(token: String, mintUrl: String, unit: String = "sat"): Boolean =
        withLoadingResult {
            val txId = walletStore.loadSavedTokens().entries.firstOrNull { it.value == token }?.key
            val operationId = txId?.let(SagaTransactionId::operationId)
            if (operationId != null) {
                return@withLoadingResult runCatching {
                    gateway.checkPendingSendClaimed(mintUrl, operationId, unit)
                }.getOrDefault(false)
            }
            // The token predates transaction-id-keyed storage (or came from
            // elsewhere): probe the proofs directly.
            gateway.checkTokenSpendable(token, mintUrl)
        }

    suspend fun checkAllPendingTokens(): Int {
        if (!mutableState.value.isRuntimeReady) return 0

        return withLoadingResult {
            var claimedCount = 0
            var foundPending = false
            transactionUnitsByMint(mutableState.value.mints).forEach { (mintUrl, units) ->
                units.forEach { unit ->
                    gateway.listPendingSendOperationIds(mintUrl, unit).forEach { operationId ->
                        foundPending = true
                        val claimed = runCatching {
                            gateway.checkPendingSendClaimed(mintUrl, operationId, unit)
                        }.getOrDefault(false)
                        if (claimed) claimedCount += 1
                    }
                }
            }
            // No local rows to merge anymore: only a claim changes history.
            if (claimedCount > 0) {
                refreshBalance()
                loadTransactions()
            } else if (foundPending) {
                loadTransactions()
            }
            claimedCount
        }
    }

    /**
     * Reclaim an unclaimed sent token: CDK swaps the proofs back and marks the
     * transaction failed/revoked, so no local bookkeeping remains.
     */
    suspend fun reclaimPendingSend(transaction: WalletTransaction): Long {
        val sagaId = transaction.sagaId
            ?: throw IllegalStateException("Transaction has no send operation to revoke.")
        val mintUrl = transaction.mintUrl
            ?: throw IllegalStateException("Transaction has no mint to revoke from.")
        return withLoadingResult {
            val amount = gateway.revokePendingSend(mintUrl, sagaId, transaction.unit)
            refreshBalance()
            loadTransactions()
            amount
        }
    }

    suspend fun calculateReceiveFee(tokenString: String): Long = gateway.calculateReceiveFee(tokenString)

    suspend fun estimateCashuPaymentRequestFee(amountSats: Long, mintUrl: String): Long =
        gateway.estimateCashuPaymentRequestFee(amountSats, mintUrl)

    suspend fun checkTokenSpent(tokenString: String, mintUrl: String): Boolean =
        gateway.checkTokenSpendable(tokenString, mintUrl)

    suspend fun payCashuPaymentRequest(encoded: String, customAmountSats: Long?, preferredMintURL: String?) {
        withLoading {
            payCashuPaymentRequestAndRefresh(
                encoded = encoded,
                customAmountSats = customAmountSats,
                preferredMintURL = preferredMintURL,
                payCashuPaymentRequest = { request, amount, mintUrl ->
                    gateway.payCashuPaymentRequest(request, amount, mintUrl)
                },
                refreshBalance = { refreshBalance() },
                loadTransactions = { loadTransactions() },
            )
        }
    }

    /**
     * Acquire ecash at the requested mint, then pay the Cashu Request.
     *
     * A different held mint funds the target over BOLT11 when possible. If no
     * held mint can cover the transfer and its fee reserve, return the already
     * created target quote so the UI can collect an explicit external top-up.
     */
    internal suspend fun acquireAndPayCashuPaymentRequest(
        encoded: String,
        amountSats: Long,
        targetMintUrl: String,
    ): CashuRequestAcquireResult = withLoadingResult {
        val trackedTargetMintUrl = ensureMintTracked(targetMintUrl)
        val inputFeePpk = try {
            gateway.activeMintInputFeePpk(trackedTargetMintUrl)
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (_: Throwable) {
            null
        }
        val mintAmount = cashuRequestTopUpAmount(amountSats, inputFeePpk)
        val targetQuote = gateway.createMintQuote(
            amount = mintAmount,
            method = PaymentMethodKind.Bolt11,
            mintUrl = trackedTargetMintUrl,
            unit = "sat",
        ).also { mintQuoteSyncService.rememberMintQuoteTimestamp(it.id) }

        val source = selectCashuRequestFundingSource(
            mints = mutableState.value.mints,
            targetMintUrl = trackedTargetMintUrl,
            requiredAmountSats = mintAmount,
        ) ?: return@withLoadingResult CashuRequestAcquireResult.NeedsExternalTopUp(
            quote = targetQuote,
            targetMintUrl = trackedTargetMintUrl,
            requestedAmountSats = amountSats,
        )

        val sourceMeltQuote = try {
            gateway.createMeltQuote(
                request = targetQuote.request,
                amountSats = null,
                preferredMintURL = source.url,
            )
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (failure: Throwable) {
            if (failure.isInsufficientBalance) {
                return@withLoadingResult CashuRequestAcquireResult.NeedsExternalTopUp(
                    quote = targetQuote,
                    targetMintUrl = trackedTargetMintUrl,
                    requestedAmountSats = amountSats,
                )
            }
            throw failure
        }

        if (sourceMeltQuote.totalAmount > source.balance) {
            return@withLoadingResult CashuRequestAcquireResult.NeedsExternalTopUp(
                quote = targetQuote,
                targetMintUrl = trackedTargetMintUrl,
                requestedAmountSats = amountSats,
            )
        }

        val fundingConfirmation = gateway.meltTokens(sourceMeltQuote.id, source.url)
        fundingConfirmation.pendingMelt?.let { watchPendingMelt(it, sourceMeltQuote.id) }
        refreshBalance()
        loadTransactions()

        finishCashuRequestTopUpAndPayInternal(
            encoded = encoded,
            amountSats = amountSats,
            targetMintUrl = trackedTargetMintUrl,
            quoteId = targetQuote.id,
        )
        CashuRequestAcquireResult.Paid(fundingConfirmation.result)
    }

    /** Finish an externally-paid target quote, then pay the pending request. */
    internal suspend fun finishCashuRequestTopUpAndPay(
        encoded: String,
        amountSats: Long,
        targetMintUrl: String,
        quoteId: String,
    ) {
        withLoading {
            finishCashuRequestTopUpAndPayInternal(encoded, amountSats, targetMintUrl, quoteId)
        }
    }

    private suspend fun finishCashuRequestTopUpAndPayInternal(
        encoded: String,
        amountSats: Long,
        targetMintUrl: String,
        quoteId: String,
    ) {
        mintCashuRequestTopUpWithRetries(quoteId)
        try {
            gateway.payCashuPaymentRequest(encoded, amountSats, targetMintUrl)
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (failure: Throwable) {
            if (failure.isInsufficientBalance) throw CashuRequestMintSettling()
            throw failure
        }
        refreshBalance()
        loadTransactions()
    }

    private suspend fun mintCashuRequestTopUpWithRetries(quoteId: String) {
        repeat(8) { attempt ->
            val quote = try {
                gateway.checkMintQuote(quoteId)
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (_: Throwable) {
                null
            }
            when (quote?.state) {
                MintQuoteState.Issued -> return
                MintQuoteState.Paid -> {
                    try {
                        gateway.mintTokens(quoteId)
                        return
                    } catch (cancellation: CancellationException) {
                        throw cancellation
                    } catch (failure: Throwable) {
                        if (mintQuoteSyncService.isAlreadyIssuedMintError(failure)) return
                    }
                }
                else -> Unit
            }
            if (attempt < 7) delay(2_500)
        }
        throw CashuRequestMintSettling()
    }

    suspend fun loadTransactions(
        includeRemoteObservations: Boolean = true,
        observingQuoteId: String? = null,
    ) {
        val result = transactionLoader.load(
            mutableState.value.mints, includeRemoteObservations, observingQuoteId,
        )
        // Quote-backed requests (notably the long-lived BOLT12 offer) own their
        // received payments in history. Reconcile before publishing so the UI
        // shows the one reusable-invoice row rather than duplicate payments.
        cashuRequestStore.reconcileIncomingQuotePayments(result.transactions)
        update {
            copy(
                transactions = result.transactions,
                pendingReceiveTokens = result.pendingReceiveTokens,
                transactionUpdateVersion = nextTransactionUpdateVersion(transactionUpdateVersion),
            )
        }
    }

    fun clearError() = update { copy(errorMessage = null, startupFailure = null) }

    fun backupMnemonic(): String? = secureStorage.loadString(StorageKeys.secureWalletMnemonic)

    fun openRestoreFlow() {
        if (!secureStorage.contains(StorageKeys.secureWalletMnemonic)) return
        update { copy(needsOnboarding = true, canExitOnboarding = true, errorMessage = null) }
    }

    fun closeRestoreFlow() {
        if (!mutableState.value.canExitOnboarding) return
        update { copy(needsOnboarding = false, errorMessage = null) }
    }

    suspend fun completeOnboarding() {
        settingsManager.onboardingCompleted = true
        settingsManager.walletRestoreIncomplete = false
        loadCachedState(needsOnboarding = false)
        refreshBalance()
        loadTransactions()
    }

    /** Restore complete (iOS completeRestore): dismiss onboarding, then refresh the Nostr backup. */
    suspend fun completeRestore() {
        completeOnboarding()
        // The restored mint list is final now — refresh the Nostr backup with it.
        // (Must not run earlier: publishing while the repository is still empty
        // would replace the addressable backup event with an empty list.)
        if (externalServicesEnabled) {
            scope.launch { nostrMintBackupService.backupCurrentMintsIfEnabled() }
        }
    }

    private fun decodeReplacementSnapshot(encoded: String): WalletReplacementSnapshot = try {
        Json.decodeFromString<WalletReplacementSnapshot>(encoded)
    } catch (_: Exception) {
        // Serialization diagnostics can include input values; this payload contains secrets.
        throw IllegalStateException("Wallet recovery state could not be decoded.")
    }

    private suspend fun recoverWalletReplacement() = withContext(Dispatchers.IO) {
        replacement.recover(
            restoreState = { encoded ->
                val snapshot = decodeReplacementSnapshot(encoded)
                if (snapshot.mnemonic == null) secureStorage.delete(StorageKeys.secureWalletMnemonic)
                else secureStorage.saveString(StorageKeys.secureWalletMnemonic, snapshot.mnemonic)
                walletStore.restoreWalletScopedData(snapshot.wallet)
                settingsManager.restoreWalletScopedData(snapshot.settings)
                nwcManager.restoreWalletScopedData(snapshot.nwc)
                npcService.restoreWalletScopedData(snapshot.npc)
                cashuRequestStore.reload()
                nostrMintBackupService.reloadStoredState()
            },
            cleanupCommittedState = { encoded ->
                val snapshot = decodeReplacementSnapshot(encoded)
                settingsManager.deleteWalletScopedSecrets(snapshot.settings, deleteNostrPrivateKey = false)
                // Cleanup may be retried on a later launch. Do not delete a new
                // imported key the user saved after this replacement committed.
                if (snapshot.nostrPrivateKey != null &&
                    secureStorage.loadString(StorageKeys.secureNostrPrivateKey) == snapshot.nostrPrivateKey
                ) secureStorage.delete(StorageKeys.secureNostrPrivateKey)
            },
        )
    }

    private suspend fun installCleanWallet(mnemonic: String, needsOnboarding: Boolean, restoring: Boolean = false) = initializationMutex.withLock {
        // Finish any previous recovery before starting another replacement.
        recoverWalletReplacement()
        val previousMnemonic = secureStorage.loadString(StorageKeys.secureWalletMnemonic)
        cashuRequestListener?.pauseForWalletBoundary()
        npcService.pauseForWalletBoundary()
        pendingQuotePollJob?.cancelAndJoin()
        startupMaintenanceJob?.cancelAndJoin()
        pendingMeltWaiters.values.toList().forEach { it.cancelAndJoin() }
        pendingMeltWaiters.clear()
        nwcManager.stop()
        gateway.closeWalletRepository()
        update { copy(isRuntimeReady = false) }

        runWalletReplacementCommit(
            installAndCommit = {
                withContext(Dispatchers.IO) { databasePathManager.checkpointBeforeReplacement() }
                val snapshot = WalletReplacementSnapshot(
                    mnemonic = previousMnemonic,
                    nostrPrivateKey = secureStorage.loadString(StorageKeys.secureNostrPrivateKey),
                    wallet = walletStore.snapshotWalletScopedData(),
                    settings = settingsManager.snapshotWalletScopedData(),
                    nwc = nwcManager.snapshotWalletScopedData(),
                    npc = npcService.snapshotWalletScopedData(),
                )
                withContext(Dispatchers.IO) { replacement.begin(Json.encodeToString(snapshot)) }
                nwcManager.resetForWalletBoundary()
                cashuRequestStore.resetForWalletBoundary()
                walletStore.removeAllWalletData()
                settingsManager.prepareForWalletReplacement()
                settingsManager.walletRestoreIncomplete = restoring
                nostrService.resetForWalletBoundary(deleteStoredKey = false)
                npcService.resetForWalletBoundary()
                openWalletRepositoryWithRecovery(mnemonic)
                deriveNostrKey(mnemonic)
                secureStorage.saveString(StorageKeys.secureWalletMnemonic, mnemonic)
                nostrMintBackupService.resetForWalletBoundary()
                settingsManager.onboardingCompleted = !needsOnboarding
                withContext(Dispatchers.IO) { replacement.commit() }
            },
            rollback = {
                gateway.closeWalletRepository()
                recoverWalletReplacement()
                val recoveredMnemonic = secureStorage.loadString(StorageKeys.secureWalletMnemonic)
                if (recoveredMnemonic != null) {
                    npcService.reloadStoredSettings()
                    openWalletRepositoryWithRecovery(recoveredMnemonic)
                    deriveNostrKey(recoveredMnemonic)
                    loadCachedState(needsOnboarding = !settingsManager.onboardingCompleted || settingsManager.walletRestoreIncomplete)
                    update { copy(isRuntimeReady = true) }
                    if (startNwc) nwcManager.startIfEnabled()
                } else {
                    update { WalletState(isInitialized = true, isRuntimeReady = true, needsOnboarding = true) }
                }
                cashuRequestListener?.resetForWalletBoundary(restart = externalServicesEnabled && previousMnemonic != null)
            },
            cleanupSteps = listOf(WalletReplacementCleanupStep("wallet recovery journal") { recoverWalletReplacement() }),
            onCleanupFailure = { description, error -> AppLogger.wallet.error("Post-commit $description cleanup failed", error) },
        )
        loadCachedState(needsOnboarding = needsOnboarding)
        update { copy(isRuntimeReady = true) }
        cashuRequestListener?.resetForWalletBoundary(restart = externalServicesEnabled && !needsOnboarding)
    }

    private fun loadCachedState(needsOnboarding: Boolean) {
        val mints = walletStore.loadMints()
        val cachedBalance = mints.sumOf { it.balance }
        val cachedBalancesByUnit = walletStore.loadBalancesByUnit().toMutableMap().apply {
            this["sat"] = cachedBalance
        }
        val active = activeMintFrom(mints)
        val transactions = walletStore.loadTransactions()
        val pendingReceiveTokens = walletStore.loadPendingReceiveTokens()
        processedNPCQuotes = walletStore.loadProcessedNPCQuotes().toMutableSet()
        update {
            copy(
                balance = cachedBalance,
                balancesByUnit = cachedBalancesByUnit,
                isInitialized = true,
                isLoading = false,
                needsOnboarding = needsOnboarding,
                canExitOnboarding = secureStorage.contains(StorageKeys.secureWalletMnemonic),
                mints = mints,
                activeMint = active,
                transactions = transactions,
                pendingReceiveTokens = pendingReceiveTokens,
            )
        }
    }

    private fun markNPCQuoteProcessed(quoteId: String) {
        processedNPCQuotes += quoteId
        walletStore.saveProcessedNPCQuotes(processedNPCQuotes.sorted())
    }

    private fun activeMintFrom(mints: List<MintInfo>): MintInfo? {
        val saved = walletStore.activeMintURL
        return mints.firstOrNull { it.url == saved } ?: mints.firstOrNull()
    }

    private suspend fun ensureMintTracked(url: String): String {
        val normalized = mintMetadataFetcher.normalizeMintUrl(url)
        runCatching { gateway.ensureWallet(normalized) }
            .onFailure { AppLogger.wallet.error("CDK wallet preparation is not available yet for $normalized", it) }
        if (walletStore.loadMints().any { it.url == normalized }) return normalized

        val fetched = runCatching { gateway.fetchMintInfo(normalized) }.getOrElse {
            AppLogger.wallet.error("Failed to fetch CDK mint info for $normalized", it)
            MintInfo(
                url = normalized,
                name = runCatching { URL(normalized).host }.getOrNull() ?: "Unknown Mint",
            )
        } ?: MintInfo(
            url = normalized,
            name = runCatching { URL(normalized).host }.getOrNull() ?: "Unknown Mint",
        )
        val updated = walletStore.loadMints().filterNot { it.url == normalized } + fetched
        walletStore.saveMints(updated)
        if (walletStore.activeMintURL == null) walletStore.activeMintURL = fetched.url
        update {
            copy(
                mints = updated,
                activeMint = activeMintFrom(updated),
                balance = updated.sumOf { it.balance },
            )
        }
        return normalized
    }

    private suspend fun deriveNostrKey(mnemonic: String) {
        // The app's Nostr identity is the NIP-06 key (m/44'/1237'/0'/0/0)
        // derived from the same 64-byte BIP39 seed as the wallet — identical
        // to the npub.cash identity and reproducible by any NIP-06 client.
        // This matches iOS WalletManager+NPC exactly.
        runCatching {
            val seed = walletBip39Seed(mnemonic)
            nostrService.deriveKeypairFromSeed(
                NostrService.hexToBytes(npubcashDeriveSecretKeyFromSeed(seed)),
            )
        }.onFailure { AppLogger.wallet.error("Nostr key derivation failed", it) }

        runCatching {
            npcService.initializeWithSeed(walletBip39Seed(mnemonic))
        }.onFailure { AppLogger.wallet.error("npub.cash key derivation failed", it) }
    }

    private suspend fun openWalletRepositoryWithRecovery(mnemonic: String) {
        val databasePath = databasePathManager.databasePathAfterLegacyMigration()
        val initialResult = runCatching { gateway.openWalletRepository(mnemonic, databasePath) }
        val error = initialResult.exceptionOrNull() ?: return
        if (!shouldAttemptWalletDatabaseRecovery(error)) throw error
        val backup = databasePathManager.backupCorruptedDatabase() ?: throw error
        AppLogger.wallet.info("Wallet DB recovery: moved corrupted database to ${backup.absolutePath}")
        gateway.openWalletRepository(mnemonic, databasePath)
    }

    private suspend fun withLoading(block: suspend () -> Unit) {
        withLoadingResult { block() }
    }

    private suspend fun <T> withLoadingResult(block: suspend () -> T): T {
        update { copy(isLoading = true, errorMessage = null) }
        return try {
            block().also { update { copy(isLoading = false) } }
        } catch (cancellation: CancellationException) {
            update { copy(isLoading = false) }
            throw cancellation
        } catch (error: Throwable) {
            AppLogger.wallet.error("Wallet operation failed", error)
            update { copy(isLoading = false, errorMessage = error.message) }
            throw error
        }
    }

    private fun update(transform: WalletState.() -> WalletState) {
        mutableState.value = mutableState.value.transform()
    }

    private fun publishReceivedPayment(
        amount: Long,
        unit: String,
        confirmationOwner: ReceiveConfirmationOwner,
    ) {
        confirmedReceivedPaymentEvent(amount, unit, confirmationOwner)?.let {
            mutableReceivedPayments.tryEmit(it)
        }
    }

    internal val deletionAction by lazy {
        WalletDeletionAction(::launch, ::deleteWallet)
    }

    fun launch(block: suspend CoroutineScope.() -> Unit) {
        scope.launch { block() }
    }

    fun reopenOnboarding() {
        update { copy(needsOnboarding = true, canExitOnboarding = true) }
    }

    private companion object {
        // Minimum gap between passive mint-quote sync passes. Equal to the
        // foreground poll interval so the poll drives one pass per interval
        // (iOS `mintQuoteSyncCooldown` parity).
        const val MINT_QUOTE_SYNC_COOLDOWN_MS = 10_000L

        // How often the foreground poll re-checks pending quotes while the
        // app is active (iOS `pendingQuotePollInterval` parity).
        const val PENDING_QUOTE_POLL_INTERVAL_MS = 10_000L
    }
}

/** BIP39 PBKDF2-HMAC-SHA512 seed, with the NFKD normalization required by BIP39. */
internal fun walletBip39Seed(mnemonic: String, passphrase: String = ""): ByteArray {
    val password = Normalizer.normalize(mnemonic, Normalizer.Form.NFKD).toByteArray(Charsets.UTF_8)
    val salt = Normalizer.normalize("mnemonic$passphrase", Normalizer.Form.NFKD).toByteArray(Charsets.UTF_8)
    val generator = PKCS5S2ParametersGenerator(SHA512Digest()).apply {
        init(password, salt, 2_048)
    }
    return (generator.generateDerivedParameters(512) as KeyParameter).key
}
