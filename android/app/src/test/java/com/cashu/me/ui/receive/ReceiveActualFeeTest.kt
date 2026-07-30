package com.cashu.me.ui.receive

import com.cashu.me.Models.TokenInfo
import org.junit.Assert.assertEquals
import org.junit.Test

class ReceiveActualFeeTest {
    @Test
    fun `settlement difference replaces preview fee`() {
        val claim = settledTokenClaim(
            review(grossAmount = 100, previewFee = 3),
            creditedAmount = 93,
        )

        assertEquals(93L, claim.amount)
        assertEquals(7L, claim.fee)
    }

    @Test
    fun `matching settlement preserves normal fee`() {
        val claim = settledTokenClaim(
            review(grossAmount = 100, previewFee = 7),
            creditedAmount = 93,
        )

        assertEquals(93L, claim.amount)
        assertEquals(7L, claim.fee)
    }

    @Test
    fun `full credit reports zero fee even when preview was nonzero`() {
        val claim = settledTokenClaim(
            review(grossAmount = 100, previewFee = 4),
            creditedAmount = 100,
        )

        assertEquals(100L, claim.amount)
        assertEquals(0L, claim.fee)
    }

    @Test
    fun `credited amount is safely bounded only for fee arithmetic`() {
        val overCredit = settledTokenClaim(
            review(grossAmount = 100, previewFee = 4),
            creditedAmount = 105,
        )
        val invalidNegativeCredit = settledTokenClaim(
            review(grossAmount = 100, previewFee = 4),
            creditedAmount = -1,
        )

        assertEquals(105L, overCredit.amount)
        assertEquals(0L, overCredit.fee)
        assertEquals(0L, invalidNegativeCredit.amount)
        assertEquals(100L, invalidNegativeCredit.fee)
    }

    private fun review(
        grossAmount: Long,
        previewFee: Long,
    ) = TokenReview(
        token = "cashu-token",
        info = TokenInfo(
            amount = grossAmount,
            mint = "https://mint.example.com",
            unit = "sat",
            memo = null,
            proofCount = 1,
        ),
        fee = previewFee,
        locked = false,
    )
}
