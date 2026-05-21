package org.cashu.wallet.Core.Protocols

import org.cashu.wallet.Models.MeltPaymentResult
import org.cashu.wallet.Models.MeltQuoteInfo
import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Models.MintQuoteInfo
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashu.wallet.Models.RestoreMintResult
import org.cashu.wallet.Models.SendTokenResult

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
