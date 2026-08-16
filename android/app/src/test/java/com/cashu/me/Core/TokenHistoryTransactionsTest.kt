package com.cashu.me.Core

import com.cashu.me.Models.PendingReceiveToken
import com.cashu.me.Models.TransactionKind
import com.cashu.me.Models.TransactionStatus
import com.cashu.me.Models.TransactionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TokenHistoryTransactionsTest {
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
        assertEquals(TransactionKind.Ecash, row.kind)
        assertEquals(TransactionStatus.Pending, row.status)
        assertEquals("Not claimed yet", row.statusNote)
        assertEquals("cashu-receive", row.token)
        assertEquals(0L, row.fee)
        assertEquals("eur", row.unit)
        assertEquals("Coffee from Alice", row.memo)
        assertTrue(row.isPendingReceiveToken)
    }

    @Test
    fun pendingReceiveRowsKeepCashuRequestAttribution() {
        val rows = pendingReceiveTokenTransactions(
            listOf(
                PendingReceiveToken(
                    tokenId = "receive",
                    token = "cashu-receive",
                    amount = 21,
                    dateEpochMillis = 200,
                    mintUrl = MintUrl,
                    cashuRequestId = "request-1",
                ),
            ),
        )

        assertEquals("request-1", rows.single().cashuRequestId)
    }

    @Test
    fun pendingReceiveRowsCarryNoSagaId() {
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

        assertNull(rows.single().sagaId)
    }

    private companion object {
        const val MintUrl = "https://mint.example.com"
    }
}
