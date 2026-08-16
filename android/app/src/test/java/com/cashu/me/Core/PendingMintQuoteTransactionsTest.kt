package com.cashu.me.Core

import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.Models.MintQuoteState
import com.cashu.me.Models.PaymentMethodKind
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PendingMintQuoteTransactionsTest {
    @Test
    fun buildsPendingLightningRowsWithStableTimestamp() {
        val timestamps = mutableMapOf<String, Long>()

        val rows = pendingMintQuoteTransactions(
            quotes = listOf(quote(id = "quote-1", amount = 21, unit = "usd")),
            trackedMintUrls = setOf(MintUrl),
            quoteIdsWithTransactions = emptySet(),
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
        assertTrue(row.isUnpaidInvoice)
        assertEquals("lnbc1quote", row.invoice)
        assertEquals("usd", row.unit)
        assertEquals(1_700_000_000_000L, row.dateEpochMillis)
        assertEquals(1_700_000_000_000L, timestamps["quote-1"])

        val secondRows = pendingMintQuoteTransactions(
            quotes = listOf(quote(id = "quote-1", amount = 21, unit = "usd")),
            trackedMintUrls = setOf(MintUrl),
            quoteIdsWithTransactions = emptySet(),
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
            quoteIdsWithTransactions = emptySet(),
            timestamps = mutableMapOf(),
            nowEpochMillis = 1,
        )

        assertEquals(42L, rows.single().amount)
        assertEquals(TransactionStatus.Completed, rows.single().status)
        assertFalse(rows.single().isUnpaidInvoice)
    }

    @Test
    fun expiresUnpaidBolt11InvoicesPastExpiry() {
        val nowMillis = 1_700_000_000_000L
        val nowSeconds = nowMillis / 1000

        fun rowFor(quote: MintQuoteInfo) = pendingMintQuoteTransactions(
            quotes = listOf(quote),
            trackedMintUrls = setOf(MintUrl),
            quoteIdsWithTransactions = emptySet(),
            timestamps = mutableMapOf(),
            nowEpochMillis = nowMillis,
        ).single()

        val expired = rowFor(quote(expiryEpochSeconds = nowSeconds - 1))
        assertEquals(TransactionStatus.Expired, expired.status)
        assertTrue(expired.isUnpaidInvoice)

        val live = rowFor(quote(expiryEpochSeconds = nowSeconds + 60))
        assertEquals(TransactionStatus.Pending, live.status)
        assertTrue(live.isUnpaidInvoice)

        // Paid before expiry stays mintable (NUT-04): Pending, titled as received.
        val paid = rowFor(quote(state = MintQuoteState.Paid, amountPaid = 10, expiryEpochSeconds = nowSeconds - 1))
        assertEquals(TransactionStatus.Pending, paid.status)
        assertFalse(paid.isUnpaidInvoice)

        // No expiry recorded (null or 0 sentinel) means the invoice never expires.
        assertEquals(TransactionStatus.Pending, rowFor(quote(expiryEpochSeconds = null)).status)
        assertEquals(TransactionStatus.Pending, rowFor(quote(expiryEpochSeconds = 0)).status)

        // Only the BOLT11 rail expires; addresses stay fundable.
        val onchain = rowFor(quote(method = PaymentMethodKind.Onchain, expiryEpochSeconds = nowSeconds - 1))
        assertEquals(TransactionStatus.Pending, onchain.status)
        assertFalse(onchain.isUnpaidInvoice)
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
            quoteIdsWithTransactions = setOf("bolt12-quote"),
            timestamps = mutableMapOf(),
            nowEpochMillis = 1,
        )

        assertTrue(rows.isEmpty())
    }

    @Test
    fun suppressesAnyQuoteOnceCdkOwnsATransactionForIt() {
        // An in-flight mint surfaces a Pending CDK transaction carrying the
        // quote id; the quote-backed row would only duplicate it.
        val rows = pendingMintQuoteTransactions(
            quotes = listOf(
                quote(
                    id = "bolt11-quote",
                    method = PaymentMethodKind.Bolt11,
                    state = MintQuoteState.Paid,
                    amountPaid = 21,
                ),
            ),
            trackedMintUrls = setOf(MintUrl),
            quoteIdsWithTransactions = setOf("bolt11-quote"),
            timestamps = mutableMapOf(),
            nowEpochMillis = 1,
        )

        assertTrue(rows.isEmpty())
    }

    @Test
    fun prefersCdkUpdatedAtOverLocalFirstSeenTimestamps() {
        val timestamps = mutableMapOf<String, Long>()

        val rows = pendingMintQuoteTransactions(
            quotes = listOf(
                quote(id = "quote-1", amount = 21).copy(updatedAtEpochSeconds = 1_600_000_000),
            ),
            trackedMintUrls = setOf(MintUrl),
            quoteIdsWithTransactions = emptySet(),
            timestamps = timestamps,
            nowEpochMillis = 1_700_000_000_000,
        )

        assertEquals(1_600_000_000_000L, rows.single().dateEpochMillis)
        // A quote with a CDK timestamp never touches the local fallback map.
        assertTrue(timestamps.isEmpty())
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
        unit: String = "sat",
        expiryEpochSeconds: Long? = null,
    ) = MintQuoteInfo(
        id = id,
        request = "lnbc1quote",
        amount = amount,
        paymentMethod = method,
        state = state,
        expiryEpochSeconds = expiryEpochSeconds,
        mintUrl = MintUrl,
        amountPaid = amountPaid,
        amountIssued = amountIssued,
        unit = unit,
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
