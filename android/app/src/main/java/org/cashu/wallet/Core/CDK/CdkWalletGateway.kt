package org.cashu.wallet.Core.CDK

import kotlinx.coroutines.flow.Flow
import org.cashu.wallet.Core.NPCQuote
import org.cashu.wallet.Models.MeltPaymentResult
import org.cashu.wallet.Models.MeltQuoteInfo
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Models.MintQuoteInfo
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashu.wallet.Models.RestoreMintResult
import org.cashu.wallet.Models.SendTokenResult
import org.cashu.wallet.Models.WalletTransaction

interface CdkWalletGateway {
    suspend fun initializeLogging(level: String = "info")
    suspend fun generateMnemonic(): String
    suspend fun mnemonicEntropy(mnemonic: String): ByteArray
    suspend fun validateMnemonic(mnemonic: String): Boolean
    suspend fun openWalletRepository(mnemonic: String, databasePath: String)
    suspend fun closeWalletRepository()
    suspend fun ensureWallet(mintUrl: String, unit: String = "sat")
    suspend fun removeWallet(mintUrl: String, unit: String = "sat")
    suspend fun fetchMintInfo(mintUrl: String): MintInfo?
    suspend fun restoreMint(mintUrl: String): RestoreMintResult
    suspend fun totalBalance(mintUrl: String): Long
    suspend fun createMintQuote(amount: Long?, method: PaymentMethodKind, mintUrl: String): MintQuoteInfo
    suspend fun checkMintQuote(quoteId: String): MintQuoteInfo
    fun subscribeToMintQuote(quoteId: String): Flow<MintQuoteInfo>
    suspend fun listUnissuedMintQuotes(): List<MintQuoteInfo>
    suspend fun mintTokens(quoteId: String): Long
    suspend fun mintNPCQuote(quote: NPCQuote, p2pkPubkey: String?): Long
    suspend fun createMeltQuote(request: String, amountSats: Long? = null, preferredMintURL: String? = null): MeltQuoteInfo
    suspend fun listMeltQuotes(): List<MeltQuoteInfo>
    suspend fun meltTokens(quoteId: String, mintUrl: String? = null): MeltPaymentResult
    suspend fun sendEcashToken(amount: Long, memo: String?, p2pkPubkey: String?, mintUrl: String): SendTokenResult
    suspend fun receiveEcashToken(tokenString: String, p2pkSigningKeys: List<String> = emptyList()): Long
    suspend fun calculateReceiveFee(tokenString: String): Long
    suspend fun checkTokenSpendable(token: String, mintUrl: String): Boolean
    suspend fun listTransactions(mintUrls: List<String>): List<WalletTransaction>
    suspend fun payCashuPaymentRequest(encoded: String, customAmountSats: Long?, preferredMintURL: String?)
}

class CdkGatewayUnavailable(message: String) : IllegalStateException(message)
