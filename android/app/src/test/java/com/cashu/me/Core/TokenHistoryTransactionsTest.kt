package com.cashu.me.Core

import com.cashu.me.Models.ClaimedToken
import com.cashu.me.Models.PendingReceiveToken
import com.cashu.me.Models.PendingToken
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import com.cashu.me.Models.WalletTransaction
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
                    unit = "usd",
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
        assertEquals("usd", row.unit)
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
                    unit = "eur",
                    memo = "Coffee from Alice",
                ),
            ),
        )

        val row = rows.single()
        assertEquals("receive", row.id)
        assertEquals(TransactionType.Incoming, row.type)
        assertEquals(TransactionStatus.Pending, row.status)
        assertEquals("cashu-receive", row.token)
        assertEquals(0L, row.fee)
        assertEquals("eur", row.unit)
        assertEquals("Coffee from Alice", row.memo)
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
                    unit = "points",
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
        assertEquals("points", row.unit)
    }

    @Test
    fun mergesPendingUsdTokenIntoCdkRowWithoutCreatingSatDuplicate() {
        val pending = PendingToken(
            tokenId = "pending-usd",
            token = "cashu-usd",
            amount = 10,
            fee = 1,
            dateEpochMillis = 100,
            mintUrl = MintUrl,
            unit = "usd",
        )
        val cdkRow = WalletTransaction(
            id = "cdk-usd",
            amount = 10,
            type = TransactionType.Outgoing,
            kind = TransactionKind.Ecash,
            dateEpochMillis = 100,
            status = TransactionStatus.Completed,
            mintUrl = MintUrl,
            unit = "usd",
        )

        val rows = mergeSentTokenTransactions(
            transactions = listOf(cdkRow),
            pendingTokens = listOf(pending),
            claimedTokens = emptyList(),
        )

        val row = rows.single()
        assertEquals("usd", row.unit)
        assertEquals(TransactionStatus.Pending, row.status)
        assertEquals("cashu-usd", row.token)
        assertTrue(row.isPendingToken)
    }

    private companion object {
        const val MintUrl = "https://mint.example.com"
    }
}
