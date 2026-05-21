package org.cashu.wallet.Core

import org.cashu.wallet.Models.ClaimedToken
import org.cashu.wallet.Models.PendingReceiveToken
import org.cashu.wallet.Models.PendingToken
import org.cashu.wallet.Models.TransactionStatus
import org.cashu.wallet.Models.TransactionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TokenHistoryTransactionsTest {
    @Test
    fun mapsPendingSentTokensToOutgoingPendingRows() {
        val rows = pendingSentTokenTransactions(
            listOf(
                PendingToken(
                    tokenId = "sent",
                    token = "cashu-sent",
                    amount = 10,
                    fee = 1,
                    dateEpochMillis = 100,
                    mintUrl = MintUrl,
                    memo = "memo",
                ),
            ),
        )

        val row = rows.single()
        assertEquals("sent", row.id)
        assertEquals(TransactionType.Outgoing, row.type)
        assertEquals(TransactionStatus.Pending, row.status)
        assertEquals("cashu-sent", row.token)
        assertEquals(1L, row.fee)
        assertEquals("memo", row.memo)
        assertTrue(row.isPendingToken)
    }

    @Test
    fun mapsPendingReceiveTokensToIncomingPendingRows() {
        val rows = pendingReceiveTokenTransactions(
            listOf(
                PendingReceiveToken(
                    tokenId = "receive",
                    token = "cashu-receive",
                    amount = 21,
                    dateEpochMillis = 200,
                    mintUrl = MintUrl,
                ),
            ),
        )

        val row = rows.single()
        assertEquals("receive", row.id)
        assertEquals(TransactionType.Incoming, row.type)
        assertEquals(TransactionStatus.Pending, row.status)
        assertEquals("cashu-receive", row.token)
        assertEquals(0L, row.fee)
        assertTrue(row.isPendingToken)
    }

    @Test
    fun mapsClaimedTokensToOutgoingCompletedRows() {
        val rows = claimedTokenTransactions(
            listOf(
                ClaimedToken(
                    tokenId = "claimed",
                    token = "cashu-claimed",
                    amount = 34,
                    fee = 2,
                    dateEpochMillis = 300,
                    mintUrl = MintUrl,
                    memo = "claimed memo",
                    claimedDateEpochMillis = 400,
                ),
            ),
        )

        val row = rows.single()
        assertEquals("claimed", row.id)
        assertEquals(TransactionType.Outgoing, row.type)
        assertEquals(TransactionStatus.Completed, row.status)
        assertEquals("cashu-claimed", row.token)
        assertEquals(2L, row.fee)
        assertEquals("claimed memo", row.memo)
    }

    private companion object {
        const val MintUrl = "https://mint.example.com"
    }
}

