package com.cashu.me.ui.send

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SendEcashReceiptDetailsTest {
    @Test
    fun claimedReceiptPreservesAmountNonzeroSatFeeAndMint() {
        val receipt = buildSendEcashReceiptDetails(
            amountLabel = "21 sat",
            fee = 3,
            unit = "sat",
            mintUrl = "https://mint.example.com/",
        )

        assertEquals("21 sat", receipt.amount)
        assertEquals("3 sat", receipt.fee)
        assertEquals("mint.example.com", receipt.mint)
    }

    @Test
    fun claimedReceiptFormatsFeeInNativeMintUnit() {
        val receipt = buildSendEcashReceiptDetails(
            amountLabel = "$12.34",
            fee = 25,
            unit = "usd",
            mintUrl = "https://mint.example.com",
        )

        assertEquals("$0.25", receipt.fee)
    }

    @Test
    fun claimedReceiptOmitsZeroFee() {
        val receipt = buildSendEcashReceiptDetails(
            amountLabel = "21 sat",
            fee = 0,
            unit = "sat",
            mintUrl = "https://mint.example.com",
        )

        assertNull(receipt.fee)
    }
}
