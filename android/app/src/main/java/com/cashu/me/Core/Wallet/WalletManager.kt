package com.cashu.me.Core

import java.net.URL
import java.text.Normalizer
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.BufferOverflow
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
import org.cashudevkit.PendingMelt
import org.cashudevkit.QuoteState as CdkQuoteState
import com.cashu.me.Core.CDK.CdkWalletGateway
import com.cashu.me.Core.Platform.WalletDatabasePathManager
import com.cashu.me.Core.Platform.WalletFileBackup
import com.cashu.me.Core.Protocols.SecureStorage
import com.cashu.me.Core.Protocols.StorageKeys
import com.cashu.me.Core.Protocols.WalletServiceProtocol
import com.cashu.me.Models.MeltPaymentResult
import com.cashu.me.Models.MeltQuoteInfo
import com.cashu.me.Models.MeltQuoteState
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.MintQuoteInfo
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
    private data class WalletReplacementSnapshot(
        val databaseBackups: List<WalletFileBackup>,
        val wallet: PreferenceSnapshot,
        val settings: SettingsWalletScopedSnapshot,
        val nwc: NwcWalletScopedSnapshot,
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
    private val mintMetadataFetcher = WalletMintMetadataFetcher(allowCleartextLocalTestMints)
    private val mintQuoteSyncService = WalletMintQuoteSyncService(gateway, walletStore)
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
    private val isSyncingMintQuotes = AtomicBoolean(false)
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

    override suspend fun initialize() {
        initializationMutex.withLock {
            if (mutableState.value.isRuntimeReady) return@withLock

            withContext(Dispatchers.IO) {
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
                    loadCachedState(needsOnboarding = !settingsManager.onboardingCompleted)
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
        scope.launch(Dispatchers.IO) {
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
        withLoading { installCleanWallet(normalized, needsOnboarding = keepOnboarding) }
    }

    override suspend fun restoreWallet(mnemonic: String) {
        val normalized = MnemonicInput.normalize(mnemonic)
        require(MnemonicInput.hasSupportedWordCount(normalized)) {
            "Seed phrase must be ${MnemonicInput.supportedWordCountLabel} words."
        }
        require(gateway.validateMnemonic(normalized)) { "Invalid seed phrase." }
        withLoading {
            installCleanWallet(normalized, needsOnboarding = false)
        }
    }

    override suspend fun deleteWallet() {
        withLoading {
            cashuRequestListener?.pauseForWalletBoundary()
            nwcManager.resetForWalletBoundary()
            gateway.closeWalletRepository()
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
            runCatching { gateway.removeWallet(mint.url) }
                .onFailure { AppLogger.wallet.error("CDK wallet removal is not available yet for ${mint.url}", it) }
            val updated = mutableState.value.mints.filterNot { it.url == mint.url }
            walletStore.saveMints(updated)
            if (walletStore.activeMintURL == mint.url) {
                walletStore.activeMintURL = updated.firstOrNull()?.url
            }
            loadCachedState(needsOnboarding = false)
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

    override suspend fun createMintQuote(amount: Long?, method: PaymentMethodKind, unit: String): MintQuoteInfo {
        val active = mutableState.value.activeMint ?: throw IllegalStateException("No active mint.")
        return withLoadingResult {
            gateway.createMintQuote(amount, method, active.url, unit).also {
                mintQuoteSyncService.rememberMintQuoteTimestamp(it.id)
            }
        }
    }

    /** Returns the active mint's reusable amountless BOLT12 offer, if present. */
    suspend fun existingAmountlessBolt12Offer(unit: String): MintQuoteInfo? {
        val activeMint = mutableState.value.activeMint ?: return null
        return findExistingAmountlessBolt12Offer(
            quotes = gateway.listUnissuedMintQuotes(),
            mintUrl = activeMint.url,
            unit = unit,
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

    fun subscribeToMintQuote(quoteId: String): Flow<MintQuoteInfo> = gateway.subscribeToMintQuote(quoteId)

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
    suspend fun refreshPendingMintQuote(
        quoteId: String,
        confirmationOwner: ReceiveConfirmationOwner,
    ): Boolean {
        val result = mintQuoteSyncService.syncPendingMintQuote(quoteId)
        if (result.minted) refreshBalance()
        loadTransactions()
        result.receivedAmount?.let { amount ->
            publishReceivedPayment(amount, result.unit, confirmationOwner)
        }
        return result.minted
    }

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
     * Check every tracked wallet for paid-but-unissued mint quotes and mint
     * them (CDK 0.18 `mintUnissuedQuotes`): each quote's NUT-04 counters are
     * refreshed with the mint and only the outstanding delta is minted, which
     * covers reusable BOLT12 offers without any local heuristics.
     * Silent by design (iOS parity): must never flip the global loading flag.
     *
     * @param force when false (poll / startup / History open), the pass only
     *   runs when the gateway lane is idle enough; when true (pull-to-refresh),
     *   it preempts cooldown gating (explicit user intent).
     */
    suspend fun syncPendingMintQuotes(force: Boolean = false): Int {
        // Coarse in-flight guard: collapse overlapping triggers into one pass.
        if (!isSyncingMintQuotes.compareAndSet(false, true)) return 0
        lastMintQuoteSyncAtMs.set(System.currentTimeMillis())
        try {
            var mintedWallets = 0
            transactionUnitsByMint(mutableState.value.mints).forEach { (mintUrl, units) ->
                units.forEach { unit ->
                    val minted = runCatching { gateway.mintUnissuedQuotes(mintUrl, unit) }
                        .onFailure { AppLogger.wallet.error("Unissued quote sweep failed for $mintUrl ($unit)", it) }
                        .getOrDefault(0L)
                    if (minted > 0) {
                        mintedWallets += 1
                        // Home receive beat for a background-settled payment
                        // (e.g. a BOLT12 offer paid from another wallet).
                        publishReceivedPayment(
                            amount = minted,
                            unit = unit,
                            confirmationOwner = ReceiveConfirmationOwner.Home,
                        )
                    }
                }
            }
            if (mintedWallets > 0) refreshBalance()
            loadTransactions()
            return mintedWallets
        } finally {
            isSyncingMintQuotes.set(false)
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
            val confirmation = gateway.meltTokens(quoteId, mintUrl)
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
     * Wait in the background for an async-accepted melt. One waiter per quote;
     * the waiter dies with the process and [syncPendingMeltQuotes] takes over
     * after relaunch. Settlement facts (preimage, actual fee) persist on the
     * CDK transaction itself — no app-side metadata to write.
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
            gateway.settleForeignNfcToken(tokenString, settlementMintUrl).also {
                walletStore.saveProcessedCashuRequests(
                    (walletStore.loadProcessedCashuRequests() + processedId).distinct().sorted(),
                )
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
        val updated = current.filterNot { it.tokenId == token.tokenId } + token
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

    suspend fun addMintAndPayCashuPaymentRequest(encoded: String, customAmountSats: Long?, mintUrl: String) {
        withLoading {
            addMintAndPayCashuPaymentRequestAndRefresh(
                encoded = encoded,
                customAmountSats = customAmountSats,
                mintUrl = mintUrl,
                ensureMintTracked = { ensureMintTracked(it) },
                payCashuPaymentRequest = { request, amount, trackedMintUrl ->
                    gateway.payCashuPaymentRequest(request, amount, trackedMintUrl)
                },
                refreshBalance = { refreshBalance() },
                loadTransactions = { loadTransactions() },
            )
        }
    }

    suspend fun loadTransactions() {
        val result = transactionLoader.load(mutableState.value.mints)
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

    private suspend fun installCleanWallet(mnemonic: String, needsOnboarding: Boolean) {
        val previousMnemonic = secureStorage.loadString(StorageKeys.secureWalletMnemonic)
        cashuRequestListener?.pauseForWalletBoundary()
        val replacementSnapshot = try {
            WalletReplacementSnapshot(
                // Capture preference state before moving the database so a
                // preparation failure can resume the untouched wallet.
                wallet = walletStore.snapshotWalletScopedData(),
                settings = settingsManager.snapshotWalletScopedData(),
                nwc = nwcManager.snapshotWalletScopedData(),
                databaseBackups = databasePathManager.backupWalletDatabaseFiles(),
            )
        } catch (error: Throwable) {
            cashuRequestListener?.resetForWalletBoundary(
                restart = externalServicesEnabled && previousMnemonic != null,
            )
            throw error
        }
        val backups = replacementSnapshot.databaseBackups
        val walletSnapshot = replacementSnapshot.wallet
        val settingsSnapshot = replacementSnapshot.settings
        val nwcSnapshot = replacementSnapshot.nwc

        try {
            // NwcService retains the native CDK wallet, so it must stop before
            // the repository/database it is backed by is closed.
            nwcManager.resetForWalletBoundary()
            gateway.closeWalletRepository()
            cashuRequestStore.resetForWalletBoundary()
            walletStore.removeAllWalletData()
            settingsManager.prepareForWalletReplacement()
            nostrService.resetForWalletBoundary(deleteStoredKey = false)
            npcService.resetForWalletBoundary()
            openWalletRepositoryWithRecovery(mnemonic)
            deriveNostrKey(mnemonic)
            secureStorage.saveString(StorageKeys.secureWalletMnemonic, mnemonic)
            settingsManager.deleteWalletScopedSecrets(settingsSnapshot, deleteNostrPrivateKey = true)
            nostrMintBackupService.resetForWalletBoundary()
            loadCachedState(needsOnboarding = needsOnboarding)
            // A wallet installed during first-launch onboarding is incomplete
            // until completeOnboarding(); installs from Settings skip
            // onboarding entirely and are complete immediately.
            settingsManager.onboardingCompleted = !needsOnboarding
        } catch (installError: Throwable) {
            gateway.closeWalletRepository()
            val rollbackSucceeded = try {
                databasePathManager.restoreWalletFileBackups(
                    backups = backups,
                    beforeCommit = {
                        if (previousMnemonic != null) {
                            secureStorage.saveString(StorageKeys.secureWalletMnemonic, previousMnemonic)
                        } else {
                            secureStorage.delete(StorageKeys.secureWalletMnemonic)
                        }
                    },
                    onRollback = {
                        secureStorage.saveString(StorageKeys.secureWalletMnemonic, mnemonic)
                    },
                )
                true
            } catch (rollbackError: Throwable) {
                installError.addSuppressed(rollbackError)
                AppLogger.wallet.error("Failed to restore the previous wallet transaction", rollbackError)
                false
            }

            if (rollbackSucceeded) {
                walletStore.restoreWalletScopedData(walletSnapshot)
                cashuRequestStore.reload()
                settingsManager.restoreWalletScopedData(settingsSnapshot)
                nwcManager.restoreWalletScopedData(nwcSnapshot)
                nostrMintBackupService.reloadStoredState()
                if (previousMnemonic != null) {
                    runCatching {
                        openWalletRepositoryWithRecovery(previousMnemonic)
                        deriveNostrKey(previousMnemonic)
                        loadCachedState(needsOnboarding = false)
                        if (startNwc) nwcManager.startIfEnabled()
                    }
                    cashuRequestListener?.resetForWalletBoundary(restart = externalServicesEnabled)
                } else {
                    update {
                        WalletState(
                            isInitialized = true,
                            isRuntimeReady = true,
                            needsOnboarding = true,
                            canExitOnboarding = false,
                        )
                    }
                    cashuRequestListener?.resetForWalletBoundary(restart = false)
                }
            } else {
                // The replacement seed/files were rolled forward as far as
                // possible. Do not publish snapshots from the previous wallet.
                cashuRequestListener?.resetForWalletBoundary(restart = false)
            }
            throw installError
        }

        // Backup cleanup is post-commit. A cleanup error must not turn a valid
        // replacement into a rollback after old backups were partly deleted.
        try {
            databasePathManager.removeWalletFileBackups(backups)
        } catch (cleanupError: Throwable) {
            AppLogger.wallet.error("Failed to remove committed wallet replacement backups", cleanupError)
        }
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
        // The app's legacy Nostr/P2PK identity remains sha256(mnemonic utf8).
        runCatching {
            val seed = java.security.MessageDigest.getInstance("SHA-256")
                .digest(mnemonic.toByteArray(Charsets.UTF_8))
            nostrService.deriveKeypairFromSeed(seed)
        }.onFailure { AppLogger.wallet.error("Nostr key derivation failed", it) }

        // npub.cash is a separate NIP-06 identity derived by CDK from the
        // 64-byte BIP39 seed. This matches iOS WalletManager+NPC exactly.
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
        const val MINT_QUOTE_SYNC_COOLDOWN_MS = 5_000L

        // How often the foreground poll re-checks pending quotes while the
        // app is active (iOS `pendingQuotePollInterval` parity).
        const val PENDING_QUOTE_POLL_INTERVAL_MS = 5_000L
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
