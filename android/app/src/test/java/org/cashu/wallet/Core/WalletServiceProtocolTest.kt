package org.cashu.wallet.Core

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import org.cashu.wallet.Core.Protocols.MintServiceProtocol
import org.cashu.wallet.Core.Protocols.QuoteServiceProtocol
import org.cashu.wallet.Core.Protocols.TokenServiceProtocol
import org.cashu.wallet.Core.Protocols.TransactionServiceProtocol
import org.cashu.wallet.Models.MeltPaymentResult
import org.cashu.wallet.Models.MeltQuoteInfo
import org.cashu.wallet.Models.MeltQuoteState
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Models.MintQuoteInfo
import org.cashu.wallet.Models.MintQuoteState
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashu.wallet.Models.SendTokenResult
import org.cashu.wallet.Models.TokenInfo
import org.cashu.wallet.Models.TransactionKind
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.TransactionType
import org.cashu.wallet.Models.WalletTransaction
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class WalletServiceProtocolTest {
    @Test
    fun serviceProtocolsExposeDomainModelsWithoutCdkTypes() = runBlocking {
        val fake = FakeWalletServices()
        val mint = fake.addMint("https://mint.example")
        fake.setActiveMint(mint)

        assertEquals(listOf(mint), fake.mints())
        assertEquals(mint, fake.activeMint())
        assertEquals(mint.url, fake.refreshMintInfo(mint).url)

        assertEquals("cashuAexample", fake.sendTokens(amount = 21, memo = "memo").token)
        assertEquals(21, fake.receiveToken("cashuAexample"))
        assertEquals(21, fake.parseToken("cashuAexample").amount)
        assertFalse(fake.checkTokenSpent("cashuAexample"))

        val transaction = WalletTransaction(
            id = "tx1",
            amount = 21,
            type = TransactionType.Incoming,
            kind = TransactionKind.Ecash,
            dateEpochMillis = 1_000,
            status = TransactionStatus.Pending,
        )
        fake.addTransaction(transaction)
        fake.updateTransactionStatus("tx1", TransactionStatus.Completed)
        assertEquals(TransactionStatus.Completed, fake.transactions().single().status)

        assertEquals(PaymentMethodKind.Bolt11, fake.createMintQuote(21, PaymentMethodKind.Bolt11).paymentMethod)
        assertEquals(MintQuoteState.Paid, fake.checkMintQuote("quote1").state)
        assertEquals(21, fake.mintTokens("quote1"))
        assertEquals(PaymentMethodKind.Onchain, fake.createOnchainMeltQuote("bc1qexample", 21).paymentMethod)
        assertEquals(21, fake.meltTokens("melt1").amount)
    }
}

private class FakeWalletServices :
    MintServiceProtocol,
    TokenServiceProtocol,
    TransactionServiceProtocol,
    QuoteServiceProtocol {
    private val mints = mutableListOf<MintInfo>()
    private var activeMint: MintInfo? = null
    private val transactions = mutableListOf<WalletTransaction>()

    override suspend fun mints(): List<MintInfo> = mints

    override suspend fun activeMint(): MintInfo? = activeMint

    override suspend fun addMint(url: String): MintInfo {
        val mint = MintInfo(url = url, name = "Example mint")
        mints += mint
        return mint
    }

    override suspend fun removeMint(url: String) {
        mints.removeAll { it.url == url }
        if (activeMint?.url == url) activeMint = null
    }

    override suspend fun setActiveMint(mint: MintInfo) {
        activeMint = mint
    }

    override suspend fun refreshMintInfo(mint: MintInfo): MintInfo = mint.copy(lastUpdatedEpochMillis = mint.lastUpdatedEpochMillis + 1)

    override suspend fun sendTokens(amount: Long, memo: String?): SendTokenResult = SendTokenResult(
        token = "cashuAexample",
        fee = 0,
    )

    override suspend fun receiveToken(tokenString: String): Long = 21

    override fun parseToken(tokenString: String): TokenInfo = TokenInfo(
        amount = 21,
        mint = "https://mint.example",
        unit = "sat",
        memo = null,
        proofCount = 1,
    )

    override suspend fun checkTokenSpent(tokenString: String): Boolean = false

    override suspend fun transactions(): List<WalletTransaction> = transactions

    override suspend fun loadTransactions() = Unit

    override suspend fun addTransaction(transaction: WalletTransaction) {
        transactions += transaction
    }

    override suspend fun updateTransactionStatus(id: String, status: TransactionStatus) {
        val index = transactions.indexOfFirst { it.id == id }
        if (index >= 0) transactions[index] = transactions[index].copy(status = status)
    }

    override suspend fun createMintQuote(amount: Long?, method: PaymentMethodKind): MintQuoteInfo = MintQuoteInfo(
        id = "quote1",
        request = "lnbc1example",
        amount = amount,
        paymentMethod = method,
        state = MintQuoteState.Unpaid,
        expiryEpochSeconds = null,
        mintUrl = "https://mint.example",
    )

    override suspend fun checkMintQuote(id: String): MintQuoteInfo = createMintQuote(21, PaymentMethodKind.Bolt11).copy(
        id = id,
        state = MintQuoteState.Paid,
    )

    override fun subscribeToMintQuote(quoteId: String, paymentMethod: PaymentMethodKind): Flow<MintQuoteInfo> = flowOf(
        MintQuoteInfo(
            id = quoteId,
            request = "lnbc1example",
            amount = 21,
            paymentMethod = paymentMethod,
            state = MintQuoteState.Paid,
            expiryEpochSeconds = null,
            mintUrl = "https://mint.example",
        ),
    )

    override suspend fun mintTokens(quoteId: String): Long = 21

    override suspend fun createMeltQuote(request: String): MeltQuoteInfo = meltQuote(request, PaymentMethodKind.Bolt11)

    override suspend fun createBolt11MeltQuote(invoice: String): MeltQuoteInfo = meltQuote(invoice, PaymentMethodKind.Bolt11)

    override suspend fun createOnchainMeltQuote(address: String, amount: Long): MeltQuoteInfo = meltQuote(address, PaymentMethodKind.Onchain, amount)

    override suspend fun meltTokens(quoteId: String): MeltPaymentResult = MeltPaymentResult(
        preimage = "preimage",
        amount = 21,
        feePaid = 1,
        mintUrl = "https://mint.example",
        paymentMethod = PaymentMethodKind.Bolt11,
        request = "lnbc1example",
    )

    private fun meltQuote(
        request: String,
        method: PaymentMethodKind,
        amount: Long = 21,
    ): MeltQuoteInfo = MeltQuoteInfo(
        id = "melt1",
        mintUrl = "https://mint.example",
        amount = amount,
        feeReserve = 1,
        paymentMethod = method,
        state = MeltQuoteState.Unpaid,
        expiryEpochSeconds = null,
        request = request,
    )
}
