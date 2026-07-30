package com.cashu.me.Core.CDK

import kotlinx.coroutines.flow.Flow
import org.cashudevkit.PendingMelt
import com.cashu.me.Core.NPCQuote
import com.cashu.me.Models.MeltPaymentResult
import com.cashu.me.Models.MeltQuoteInfo
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.Models.PaymentMethodKind
import com.cashu.me.Models.RestoreMintResult
import com.cashu.me.Models.SendTokenResult
import com.cashu.me.Models.WalletTransaction

interface CdkWalletGateway {
    suspend fun initializeLogging(level: String = "info")
    suspend fun generateMnemonic(): String
    suspend fun mnemonicEntropy(mnemonic: String): ByteArray
    suspend fun validateMnemonic(mnemonic: String): Boolean
    suspend fun openWalletRepository(mnemonic: String, databasePath: String)
    suspend fun closeWalletRepository()

    /** Whether the repository currently tracks any mint wallets. */
    suspend fun hasWallets(): Boolean

    /** NUT-27: publish the encrypted mint-list backup for the open seed to the given relays. */
    suspend fun backupMints(relays: List<String>, client: String)

    /** NUT-27: fetch the newest mint-list backup for the open seed; returns the backed-up mint URLs. */
    suspend fun fetchMintBackup(relays: List<String>, timeoutSecs: ULong): List<String>
    suspend fun ensureWallet(mintUrl: String, unit: String = "sat")
    suspend fun removeWallet(mintUrl: String, unit: String = "sat")
    suspend fun fetchMintInfo(mintUrl: String): MintInfo?
    suspend fun restoreMint(mintUrl: String): RestoreMintResult
    suspend fun totalBalance(mintUrl: String): Long

    /** Balance of the (mint, unit) wallet, registering the unit wallet if needed. */
    suspend fun unitBalance(mintUrl: String, unit: String): Long

    /**
     * Balance of the (mint, unit) wallet WITHOUT creating it — null when the
     * wallet was never registered. Used by refreshBalance so advertising a unit
     * never registers keysets/counters the user hasn't touched.
     */
    suspend fun unitBalanceIfExists(mintUrl: String, unit: String): Long?
    suspend fun createMintQuote(amount: Long?, method: PaymentMethodKind, mintUrl: String, unit: String = "sat"): MintQuoteInfo
    suspend fun checkMintQuote(quoteId: String): MintQuoteInfo
    fun subscribeToMintQuote(quoteId: String): Flow<MintQuoteInfo>
    suspend fun listUnissuedMintQuotes(): List<MintQuoteInfo>
    suspend fun mintTokens(quoteId: String): Long
    suspend fun mintNPCQuote(quote: NPCQuote, p2pkPubkey: String?): Long
    suspend fun createMeltQuote(request: String, amountSats: Long? = null, preferredMintURL: String? = null): MeltQuoteInfo
    suspend fun listMeltQuotes(): List<MeltQuoteInfo>
    suspend fun meltTokens(quoteId: String, mintUrl: String? = null): MeltConfirmation

    /** Re-check a melt quote against the mint (NUT-05 async settlement follow-up). */
    suspend fun checkMeltQuoteStatus(quoteId: String, mintUrl: String? = null): MeltQuoteInfo

    /**
     * Ask CDK to complete or compensate interrupted wallet sagas for a mint
     * (e.g. a melt the process never saw the outcome of). iOS startup
     * maintenance parity.
     */
    suspend fun recoverIncompleteSagas(mintUrl: String): SagaRecoveryReport
    suspend fun sendEcashToken(amount: Long, memo: String?, p2pkPubkey: String?, mintUrl: String, unit: String = "sat", p2pkSigningKeys: List<String> = emptyList()): SendTokenResult
    suspend fun receiveEcashToken(tokenString: String, p2pkSigningKeys: List<String> = emptyList()): Long
    suspend fun receiveNfcEcashToken(
        tokenString: String,
        p2pkSigningKeys: List<String> = emptyList(),
    ): NfcReceiveReceipt
    suspend fun settleForeignNfcToken(tokenString: String, settlementMintUrl: String): ForeignNfcSettlement
    suspend fun calculateReceiveFee(tokenString: String): Long

    /**
     * Exact input fee for paying a Cashu Request from [mintUrl].
     *
     * The preview must use the same `includeFee = true` coin selection as
     * `payCashuPaymentRequest`, then release any prepared proofs.
     */
    suspend fun estimateCashuPaymentRequestFee(amountSats: Long, mintUrl: String): Long
    suspend fun checkTokenSpendable(token: String, mintUrl: String): Boolean
    suspend fun listTransactions(unitsByMint: Map<String, List<String>>): List<WalletTransaction>
    suspend fun payCashuPaymentRequest(encoded: String, customAmountSats: Long?, preferredMintURL: String?)
}

data class ForeignNfcSettlement(
    val amountReceived: Long,
    val transactionId: String,
    val feePaid: Long,
    val sourceMintUrl: String,
    val settlementMintUrl: String,
)

/**
 * Outcome of confirming a melt (iOS LightningService.MeltConfirmation parity).
 * Settled synchronously for most Lightning payments; carries a `PendingMelt`
 * handle when the mint accepted asynchronous (NUT-05) settlement, which
 * on-chain melts typically do. The handle's `wait()` completes when the mint
 * reaches a terminal state; it dies with the process, so WalletManager also
 * persists the quote and re-checks it via `syncPendingMeltQuotes()`.
 */
data class MeltConfirmation(
    val result: MeltPaymentResult,
    val pendingMelt: PendingMelt?,
)

/** Counts from CDK's `recoverIncompleteSagas()` for one mint. */
data class SagaRecoveryReport(
    val recovered: Long,
    val compensated: Long,
    val skipped: Long,
    val failed: Long,
) {
    val hasActivity: Boolean get() = recovered > 0 || compensated > 0 || skipped > 0 || failed > 0
}

data class NfcReceiveReceipt(
    val amountReceived: Long,
    val transactionId: String,
)

class CdkGatewayUnavailable(message: String) : IllegalStateException(message)
