package com.cashu.me.Core.CDK

import java.net.URI
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

    /**
     * Atomically inspects the native repository and removes [mintUrl] only when
     * it has at most one registered unit. Returns false when no native wallet
     * existed and throws [MultiUnitWalletRemovalException] before changing the
     * repository when multiple units are registered.
     */
    suspend fun removeWalletIfSingleUnit(mintUrl: String): Boolean
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

    /** Last durable local quote snapshot, without contacting the mint. */
    suspend fun storedMintQuote(quoteId: String): MintQuoteInfo? = null

    /** Push updates may trigger CDK saga recovery, so callers can defer the
     * network refresh while their persisted retry deadline is in the future. */
    fun subscribeToMintQuote(quoteId: String, mayRefresh: () -> Boolean = { true }): Flow<MintQuoteInfo>
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

    /** Active sat keyset input fee in parts per thousand, or null when unavailable. */
    suspend fun activeMintInputFeePpk(mintUrl: String): Long?

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

    /**
     * CDK 0.18 send lifecycle: operation ids of outgoing sends whose token is
     * still unclaimed (their transactions read as Pending).
     */
    suspend fun listPendingSendOperationIds(mintUrl: String, unit: String = "sat"): List<String>

    /**
     * Ask the mint whether a pending send's token was claimed; CDK flips its
     * transaction to Completed when it was. Returns the claim state.
     */
    suspend fun checkPendingSendClaimed(mintUrl: String, operationId: String, unit: String = "sat"): Boolean

    /**
     * Revoke an unclaimed send: CDK swaps the proofs back and marks the
     * transaction Failed. Returns the recovered amount in [unit] base units.
     */
    suspend fun revokePendingSend(mintUrl: String, operationId: String, unit: String = "sat"): Long

    /**
     * CDK 0.18: refresh every unissued mint quote of one wallet against its
     * mint and mint the outstanding (paid, not yet issued) amounts — including
     /// reusable BOLT12 offers. Returns the total newly minted in [unit] base units.
     */
    suspend fun mintUnissuedQuotes(mintUrl: String, unit: String = "sat"): Long

    /** Extract the encoded token a send saga persists until the token is
     * claimed; null for non-send or already-finalized operations. */
    suspend fun pendingSendTokenFromSaga(operationId: String): String?
}

class MultiUnitWalletRemovalException(
    val registeredUnits: List<String>,
) : IllegalStateException(
    "This mint uses multiple currency units and cannot be removed safely yet. Keep it connected and try again after updating the app.",
)

internal fun normalizedRegisteredWalletUnits(units: List<String>): List<String> =
    units
        .map { it.trim().lowercase() }
        .filter(String::isNotEmpty)
        .distinct()

internal fun mintRemovalUrlsMatch(lhs: String, rhs: String): Boolean {
    fun identity(raw: String): List<Any?>? = runCatching {
        val uri = URI(raw.trim())
        val scheme = uri.scheme?.lowercase() ?: return@runCatching null
        val authority = uri.rawAuthority?.lowercase() ?: return@runCatching null
        var path = uri.rawPath.orEmpty()
        while (path.length > 1 && path.endsWith('/')) path = path.dropLast(1)
        if (path == "/") path = ""
        listOf(scheme, authority, path, uri.rawQuery, uri.rawFragment)
    }.getOrNull()

    val left = identity(lhs) ?: return lhs.trim() == rhs.trim()
    val right = identity(rhs) ?: return false
    return left == right
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
 * Lightning melts settle synchronously in the common case — an async-accepted
 * (NUT-05) lightning melt is awaited in-lane via the handle's `wait()` for a
 * bounded window before the gateway gives up on a terminal answer. A
 * `PendingMelt` handle survives here only for on-chain melts (minutes-scale by
 * nature) and lightning waits that outlived the cap; the manager re-arms
 * `wait()` on it in the background. The handle dies with the process, after
 * which CDK's durable saga (surfaced as a Pending transaction) is the
 * reconciliation path.
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
