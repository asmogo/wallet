package org.cashu.wallet.Core

import org.cashu.wallet.Core.Protocols.CurrencyAmount
import org.cashu.wallet.Core.Protocols.PaymentRequest
import org.cashu.wallet.Core.Protocols.PaymentStatus
import org.cashu.wallet.Core.Protocols.capabilityLabel
import org.cashu.wallet.Core.Protocols.iconName
import org.cashu.wallet.Models.PaymentMethodKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PaymentMethodProtocolTest {
    @Test
    fun paymentMethodKindsExposeStableIconAndCapabilityLabels() {
        assertEquals("bolt", PaymentMethodKind.Bolt11.iconName)
        assertEquals("bolt12", PaymentMethodKind.Bolt12.iconName)
        assertEquals("bitcoin", PaymentMethodKind.Onchain.iconName)

        assertEquals("Lightning invoice", PaymentMethodKind.Bolt11.capabilityLabel)
        assertEquals("Reusable offer", PaymentMethodKind.Bolt12.capabilityLabel)
        assertEquals("Bitcoin address", PaymentMethodKind.Onchain.capabilityLabel)
    }

    @Test
    fun paymentRequestExpiryMatchesSwiftNilAndDateBehavior() {
        val amount = CurrencyAmount.sats(21)
        val noExpiry = PaymentRequest(
            id = "request-1",
            paymentRail = PaymentMethodKind.Bolt11.rawValue,
            amount = amount,
            encodedRequest = "lnbc",
        )
        val expired = noExpiry.copy(expiresAtEpochMillis = 1_000)
        val active = noExpiry.copy(expiresAtEpochMillis = 3_000)

        assertFalse(noExpiry.isExpired(nowEpochMillis = 2_000))
        assertTrue(expired.isExpired(nowEpochMillis = 2_000))
        assertFalse(active.isExpired(nowEpochMillis = 2_000))
    }

    @Test
    fun paymentStatusConvenienceFlagsMatchSwiftCases() {
        assertTrue(PaymentStatus.Pending.isPending)
        assertFalse(PaymentStatus.Pending.isCompleted)
        assertTrue(PaymentStatus.Completed(preimage = "abc").isCompleted)
        assertFalse(PaymentStatus.Failed("no route").isCompleted)
        assertFalse(PaymentStatus.Expired.isPending)
    }
}
