package com.cashu.me.ui.receive

import com.cashu.me.Models.PaymentMethodKind
import org.junit.Assert.*
import org.junit.Test

class ReceiveInvoiceExpiryTest {
    @Test fun oneShotExpiresAtBoundaryAndWhenReopened() {
        for (method in listOf(PaymentMethodKind.Bolt11, PaymentMethodKind.Onchain)) {
            assertFalse(receiveInvoiceIsExpired(method, 100L, 99L, null))
            assertTrue(receiveInvoiceIsExpired(method, 100L, 100L, null))
            assertTrue(receiveInvoiceIsExpired(method, 100L, 120L, null))
        }
    }
    @Test fun settlementAndReusableOffersTakePrecedence() {
        MintQuoteSettlementState.entries.forEach { state ->
            assertFalse(receiveInvoiceIsExpired(PaymentMethodKind.Bolt11, 100L, 120L, state))
        }
        assertFalse(receiveInvoiceIsExpired(PaymentMethodKind.Bolt12, 100L, 120L, null))
        for (expiry in listOf(null, 0L, 253_402_300_799L)) {
            assertFalse(receiveInvoiceIsExpired(PaymentMethodKind.Bolt11, expiry, Long.MAX_VALUE, null))
        }
    }
}
