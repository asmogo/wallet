package org.cashu.wallet.Core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NPCServiceTest {
    @Test
    fun parsesQuotesFromDataArray() {
        val quotes = NPCService.parseQuotesJson(
            """
            {
              "data": [
                {
                  "id": "quote-1",
                  "amount": 21,
                  "mint": "https://mint.example",
                  "state": "PAID",
                  "locked": true,
                  "created_at": "2026-05-20T10:00:00Z",
                  "paid_at": 1779271800
                }
              ]
            }
            """.trimIndent(),
        )

        assertEquals(1, quotes.size)
        assertEquals("quote-1", quotes.first().id)
        assertEquals(21, quotes.first().amount)
        assertEquals("https://mint.example", quotes.first().mintUrl)
        assertEquals(null, quotes.first().request)
        assertTrue(quotes.first().isPaid)
        assertTrue(quotes.first().locked)
        assertEquals(1779271200L, quotes.first().createdAtEpochSeconds)
        assertEquals(1779271800L, quotes.first().paidAtEpochSeconds)
    }

    @Test
    fun parsesPaidBooleanAsPaidState() {
        val quotes = NPCService.parseQuotesJson(
            """{"data":{"quotes":[{"quote_id":"abc","amount_sats":"42","paid":true}]}}""",
        )

        assertEquals(1, quotes.size)
        assertEquals("abc", quotes.first().id)
        assertEquals(42, quotes.first().amount)
        assertTrue(quotes.first().isPaid)
    }

    @Test
    fun parsesOptionalMintQuoteMetadata() {
        val quotes = NPCService.parseQuotesJson(
            """
            {
              "quotes": [{
                "quote_id": "quote-2",
                "amount_sats": "99",
                "mint_url": "https://mint.example",
                "payment_request": "lnbc1invoice",
                "status": "PAID",
                "expires_at": "2026-05-20T10:30:00Z"
              }]
            }
            """.trimIndent(),
        )

        assertEquals("lnbc1invoice", quotes.first().request)
        assertEquals(1779273000L, quotes.first().expiryEpochSeconds)
    }

    @Test
    fun paidQuotesForProcessingSkipsProcessedAndSortsOldestFirst() {
        val newest = NPCQuote(
            id = "newest",
            amount = 1,
            mintUrl = "https://mint.example",
            state = "PAID",
            locked = false,
            createdAtEpochSeconds = 30,
            paidAtEpochSeconds = 30,
        )
        val oldest = newest.copy(id = "oldest", paidAtEpochSeconds = 10)
        val processed = newest.copy(id = "processed", paidAtEpochSeconds = 1)
        val unpaid = newest.copy(id = "unpaid", state = "UNPAID", paidAtEpochSeconds = 0)

        val quotes = NPCService.paidQuotesForProcessing(
            quotes = listOf(newest, oldest, processed, unpaid),
            processedQuoteIds = setOf("processed"),
        )

        assertEquals(listOf("oldest", "newest"), quotes.map { it.id })
    }
}
