package com.cashu.me.Core

import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
import com.cashu.me.Models.liveDetail
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TransactionDetailLookupTest {
    @Test
    fun prefersExactIdMatch() {
        val open = tx(id = "quote-1", quoteId = "quote-1", status = TransactionStatus.Pending)
        val other = tx(id = "cdk-9", quoteId = "quote-1", status = TransactionStatus.Completed)
        assertEquals(open, listOf(other, open).liveDetail(openId = "quote-1"))
    }

    @Test
    fun fallsBackToQuoteIdWhenPendingRowGone() {
        // The pending row's id was the quote id; after minting, only the CDK
        // transaction (saga-derived id, same quoteId) remains.
        val completed = tx(id = "cdk-9", quoteId = "quote-1", status = TransactionStatus.Completed, date = 200)
        val unrelated = tx(id = "other", quoteId = "other", status = TransactionStatus.Completed, date = 300)
        assertEquals(
            completed,
            listOf(unrelated, completed).liveDetail(openId = "quote-1", openQuoteId = "quote-1"),
        )
    }

    @Test
    fun reusableOfferResolvesToNewestPayment() {
        // Rows are stored newest-first; several payments share one offer's
        // quoteId, so the fallback yields the latest one.
        val newer = tx(id = "cdk-2", quoteId = "offer", status = TransactionStatus.Completed, date = 200)
        val older = tx(id = "cdk-1", quoteId = "offer", status = TransactionStatus.Completed, date = 100)
        assertEquals(
            newer,
            listOf(newer, older).liveDetail(openId = "offer", openQuoteId = "offer"),
        )
    }

    @Test
    fun returnsNullWhenNothingMatches() {
        assertNull(
            listOf(tx(id = "a", quoteId = "a", status = TransactionStatus.Completed))
                .liveDetail(openId = "missing", openQuoteId = "also-missing"),
        )
    }

    private fun tx(
        id: String,
        quoteId: String?,
        status: TransactionStatus,
        date: Long = 0L,
    ) = WalletTransaction(
        id = id,
        amount = 21,
        type = TransactionType.Incoming,
        kind = TransactionKind.Lightning,
        dateEpochMillis = date,
        status = status,
        quoteId = quoteId,
        invoice = "lnbc1",
    )
}
