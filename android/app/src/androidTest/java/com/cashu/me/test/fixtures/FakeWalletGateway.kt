package com.cashu.me.test.fixtures

import com.cashu.me.Core.CDK.ForeignNfcSettlement
import com.cashu.me.Core.CDK.MeltConfirmation
import com.cashu.me.Core.CDK.MultiUnitWalletRemovalException
import com.cashu.me.Core.CDK.NfcReceiveReceipt
import com.cashu.me.Core.CDK.NwcServiceHandle
import com.cashu.me.Core.CDK.SagaRecoveryReport
import com.cashu.me.Core.CDK.WalletGateway
import com.cashu.me.Core.NPCQuote
import com.cashu.me.Models.MeltPaymentResult
import com.cashu.me.Models.MeltQuoteInfo
import com.cashu.me.Models.MeltQuoteState
import com.cashu.me.Models.MeltSettlement
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.Models.MintQuoteState
import com.cashu.me.Models.NutSupport
import com.cashu.me.Models.PaymentMethodKind
import com.cashu.me.Models.RestoreMintResult
import com.cashu.me.Models.SendTokenResult
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filter

/**
 * Stateful deterministic native-wallet replacement used only by app-level
 * instrumentation. Tests drive quote transitions explicitly; it starts no
 * timers and performs no network or relay calls.
 */
class FakeWalletGateway(
    initialBalances: Map<String, Long> = emptyMap(),
    initialTransactions: List<WalletTransaction> = emptyList(),
    private val supportedMintMethods: List<PaymentMethodKind> = listOf(PaymentMethodKind.Bolt11),
) : WalletGateway {
    private val sequence = AtomicInteger(1)
    private val walletUrls = linkedSetOf<String>()
    private val walletUnits = linkedMapOf<String, MutableSet<String>>()
    private val mintInfo = linkedMapOf<String, MintInfo>()
    private val balances = initialBalances.toMutableMap()
    private val nonSatBalances = mutableMapOf<Pair<String, String>, Long>()
    private val transactions = initialTransactions.toMutableList()
    private val mintQuotes = linkedMapOf<String, MutableStateFlow<MintQuoteInfo>>()
    private val meltQuotes = linkedMapOf<String, MeltQuoteInfo>()
    private var repositoryOpen = false

    var nextFailure: Throwable? = null
    val latestMintQuoteId: String?
        get() = mintQuotes.keys.lastOrNull()

    suspend fun setUnitBalance(mintUrl: String, unit: String, amount: Long) {
        ensureWallet(mintUrl, unit)
        nonSatBalances[normalize(mintUrl) to unit] = amount
    }

    fun setBalance(mintUrl: String, amount: Long) {
        balances[normalize(mintUrl)] = amount
    }

    fun addTransaction(transaction: WalletTransaction) {
        transactions.removeAll { it.id == transaction.id }
        transactions += transaction
    }

    fun markMintQuotePaid(quoteId: String, amountPaid: Long? = null) {
        val flow = checkNotNull(mintQuotes[quoteId]) { "Unknown fake quote $quoteId" }
        val current = flow.value
        flow.value = current.copy(
            state = MintQuoteState.Paid,
            amountPaid = amountPaid ?: current.amount ?: 0,
        )
    }

    private fun failIfRequested() {
        nextFailure?.let {
            nextFailure = null
            throw it
        }
    }

    override suspend fun initializeLogging(level: String) = Unit

    override suspend fun generateMnemonic(): String = FixedMnemonic

    override suspend fun mnemonicEntropy(mnemonic: String): ByteArray =
        ByteArray(32) { index -> (index + 1).toByte() }

    override suspend fun validateMnemonic(mnemonic: String): Boolean =
        mnemonic.trim().split(Regex("\\s+")).size in setOf(12, 24)

    override suspend fun openWalletRepository(mnemonic: String, databasePath: String) {
        repositoryOpen = true
    }

    override suspend fun closeWalletRepository() {
        repositoryOpen = false
    }

    override suspend fun hasWallets(): Boolean = walletUrls.isNotEmpty()

    override suspend fun backupMints(relays: List<String>, client: String) = Unit

    override suspend fun fetchMintBackup(relays: List<String>, timeoutSecs: ULong): List<String> =
        walletUrls.toList()

    override suspend fun ensureWallet(mintUrl: String, unit: String) {
        check(repositoryOpen) { "Fake wallet repository is not open." }
        val normalized = normalize(mintUrl)
        walletUrls += normalized
        walletUnits.getOrPut(normalized) { linkedSetOf() } += unit.trim().lowercase()
        balances.putIfAbsent(normalized, 0)
        mintInfo.putIfAbsent(normalized, defaultMint(normalized))
    }

    override suspend fun removeWalletIfSingleUnit(mintUrl: String): Boolean {
        val normalized = normalize(mintUrl)
        val registeredUnits = walletUnits[normalized].orEmpty().toList()
        if (registeredUnits.size > 1) throw MultiUnitWalletRemovalException(registeredUnits)
        if (registeredUnits.isEmpty()) return false
        walletUrls -= normalized
        walletUnits -= normalized
        mintInfo -= normalized
        balances -= normalized
        return true
    }

    override suspend fun fetchMintInfo(mintUrl: String): MintInfo? {
        failIfRequested()
        check(repositoryOpen) { "Fake wallet repository is not open." }
        val normalized = normalize(mintUrl)
        return mintInfo.getOrPut(normalized) { defaultMint(normalized) }
    }

    override suspend fun restoreMint(mintUrl: String): RestoreMintResult {
        val normalized = normalize(mintUrl)
        return RestoreMintResult(
            mintUrl = normalized,
            mintName = mintInfo[normalized]?.name ?: "Test Mint",
            spent = 0,
            unspent = balances[normalized] ?: 0,
            pending = 0,
        )
    }

    override suspend fun storedAccounts() = walletUnits.flatMap { (url, units) ->
        units.map { com.cashu.me.Core.CDK.WalletAccountReference(url, it) }
    } + transactions.mapNotNull { tx -> tx.mintUrl?.let { com.cashu.me.Core.CDK.WalletAccountReference(it, tx.unit) } }

    override suspend fun storedAccountBalance(account: com.cashu.me.Core.CDK.WalletAccountReference): Long =
        unitBalance(account.mintUrl, account.unit)

    override suspend fun totalBalance(mintUrl: String): Long =
        balances[normalize(mintUrl)] ?: 0

    override suspend fun unitBalance(mintUrl: String, unit: String): Long =
        if (unit.equals("sat", ignoreCase = true)) totalBalance(mintUrl) else nonSatBalances[normalize(mintUrl) to unit] ?: 0

    override suspend fun unitBalanceIfExists(mintUrl: String, unit: String): Long? =
        if (unit.equals("sat", ignoreCase = true)) totalBalance(mintUrl) else null

    override suspend fun createMintQuote(
        amount: Long?,
        method: PaymentMethodKind,
        mintUrl: String,
        unit: String,
        description: String?,
    ): MintQuoteInfo {
        failIfRequested()
        val id = "mint-quote-${sequence.getAndIncrement()}"
        val quote = MintQuoteInfo(
            id = id,
            request = when (method) {
                PaymentMethodKind.Onchain -> "bcrt1qdeterministicuitestaddress"
                PaymentMethodKind.Bolt11 -> "lnbc${amount ?: 0}n1deterministicuitest"
                PaymentMethodKind.Bolt12 -> "lno1deterministicuitest"
            },
            amount = amount,
            paymentMethod = method,
            state = MintQuoteState.Unpaid,
            expiryEpochSeconds = System.currentTimeMillis() / 1000 + 3_600,
            mintUrl = normalize(mintUrl),
            unit = unit,
            description = description.takeIf { method == PaymentMethodKind.Bolt12 },
        )
        mintQuotes[id] = MutableStateFlow(quote)
        return quote
    }

    override suspend fun checkMintQuote(quoteId: String): MintQuoteInfo =
        checkNotNull(mintQuotes[quoteId]) { "Unknown fake quote $quoteId" }.value

    override fun subscribeToMintQuote(quoteId: String, mayRefresh: () -> Boolean): Flow<MintQuoteInfo> =
        checkNotNull(mintQuotes[quoteId]) { "Unknown fake quote $quoteId" }
            .filter { mayRefresh() }

    override suspend fun listUnissuedMintQuotes(): List<MintQuoteInfo> =
        mintQuotes.values.map { it.value }.filter { it.state != MintQuoteState.Issued }

    override suspend fun mintTokens(quoteId: String): Long {
        val flow = checkNotNull(mintQuotes[quoteId]) { "Unknown fake quote $quoteId" }
        val quote = flow.value
        check(quote.state == MintQuoteState.Paid) { "Fake quote has not been paid." }
        val credited = (quote.amountPaid.takeIf { it > 0 } ?: quote.amount ?: 0) - quote.amountIssued
        val mintUrl = checkNotNull(quote.mintUrl)
        balances[mintUrl] = (balances[mintUrl] ?: 0) + credited
        transactions += WalletTransaction(
            id = "mint-payment-${sequence.getAndIncrement()}",
            quoteId = quote.id,
            amount = credited,
            type = TransactionType.Incoming,
            kind = if (quote.paymentMethod == PaymentMethodKind.Onchain) {
                TransactionKind.Onchain
            } else {
                TransactionKind.Lightning
            },
            dateEpochMillis = System.currentTimeMillis(),
            status = TransactionStatus.Completed,
            mintUrl = mintUrl,
            invoice = quote.request,
            unit = quote.unit,
        )
        flow.value = quote.copy(
            state = MintQuoteState.Issued,
            amountIssued = quote.amountIssued + credited,
        )
        return credited
    }

    override suspend fun mintNPCQuote(quote: NPCQuote, p2pkPubkey: String?): Long {
        val mintUrl = normalize(checkNotNull(quote.mintUrl))
        balances[mintUrl] = (balances[mintUrl] ?: 0) + quote.amount
        return quote.amount
    }

    override suspend fun createMeltQuote(
        request: String,
        amountSats: Long?,
        preferredMintURL: String?,
    ): MeltQuoteInfo {
        failIfRequested()
        val mintUrl = normalize(preferredMintURL ?: walletUrls.first())
        val quote = MeltQuoteInfo(
            id = "melt-quote-${sequence.getAndIncrement()}",
            mintUrl = mintUrl,
            amount = amountSats ?: 21,
            feeReserve = 2,
            paymentMethod = if (request.startsWith("bitcoin", ignoreCase = true)) {
                PaymentMethodKind.Onchain
            } else {
                PaymentMethodKind.Bolt11
            },
            state = MeltQuoteState.Unpaid,
            expiryEpochSeconds = System.currentTimeMillis() / 1000 + 3_600,
            request = request,
        )
        meltQuotes[quote.id] = quote
        return quote
    }

    override suspend fun listMeltQuotes(): List<MeltQuoteInfo> = meltQuotes.values.toList()

    override suspend fun meltTokens(quoteId: String, mintUrl: String?): MeltConfirmation {
        failIfRequested()
        val quote = checkNotNull(meltQuotes[quoteId]) { "Unknown fake melt quote $quoteId" }
        val total = quote.amount + quote.feeReserve
        check((balances[quote.mintUrl] ?: 0) >= total) { "Insufficient balance." }
        balances[quote.mintUrl] = checkNotNull(balances[quote.mintUrl]) - total
        meltQuotes[quoteId] = quote.copy(state = MeltQuoteState.Paid)
        transactions += WalletTransaction(
            id = "melt-payment-${sequence.getAndIncrement()}",
            quoteId = quote.id,
            amount = quote.amount,
            type = TransactionType.Outgoing,
            kind = if (quote.paymentMethod == PaymentMethodKind.Onchain) {
                TransactionKind.Onchain
            } else {
                TransactionKind.Lightning
            },
            dateEpochMillis = System.currentTimeMillis(),
            status = TransactionStatus.Completed,
            mintUrl = quote.mintUrl,
            fee = quote.feeReserve,
            invoice = quote.request,
        )
        return MeltConfirmation(
            result = MeltPaymentResult(
                preimage = "deterministic-preimage",
                amount = quote.amount,
                feePaid = quote.feeReserve,
                mintUrl = quote.mintUrl,
                paymentMethod = quote.paymentMethod,
                request = quote.request,
                settlement = MeltSettlement.Settled,
            ),
            pendingMelt = null,
        )
    }

    override suspend fun checkMeltQuoteStatus(quoteId: String, mintUrl: String?): MeltQuoteInfo =
        checkNotNull(meltQuotes[quoteId]) { "Unknown fake melt quote $quoteId" }

    override suspend fun recoverIncompleteSagas(mintUrl: String): SagaRecoveryReport =
        SagaRecoveryReport(recovered = 0, compensated = 0, skipped = 0, failed = 0)

    override suspend fun sendEcashToken(
        amount: Long,
        memo: String?,
        p2pkPubkey: String?,
        mintUrl: String,
        unit: String,
        p2pkSigningKeys: List<String>,
    ): SendTokenResult {
        failIfRequested()
        val normalized = normalize(mintUrl)
        val fee = 1L
        check((balances[normalized] ?: 0) >= amount + fee) { "Insufficient balance." }
        balances[normalized] = checkNotNull(balances[normalized]) - amount - fee
        return SendTokenResult(
            token = DeterministicToken,
            fee = fee,
        )
    }

    override suspend fun receiveEcashToken(
        tokenString: String,
        p2pkSigningKeys: List<String>,
    ): Long {
        failIfRequested()
        val mintUrl = walletUrls.firstOrNull() ?: normalize(TestMintUrl)
        ensureWallet(mintUrl)
        val credited = 25L
        balances[mintUrl] = (balances[mintUrl] ?: 0) + credited
        transactions += WalletTransaction(
            id = "ecash-receive-${sequence.getAndIncrement()}",
            amount = credited,
            type = TransactionType.Incoming,
            kind = TransactionKind.Ecash,
            dateEpochMillis = System.currentTimeMillis(),
            status = TransactionStatus.Completed,
            mintUrl = mintUrl,
            token = tokenString,
        )
        return credited
    }

    override suspend fun receiveNfcEcashToken(
        tokenString: String,
        p2pkSigningKeys: List<String>,
    ): NfcReceiveReceipt = NfcReceiveReceipt(
        amountReceived = receiveEcashToken(tokenString, p2pkSigningKeys),
        transactionId = "nfc-${sequence.getAndIncrement()}",
    )

    override suspend fun settleForeignNfcToken(
        tokenString: String,
        settlementMintUrl: String,
    ): ForeignNfcSettlement = ForeignNfcSettlement(
        amountReceived = receiveEcashToken(tokenString, emptyList()),
        transactionId = "nfc-settlement-${sequence.getAndIncrement()}",
        feePaid = 1,
        sourceMintUrl = TestMintUrl,
        settlementMintUrl = normalize(settlementMintUrl),
    )

    override suspend fun calculateReceiveFee(tokenString: String): Long = 0

    override suspend fun activeMintInputFeePpk(mintUrl: String): Long? = 0

    override suspend fun estimateCashuPaymentRequestFee(amountSats: Long, mintUrl: String): Long = 0

    override suspend fun checkTokenSpendable(token: String, mintUrl: String): Boolean = true

    override suspend fun listTransactions(
        unitsByMint: Map<String, List<String>>,
    ): List<WalletTransaction> = transactions.toList()

    override suspend fun listPendingSendOperationIds(mintUrl: String, unit: String): List<String> = emptyList()

    override suspend fun checkPendingSendClaimed(mintUrl: String, operationId: String, unit: String): Boolean = false

    override suspend fun revokePendingSend(mintUrl: String, operationId: String, unit: String): Long = 0

    override suspend fun mintUnissuedQuotes(mintUrl: String, unit: String): Long = 0

    override suspend fun pendingSendTokenFromSaga(operationId: String): String? = null

    override suspend fun payCashuPaymentRequest(
        encoded: String,
        customAmountSats: Long?,
        preferredMintURL: String?,
    ) {
        val mintUrl = normalize(preferredMintURL ?: walletUrls.first())
        val amount = customAmountSats ?: 21
        check((balances[mintUrl] ?: 0) >= amount) { "Insufficient balance." }
        balances[mintUrl] = checkNotNull(balances[mintUrl]) - amount
    }

    override suspend fun createOrRestoreNwcService(
        mintUrl: String,
        relays: List<String>,
        seed: ByteArray,
        clientSecretKey: String?,
        maxPaymentMsat: ULong?,
    ): NwcServiceHandle = FakeNwcServiceHandle

    private fun defaultMint(url: String): MintInfo = MintInfo(
        url = url,
        supportedMintMethods = supportedMintMethods,
        name = if (url == TestMintUrl) "Nutshell UI Test Mint" else "Test Mint",
        description = "Deterministic instrumented-test mint",
        nutSupport = NutSupport(
            tokenStateCheck = true,
            restoreFromSeed = true,
            p2pk = true,
        ),
    )

    private fun normalize(url: String): String = url.trim().trimEnd('/')

    companion object {
        const val TestMintUrl = "https://mint.test"
        const val FixedMnemonic =
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        const val DeterministicToken =
            "cashuAeyJ0b2tlbiI6W3sicHJvb2ZzIjpbXSwibWludCI6Imh0dHBzOi8vbWludC50ZXN0In1dfQ"
        const val UnknownMintDeterministicToken =
            "cashuAeyJ0b2tlbiI6W3sicHJvb2ZzIjpbXSwibWludCI6Imh0dHBzOi8vbWludC5taW5pYml0cy5jYXNoIn1dfQ"
        const val MemoDeterministicToken =
            "cashuAeyJ0b2tlbiI6W3sibWludCI6Imh0dHBzOi8vbWludC5taW5pYml0cy5jYXNoIiwicHJvb2ZzIjpbXX1dLCJ1bml0Ijoic2F0IiwibWVtbyI6IkNvZmZlZSBmcm9tIEFsaWNlIn0"
    }
}

private object FakeNwcServiceHandle : NwcServiceHandle {
    override val connectionUri: String = "nostr+walletconnect://deterministic-ui-test"
    private var running = false

    override suspend fun start() {
        running = true
    }

    override suspend fun stop() {
        running = false
    }

    override suspend fun isRunning(): Boolean = running

    override suspend fun close() {
        running = false
    }
}
