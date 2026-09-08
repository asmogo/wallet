package com.cashu.me.Core

import com.cashu.me.Core.CDK.CdkWalletGateway
import com.cashu.me.Models.MintInfo
import com.cashu.me.Models.PendingReceiveToken
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import com.cashu.me.Models.restoringDescription

internal data class WalletTransactionLoadResult(
    val transactions: List<WalletTransaction>,
    val pendingReceiveTokens: List<PendingReceiveToken>,
)

/**
 * Assembles History from CDK's own transaction store.
 *
 * CDK 0.18 tracks the full transaction lifecycle (pending / completed /
 * failed) with stable saga-derived ids, including in-flight sends, melts, and
 * mints, so this loader is a thin projection: CDK rows + token strings from
 * the txId-keyed token store + synthesized rows for quotes that have no
 * transaction yet (unpaid invoices, paid-not-yet-minted quotes) + incoming
 * ecash held for user approval.
 */
internal class WalletTransactionLoader(
    private val walletStore: WalletStore,
    private val gateway: CdkWalletGateway,
) {
    suspend fun load(
        mints: List<MintInfo>,
        includeRemoteObservations: Boolean = true,
        observingQuoteId: String? = null,
    ): WalletTransactionLoadResult {
        val trackedMintUrls = mints.map { it.url }.toSet()
        val savedTokens = walletStore.loadSavedTokens()
        val pendingReceiveTokens = walletStore.loadPendingReceiveTokens()
        val previous = walletStore.loadTransactions().filter { !it.isPendingReceiveToken }
        // Synthesized invoice rows use the quote id as their row id; CDK rows
        // use transaction ids. Only CDK rows may suppress a fresh quote read.
        val previousAccountTransactions = previous.filter { it.id != it.quoteId }
        val remote = try {
            gateway.storedAccounts().filter { account ->
                mints.any { com.cashu.me.Core.CDK.mintRemovalUrlsMatch(it.url, account.mintUrl) }
            }.flatMap { account ->
                try {
                    gateway.listTransactions(mapOf(account.mintUrl to listOf(account.unit)))
                } catch (error: Exception) {
                    if (error is kotlinx.coroutines.CancellationException) throw error
                    previousAccountTransactions.filter { it.unit == account.unit && com.cashu.me.Core.CDK.mintRemovalUrlsMatch(it.mintUrl.orEmpty(), account.mintUrl) }
                }
            }
        } catch (error: Exception) {
            if (error is kotlinx.coroutines.CancellationException) throw error
            previousAccountTransactions.filter { tx -> mints.any { com.cashu.me.Core.CDK.mintRemovalUrlsMatch(it.url, tx.mintUrl.orEmpty()) } }
        }
        val remoteWithSavedTokens = remote
            .map { transaction ->
                if (transaction.kind == TransactionKind.Ecash && transaction.token == null) {
                    transaction.copy(token = savedTokens[transaction.id])
                } else {
                    transaction
                }
            }
        // A sent token's string survives in the send saga until the token is
        // claimed. Backfill rows that predate the transaction-id-keyed token
        // store (e.g. sends recorded by an older app version) from the saga.
        val remoteWithTokens = remoteWithSavedTokens.map { transaction ->
            if (
                transaction.kind == TransactionKind.Ecash &&
                transaction.type == TransactionType.Outgoing &&
                transaction.status == TransactionStatus.Pending &&
                transaction.token == null &&
                transaction.sagaId != null
            ) {
                val token = runCatching { gateway.pendingSendTokenFromSaga(transaction.sagaId) }
                    .getOrNull()
                if (token != null) {
                    walletStore.saveSavedTokens(savedTokens + (transaction.id to token))
                    transaction.copy(token = token)
                } else {
                    transaction
                }
            } else {
                transaction
            }
        }
        val quoteIdsWithTransactions = remoteWithTokens.mapNotNull { it.quoteId }.toSet()
        val mintQuoteTimestamps = walletStore.loadMintQuoteTimestamps().toMutableMap()
        val quoteRead = runCatching { gateway.listUnissuedMintQuotes() }
        quoteRead.exceptionOrNull()?.let { if (it is kotlinx.coroutines.CancellationException) throw it }
        val unissuedMintQuotes = quoteRead.getOrDefault(emptyList())
        val retainedQuotes = if (quoteRead.isFailure) previous.filter {
            it.id == it.quoteId && it.id !in quoteIdsWithTransactions && it.mintUrl in trackedMintUrls
        } else emptyList()
        val pendingQuotes = pendingMintQuoteTransactions(
            quotes = unissuedMintQuotes,
            trackedMintUrls = trackedMintUrls,
            quoteIdsWithTransactions = quoteIdsWithTransactions,
            timestamps = mintQuoteTimestamps,
            nowEpochMillis = System.currentTimeMillis(),
        )
        val pendingQuoteTransactions = if (includeRemoteObservations) {
            observePendingOnchainMintQuotes(pendingQuotes, observingQuoteId)
        } else {
            pendingQuotes
        }
        val requests = walletStore.loadCashuRequests()
        val receiveTokenTransactions = pendingReceiveTokenTransactions(pendingReceiveTokens)
        // Row id spaces are disjoint by construction (saga-derived tx ids,
        // mint-issued quote ids, random pending-receive ids) and quote-backed
        // rows are skipped once CDK owns a transaction for the quote, so a
        // plain id dedupe is sufficient.
        val merged = (remoteWithTokens + pendingQuoteTransactions + retainedQuotes + receiveTokenTransactions)
            .map { it.restoringDescription(requests) }
            .distinctBy { it.id }
            .sortedByDescending { it.dateEpochMillis }
        walletStore.saveTransactions(merged)
        walletStore.saveMintQuoteTimestamps(pruneMintQuoteTimestamps(merged, mintQuoteTimestamps))
        return WalletTransactionLoadResult(
            transactions = merged,
            pendingReceiveTokens = pendingReceiveTokens,
        )
    }

    private suspend fun observePendingOnchainMintQuotes(
        transactions: List<WalletTransaction>,
        observingQuoteId: String?,
    ): List<WalletTransaction> =
        transactions.map { transaction ->
            if (
                transaction.type != TransactionType.Incoming ||
                (observingQuoteId != null && observingQuoteId != transaction.quoteId) ||
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

/** CDK stores an independent wallet per (mint, unit), including transaction history. */
internal fun transactionUnitsByMint(mints: List<MintInfo>): Map<String, List<String>> =
    mints.associate { mint ->
        val units = buildList {
            add("sat")
            addAll(mint.units)
        }.map(String::trim)
            .filter(String::isNotEmpty)
            .distinctBy(String::lowercase)
        mint.url to units
    }
