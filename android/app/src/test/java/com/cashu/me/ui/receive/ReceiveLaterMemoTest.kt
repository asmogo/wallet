package com.cashu.me.ui.receive

import com.cashu.me.Models.TokenInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReceiveLaterMemoTest {
    @Test
    fun receiveLaterPreservesMemoForHistoryAndLaterClaim() {
        val pending = pendingReceiveTokenFrom(
            TokenReview(
                token = MemoToken,
                info = TokenInfo(
                    amount = 0,
                    mint = "https://mint.minibits.cash",
                    unit = "sat",
                    memo = "Coffee from Alice",
                    proofCount = 0,
                ),
                fee = 0,
                locked = false,
            ),
        )

        assertEquals("Coffee from Alice", pending.memo)
        assertEquals(MemoToken, pending.token)
    }

    @Test
    fun receiveLaterKeepsAbsentMemoAbsent() {
        val pending = pendingReceiveTokenFrom(
            TokenReview(
                token = "cashuAtoken-without-memo",
                info = TokenInfo(
                    amount = 21,
                    mint = "https://mint.example.com",
                    unit = "sat",
                    memo = null,
                    proofCount = 1,
                ),
                fee = 0,
                locked = false,
            ),
        )

        assertNull(pending.memo)
    }

    private companion object {
        const val MemoToken =
            "cashuAeyJ0b2tlbiI6W3sibWludCI6Imh0dHBzOi8vbWludC5taW5pYml0cy5jYXNoIiwicHJvb2ZzIjpbXX1dLCJ1bml0Ijoic2F0IiwibWVtbyI6IkNvZmZlZSBmcm9tIEFsaWNlIn0"
    }
}
