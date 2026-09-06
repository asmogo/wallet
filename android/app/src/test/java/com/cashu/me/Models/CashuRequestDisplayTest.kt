package com.cashu.me.Models

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CashuRequestDisplayTest {
    @Test
    fun legacyRequestKeepsCashuTitleAndEditing() {
        val request = CashuRequest(encoded = "creqA")

        assertEquals("Cashu Request", request.displayTitle)
        assertTrue(request.isEcashRequest)
        assertTrue(request.isReusable)
    }

    @Test
    fun quoteBackedIntentsUseRailSpecificTitles() {
        val bolt11 = CashuRequest(encoded = "lnbc1", quoteKind = "bolt11")
        val bolt12 = CashuRequest(encoded = "lno1", quoteKind = "bolt12")
        val onchain = CashuRequest(encoded = "bc1q", quoteKind = "onchain")

        assertEquals("Lightning invoice", bolt11.displayTitle)
        assertEquals("Reusable Invoice", bolt12.displayTitle)
        assertEquals("Bitcoin Address", onchain.displayTitle)
        assertFalse(bolt11.isEcashRequest)
        assertFalse(bolt11.isReusable)
        assertTrue(bolt12.isReusable)
        assertFalse(onchain.isReusable)

        val payment = CashuRequestPayment("tx", 10, 1_700_000_000)
        assertEquals("Lightning received", bolt11.copy(receivedPayments = listOf(payment)).displayTitle)
        assertEquals("Bitcoin received", onchain.copy(receivedPayments = listOf(payment)).displayTitle)
    }
}
