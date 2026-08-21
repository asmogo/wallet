package com.cashu.me.Core.CDK

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import com.cashu.me.Core.LightningRequestParser
import com.cashu.me.Core.NPCQuote
import com.cashu.me.Core.mintQuoteAmountForDomain
import com.cashu.me.Core.mintQuoteDisplayExpiry
import com.cashu.me.Core.mintQuoteStateForDomain
import com.cashu.me.Core.PaymentRequestDecodeResult
import com.cashu.me.Core.PaymentRequestDecoder
import com.cashu.me.Core.PaymentRequestParser
import com.cashu.me.Models.MeltPaymentResult
import com.cashu.me.Models.MeltQuoteInfo
import com.cashu.me.Models.MeltQuoteState
import com.cashu.me.Models.MeltSettlement
import com.cashu.me.Models.MintContact
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.Models.MintQuoteState
import com.cashu.me.Models.MintSoftware
import com.cashu.me.Models.NutSupport
import com.cashu.me.Models.PaymentMethodKind
import com.cashu.me.Models.RestoreMintResult
import com.cashu.me.Models.SagaTransactionId
import com.cashu.me.Models.SendTokenResult
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import org.cashudevkit.Amount as CdkAmount
import org.cashudevkit.BackupOptions as CdkBackupOptions
import org.cashudevkit.BitcoinNetwork as CdkBitcoinNetwork
import org.cashudevkit.CurrencyUnit as CdkCurrencyUnit
import org.cashudevkit.FinalizedMelt as CdkFinalizedMelt
import org.cashudevkit.KeysetLoadPolicy as CdkKeysetLoadPolicy
import org.cashudevkit.MeltConfirmOutcome as CdkMeltConfirmOutcome
import org.cashudevkit.MeltOptions as CdkMeltOptions
import org.cashudevkit.MeltQuote as CdkMeltQuote
import org.cashudevkit.MintInfo as CdkMintInfo
import org.cashudevkit.MintQuote as CdkMintQuote
import org.cashudevkit.MintUrl as CdkMintUrl
import org.cashudevkit.NotificationPayload as CdkNotificationPayload
import org.cashudevkit.NwcService as CdkNwcService
import org.cashudevkit.P2pkLockedProofSendMode as CdkP2pkLockedProofSendMode
import org.cashudevkit.PaymentMethod as CdkPaymentMethod
import org.cashudevkit.QuoteState as CdkQuoteState
import org.cashudevkit.ReceiveOptions as CdkReceiveOptions
import org.cashudevkit.RestoreOptions as CdkRestoreOptions
import org.cashudevkit.SendKind as CdkSendKind
import org.cashudevkit.SendMemo as CdkSendMemo
import org.cashudevkit.SendOptions as CdkSendOptions
import org.cashudevkit.SecretKey as CdkSecretKey
import org.cashudevkit.SplitTarget as CdkSplitTarget
import org.cashudevkit.SpendingConditions as CdkSpendingConditions
import org.cashudevkit.Token as CdkToken
import org.cashudevkit.Transaction as CdkTransaction
import org.cashudevkit.TransactionDirection as CdkTransactionDirection
import org.cashudevkit.TransactionStatus as CdkTransactionStatus
import org.cashudevkit.Wallet as CdkWallet
import org.cashudevkit.WalletRepository as CdkWalletRepository
import org.cashudevkit.WalletSqliteDatabase as CdkWalletSqliteDatabase
import com.cashu.me.Core.NfcReceive.settleForeignNfcTokenWithCdk
import org.cashudevkit.customWalletStore
import org.cashudevkit.decodePaymentRequest
import org.cashudevkit.generateMnemonic as cdkGenerateMnemonic
import org.cashudevkit.initLogging
import org.cashudevkit.mnemonicToEntropy
import org.cashudevkit.nwcDeriveServiceSecretKeyFromSeed
import org.cashudevkit.proofsTotalAmount
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

private val sagaJsonFormat = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }

// Ceiling on how long a lightning melt may hold the gateway lane while CDK's
// `PendingMelt.wait()` drives settlement. A fallback exit, not a polling knob —
// `wait()` polls the mint internally; this only bounds how long the send
// screen (and the serialized gateway) stay committed before the pending face
// takes over (iOS `LightningService.MeltSettlementWait` parity).
internal const val LIGHTNING_SETTLEMENT_WAIT_MS = 30_000L

/**
 * In-lane settlement wait for an async-accepted melt. Returns the
 * [CdkFinalizedMelt] when the melt is a lightning method and CDK's `wait()`
 * reaches a terminal state within [waitMs]; null when the method doesn't wait
 * (on-chain/unknown), the cap expires, or the wait fails ambiguously — the
 * caller then falls back to the pending result + handle, and never surfaces a
 * false terminal failure. Cancellation propagates: Kotlin's CDK bindings drop
 * the Rust future cleanly.
 */
internal suspend fun awaitLightningSettlementOrNull(
    method: CdkPaymentMethod?,
    waitMs: Long = LIGHTNING_SETTLEMENT_WAIT_MS,
    wait: suspend () -> CdkFinalizedMelt,
): CdkFinalizedMelt? {
    if (method != CdkPaymentMethod.Bolt11 && method != CdkPaymentMethod.Bolt12) return null
    return try {
        withTimeoutOrNull(waitMs) { wait() }
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: Exception) {
        null
    }
}

/** Builds CDK's explicit amount override for amountless Lightning requests. */
internal fun meltOptionsForLightningRequest(
    decoded: PaymentRequestDecodeResult,
    amountSats: Long?,
): CdkMeltOptions? {
    val requestAmountSats = when (decoded) {
        is PaymentRequestDecodeResult.Bolt11 -> decoded.amountSats
        is PaymentRequestDecodeResult.Bolt12 -> decoded.amountSats
        else -> return null
    }
    if (requestAmountSats != null && requestAmountSats > 0L) return null

    val amount = amountSats?.takeIf { it > 0L }
        ?: throw CdkGatewayUnavailable(
            "This Lightning request doesn't include an amount. Enter an amount before requesting a quote.",
        )
    val amountMsat = try {
        Math.multiplyExact(amount, 1_000L)
    } catch (_: ArithmeticException) {
        throw CdkGatewayUnavailable("Amount is too large.")
    }
    return CdkMeltOptions.Amountless(CdkAmount(amountMsat.toULong()))
}

class CdkWalletGatewayImpl : WalletGateway {
    private var database: CdkWalletSqliteDatabase? = null
    private var repository: CdkWalletRepository? = null
    private val operationMutex = Mutex()
    private val lightningAddressResolver = LightningAddressResolver()

    override suspend fun initializeLogging(level: String) = cdkCall {
        initLogging(level)
    }

    override suspend fun generateMnemonic(): String = cdkCall { cdkGenerateMnemonic() }

    override suspend fun mnemonicEntropy(mnemonic: String): ByteArray = cdkCall { mnemonicToEntropy(mnemonic) }

    override suspend fun validateMnemonic(mnemonic: String): Boolean = cdkCall {
        runCatching { mnemonicToEntropy(mnemonic); true }.getOrDefault(false)
    }

    override suspend fun openWalletRepository(mnemonic: String, databasePath: String) = cdkCall {
        closeWalletRepositoryUnlocked()
        val db = CdkWalletSqliteDatabase(databasePath)
        database = db
        repository = CdkWalletRepository(mnemonic, customWalletStore(db))
    }

    override suspend fun closeWalletRepository() = cdkCall {
        closeWalletRepositoryUnlocked()
    }

    override suspend fun hasWallets(): Boolean = cdkCall {
        requireRepository().getWallets().isNotEmpty()
    }

    /**
     * Creates or restores CDK's NIP-47 wallet service against the same native
     * sat wallet used by the rest of the app. CDK owns relay protocol handling,
     * invoice creation/payment, balance responses, and payment-limit checks.
     */
    override suspend fun createOrRestoreNwcService(
        mintUrl: String,
        relays: List<String>,
        seed: ByteArray,
        clientSecretKey: String?,
        maxPaymentMsat: ULong?,
    ): NwcServiceHandle = cdkCall {
        val normalizedMintUrl = normalizeMintUrl(mintUrl)
        ensureWalletUnlocked(normalizedMintUrl)
        val wallet = walletFor(normalizedMintUrl)
        val serviceSecretKey = nwcDeriveServiceSecretKeyFromSeed(seed)
        val nativeService = if (clientSecretKey.isNullOrBlank()) {
            CdkNwcService.create(
                wallet = wallet,
                relays = relays,
                serviceSecretKey = serviceSecretKey,
                maxPaymentMsat = maxPaymentMsat,
            )
        } else {
            CdkNwcService.restore(
                wallet = wallet,
                relays = relays,
                serviceSecretKey = serviceSecretKey,
                clientSecretKey = clientSecretKey,
                maxPaymentMsat = maxPaymentMsat,
            )
        }
        CdkNwcServiceHandle(
            service = nativeService,
            connectionUri = nativeService.connectionUri(),
        )
    }

    override suspend fun backupMints(relays: List<String>, client: String) = cdkCall {
        requireRepository().backupMints(relays, CdkBackupOptions(client = client))
        Unit
    }

    override suspend fun fetchMintBackup(relays: List<String>, timeoutSecs: ULong): List<String> = cdkCall {
        requireRepository().fetchMintBackup(relays, CdkRestoreOptions(timeoutSecs = timeoutSecs))
            .mints
            .map { it.url }
    }

    private fun closeWalletRepositoryUnlocked() {
        runCatching { repository?.close() }
        runCatching { database?.close() }
        repository = null
        database = null
    }

    override suspend fun ensureWallet(mintUrl: String, unit: String) = cdkCall {
        ensureWalletUnlocked(mintUrl, cdkUnit(unit))
    }

    override suspend fun removeWalletIfSingleUnit(mintUrl: String): Boolean = cdkCall {
        val repository = requireRepository()
        val registeredWallets = repository.getWallets()
            .filter { wallet ->
                mintRemovalUrlsMatch(wallet.mintUrl().url, mintUrl)
            }
        val registeredUnits = normalizedRegisteredWalletUnits(
            registeredWallets.map { it.unit().toDomainUnit() },
        )
        if (registeredUnits.size > 1) {
            throw MultiUnitWalletRemovalException(registeredUnits)
        }
        val registeredUnit = registeredUnits.singleOrNull() ?: return@cdkCall false
        val wallet = registeredWallets.first { wallet ->
            wallet.unit().toDomainUnit().trim().equals(registeredUnit, ignoreCase = true)
        }
        repository.removeWallet(wallet.mintUrl(), wallet.unit())
        true
    }

    override suspend fun fetchMintInfo(mintUrl: String): MintInfo? = cdkCall {
        // iOS `fetchMintPreviewInfo`: CDK requires a wallet entry before
        // fetchMintInfo() — create one if needed. Does not add the mint to the
        // app's saved list (callers own that).
        ensureWalletUnlocked(mintUrl)
        walletFor(mintUrl).fetchMintInfo()?.toDomain(mintUrl)
    }

    override suspend fun restoreMint(mintUrl: String): RestoreMintResult = cdkCall {
        ensureWalletUnlocked(mintUrl)
        val wallet = walletFor(mintUrl)
        val info = runCatching { wallet.fetchMintInfo() }.getOrNull()
        val restored = wallet.restore()
        RestoreMintResult(
            mintUrl = mintUrl,
            mintName = info?.name ?: "Unknown Mint",
            iconUrl = info?.iconUrl,
            spent = restored.spent.value.toLong(),
            unspent = restored.unspent.value.toLong(),
            pending = restored.pending.value.toLong(),
        )
    }

    override suspend fun totalBalance(mintUrl: String): Long = cdkCall {
        walletFor(mintUrl).totalBalance().value.toLong()
    }

    override suspend fun unitBalance(mintUrl: String, unit: String): Long = cdkCall {
        val cdkUnit = cdkUnit(unit)
        ensureWalletUnlocked(mintUrl, cdkUnit)
        walletFor(mintUrl, cdkUnit).totalBalance().value.toLong()
    }

    override suspend fun unitBalanceIfExists(mintUrl: String, unit: String): Long? = cdkCall {
        runCatching { walletFor(mintUrl, cdkUnit(unit)).totalBalance().value.toLong() }.getOrNull()
    }

    override suspend fun createMintQuote(amount: Long?, method: PaymentMethodKind, mintUrl: String, unit: String, description: String?): MintQuoteInfo = cdkCall {
        val cdkUnit = cdkUnit(unit)
        if (!unit.equals("sat", ignoreCase = true)) ensureWalletUnlocked(mintUrl, cdkUnit)
        val wallet = walletFor(mintUrl, cdkUnit)
        val quote = wallet.mintQuote(
            paymentMethod = cdkPaymentMethod(method),
            amount = amount?.toCdkAmount(),
            // Description is only threaded for BOLT12 offers (NUT-04 optional);
            // mint support on other rails is uneven, so they keep nil.
            description = description?.takeIf { method == PaymentMethodKind.Bolt12 },
            extra = if (method == PaymentMethodKind.Onchain) "{}" else null,
        )
        persistMintQuoteLocalMetadataIfNeeded(
            quote = quote,
            method = method,
            fallbackAmount = amount,
        ).toDomain(fallbackAmount = amount, fallbackMethod = method)
    }

    override suspend fun checkMintQuote(quoteId: String): MintQuoteInfo = cdkCall {
        val quote = database?.getMintQuote(quoteId)
            ?: throw CdkGatewayUnavailable("No stored mint quote for $quoteId.")
        // Resolve the same-unit wallet the quote was created against, so
        // resuming a non-sat quote never polls (or mints into) the sat wallet.
        val wallet = walletFor(quote.mintUrl.url, quote.unit)
        val method = quote.paymentMethod.toDomain()
        val fallbackAmount = quote.amount?.value?.toLong()
        val checkedQuote = if (method == PaymentMethodKind.Onchain) {
            wallet.checkMintQuoteStatus(quoteId)
        } else {
            wallet.checkMintQuote(quoteId)
        }
        val refreshed = checkedQuote
            .preservingLocalMetadataFrom(quote)
            .withLocalMintQuoteMetadata(method, fallbackAmount)
            .let { persistMintQuoteLocalMetadataIfNeeded(it, method, fallbackAmount = fallbackAmount) }
        refreshed.toDomain(
            fallbackAmount = fallbackAmount,
            fallbackMethod = method,
        )
    }

    override suspend fun storedMintQuote(quoteId: String): MintQuoteInfo? = cdkCall {
        database?.getMintQuote(quoteId)?.let { quote ->
            val method = quote.paymentMethod.toDomain()
            quote.withLocalMintQuoteMetadata(method).toDomain(
                fallbackAmount = quote.amount?.value?.toLong(),
                fallbackMethod = method,
            )
        }
    }

    override fun subscribeToMintQuote(quoteId: String, mayRefresh: () -> Boolean): Flow<MintQuoteInfo> = flow {
        val subscription = cdkCall {
            val quote = database?.getMintQuote(quoteId)
                ?: throw CdkGatewayUnavailable("No stored mint quote for $quoteId.")
            val method = quote.paymentMethod.toDomain()
            walletFor(quote.mintUrl.url, quote.unit)
                .subscribeMintQuoteState(listOf(quoteId), cdkPaymentMethod(method))
        }
        try {
            while (true) {
                val payload = withContext(Dispatchers.IO) { subscription.recv() }
                if (!payload.referencesMintQuote(quoteId)) continue
                if (!mayRefresh()) continue
                val refreshed = checkMintQuote(quoteId)
                emit(refreshed)
                // An amountless BOLT12 offer remains open after each mint. Keep
                // the subscription alive so its display can show later payments.
                if (refreshed.paymentMethod != PaymentMethodKind.Bolt12 &&
                    (refreshed.state == MintQuoteState.Paid || refreshed.state == MintQuoteState.Issued)
                ) {
                    return@flow
                }
            }
        } finally {
            withContext(Dispatchers.IO) { subscription.close() }
        }
    }.flowOn(Dispatchers.IO)

    override suspend fun listUnissuedMintQuotes(): List<MintQuoteInfo> = cdkCall {
        database?.getUnissuedMintQuotes().orEmpty().map { quote ->
            val method = quote.paymentMethod.toDomain()
            quote.withLocalMintQuoteMetadata(method).toDomain(
                fallbackAmount = null,
                fallbackMethod = method,
            )
        }
    }

    override suspend fun mintTokens(quoteId: String): Long = cdkCall {
        val quote = database?.getMintQuote(quoteId)
            ?: throw CdkGatewayUnavailable("No stored mint quote for $quoteId.")
        val method = quote.paymentMethod.toDomain()
        val fallbackAmount = quote.amount?.value?.toLong()
        val currentQuote = if (method == PaymentMethodKind.Onchain) {
            walletFor(quote.mintUrl.url, quote.unit)
                .checkMintQuoteStatus(quoteId)
                .preservingLocalMetadataFrom(quote)
        } else {
            quote
        }
        val normalizedQuote = persistMintQuoteLocalMetadataIfNeeded(
            quote = currentQuote.withLocalMintQuoteMetadata(method, fallbackAmount),
            method = method,
            fallbackAmount = fallbackAmount,
        )
        if (method == PaymentMethodKind.Onchain && !normalizedQuote.hasUnissuedOnchainCredit()) {
            throw CdkGatewayUnavailable(
                "Mint has not credited this on-chain quote yet " +
                    "(amount_paid=${normalizedQuote.amountPaid.value}, amount_issued=${normalizedQuote.amountIssued.value}).",
            )
        }
        if (normalizedQuote.usedByOperation != null) {
            // The live CDK saga owns the deterministic secrets required to
            // replay or restore an ambiguous mint response. Deleting it and
            // issuing fresh outputs can strand a payment the mint already
            // marked issued. Quote checks resume sagas; leave this one intact
            // for the next reconciliation pass when recovery is unavailable.
            throw CdkGatewayUnavailable(
                "A previous mint attempt is still being recovered. " +
                    "The wallet will retry automatically.",
            )
        }
        val proofs = walletFor(normalizedQuote.mintUrl.url, normalizedQuote.unit).mintUnified(
            quoteId = quoteId,
            amountSplitTarget = CdkSplitTarget.None,
            spendingConditions = null,
        )
        proofsTotalAmount(proofs).value.toLong()
    }

    override suspend fun mintNPCQuote(quote: NPCQuote, p2pkPubkey: String?): Long = cdkCall {
        val mintUrl = quote.mintUrl?.let(::normalizeMintUrl)
            ?: throw CdkGatewayUnavailable("npub.cash quote ${quote.id} has no mint URL.")
        ensureWalletUnlocked(mintUrl)
        replaceStoredMintQuote(quote.toCdkMintQuote(mintUrl))
        val proofs = walletFor(mintUrl).mintUnified(
            quoteId = quote.id,
            amountSplitTarget = CdkSplitTarget.None,
            spendingConditions = p2pkPubkey?.let { CdkSpendingConditions.P2pk(it, null) },
        )
        proofsTotalAmount(proofs).value.toLong()
    }

    override suspend fun createMeltQuote(request: String, amountSats: Long?, preferredMintURL: String?): MeltQuoteInfo = cdkCall {
        val wallet = preferredMintURL?.let { walletFor(it) } ?: firstWallet()
        val decoded = PaymentRequestDecoder.decode(request)
        when (decoded) {
            is PaymentRequestDecodeResult.LightningAddress -> {
                val amount = requirePositiveAmount(amountSats, "Lightning address payments require an amount.")
                val amountMsat = try {
                    Math.multiplyExact(amount, 1_000L)
                } catch (_: ArithmeticException) {
                    throw CdkGatewayUnavailable("Lightning address payment amount is too large.")
                }
                try {
                    /*
                     * CDK <= 0.17.3 rejects otherwise valid LNURL-pay invoices whose
                     * description hash does not commit to the advertised metadata
                     * (cashubtc/cdk#2235). Resolve and amount-check LNURL here, as iOS
                     * does, then give CDK the BOLT11 invoice directly. Remove this
                     * workaround once the Android binding includes upstream 7be1e2e7b8.
                     */
                    val invoice = lightningAddressResolver.resolveBolt11Invoice(
                        address = decoded.address,
                        amountMsat = amountMsat,
                    )
                    val quote = wallet.meltQuote(
                        method = CdkPaymentMethod.Bolt11,
                        request = invoice,
                        options = null,
                        extra = null,
                    )
                    return@cdkCall quote.toDomain(fallbackMethod = PaymentMethodKind.Bolt11)
                } catch (_: LightningAddressResolutionException.Unavailable) {
                    val quote = wallet.meltBip353Quote(
                        bip353Address = decoded.address,
                        amountMsat = amountMsat.toCdkAmount(),
                        network = bitcoinNetworkFor(wallet.mintUrl().url),
                    )
                    return@cdkCall quote.toDomain(fallbackMethod = quote.paymentMethod.toDomain())
                }
            }
            is PaymentRequestDecodeResult.Onchain -> {
                val amount = requirePositiveAmount(amountSats, "On-chain payments require an amount.")
                val options = wallet.quoteOnchainMeltOptions(
                    address = decoded.address,
                    amount = amount.toCdkAmount(),
                    maxFeeAmount = null,
                )
                val selected = options.firstOrNull()
                    ?: throw CdkGatewayUnavailable("Mint returned no on-chain fee options.")
                return@cdkCall wallet.selectOnchainMeltQuote(selected).toDomain(fallbackMethod = PaymentMethodKind.Onchain)
            }
            else -> Unit
        }
        val method = PaymentRequestParser.paymentMethod(request) ?: PaymentMethodKind.Bolt11
        val normalized = PaymentRequestDecoder.encodedLightningRequest(request) ?: request.trim()
        val options = meltOptionsForLightningRequest(decoded, amountSats)
        val quote = wallet.meltQuote(
            method = cdkPaymentMethod(method),
            request = normalized,
            options = options,
            extra = null,
        )
        quote.toDomain(fallbackMethod = method)
    }

    override suspend fun listMeltQuotes(): List<MeltQuoteInfo> = cdkCall {
        database?.getMeltQuotes().orEmpty().map { quote ->
            quote.toDomain(fallbackMethod = quote.paymentMethod.toDomain())
        }
    }

    override suspend fun meltTokens(quoteId: String, mintUrl: String?): MeltConfirmation = cdkCall {
        val quote = database?.getMeltQuote(quoteId)
        val wallet = walletFor(mintUrl ?: quote?.mintUrl?.url ?: firstWallet().mintUrl().url)
        val prepared = wallet.prepareMelt(quoteId)
        // `respond-async` lets the mint accept the payment and pay out in the
        // background (NUT-05) instead of holding the request open — the usual
        // shape for on-chain melts (iOS LightningService.meltTokens parity).
        when (val outcome = prepared.confirmPreferAsync()) {
            is CdkMeltConfirmOutcome.Paid -> {
                val finalized = outcome.finalized
                MeltConfirmation(
                    result = MeltPaymentResult(
                        preimage = finalized.preimage,
                        amount = finalized.amount.value.toLong(),
                        feePaid = finalized.feePaid.value.toLong(),
                        mintUrl = wallet.mintUrl().url,
                        paymentMethod = quote?.paymentMethod?.toDomain(),
                        request = quote?.request,
                        settlement = MeltSettlement.Settled,
                    ),
                    pendingMelt = null,
                )
            }
            is CdkMeltConfirmOutcome.Pending -> {
                // A lightning melt settles in seconds in the healthy case, so
                // hold the lane and let CDK's `wait()` drive the saga to a
                // terminal state — it polls the mint internally; the app adds
                // no polling of its own. Kotlin's bindings cancel cleanly, so
                // the cap is a plain timeout: on expiry the Rust future is
                // dropped and the handle goes back to the manager, whose
                // `watchPendingMelt` re-arms a fresh wait outside the lane
                // (iOS `MeltSettlementWait` parity). On-chain melts genuinely
                // take minutes and keep the immediate pending path.
                val finalized = awaitLightningSettlementOrNull(method = quote?.paymentMethod) {
                    outcome.pending.wait()
                }
                when {
                    finalized != null &&
                        (finalized.state == CdkQuoteState.PAID || finalized.state == CdkQuoteState.ISSUED) ->
                        MeltConfirmation(
                            result = MeltPaymentResult(
                                preimage = finalized.preimage,
                                amount = finalized.amount.value.toLong(),
                                feePaid = finalized.feePaid.value.toLong(),
                                mintUrl = wallet.mintUrl().url,
                                paymentMethod = quote?.paymentMethod?.toDomain(),
                                request = quote?.request,
                                settlement = MeltSettlement.Settled,
                            ),
                            pendingMelt = null,
                        )
                    finalized != null ->
                        // Wait finished UNPAID: the payment failed and CDK has
                        // already compensated the proofs back. The quote can't
                        // be reused.
                        throw CdkGatewayUnavailable(
                            "Payment failed — the mint returned your funds. Get a new quote and try again.",
                        )
                    else -> MeltConfirmation(
                        // Amount and fee aren't final until the payment settles;
                        // report the quote's numbers (fee = reserve upper bound)
                        // so the UI has facts to show.
                        result = MeltPaymentResult(
                            preimage = null,
                            amount = quote?.amount?.value?.toLong() ?: 0,
                            feePaid = quote?.feeReserve?.value?.toLong() ?: 0,
                            mintUrl = wallet.mintUrl().url,
                            paymentMethod = quote?.paymentMethod?.toDomain(),
                            request = quote?.request,
                            settlement = MeltSettlement.Pending,
                        ),
                        pendingMelt = outcome.pending,
                    )
                }
            }
        }
    }

    override suspend fun checkMeltQuoteStatus(quoteId: String, mintUrl: String?): MeltQuoteInfo = cdkCall {
        val stored = database?.getMeltQuote(quoteId)
        val wallet = walletFor(mintUrl ?: stored?.mintUrl?.url ?: firstWallet().mintUrl().url)
        val quote = wallet.checkMeltQuoteStatus(quoteId)
        quote.toDomain(fallbackMethod = stored?.paymentMethod?.toDomain() ?: quote.paymentMethod.toDomain())
    }

    override suspend fun recoverIncompleteSagas(mintUrl: String): SagaRecoveryReport = cdkCall {
        val report = walletFor(mintUrl, CdkCurrencyUnit.Sat).recoverIncompleteSagas()
        SagaRecoveryReport(
            recovered = report.recovered.toLong(),
            compensated = report.compensated.toLong(),
            skipped = report.skipped.toLong(),
            failed = report.failed.toLong(),
        )
    }

    override suspend fun sendEcashToken(amount: Long, memo: String?, p2pkPubkey: String?, mintUrl: String, unit: String, p2pkSigningKeys: List<String>): SendTokenResult = cdkCall {
        val cdkUnit = cdkUnit(unit)
        if (!unit.equals("sat", ignoreCase = true)) ensureWalletUnlocked(mintUrl, cdkUnit)
        val conditions = p2pkPubkey?.let { CdkSpendingConditions.P2pk(it, null) }
        // includeFee = false — the token carries exactly the requested amount;
        // the redeem fee is the recipient's cost and their wallet shows it
        // (see ReceiveFeeEstimator). Crucially this lets Send Max move the
        // whole balance: all proofs go out as-is, no swap, no fee — also on
        // fee-charging mints. The fee returned below is only the sender-side
        // change-swap fee (zero for a max send). Payment requests stay
        // includeFee = true — there the requester must net the asked amount.
        // Mirrors iOS TokenService.sendTokens.
        val sendOptions = CdkSendOptions(
            memo = memo?.let { CdkSendMemo(it, true) },
            conditions = conditions,
            amountSplitTarget = CdkSplitTarget.None,
            sendKind = CdkSendKind.OnlineExact,
            includeFee = false,
            useP2bk = false,
            maxProofs = null,
            metadata = emptyMap(),
            // Wallet signing keys let prepareSend swap proofs that are already
            // P2PK-locked to us (NPC locked quotes, locked receives) — without
            // them that balance is unspendable. Mirrors iOS TokenService.
            p2pkSigningKeys = p2pkSigningKeys.map(::CdkSecretKey),
            p2pkLockedProofSendMode = CdkP2pkLockedProofSendMode.SWAP,
        )
        val prepared = walletFor(mintUrl, cdkUnit).prepareSend(amount.toCdkAmount(), sendOptions)
        val fee = prepared.fee().value.toLong()
        val token = prepared.confirm(memo)
        // CDK 0.18 records the send as a Pending transaction whose id derives
        // from the send saga's operation id, computable without a store read.
        SendTokenResult(
            token = token.encode(),
            fee = fee,
            transactionId = SagaTransactionId.transactionIdHex(prepared.operationId()),
        )
    }

    override suspend fun receiveEcashToken(tokenString: String, p2pkSigningKeys: List<String>): Long = cdkCall {
        val token = CdkToken.decode(tokenString)
        val mintUrl = token.mintUrl().url
        // Redeem into the token's own unit — a usd/eur token must never target
        // the sat wallet.
        val tokenUnit = token.unit() ?: CdkCurrencyUnit.Sat
        ensureWalletUnlocked(mintUrl, tokenUnit)
        val amount = walletFor(mintUrl, tokenUnit).receive(
            token = token,
            options = CdkReceiveOptions(
                amountSplitTarget = CdkSplitTarget.None,
                p2pkSigningKeys = p2pkSigningKeys.map(::CdkSecretKey),
                preimages = emptyList(),
                metadata = emptyMap(),
            ),
        )
        amount.value.toLong()
    }

    override suspend fun receiveNfcEcashToken(
        tokenString: String,
        p2pkSigningKeys: List<String>,
    ): NfcReceiveReceipt = cdkCall {
        val token = CdkToken.decode(tokenString)
        val mintUrl = token.mintUrl().url
        val tokenUnit = token.unit() ?: CdkCurrencyUnit.Sat
        ensureWalletUnlocked(mintUrl, tokenUnit)
        val wallet = walletFor(mintUrl, tokenUnit)
        val existingIds = wallet.listTransactions(CdkTransactionDirection.INCOMING)
            .map { it.id.hex }
            .toSet()
        val amount = wallet.receive(
            token = token,
            options = CdkReceiveOptions(
                amountSplitTarget = CdkSplitTarget.None,
                p2pkSigningKeys = p2pkSigningKeys.map(::CdkSecretKey),
                preimages = emptyList(),
                metadata = emptyMap(),
            ),
        ).value.toLong()
        val transactionId = wallet.listTransactions(CdkTransactionDirection.INCOMING)
            .firstOrNull { it.id.hex !in existingIds }
            ?.id?.hex
            ?: throw CdkGatewayUnavailable("CDK did not record the received NFC transaction.")
        NfcReceiveReceipt(amountReceived = amount, transactionId = transactionId)
    }

    override suspend fun settleForeignNfcToken(
        tokenString: String,
        settlementMintUrl: String,
    ): ForeignNfcSettlement = cdkCall {
        settleForeignNfcTokenWithCdk(requireRepository(), database, tokenString, settlementMintUrl)
    }

    override suspend fun calculateReceiveFee(tokenString: String): Long = cdkCall {
        val token = CdkToken.decode(tokenString)
        val tokenUnit = token.unit() ?: CdkCurrencyUnit.Sat
        ensureWalletUnlocked(token.mintUrl().url, tokenUnit)
        val wallet = walletFor(token.mintUrl().url, tokenUnit)
        // Resolve proofs with their FULL keyset ids: proofsSimple() can carry a
        // short/legacy IDv2 keyset id that getKeysetFeesById below can't look
        // up, which would fail the whole preview to 0 — the review screen then
        // shows the token's gross value as if the redeem were free.
        val proofs = runCatching {
            token.proofs(wallet.keysets(null).map { it.toKeySetInfo() })
        }.getOrElse { token.proofsSimple() }
        if (proofs.isEmpty()) return@cdkCall 0
        // NUT-02 fee: sum each input's fee_ppk, then one ceil over the total.
        // Don't use wallet.calculateFee here — the 0.17.x FFI helper floor-
        // divides (ppk * count / 1000), reporting 0 where the mint charges 1.
        runCatching {
            val ppkByKeyset = mutableMapOf<String, Long>()
            val totalPpk = proofs.sumOf { proof ->
                ppkByKeyset.getOrPut(proof.keysetId) {
                    wallet.getKeysetFeesById(proof.keysetId).toLong()
                }
            }
            (totalPpk + 999) / 1000
        }.getOrDefault(0L)
    }

    override suspend fun activeMintInputFeePpk(mintUrl: String): Long? = cdkCall {
        val keysets = walletFor(mintUrl, CdkCurrencyUnit.Sat)
            .keysets(CdkKeysetLoadPolicy.REFRESH)
        val active = keysets.firstOrNull { it.active == true } ?: keysets.firstOrNull()
        active?.inputFeePpk?.toLong()
    }

    override suspend fun estimateCashuPaymentRequestFee(amountSats: Long, mintUrl: String): Long = cdkCall {
        require(amountSats > 0) { "Cashu Request fee preview requires an amount." }
        val options = CdkSendOptions(
            memo = null,
            conditions = null,
            amountSplitTarget = CdkSplitTarget.None,
            sendKind = CdkSendKind.OnlineExact,
            // CDK's pay_request includes the recipient's input fee so they net
            // the requested amount. The preview must use the identical mode.
            includeFee = true,
            useP2bk = false,
            maxProofs = null,
            metadata = emptyMap(),
            p2pkSigningKeys = emptyList(),
            p2pkLockedProofSendMode = CdkP2pkLockedProofSendMode.SWAP,
        )
        val prepared = walletFor(mintUrl, CdkCurrencyUnit.Sat)
            .prepareSend(amountSats.toCdkAmount(), options)
        try {
            prepared.fee().value.toLong()
        } finally {
            // A preview must never leave proofs reserved for a payment the user
            // has not confirmed.
            prepared.cancel()
        }
    }

    override suspend fun checkTokenSpendable(token: String, mintUrl: String): Boolean = cdkCall {
        val tokenObj = CdkToken.decode(token)
        val tokenUnit = tokenObj.unit() ?: CdkCurrencyUnit.Sat
        ensureWalletUnlocked(mintUrl, tokenUnit)
        val wallet = walletFor(mintUrl, tokenUnit)
        // Resolve proofs with their FULL keyset ids: proofsSimple() can carry a
        // short/legacy IDv2 keyset id that checkProofsSpent rejects ("Short
        // keyset id does not match any of the provided IDv2s"), which would
        // fail every spend check for tokens minted under an IDv2 keyset.
        // Errors must propagate, not coerce to false — false means "unspent",
        // and callers treat it as a definitive claim-state answer.
        val proofs = runCatching {
            tokenObj.proofs(wallet.keysets(null).map { it.toKeySetInfo() })
        }.getOrElse { tokenObj.proofsSimple() }
        val states = wallet.checkProofsSpent(proofs)
        states.any { it }
    }

    override suspend fun listTransactions(unitsByMint: Map<String, List<String>>): List<WalletTransaction> = cdkCall {
        unitsByMint.flatMap { (mintUrl, units) ->
            units.flatMap units@{ unit ->
                val wallet = runCatching { walletFor(mintUrl, cdkUnit(unit)) }
                    .getOrNull() ?: return@units emptyList()
                val incoming = runCatching { wallet.listTransactions(CdkTransactionDirection.INCOMING) }
                    .getOrDefault(emptyList())
                val outgoing = runCatching { wallet.listTransactions(CdkTransactionDirection.OUTGOING) }
                    .getOrDefault(emptyList())
                (incoming + outgoing).map { it.toDomain(unit) }
            }
        }
    }

    override suspend fun payCashuPaymentRequest(encoded: String, customAmountSats: Long?, preferredMintURL: String?) = cdkCall {
        val cdkEncoded = PaymentRequestDecoder.cdkCompatibleCashuPaymentRequest(encoded) ?: encoded
        val request = decodePaymentRequest(cdkEncoded)
        when (request.unit()) {
            null, CdkCurrencyUnit.Sat -> Unit
            else -> throw CdkGatewayUnavailable("Only sat Cashu payment requests are supported.")
        }
        val amount = request.amount() ?: customAmountSats?.takeIf { it > 0 }?.toCdkAmount()
            ?: throw CdkGatewayUnavailable("Cashu payment request requires an amount.")
        val candidateMints = request.mints().map(::normalizeMintUrl)
        val preferredMint = preferredMintURL
            ?.let(::normalizeMintUrl)
            ?.takeIf { candidateMints.isEmpty() || it in candidateMints }
        val mintUrl = preferredMint
            ?: candidateMints.firstOrNull()
            ?: firstWallet().mintUrl().url
        // CDK rc.1 splits atomic pay_request into prepare + confirm: prepare
        // resolves method/fees and reserves proofs, confirm delivers. On
        // delivery failure the pending operation stays reclaimable via
        // revokeSend instead of paying twice.
        walletFor(mintUrl)
            .preparePayRequest(request, if (request.amount() == null) amount else null)
            .confirm()
    }

    override suspend fun listPendingSendOperationIds(mintUrl: String, unit: String): List<String> = cdkCall {
        runCatching { walletFor(mintUrl, cdkUnit(unit)).getPendingSends() }.getOrDefault(emptyList())
    }

    override suspend fun checkPendingSendClaimed(mintUrl: String, operationId: String, unit: String): Boolean = cdkCall {
        walletFor(mintUrl, cdkUnit(unit)).checkSendStatus(operationId)
    }

    override suspend fun revokePendingSend(mintUrl: String, operationId: String, unit: String): Long = cdkCall {
        walletFor(mintUrl, cdkUnit(unit)).revokeSend(operationId).value.toLong()
    }

    override suspend fun mintUnissuedQuotes(mintUrl: String, unit: String): Long = cdkCall {
        walletFor(mintUrl, cdkUnit(unit)).mintUnissuedQuotes().value.toLong()
    }

    override suspend fun pendingSendTokenFromSaga(operationId: String): String? = cdkCall {
        val sagaJson = runCatching { database?.getSaga(operationId) }.getOrNull() ?: return@cdkCall null
        runCatching {
            val data = sagaJsonFormat.parseToJsonElement(sagaJson).jsonObject["data"]?.jsonObject
            if (data?.get("kind")?.jsonPrimitive?.content != "send") return@cdkCall null
            data["data"]?.jsonObject?.get("token")?.jsonPrimitive?.content
        }.getOrNull()
    }

    private suspend fun <T> cdkCall(block: suspend () -> T): T =
        withContext(Dispatchers.IO) {
            operationMutex.withLock { block() }
        }

    private suspend fun ensureWalletUnlocked(
        mintUrl: String,
        unit: CdkCurrencyUnit = CdkCurrencyUnit.Sat,
    ) {
        requireRepository().createWallet(CdkMintUrl(mintUrl), unit, null)
    }

    private fun normalizeMintUrl(url: String): String = url.trim().trimEnd('/')

    private fun requireRepository(): CdkWalletRepository =
        repository ?: throw CdkGatewayUnavailable("Wallet repository is not initialized.")

    private suspend fun walletFor(
        mintUrl: String,
        unit: CdkCurrencyUnit = CdkCurrencyUnit.Sat,
    ): CdkWallet = requireRepository().getWallet(CdkMintUrl(mintUrl), unit)

    private suspend fun firstWallet(): CdkWallet =
        requireRepository().getWallets().firstOrNull()
            ?: throw CdkGatewayUnavailable("No mint wallet is available.")

    private inner class CdkNwcServiceHandle(
        private val service: CdkNwcService,
        override val connectionUri: String,
    ) : NwcServiceHandle {
        override suspend fun start() = cdkCall { service.start() }

        override suspend fun stop() = cdkCall { service.stop() }

        override suspend fun isRunning(): Boolean = cdkCall { service.isRunning() }

        override suspend fun close() = cdkCall { service.close() }
    }

    private fun cdkUnit(unit: String): CdkCurrencyUnit = when (unit.lowercase()) {
        "sat" -> CdkCurrencyUnit.Sat
        "msat" -> CdkCurrencyUnit.Msat
        "usd" -> CdkCurrencyUnit.Usd
        "eur" -> CdkCurrencyUnit.Eur
        "auth" -> CdkCurrencyUnit.Auth
        else -> CdkCurrencyUnit.Custom(unit)
    }

    private fun cdkPaymentMethod(method: PaymentMethodKind): CdkPaymentMethod = when (method) {
        PaymentMethodKind.Bolt11 -> CdkPaymentMethod.Bolt11
        PaymentMethodKind.Bolt12 -> CdkPaymentMethod.Bolt12
        PaymentMethodKind.Onchain -> CdkPaymentMethod.Onchain
    }

    private fun CdkPaymentMethod.toDomain(): PaymentMethodKind = when (this) {
        CdkPaymentMethod.Bolt11 -> PaymentMethodKind.Bolt11
        CdkPaymentMethod.Bolt12 -> PaymentMethodKind.Bolt12
        CdkPaymentMethod.Onchain -> PaymentMethodKind.Onchain
        is CdkPaymentMethod.Custom -> PaymentMethodKind.fromRaw(method) ?: PaymentMethodKind.Bolt11
    }

    private fun CdkQuoteState.toMintState(): MintQuoteState = when (this) {
        CdkQuoteState.UNPAID -> MintQuoteState.Unpaid
        CdkQuoteState.PAID -> MintQuoteState.Paid
        CdkQuoteState.PENDING -> MintQuoteState.Pending
        CdkQuoteState.ISSUED -> MintQuoteState.Issued
    }

    private fun CdkQuoteState.toMeltState(): MeltQuoteState = when (this) {
        CdkQuoteState.UNPAID -> MeltQuoteState.Unpaid
        CdkQuoteState.PAID -> MeltQuoteState.Paid
        CdkQuoteState.PENDING -> MeltQuoteState.Pending
        CdkQuoteState.ISSUED -> MeltQuoteState.Paid
    }

    private fun CdkNotificationPayload.referencesMintQuote(quoteId: String): Boolean = when (this) {
        is CdkNotificationPayload.MintQuoteUpdate -> quote.quote == quoteId
        is CdkNotificationPayload.MintQuoteOnchainUpdate -> quote.quote == quoteId
        else -> false
    }

    private fun CdkMintInfo.toDomain(mintUrl: String): MintInfo {
        // NUT-04/05 rails keep their reported-empty state (an absent direction is
        // hidden, not replaced with BOLT11); see CdkMintMethodMapping.kt.
        val mintMethods = nuts.reportedMintMethods()
        val meltMethods = nuts.reportedMeltMethods()
        val units = (nuts.mintUnits + nuts.meltUnits)
            .map { it.toDomainUnit() }
            .distinct()
            .sorted()
            .ifEmpty { listOf("sat") }
        val mintUnits = nuts.mintUnits
            .map { it.toDomainUnit() }
            .distinct()
            .sorted()
            .ifEmpty { listOf("sat") }
        return MintInfo(
            url = mintUrl,
            name = name ?: "Unknown Mint",
            description = description,
            iconUrl = iconUrl,
            units = units,
            mintUnits = mintUnits,
            supportedMintMethods = mintMethods,
            supportedMeltMethods = meltMethods,
            contacts = contact.orEmpty().map { MintContact(method = it.method, info = it.info) },
            tosUrl = tosUrl,
            software = version?.let { MintSoftware(name = it.name, version = it.version) },
            descriptionLong = descriptionLong,
            motd = motd,
            nutSupport = NutSupport(
                tokenStateCheck = nuts.nut07Supported,
                lightningFeeReturn = nuts.nut08Supported,
                restoreFromSeed = nuts.nut09Supported,
                spendingConditions = nuts.nut10Supported,
                p2pk = nuts.nut11Supported,
                dleq = nuts.nut12Supported,
                htlc = nuts.nut14Supported,
                webSocket = nuts.nut20Supported,
            ),
            lastUpdatedEpochMillis = System.currentTimeMillis(),
        )
    }

    private fun CdkCurrencyUnit.toDomainUnit(): String = when (this) {
        CdkCurrencyUnit.Sat -> "sat"
        CdkCurrencyUnit.Msat -> "msat"
        CdkCurrencyUnit.Usd -> "usd"
        CdkCurrencyUnit.Eur -> "eur"
        CdkCurrencyUnit.Auth -> "auth"
        is CdkCurrencyUnit.Custom -> unit
    }

    private fun CdkMintQuote.toDomain(
        fallbackAmount: Long?,
        fallbackMethod: PaymentMethodKind,
    ): MintQuoteInfo {
        val method = paymentMethod.toDomain().takeIf { it == fallbackMethod } ?: fallbackMethod
        val paid = amountPaid.value.toLong()
        val issued = amountIssued.value.toLong()
        return MintQuoteInfo(
            id = id,
            request = request,
            amount = mintQuoteAmountForDomain(amount?.value?.toLong(), fallbackAmount, paid, issued),
            isAmountless = amount == null,
            paymentMethod = method,
            state = mintQuoteStateForDomain(method, state.toMintState(), paid, issued),
            expiryEpochSeconds = mintQuoteDisplayExpiry(expiry.toLong()),
            mintUrl = mintUrl.url,
            amountPaid = paid,
            amountIssued = issued,
            updatedAtEpochSeconds = updatedAt.toLong(),
            unit = unit.toDomainUnit(),
        )
    }

    private fun NPCQuote.toCdkMintQuote(mintUrl: String): CdkMintQuote {
        val amountValue = amount.takeIf { it > 0 }?.toCdkAmount()
        val state = toCdkQuoteState()
        return CdkMintQuote(
            id = id,
            amount = amountValue,
            unit = CdkCurrencyUnit.Sat,
            request = request.orEmpty(),
            state = state,
            expiry = expiryEpochSeconds?.takeIf { it > 0 }?.toULong() ?: 0uL,
            mintUrl = CdkMintUrl(mintUrl),
            amountIssued = if (state == CdkQuoteState.ISSUED) amountValue ?: CdkAmount(0uL) else CdkAmount(0uL),
            amountPaid = if (isPaid || state == CdkQuoteState.ISSUED) amountValue ?: CdkAmount(0uL) else CdkAmount(0uL),
            updatedAt = 0uL,
            estimatedBlocks = null,
            paymentMethod = CdkPaymentMethod.Bolt11,
            secretKey = null,
            usedByOperation = null,
            version = 0u,
        )
    }

    private fun NPCQuote.toCdkQuoteState(): CdkQuoteState = when (state?.uppercase()) {
        "PAID" -> CdkQuoteState.PAID
        "PENDING" -> CdkQuoteState.PENDING
        "ISSUED" -> CdkQuoteState.ISSUED
        else -> CdkQuoteState.UNPAID
    }

    private suspend fun CdkMintQuote.clearingOrphanedReservationIfNeeded(): CdkMintQuote {
        val operationId = usedByOperation ?: return this
        val saga = runCatching { database?.getSaga(operationId) }.getOrNull()
        if (saga != null) return this
        return clearingReservation()
    }

    private suspend fun replaceStoredMintQuote(quote: CdkMintQuote) {
        val db = database ?: return
        try {
            db.addMintQuote(quote)
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (_: Throwable) {
            db.removeMintQuote(quote.id)
            db.addMintQuote(quote)
        }
    }

    private suspend fun persistMintQuoteLocalMetadataIfNeeded(
        quote: CdkMintQuote,
        method: PaymentMethodKind,
        fallbackAmount: Long? = null,
        clearOrphanedReservation: Boolean = true,
    ): CdkMintQuote {
        val withLocalMetadata = quote.withLocalMintQuoteMetadata(method, fallbackAmount)
        val normalized = if (clearOrphanedReservation) {
            withLocalMetadata.clearingOrphanedReservationIfNeeded()
        } else {
            withLocalMetadata
        }
        if (normalized != quote) runCatching { replaceStoredMintQuote(normalized) }
        return normalized
    }

    private fun CdkMeltQuote.toDomain(fallbackMethod: PaymentMethodKind): MeltQuoteInfo = MeltQuoteInfo(
        id = id,
        mintUrl = mintUrl?.url.orEmpty(),
        amount = amount.value.toLong(),
        feeReserve = feeReserve.value.toLong(),
        paymentMethod = paymentMethod.toDomain().takeIf { it == fallbackMethod } ?: fallbackMethod,
        state = state.toMeltState(),
        expiryEpochSeconds = expiry.toLong(),
        request = request,
        paymentProof = paymentProof,
    )

    private fun CdkTransaction.toDomain(unit: String): WalletTransaction {
        val direction = if (direction == CdkTransactionDirection.INCOMING) TransactionType.Incoming else TransactionType.Outgoing
        val method = paymentMethod?.toDomain()
        return WalletTransaction(
            id = id.hex,
            amount = amount.value.toLong(),
            type = direction,
            kind = when (method) {
                PaymentMethodKind.Onchain -> TransactionKind.Onchain
                PaymentMethodKind.Bolt11, PaymentMethodKind.Bolt12 -> TransactionKind.Lightning
                null -> TransactionKind.Ecash
            },
            dateEpochMillis = timestamp.toLong() * 1000,
            memo = memo,
            // CDK 0.18 owns the lifecycle: pending while a send is unclaimed /
            // a mint or melt is in flight, failed when failed or revoked.
            status = status.toDomain(),
            mintUrl = mintUrl.url,
            preimage = paymentProof,
            invoice = paymentRequest,
            fee = fee.value.toLong(),
            unit = unit,
            sagaId = sagaId,
            quoteId = quoteId,
        )
    }

    private fun CdkTransactionStatus.toDomain(): TransactionStatus = when (this) {
        CdkTransactionStatus.PENDING -> TransactionStatus.Pending
        CdkTransactionStatus.COMPLETED -> TransactionStatus.Completed
        CdkTransactionStatus.FAILED -> TransactionStatus.Failed
    }

    private fun org.cashudevkit.KeySet.toKeySetInfo(): org.cashudevkit.KeySetInfo =
        org.cashudevkit.KeySetInfo(
            id = id,
            unit = unit,
            active = active ?: false,
            inputFeePpk = inputFeePpk,
        )

    private fun requirePositiveAmount(amountSats: Long?, message: String): Long {
        require(amountSats != null && amountSats > 0) { message }
        return amountSats
    }

    private fun bitcoinNetworkFor(mintUrl: String): CdkBitcoinNetwork {
        val host = runCatching { java.net.URI.create(mintUrl).host.orEmpty().lowercase() }
            .getOrDefault("")
        return when {
            host == "onchain.cashudevkit.org" || "signet" in host || "mutinynet" in host -> CdkBitcoinNetwork.SIGNET
            "regtest" in host -> CdkBitcoinNetwork.REGTEST
            "testnet" in host -> CdkBitcoinNetwork.TESTNET
            else -> CdkBitcoinNetwork.BITCOIN
        }
    }

    private fun Long.toCdkAmount(): CdkAmount = CdkAmount(toULong())
}
