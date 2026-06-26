package org.cashu.wallet.Core

import java.net.URL
import java.util.UUID
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.cashu.wallet.Core.CDK.CdkWalletGateway
import org.cashu.wallet.Core.Platform.WalletDatabasePathManager
import org.cashu.wallet.Core.Protocols.SecureStorage
import org.cashu.wallet.Core.Protocols.StorageKeys
import org.cashu.wallet.Core.Protocols.WalletServiceProtocol
import org.cashu.wallet.Models.MeltPaymentResult
import org.cashu.wallet.Models.MeltQuoteInfo
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Models.MintQuoteInfo
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashu.wallet.Models.PendingReceiveToken
import org.cashu.wallet.Models.PendingToken
import org.cashu.wallet.Models.RestoreMintResult
import org.cashu.wallet.Models.SendTokenResult

class WalletManager(
    private val secureStorage: SecureStorage,
    private val walletStore: WalletStore,
    private val settingsManager: SettingsManager,
    private val nostrService: NostrService,
    private val npcService: NPCService,
    private val databasePathManager: WalletDatabasePathManager,
    private val gateway: CdkWalletGateway,
) : WalletServiceProtocol, NPCQuoteClaimHandler {
    private val exceptionHandler = CoroutineExceptionHandler { _, error ->
        AppLogger.wallet.error("Unhandled wallet coroutine error", error)
        update { copy(isLoading = false, errorMessage = error.message ?: error::class.simpleName) }
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate + exceptionHandler)
    private val mutableState = MutableStateFlow(WalletState())
    val state: StateFlow<WalletState> = mutableState.asStateFlow()
    private val mintMetadataFetcher = WalletMintMetadataFetcher()
    private val mintQuoteSyncService = WalletMintQuoteSyncService(gateway, walletStore)
    private val transactionLoader = WalletTransactionLoader(walletStore, gateway)
    private val npcQuotesInFlight = mutableSetOf<String>()
    private var processedNPCQuotes = walletStore.loadProcessedNPCQuotes().toMutableSet()

    override suspend fun initialize() {
        if (mutableState.value.isInitialized) return
        update { copy(isLoading = true, errorMessage = null) }
        runCatching {
            gateway.initializeLogging()
            secureStorage.loadString(StorageKeys.secureWalletMnemonic)?.let { mnemonic ->
                openWalletRepositoryWithRecovery(mnemonic)
                deriveNostrKey(mnemonic)
                loadCachedState(needsOnboarding = false)
            } ?: update {
                copy(
                    isInitialized = true,
                    isLoading = false,
                    needsOnboarding = true,
                    canExitOnboarding = false,
                    mints = walletStore.loadMints(),
                )
            }
        }.onFailure { error ->
            AppLogger.wallet.error("Wallet initialization failed", error)
            update {
                copy(
                    isInitialized = true,
                    isLoading = false,
                    needsOnboarding = true,
                    canExitOnboarding = false,
                    errorMessage = error.message,
                )
            }
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
        withLoading { installCleanWallet(normalized, needsOnboarding = true) }
    }

    suspend fun initializeRestoredWallet(mnemonic: String) {
        val normalized = MnemonicInput.normalize(mnemonic)
        require(MnemonicInput.hasSupportedWordCount(normalized)) {
            "Seed phrase must be ${MnemonicInput.supportedWordCountLabel} words."
        }
        require(gateway.validateMnemonic(normalized)) { "Invalid seed phrase." }
        withLoading { installCleanWallet(normalized, needsOnboarding = true) }
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
            gateway.closeWalletRepository()
            secureStorage.delete(StorageKeys.secureWalletMnemonic)
            secureStorage.delete(StorageKeys.secureNostrPrivateKey)
            databasePathManager.removeWalletDatabaseFiles()
            walletStore.removeAllWalletData()
            settingsManager.resetWalletScopedData()
            npcService.resetForWalletBoundary()
            update {
                WalletState(
                    isInitialized = true,
                    needsOnboarding = true,
                    canExitOnboarding = false,
                )
            }
        }
    }

    override suspend fun addMint(url: String) {
        withLoading {
            val normalized = mintMetadataFetcher.normalizeMintUrl(url)
            mintMetadataFetcher.validateMintUrl(normalized)?.let { throw IllegalArgumentException(it) }
            if (mutableState.value.mints.any { it.url == normalized }) {
                throw IllegalArgumentException("Mint already exists.")
            }
            runCatching { gateway.ensureWallet(normalized) }
                .onFailure { AppLogger.wallet.error("CDK wallet preparation is not available yet for $normalized", it) }
            val fetched = gateway.fetchMintInfo(normalized) ?: mintMetadataFetcher.fetchRawMintInfo(normalized)
            val updated = mutableState.value.mints + fetched
            walletStore.saveMints(updated)
            if (mutableState.value.activeMint == null) walletStore.activeMintURL = fetched.url
            loadCachedState(needsOnboarding = false)
            refreshBalance()
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
        val updated = mints.map { mint ->
            val balance = runCatching { gateway.totalBalance(mint.url) }.getOrDefault(mint.balance)
            total += balance
            mint.copy(balance = balance)
        }
        walletStore.saveMints(updated)
        update {
            copy(
                balance = total,
                mints = updated,
                activeMint = activeMintFrom(updated),
            )
        }
    }

    override suspend fun createMintQuote(amount: Long?, method: PaymentMethodKind): MintQuoteInfo {
        val active = mutableState.value.activeMint ?: throw IllegalStateException("No active mint.")
        return withLoadingResult {
            gateway.createMintQuote(amount, method, active.url).also {
                mintQuoteSyncService.rememberMintQuoteTimestamp(it.id)
            }
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
        withLoadingResult {
            gateway.mintTokens(quoteId).also {
                refreshBalance()
                loadTransactions()
            }
        }

    suspend fun refreshPendingMintQuote(quoteId: String): Boolean =
        withLoadingResult {
            val minted = mintQuoteSyncService.syncPendingMintQuote(
                quoteId,
                allowPendingOnchainMintAttempt = true,
            )
            if (minted) refreshBalance()
            loadTransactions()
            minted
        }

    suspend fun syncPendingMintQuotes(): Int =
        withLoadingResult {
            val pendingQuotes = runCatching { gateway.listUnissuedMintQuotes() }
                .getOrDefault(emptyList())
            var mintedCount = 0
            pendingQuotes.forEach { quote ->
                if (
                    mintQuoteSyncService.syncPendingMintQuote(
                        quote.id,
                        allowPendingOnchainMintAttempt = false,
                    )
                ) {
                    mintedCount += 1
                }
            }
            if (mintedCount > 0) refreshBalance()
            loadTransactions()
            mintedCount
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
            val result = gateway.meltTokens(quoteId, mintUrl)
            transactionLoader.saveMeltPaymentMetadata(quoteId, result)
            refreshBalance()
            loadTransactions()
            result
        }

    override suspend fun sendTokens(amount: Long, memo: String?, p2pkPubkey: String?, mintUrl: String?): SendTokenResult {
        val selectedMint = mintUrl ?: mutableState.value.activeMint?.url ?: throw IllegalStateException("No active mint.")
        val normalizedP2PKPubkey = SettingsManager.normalizeP2PKPublicKeyForSend(p2pkPubkey)
        return withLoadingResult {
            val result = gateway.sendEcashToken(amount, memo, normalizedP2PKPubkey, selectedMint)
            val pending = PendingToken(
                tokenId = UUID.randomUUID().toString(),
                token = result.token,
                amount = amount,
                fee = result.fee,
                dateEpochMillis = System.currentTimeMillis(),
                mintUrl = selectedMint,
                memo = memo,
            )
            normalizedP2PKPubkey?.let(settingsManager::markP2PKKeyUsed)
            walletStore.savePendingTokens(walletStore.loadPendingTokens() + pending)
            refreshBalance()
            loadTransactions()
            result
        }
    }

    override suspend fun receiveTokens(tokenString: String): Long =
        withLoadingResult {
            val p2pkPubkeys = TokenParser.p2pkPubkeys(tokenString)
            val signingKeys = settingsManager.p2pkSigningKeysFor(p2pkPubkeys)
            gateway.receiveEcashToken(tokenString, signingKeys).also {
                p2pkPubkeys.forEach(settingsManager::markP2PKKeyUsed)
                refreshBalance()
                loadTransactions()
            }
        }

    suspend fun receiveCashuRequestPayment(tokenString: String, requestId: String?, processedId: String? = requestId): Long {
        val normalizedProcessedId = processedId?.trim()?.takeIf { it.isNotEmpty() }
        if (normalizedProcessedId != null && normalizedProcessedId in walletStore.loadProcessedCashuRequests()) {
            return 0
        }
        val amount = receiveTokens(tokenString)
        normalizedProcessedId?.let { id ->
            walletStore.saveProcessedCashuRequests((walletStore.loadProcessedCashuRequests() + id).distinct().sorted())
        }
        return amount
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
        val amount = receiveTokens(token.token)
        removePendingReceiveToken(token.tokenId)
        return amount
    }

    fun removePendingToken(tokenId: String) {
        val updated = walletStore.loadPendingTokens().filterNot { it.tokenId == tokenId }
        walletStore.savePendingTokens(updated)
        update { copy(pendingTokens = updated) }
    }

    suspend fun checkPendingTokenStatus(pendingToken: PendingToken): Boolean =
        withLoadingResult {
            val claimed = gateway.checkTokenSpendable(pendingToken.token, pendingToken.mintUrl)
            if (claimed) {
                val mutation = transactionLoader.markPendingTokenClaimed(pendingToken)
                update {
                    copy(
                        pendingTokens = mutation.pendingTokens,
                        claimedTokens = mutation.claimedTokens,
                    )
                }
                loadTransactions()
            }
            claimed
        }

    suspend fun checkAllPendingTokens(): Int =
        withLoadingResult {
            val pendingTokens = walletStore.loadPendingTokens()
            var claimedCount = 0
            pendingTokens.forEach { token ->
                val claimed = runCatching { gateway.checkTokenSpendable(token.token, token.mintUrl) }
                    .getOrDefault(false)
                if (claimed) {
                    val mutation = transactionLoader.markPendingTokenClaimed(token)
                    update {
                        copy(
                            pendingTokens = mutation.pendingTokens,
                            claimedTokens = mutation.claimedTokens,
                        )
                    }
                    claimedCount += 1
                }
            }
            loadTransactions()
            claimedCount
        }

    suspend fun reclaimPendingToken(pendingToken: PendingToken): Long {
        val amount = receiveTokens(pendingToken.token)
        removePendingToken(pendingToken.tokenId)
        loadTransactions()
        return amount
    }

    suspend fun calculateReceiveFee(tokenString: String): Long = gateway.calculateReceiveFee(tokenString)

    suspend fun checkTokenSpent(tokenString: String, mintUrl: String): Boolean =
        gateway.checkTokenSpendable(tokenString, mintUrl)

    suspend fun payCashuPaymentRequest(encoded: String, customAmountSats: Long?, preferredMintURL: String?) {
        withLoading {
            gateway.payCashuPaymentRequest(encoded, customAmountSats, preferredMintURL)
            refreshBalance()
            loadTransactions()
        }
    }

    suspend fun loadTransactions() {
        val mintUrls = mutableState.value.mints.map { it.url }
        val result = transactionLoader.load(mintUrls)
        update {
            copy(
                transactions = result.transactions,
                pendingTokens = result.pendingTokens,
                pendingReceiveTokens = result.pendingReceiveTokens,
                claimedTokens = result.claimedTokens,
                transactionUpdateVersion = nextTransactionUpdateVersion(transactionUpdateVersion),
            )
        }
    }

    fun clearError() = update { copy(errorMessage = null) }

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
        loadCachedState(needsOnboarding = false)
        refreshBalance()
        loadTransactions()
    }

    private suspend fun installCleanWallet(mnemonic: String, needsOnboarding: Boolean) {
        val previousMnemonic = secureStorage.loadString(StorageKeys.secureWalletMnemonic)
        val backups = databasePathManager.backupWalletDatabaseFiles()
        val walletSnapshot = walletStore.snapshotWalletScopedData()
        val settingsSnapshot = settingsManager.snapshotWalletScopedData()

        runCatching {
            gateway.closeWalletRepository()
            walletStore.removeAllWalletData()
            settingsManager.prepareForWalletReplacement()
            nostrService.resetForWalletBoundary(deleteStoredKey = false)
            openWalletRepositoryWithRecovery(mnemonic)
            deriveNostrKey(mnemonic)
            secureStorage.saveString(StorageKeys.secureWalletMnemonic, mnemonic)
            settingsManager.deleteWalletScopedSecrets(settingsSnapshot, deleteNostrPrivateKey = true)
            npcService.resetForWalletBoundary()
            databasePathManager.removeWalletFileBackups(backups)
            loadCachedState(needsOnboarding = needsOnboarding)
        }.onFailure { error ->
            gateway.closeWalletRepository()
            walletStore.restoreWalletScopedData(walletSnapshot)
            settingsManager.restoreWalletScopedData(settingsSnapshot)
            databasePathManager.removeWalletDatabaseFiles()
            databasePathManager.restoreWalletFileBackups(backups)
            if (previousMnemonic != null) {
                secureStorage.saveString(StorageKeys.secureWalletMnemonic, previousMnemonic)
                runCatching {
                    openWalletRepositoryWithRecovery(previousMnemonic)
                    deriveNostrKey(previousMnemonic)
                    loadCachedState(needsOnboarding = false)
                }
            } else {
                secureStorage.delete(StorageKeys.secureWalletMnemonic)
                update {
                    WalletState(
                        isInitialized = true,
                        needsOnboarding = true,
                        canExitOnboarding = false,
                    )
                }
            }
            throw error
        }
    }

    private fun loadCachedState(needsOnboarding: Boolean) {
        val mints = walletStore.loadMints()
        val active = activeMintFrom(mints)
        val preimages = walletStore.loadPaymentPreimages()
        val meltFees = walletStore.loadMeltQuoteFees()
        val transactions = walletStore.loadTransactions()
            .map { it.withStoredMeltMetadata(preimages, meltFees) }
        val pendingTokens = walletStore.loadPendingTokens()
        val pendingReceiveTokens = walletStore.loadPendingReceiveTokens()
        val claimedTokens = walletStore.loadClaimedTokens()
        processedNPCQuotes = walletStore.loadProcessedNPCQuotes().toMutableSet()
        update {
            copy(
                balance = mints.sumOf { it.balance },
                isInitialized = true,
                isLoading = false,
                needsOnboarding = needsOnboarding,
                canExitOnboarding = secureStorage.contains(StorageKeys.secureWalletMnemonic),
                mints = mints,
                activeMint = active,
                transactions = transactions,
                pendingTokens = pendingTokens,
                pendingReceiveTokens = pendingReceiveTokens,
                claimedTokens = claimedTokens,
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

        val fetched = runCatching { gateway.fetchMintInfo(normalized) }
            .getOrNull()
            ?: runCatching { mintMetadataFetcher.fetchRawMintInfo(normalized) }.getOrElse {
                MintInfo(
                    url = normalized,
                    name = runCatching { URL(normalized).host }.getOrNull() ?: "Unknown Mint",
                )
            }
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
        runCatching { nostrService.deriveKeypairFromSeed(gateway.mnemonicEntropy(mnemonic)) }
            .onFailure { AppLogger.wallet.error("Nostr key derivation failed", it) }
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
        return runCatching { block() }
            .onSuccess { update { copy(isLoading = false) } }
            .onFailure { error ->
                AppLogger.wallet.error("Wallet operation failed", error)
                update { copy(isLoading = false, errorMessage = error.message) }
            }
            .getOrThrow()
    }

    private fun update(transform: WalletState.() -> WalletState) {
        mutableState.value = mutableState.value.transform()
    }

    fun launch(block: suspend CoroutineScope.() -> Unit) {
        scope.launch { block() }
    }

    fun reopenOnboarding() {
        update { copy(needsOnboarding = true, canExitOnboarding = true) }
    }
}
