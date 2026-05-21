package org.cashu.wallet.Core

import org.cashu.wallet.Models.MeltQuoteInfo
import org.cashu.wallet.Models.MeltQuoteState
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashu.wallet.Models.TransactionKind
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.TransactionType
import org.cashu.wallet.Models.WalletTransaction
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StoredMeltQuoteTransactionsTest {
    @Test
    fun buildsPendingOutgoingLightningRowsWithStoredMetadata() {
        val timestamps = mutableMapOf<String, Long>()

        val rows = storedMeltQuoteTransactions(
            quotes = listOf(quote(id = "melt-1", state = MeltQuoteState.Pending)),
            trackedMintUrls = setOf(MintUrl),
            completedQuoteIds = emptySet(),
            timestamps = timestamps,
            nowEpochMillis = 1_700_000_000_000,
            preimages = mapOf("melt-1" to "stored-preimage"),
            fees = mapOf("melt-1" to 3),
        )

        val row = rows.single()
        assertEquals("melt-1", row.id)
        assertEquals(TransactionType.Outgoing, row.type)
        assertEquals(TransactionKind.Lightning, row.kind)
        assertEquals(TransactionStatus.Pending, row.status)
        assertEquals("lnbc1invoice", row.invoice)
        assertEquals("stored-preimage", row.preimage)
        assertEquals(3L, row.fee)
        assertEquals(1_700_000_000_000L, row.dateEpochMillis)
        assertEquals(1_700_000_000_000L, timestamps["melt-1"])
    }

    @Test
    fun mapsPaidOnchainQuotesToCompletedRows() {
        val rows = storedMeltQuoteTransactions(
            quotes = listOf(
                quote(
                    method = PaymentMethodKind.Onchain,
                    state = MeltQuoteState.Paid,
                    paymentProof = "txid",
                ),
            ),
            trackedMintUrls = setOf(MintUrl),
            completedQuoteIds = emptySet(),
            timestamps = mutableMapOf(),
            nowEpochMillis = 1,
            preimages = emptyMap(),
            fees = emptyMap(),
        )

        assertEquals(TransactionKind.Onchain, rows.single().kind)
        assertEquals(TransactionStatus.Completed, rows.single().status)
        assertEquals("txid", rows.single().preimage)
        assertEquals(2L, rows.single().fee)
    }

    @Test
    fun skipsUnpaidUnknownAndRemoteCompletedQuotes() {
        val rows = storedMeltQuoteTransactions(
            quotes = listOf(
                quote(id = "unpaid", state = MeltQuoteState.Unpaid),
                quote(id = "unknown", state = MeltQuoteState.Unknown),
                quote(id = "remote", state = MeltQuoteState.Paid),
            ),
            trackedMintUrls = setOf(MintUrl),
            completedQuoteIds = setOf("remote"),
            timestamps = mutableMapOf(),
            nowEpochMillis = 1,
            preimages = emptyMap(),
            fees = emptyMap(),
        )

        assertTrue(rows.isEmpty())
    }

    @Test
    fun timestampPruningKeepsOutgoingQuoteRows() {
        val outgoing = WalletTransaction(
            id = "melt",
            amount = 10,
            type = TransactionType.Outgoing,
            kind = TransactionKind.Lightning,
            dateEpochMillis = 1,
            status = TransactionStatus.Pending,
            invoice = "lnbc1invoice",
            quoteId = "melt-quote",
        )

        assertEquals(
            mapOf("melt-quote" to 10L),
            pruneMintQuoteTimestamps(
                transactions = listOf(outgoing),
                timestamps = mapOf("melt-quote" to 10L, "old" to 20L),
            ),
        )
    }

    private fun quote(
        id: String = "melt",
        method: PaymentMethodKind = PaymentMethodKind.Bolt11,
        state: MeltQuoteState = MeltQuoteState.Paid,
        paymentProof: String? = null,
    ) = MeltQuoteInfo(
        id = id,
        mintUrl = MintUrl,
        amount = 10,
        feeReserve = 2,
        paymentMethod = method,
        state = state,
        expiryEpochSeconds = null,
        request = "lnbc1invoice",
        paymentProof = paymentProof,
    )

    private companion object {
        const val MintUrl = "https://mint.example.com"
    }
}
