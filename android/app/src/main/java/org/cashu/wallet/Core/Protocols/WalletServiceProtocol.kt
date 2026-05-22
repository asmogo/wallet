package org.cashu.wallet.Core.Protocols

import kotlinx.coroutines.flow.Flow
import org.cashu.wallet.Models.MeltPaymentResult
import org.cashu.wallet.Models.MeltQuoteInfo
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Models.MintQuoteInfo
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashu.wallet.Models.RestoreMintResult
import org.cashu.wallet.Models.SendTokenResult
import org.cashu.wallet.Models.TokenInfo
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.WalletTransaction

interface WalletServiceProtocol {
    suspend fun initialize()
    suspend fun createNewWallet()
    suspend fun restoreWallet(mnemonic: String)
    suspend fun deleteWallet()
    suspend fun addMint(url: String)
    suspend fun removeMint(mint: MintInfo)
    suspend fun setActiveMint(mint: MintInfo)
    suspend fun restoreFromMint(url: String): RestoreMintResult
    suspend fun createMintQuote(amount: Long?, method: PaymentMethodKind): MintQuoteInfo
    suspend fun mintTokens(quoteId: String): Long
    suspend fun createMeltQuote(request: String, amountSats: Long? = null, preferredMintURL: String? = null): MeltQuoteInfo
    suspend fun meltTokens(quoteId: String, mintUrl: String? = null): MeltPaymentResult
    suspend fun sendTokens(amount: Long, memo: String?, p2pkPubkey: String?, mintUrl: String?): SendTokenResult
    suspend fun receiveTokens(tokenString: String): Long
}

interface MintServiceProtocol {
    suspend fun mints(): List<MintInfo>
    suspend fun activeMint(): MintInfo?
    suspend fun addMint(url: String): MintInfo
    suspend fun removeMint(url: String)
    suspend fun setActiveMint(mint: MintInfo)
    suspend fun refreshMintInfo(mint: MintInfo): MintInfo
}

interface TokenServiceProtocol {
    suspend fun sendTokens(amount: Long, memo: String? = null): SendTokenResult
    suspend fun receiveToken(tokenString: String): Long
    fun parseToken(tokenString: String): TokenInfo
    suspend fun checkTokenSpent(tokenString: String): Boolean
}

interface TransactionServiceProtocol {
    suspend fun transactions(): List<WalletTransaction>
    suspend fun loadTransactions()
    suspend fun addTransaction(transaction: WalletTransaction)
    suspend fun updateTransactionStatus(id: String, status: TransactionStatus)
}

interface QuoteServiceProtocol {
    suspend fun createMintQuote(amount: Long?, method: PaymentMethodKind): MintQuoteInfo
    suspend fun checkMintQuote(id: String): MintQuoteInfo
    fun subscribeToMintQuote(quoteId: String, paymentMethod: PaymentMethodKind): Flow<MintQuoteInfo>
    suspend fun mintTokens(quoteId: String): Long
    suspend fun createMeltQuote(request: String): MeltQuoteInfo
    suspend fun createBolt11MeltQuote(invoice: String): MeltQuoteInfo
    suspend fun createOnchainMeltQuote(address: String, amount: Long): MeltQuoteInfo
    suspend fun meltTokens(quoteId: String): MeltPaymentResult
}
