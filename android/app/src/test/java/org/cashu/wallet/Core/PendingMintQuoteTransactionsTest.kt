package org.cashu.wallet.Core

import org.cashu.wallet.Models.MintQuoteInfo
import org.cashu.wallet.Models.MintQuoteState
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashu.wallet.Models.TransactionKind
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.TransactionType
import org.cashu.wallet.Models.WalletTransaction
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PendingMintQuoteTransactionsTest {
    @Test
    fun buildsPendingLightningRowsWithStableTimestamp() {
        val timestamps = mutableMapOf<String, Long>()

        val rows = pendingMintQuoteTransactions(
            quotes = listOf(quote(id = "quote-1", amount = 21)),
            trackedMintUrls = setOf(MintUrl),
            completedQuoteIds = emptySet(),
            timestamps = timestamps,
            nowEpochMillis = 1_700_000_000_000,
        )

        assertEquals(1, rows.size)
        val row = rows.single()
        assertEquals("quote-1", row.id)
        assertEquals(21L, row.amount)
        assertEquals(TransactionType.Incoming, row.type)
        assertEquals(TransactionKind.Lightning, row.kind)
        assertEquals(TransactionStatus.Pending, row.status)
        assertEquals("lnbc1quote", row.invoice)
        assertEquals(1_700_000_000_000L, row.dateEpochMillis)
        assertEquals(1_700_000_000_000L, timestamps["quote-1"])

        val secondRows = pendingMintQuoteTransactions(
            quotes = listOf(quote(id = "quote-1", amount = 21)),
            trackedMintUrls = setOf(MintUrl),
            completedQuoteIds = emptySet(),
            timestamps = timestamps,
            nowEpochMillis = 1_800_000_000_000,
        )
        assertEquals(1_700_000_000_000L, secondRows.single().dateEpochMillis)
    }

    @Test
    fun marksIssuedQuotesCompletedAndUsesPaidAmountFallback() {
        val rows = pendingMintQuoteTransactions(
            quotes = listOf(
                quote(
                    amount = null,
                    state = MintQuoteState.Issued,
                    amountPaid = 42,
                    amountIssued = 42,
                ),
            ),
            trackedMintUrls = setOf(MintUrl),
            completedQuoteIds = emptySet(),
            timestamps = mutableMapOf(),
            nowEpochMillis = 1,
        )

        assertEquals(42L, rows.single().amount)
        assertEquals(TransactionStatus.Completed, rows.single().status)
    }

    @Test
    fun suppressesReusableBolt12QuotesAlreadySurfacedByCdkTransactions() {
        val rows = pendingMintQuoteTransactions(
            quotes = listOf(
                quote(
                    id = "bolt12-quote",
                    method = PaymentMethodKind.Bolt12,
                    amountPaid = 30,
                    amountIssued = 30,
                ),
            ),
            trackedMintUrls = setOf(MintUrl),
            completedQuoteIds = setOf("bolt12-quote"),
            timestamps = mutableMapOf(),
            nowEpochMillis = 1,
        )

        assertTrue(rows.isEmpty())
    }

    @Test
    fun detectsPendingMintQuoteRows() {
        assertTrue(
            isPendingMintQuoteTransaction(
                transaction(kind = TransactionKind.Onchain, status = TransactionStatus.Pending, invoice = "bc1q"),
            ),
        )
        assertFalse(
            isPendingMintQuoteTransaction(
                transaction(kind = TransactionKind.Ecash, status = TransactionStatus.Pending, invoice = "cashu"),
            ),
        )
        assertFalse(
            isPendingMintQuoteTransaction(
                transaction(kind = TransactionKind.Lightning, status = TransactionStatus.Completed, invoice = "lnbc"),
            ),
        )
    }

    @Test
    fun prunesTimestampsForMissingQuoteRows() {
        val kept = transaction(
            id = "kept",
            quoteId = "quote-kept",
            kind = TransactionKind.Lightning,
            status = TransactionStatus.Pending,
            invoice = "lnbc",
        )
        val timestamps = mapOf("quote-kept" to 10L, "old" to 20L)

        assertEquals(mapOf("quote-kept" to 10L), pruneMintQuoteTimestamps(listOf(kept), timestamps))
    }

    private fun quote(
        id: String = "quote",
        amount: Long? = 10,
        method: PaymentMethodKind = PaymentMethodKind.Bolt11,
        state: MintQuoteState = MintQuoteState.Unpaid,
        amountPaid: Long = 0,
        amountIssued: Long = 0,
    ) = MintQuoteInfo(
        id = id,
        request = "lnbc1quote",
        amount = amount,
        paymentMethod = method,
        state = state,
        expiryEpochSeconds = null,
        mintUrl = MintUrl,
        amountPaid = amountPaid,
        amountIssued = amountIssued,
    )

    private fun transaction(
        id: String = "tx",
        quoteId: String? = null,
        kind: TransactionKind,
        status: TransactionStatus,
        invoice: String?,
    ) = WalletTransaction(
        id = id,
        amount = 1,
        type = TransactionType.Incoming,
        kind = kind,
        dateEpochMillis = 1,
        status = status,
        invoice = invoice,
        quoteId = quoteId,
    )

    private companion object {
        const val MintUrl = "https://mint.example.com"
    }
}
