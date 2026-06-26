package org.cashu.wallet.Core

import org.cashu.wallet.Core.CDK.CdkWalletGateway
import org.cashu.wallet.Models.ClaimedToken
import org.cashu.wallet.Models.MeltPaymentResult
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashu.wallet.Models.PendingReceiveToken
import org.cashu.wallet.Models.PendingToken
import org.cashu.wallet.Models.TransactionKind
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.TransactionType
import org.cashu.wallet.Models.WalletTransaction

internal data class WalletTransactionLoadResult(
    val transactions: List<WalletTransaction>,
    val pendingTokens: List<PendingToken>,
    val pendingReceiveTokens: List<PendingReceiveToken>,
    val claimedTokens: List<ClaimedToken>,
)

internal data class TokenHistoryMutation(
    val pendingTokens: List<PendingToken>,
    val claimedTokens: List<ClaimedToken>,
)

internal class WalletTransactionLoader(
    private val walletStore: WalletStore,
    private val gateway: CdkWalletGateway,
) {
    suspend fun load(mintUrls: List<String>): WalletTransactionLoadResult {
        val trackedMintUrls = mintUrls.toSet()
        val preimages = walletStore.loadPaymentPreimages()
        val meltFees = walletStore.loadMeltQuoteFees()
        val pendingTokens = walletStore.loadPendingTokens()
        val pendingReceiveTokens = walletStore.loadPendingReceiveTokens()
        val claimedTokens = walletStore.loadClaimedTokens()
        val remote = runCatching { gateway.listTransactions(mintUrls) }.getOrDefault(emptyList())
            .map { it.withStoredMeltMetadata(preimages, meltFees) }
        val completedQuoteIds = remote.mapNotNull { it.quoteId }.toSet()
        val mintQuoteTimestamps = walletStore.loadMintQuoteTimestamps().toMutableMap()
        val pendingQuoteTransactions = observePendingOnchainMintQuotes(
            runCatching { gateway.listUnissuedMintQuotes() }
                .getOrDefault(emptyList())
                .let { quotes ->
                    pendingMintQuoteTransactions(
                        quotes = quotes,
                        trackedMintUrls = trackedMintUrls,
                        completedQuoteIds = completedQuoteIds,
                        timestamps = mintQuoteTimestamps,
                        nowEpochMillis = System.currentTimeMillis(),
                    )
                }
                .map { it.withStoredMeltMetadata(preimages, meltFees) },
        )
        val storedMeltTransactions = runCatching { gateway.listMeltQuotes() }
            .getOrDefault(emptyList())
            .let { quotes ->
                storedMeltQuoteTransactions(
                    quotes = quotes,
                    trackedMintUrls = trackedMintUrls,
                    completedQuoteIds = completedQuoteIds,
                    timestamps = mintQuoteTimestamps,
                    nowEpochMillis = System.currentTimeMillis(),
                    preimages = preimages,
                    fees = meltFees,
                )
            }
        val tokenTransactions = pendingSentTokenTransactions(pendingTokens) +
            pendingReceiveTokenTransactions(pendingReceiveTokens) +
            claimedTokenTransactions(claimedTokens)
        val cached = walletStore.loadTransactions()
            .filterNot { it.isPendingToken }
            .map { it.withStoredMeltMetadata(preimages, meltFees) }
        val merged = (remote + pendingQuoteTransactions + storedMeltTransactions + tokenTransactions + cached)
            .distinctBy { "${it.mintUrl.orEmpty()}|${it.quoteId ?: it.id}" }
            .sortedByDescending { it.dateEpochMillis }
        walletStore.saveTransactions(merged)
        walletStore.saveMintQuoteTimestamps(pruneMintQuoteTimestamps(merged, mintQuoteTimestamps))
        return WalletTransactionLoadResult(
            transactions = merged,
            pendingTokens = pendingTokens,
            pendingReceiveTokens = pendingReceiveTokens,
            claimedTokens = claimedTokens,
        )
    }

    fun markPendingTokenClaimed(pendingToken: PendingToken): TokenHistoryMutation {
        val pending = walletStore.loadPendingTokens().filterNot { it.tokenId == pendingToken.tokenId }
        val claimedToken = ClaimedToken(
            tokenId = pendingToken.tokenId,
            token = pendingToken.token,
            amount = pendingToken.amount,
            fee = pendingToken.fee,
            dateEpochMillis = pendingToken.dateEpochMillis,
            mintUrl = pendingToken.mintUrl,
            memo = pendingToken.memo,
            claimedDateEpochMillis = System.currentTimeMillis(),
        )
        val claimed = walletStore.loadClaimedTokens()
            .filterNot { it.tokenId == pendingToken.tokenId } + claimedToken
        walletStore.savePendingTokens(pending)
        walletStore.saveClaimedTokens(claimed)
        return TokenHistoryMutation(pendingTokens = pending, claimedTokens = claimed)
    }

    fun saveMeltPaymentMetadata(quoteId: String, result: MeltPaymentResult) {
        result.preimage?.let { preimage ->
            walletStore.savePaymentPreimages(walletStore.loadPaymentPreimages() + (quoteId to preimage))
        }
        walletStore.saveMeltQuoteFees(walletStore.loadMeltQuoteFees() + (quoteId to result.feePaid))

        val current = walletStore.loadTransactions()
        val existing = current.firstOrNull { it.quoteId == quoteId || it.id == quoteId }
        val transaction = WalletTransaction(
            id = existing?.id ?: quoteId,
            amount = result.amount,
            type = TransactionType.Outgoing,
            kind = when (result.paymentMethod) {
                PaymentMethodKind.Onchain -> TransactionKind.Onchain
                else -> TransactionKind.Lightning
            },
            dateEpochMillis = existing?.dateEpochMillis ?: System.currentTimeMillis(),
            memo = existing?.memo,
            status = TransactionStatus.Completed,
            mintUrl = result.mintUrl,
            preimage = result.preimage ?: existing?.preimage,
            invoice = result.request ?: existing?.invoice,
            fee = result.feePaid,
            quoteId = quoteId,
        )
        walletStore.saveTransactions(
            listOf(transaction) + current.filterNot { it.id == transaction.id || it.quoteId == quoteId },
        )
    }

    private suspend fun observePendingOnchainMintQuotes(
        transactions: List<WalletTransaction>,
    ): List<WalletTransaction> =
        transactions.map { transaction ->
            if (
                transaction.type != TransactionType.Incoming ||
                transaction.kind != TransactionKind.Onchain ||
                transaction.invoice == null
            ) {
                return@map transaction
            }

            val observation = OnchainExplorer.observePayment(
                address = transaction.invoice,
                mintUrl = transaction.mintUrl,
                expectedAmount = transaction.amount,
                createdAfterEpochMillis = transaction.dateEpochMillis,
            )

            if (observation != null) {
                val key = transaction.quoteId ?: transaction.id
                val currentPreimages = walletStore.loadPaymentPreimages()
                if (currentPreimages[key] != observation.txid) {
                    walletStore.savePaymentPreimages(currentPreimages + (key to observation.txid))
                }
                transaction.copy(
                    preimage = observation.txid,
                    statusNote = observation.statusText,
                )
            } else if (transaction.preimage != null) {
                transaction.copy(statusNote = transaction.statusNote ?: "Payment detected on-chain")
            } else {
                transaction
            }
        }
}

internal fun WalletTransaction.withStoredMeltMetadata(
    preimages: Map<String, String>,
    meltFees: Map<String, Long>,
): WalletTransaction {
    val key = quoteId ?: id
    return copy(
        preimage = preimage ?: preimages[key],
        fee = meltFees[key] ?: fee,
    )
}
