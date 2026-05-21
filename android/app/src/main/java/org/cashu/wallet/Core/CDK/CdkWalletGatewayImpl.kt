package org.cashu.wallet.Core.CDK

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import org.cashu.wallet.Core.LightningRequestParser
import org.cashu.wallet.Core.NPCQuote
import org.cashu.wallet.Core.mintQuoteAmountForDomain
import org.cashu.wallet.Core.mintQuoteDisplayExpiry
import org.cashu.wallet.Core.mintQuoteStateForDomain
import org.cashu.wallet.Core.PaymentRequestDecodeResult
import org.cashu.wallet.Core.PaymentRequestDecoder
import org.cashu.wallet.Core.PaymentRequestParser
import org.cashu.wallet.Models.MeltPaymentResult
import org.cashu.wallet.Models.MeltQuoteInfo
import org.cashu.wallet.Models.MeltQuoteState
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Models.MintQuoteInfo
import org.cashu.wallet.Models.MintQuoteState
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashu.wallet.Models.RestoreMintResult
import org.cashu.wallet.Models.SendTokenResult
import org.cashu.wallet.Models.TransactionKind
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.TransactionType
import org.cashu.wallet.Models.WalletTransaction
import org.cashudevkit.Amount as CdkAmount
import org.cashudevkit.BitcoinNetwork as CdkBitcoinNetwork
import org.cashudevkit.CurrencyUnit as CdkCurrencyUnit
import org.cashudevkit.MeltQuote as CdkMeltQuote
import org.cashudevkit.MintInfo as CdkMintInfo
import org.cashudevkit.MintQuote as CdkMintQuote
import org.cashudevkit.MintUrl as CdkMintUrl
import org.cashudevkit.NotificationPayload as CdkNotificationPayload
import org.cashudevkit.PaymentMethod as CdkPaymentMethod
import org.cashudevkit.QuoteState as CdkQuoteState
import org.cashudevkit.ReceiveOptions as CdkReceiveOptions
import org.cashudevkit.SendKind as CdkSendKind
import org.cashudevkit.SendMemo as CdkSendMemo
import org.cashudevkit.SendOptions as CdkSendOptions
import org.cashudevkit.SecretKey as CdkSecretKey
import org.cashudevkit.SplitTarget as CdkSplitTarget
import org.cashudevkit.SpendingConditions as CdkSpendingConditions
import org.cashudevkit.Token as CdkToken
import org.cashudevkit.Transaction as CdkTransaction
import org.cashudevkit.TransactionDirection as CdkTransactionDirection
import org.cashudevkit.Wallet as CdkWallet
import org.cashudevkit.WalletRepository as CdkWalletRepository
import org.cashudevkit.WalletSqliteDatabase as CdkWalletSqliteDatabase
import org.cashudevkit.customWalletStore
import org.cashudevkit.decodePaymentRequest
import org.cashudevkit.generateMnemonic as cdkGenerateMnemonic
import org.cashudevkit.initLogging
import org.cashudevkit.mnemonicToEntropy
import org.cashudevkit.proofsTotalAmount

class CdkWalletGatewayImpl : CdkWalletGateway {
    private var database: CdkWalletSqliteDatabase? = null
    private var repository: CdkWalletRepository? = null

    override suspend fun initializeLogging(level: String) {
        initLogging(level)
    }

    override suspend fun generateMnemonic(): String = cdkGenerateMnemonic()

    override suspend fun mnemonicEntropy(mnemonic: String): ByteArray = mnemonicToEntropy(mnemonic)

    override suspend fun validateMnemonic(mnemonic: String): Boolean =
        runCatching { mnemonicToEntropy(mnemonic); true }.getOrDefault(false)

    override suspend fun openWalletRepository(mnemonic: String, databasePath: String) {
        closeWalletRepository()
        val db = CdkWalletSqliteDatabase(databasePath)
        database = db
        repository = CdkWalletRepository(mnemonic, customWalletStore(db))
    }

    override suspend fun closeWalletRepository() {
        runCatching { repository?.close() }
        runCatching { database?.close() }
        repository = null
        database = null
    }

    override suspend fun ensureWallet(mintUrl: String, unit: String) {
        requireRepository().createWallet(CdkMintUrl(mintUrl), cdkUnit(unit), null)
    }

    override suspend fun removeWallet(mintUrl: String, unit: String) {
        requireRepository().removeWallet(CdkMintUrl(mintUrl), cdkUnit(unit))
    }

    override suspend fun fetchMintInfo(mintUrl: String): MintInfo? {
        val wallet = walletFor(mintUrl)
        return wallet.fetchMintInfo()?.toDomain(mintUrl)
    }

    override suspend fun restoreMint(mintUrl: String): RestoreMintResult {
        ensureWallet(mintUrl)
        val wallet = walletFor(mintUrl)
        val info = runCatching { wallet.fetchMintInfo() }.getOrNull()
        val restored = wallet.restore()
        return RestoreMintResult(
            mintUrl = mintUrl,
            mintName = info?.name ?: "Unknown Mint",
            spent = restored.spent.value.toLong(),
            unspent = restored.unspent.value.toLong(),
            pending = restored.pending.value.toLong(),
        )
    }

    override suspend fun totalBalance(mintUrl: String): Long =
        walletFor(mintUrl).totalBalance().value.toLong()

    override suspend fun createMintQuote(amount: Long?, method: PaymentMethodKind, mintUrl: String): MintQuoteInfo {
        val wallet = walletFor(mintUrl)
        val quote = wallet.mintQuote(
            paymentMethod = cdkPaymentMethod(method),
            amount = amount?.toCdkAmount(),
            description = null,
            extra = if (method == PaymentMethodKind.Onchain) "{}" else null,
        )
        return persistMintQuoteLocalMetadataIfNeeded(
            quote = quote,
            method = method,
            fallbackAmount = amount,
        ).toDomain(fallbackAmount = amount, fallbackMethod = method)
    }

    override suspend fun checkMintQuote(quoteId: String): MintQuoteInfo {
        val quote = database?.getMintQuote(quoteId)
            ?: throw CdkGatewayUnavailable("No stored mint quote for $quoteId.")
        val wallet = walletFor(quote.mintUrl.url)
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
        return refreshed.toDomain(
            fallbackAmount = fallbackAmount,
            fallbackMethod = method,
        )
    }

    override fun subscribeToMintQuote(quoteId: String): Flow<MintQuoteInfo> = flow {
        val quote = database?.getMintQuote(quoteId)
            ?: throw CdkGatewayUnavailable("No stored mint quote for $quoteId.")
        val method = quote.paymentMethod.toDomain()
        val subscription = walletFor(quote.mintUrl.url)
            .subscribeMintQuoteState(listOf(quoteId), cdkPaymentMethod(method))
        try {
            while (true) {
                val payload = subscription.recv()
                if (!payload.referencesMintQuote(quoteId)) continue
                val refreshed = checkMintQuote(quoteId)
                emit(refreshed)
                if (refreshed.state == MintQuoteState.Paid || refreshed.state == MintQuoteState.Issued) return@flow
            }
        } finally {
            subscription.close()
        }
    }.flowOn(Dispatchers.IO)

    override suspend fun listUnissuedMintQuotes(): List<MintQuoteInfo> =
        database?.getUnissuedMintQuotes().orEmpty().map { quote ->
            val method = quote.paymentMethod.toDomain()
            quote.withLocalMintQuoteMetadata(method).toDomain(
                fallbackAmount = null,
                fallbackMethod = method,
            )
        }

    override suspend fun mintTokens(quoteId: String): Long {
        val quote = database?.getMintQuote(quoteId)
            ?: throw CdkGatewayUnavailable("No stored mint quote for $quoteId.")
        val method = quote.paymentMethod.toDomain()
        val fallbackAmount = quote.amount?.value?.toLong()
        val currentQuote = if (method == PaymentMethodKind.Onchain) {
            walletFor(quote.mintUrl.url)
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
        normalizedQuote.usedByOperation?.let { releaseMintQuoteReservation(it, quoteId) }
        val proofs = walletFor(normalizedQuote.mintUrl.url).mintUnified(
            quoteId = quoteId,
            amountSplitTarget = normalizedQuote.mintAmountSplitTarget(method),
            spendingConditions = null,
        )
        return proofsTotalAmount(proofs).value.toLong()
    }

    override suspend fun mintNPCQuote(quote: NPCQuote, p2pkPubkey: String?): Long {
        val mintUrl = quote.mintUrl?.let(::normalizeMintUrl)
            ?: throw CdkGatewayUnavailable("npub.cash quote ${quote.id} has no mint URL.")
        ensureWallet(mintUrl)
        replaceStoredMintQuote(quote.toCdkMintQuote(mintUrl))
        val proofs = walletFor(mintUrl).mintUnified(
            quoteId = quote.id,
            amountSplitTarget = CdkSplitTarget.None,
            spendingConditions = p2pkPubkey?.let { CdkSpendingConditions.P2pk(it, null) },
        )
        return proofsTotalAmount(proofs).value.toLong()
    }

    override suspend fun createMeltQuote(request: String, amountSats: Long?, preferredMintURL: String?): MeltQuoteInfo {
        val wallet = preferredMintURL?.let { walletFor(it) } ?: firstWallet()
        when (val decoded = PaymentRequestDecoder.decode(request)) {
            is PaymentRequestDecodeResult.LightningAddress -> {
                val amount = requirePositiveAmount(amountSats, "Lightning address payments require an amount.")
                val quote = wallet.meltHumanReadable(
                    address = decoded.address,
                    amountMsat = (amount * 1_000).toCdkAmount(),
                    network = bitcoinNetworkFor(wallet.mintUrl().url),
                )
                return quote.toDomain(fallbackMethod = PaymentMethodKind.Bolt11)
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
                return wallet.selectOnchainMeltQuote(selected).toDomain(fallbackMethod = PaymentMethodKind.Onchain)
            }
            else -> Unit
        }
        val method = PaymentRequestParser.paymentMethod(request) ?: PaymentMethodKind.Bolt11
        val normalized = PaymentRequestDecoder.encodedLightningRequest(request) ?: request.trim()
        val quote = wallet.meltQuote(
            method = cdkPaymentMethod(method),
            request = normalized,
            options = null,
            extra = null,
        )
        return quote.toDomain(fallbackMethod = method)
    }

    override suspend fun listMeltQuotes(): List<MeltQuoteInfo> =
        database?.getMeltQuotes().orEmpty().map { quote ->
            quote.toDomain(fallbackMethod = quote.paymentMethod.toDomain())
        }

    override suspend fun meltTokens(quoteId: String, mintUrl: String?): MeltPaymentResult {
        val quote = database?.getMeltQuote(quoteId)
        val wallet = walletFor(mintUrl ?: quote?.mintUrl?.url ?: firstWallet().mintUrl().url)
        val prepared = wallet.prepareMelt(quoteId)
        val finalized = prepared.confirm()
        return MeltPaymentResult(
            preimage = finalized.preimage,
            amount = finalized.amount.value.toLong(),
            feePaid = finalized.feePaid.value.toLong(),
            mintUrl = wallet.mintUrl().url,
            paymentMethod = quote?.paymentMethod?.toDomain(),
            request = quote?.request,
        )
    }

    override suspend fun sendEcashToken(amount: Long, memo: String?, p2pkPubkey: String?, mintUrl: String): SendTokenResult {
        val conditions = p2pkPubkey?.let { CdkSpendingConditions.P2pk(it, null) }
        val sendOptions = CdkSendOptions(
            memo = memo?.let { CdkSendMemo(it, true) },
            conditions = conditions,
            amountSplitTarget = CdkSplitTarget.None,
            sendKind = CdkSendKind.OnlineExact,
            includeFee = false,
            useP2bk = false,
            maxProofs = null,
            metadata = emptyMap(),
        )
        val prepared = walletFor(mintUrl).prepareSend(amount.toCdkAmount(), sendOptions)
        val fee = prepared.fee().value.toLong()
        val token = prepared.confirm(memo)
        return SendTokenResult(token = token.encode(), fee = fee)
    }

    override suspend fun receiveEcashToken(tokenString: String, p2pkSigningKeys: List<String>): Long {
        val token = CdkToken.decode(tokenString)
        val mintUrl = token.mintUrl().url
        ensureWallet(mintUrl)
        val amount = walletFor(mintUrl).receive(
            token = token,
            options = CdkReceiveOptions(
                amountSplitTarget = CdkSplitTarget.None,
                p2pkSigningKeys = p2pkSigningKeys.map(::CdkSecretKey),
                preimages = emptyList(),
                metadata = emptyMap(),
            ),
        )
        return amount.value.toLong()
    }

    override suspend fun calculateReceiveFee(tokenString: String): Long {
        val token = CdkToken.decode(tokenString)
        val proofs = token.proofsSimple()
        val first = proofs.firstOrNull() ?: return 0
        val wallet = walletFor(token.mintUrl().url)
        return runCatching {
            wallet.calculateFee(proofs.size.toUInt(), first.keysetId).value.toLong()
        }.getOrElse {
            wallet.getKeysetFeesById(first.keysetId).toLong() * proofs.size
        }
    }

    override suspend fun checkTokenSpendable(token: String, mintUrl: String): Boolean {
        val tokenObj = CdkToken.decode(token)
        val states = walletFor(mintUrl).checkProofsSpent(tokenObj.proofsSimple())
        return states.any { it }
    }

    override suspend fun listTransactions(mintUrls: List<String>): List<WalletTransaction> {
        return mintUrls.flatMap { mintUrl ->
            val wallet = runCatching { walletFor(mintUrl) }.getOrNull() ?: return@flatMap emptyList()
            val incoming = runCatching { wallet.listTransactions(CdkTransactionDirection.INCOMING) }.getOrDefault(emptyList())
            val outgoing = runCatching { wallet.listTransactions(CdkTransactionDirection.OUTGOING) }.getOrDefault(emptyList())
            (incoming + outgoing).map { it.toDomain() }
        }
    }

    override suspend fun payCashuPaymentRequest(encoded: String, customAmountSats: Long?, preferredMintURL: String?) {
        val request = decodePaymentRequest(encoded)
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
        walletFor(mintUrl).payRequest(request, if (request.amount() == null) amount else null)
    }

    private fun normalizeMintUrl(url: String): String = url.trim().trimEnd('/')

    private fun requireRepository(): CdkWalletRepository =
        repository ?: throw CdkGatewayUnavailable("Wallet repository is not initialized.")

    private suspend fun walletFor(mintUrl: String): CdkWallet =
        requireRepository().getWallet(CdkMintUrl(mintUrl), CdkCurrencyUnit.Sat)

    private suspend fun firstWallet(): CdkWallet =
        requireRepository().getWallets().firstOrNull()
            ?: throw CdkGatewayUnavailable("No mint wallet is available.")

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
        val mintMethods = nuts.nut04.methods
            .filter { it.unit == CdkCurrencyUnit.Sat }
            .map { it.method.toDomain() }
            .distinct()
            .sortedBy { it.sortOrder }
            .ifEmpty { listOf(PaymentMethodKind.Bolt11) }
        val meltMethods = nuts.nut05.methods
            .filter { it.unit == CdkCurrencyUnit.Sat }
            .map { it.method.toDomain() }
            .distinct()
            .sortedBy { it.sortOrder }
            .ifEmpty { listOf(PaymentMethodKind.Bolt11) }
        val units = (nuts.mintUnits + nuts.meltUnits)
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
            supportedMintMethods = mintMethods,
            supportedMeltMethods = meltMethods,
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
            paymentMethod = method,
            state = mintQuoteStateForDomain(method, state.toMintState(), paid, issued),
            expiryEpochSeconds = mintQuoteDisplayExpiry(expiry.toLong()),
            mintUrl = mintUrl.url,
            amountPaid = paid,
            amountIssued = issued,
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

    private suspend fun releaseMintQuoteReservation(operationId: String, quoteId: String) {
        runCatching {
            database?.releaseMintQuote(operationId)
            runCatching { database?.deleteSaga(operationId) }
            val refreshed = database?.getMintQuote(quoteId)
            if (refreshed?.usedByOperation != null) {
                replaceStoredMintQuote(refreshed.clearingReservation())
            }
        }
    }

    private suspend fun replaceStoredMintQuote(quote: CdkMintQuote) {
        val db = database ?: return
        runCatching { db.addMintQuote(quote) }
            .onFailure {
                db.removeMintQuote(quote.id)
                db.addMintQuote(quote)
            }
            .getOrThrow()
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

    private fun CdkTransaction.toDomain(): WalletTransaction {
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
            status = TransactionStatus.Completed,
            mintUrl = mintUrl.url,
            preimage = paymentProof,
            invoice = paymentRequest,
            fee = fee.value.toLong(),
            quoteId = quoteId,
        )
    }

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
