package com.cashu.me.Core

import com.cashu.me.Core.CDK.CdkWalletGateway
import kotlinx.coroutines.CancellationException

internal data class MintQuoteSyncResult(
    val minted: Boolean,
    val receivedAmount: Long? = null,
    val unit: String = "sat",
)

internal class WalletMintQuoteSyncService(
    private val gateway: CdkWalletGateway,
    private val walletStore: WalletStore,
) {
    private val mintQuoteSyncsInFlight = mutableSetOf<String>()

    /**
     * Check one quote with its mint and mint it when a paid amount is still
     * outstanding. CDK's NUT-04 `amountPaid`/`amountIssued` counters make
     * this correct for reusable BOLT12 offers too: fully-issued offers mint 0.
     */
    suspend fun syncPendingMintQuote(quoteId: String): MintQuoteSyncResult {
        if (!mintQuoteSyncsInFlight.add(quoteId)) return MintQuoteSyncResult(minted = false)
        return try {
            val updatedQuote = try {
                gateway.checkMintQuote(quoteId).also { rememberMintQuoteTimestamp(it.id) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (!isMissingQuoteError(error)) {
                    AppLogger.wallet.error("Failed to refresh pending quote $quoteId", error)
                }
                return MintQuoteSyncResult(minted = false)
            }

            if (updatedQuote.amountPaid <= updatedQuote.amountIssued) {
                return MintQuoteSyncResult(minted = false)
            }

            val minted = try {
                gateway.mintTokens(quoteId)
                true
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                when {
                    isAlreadyIssuedMintError(error) -> true
                    else -> {
                        AppLogger.wallet.error("Failed to mint pending quote $quoteId", error)
                        false
                    }
                }
            }

            MintQuoteSyncResult(
                minted = minted,
                receivedAmount = (updatedQuote.amountPaid - updatedQuote.amountIssued).takeIf { minted && it > 0 },
                unit = updatedQuote.unit,
            )
        } finally {
            mintQuoteSyncsInFlight.remove(quoteId)
        }
    }

    fun rememberMintQuoteTimestamp(quoteId: String) {
        val current = walletStore.loadMintQuoteTimestamps()
        if (quoteId !in current) {
            walletStore.saveMintQuoteTimestamps(current + (quoteId to System.currentTimeMillis()))
        }
    }

    fun isAlreadyIssuedMintError(error: Throwable): Boolean {
        val message = "${error.message.orEmpty()} ${error}".lowercase()
        if (
            message.contains("already being minted") ||
            message.contains("not issued") ||
            message.contains("not yet") ||
            message.contains("unissued")
        ) {
            return false
        }
        return message.contains("already issued") ||
            message.contains("already minted") ||
            message.contains("quote is issued") ||
            message.contains("state=issued") ||
            message.contains("tokens already issued")
    }

    private fun isMissingQuoteError(error: Throwable): Boolean {
        val message = "${error.message.orEmpty()} ${error}".lowercase()
        return message.contains("not found") ||
            message.contains("no stored mint quote") ||
            message.contains("missing quote")
    }
}
