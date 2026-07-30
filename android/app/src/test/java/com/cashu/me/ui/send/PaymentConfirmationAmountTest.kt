package com.cashu.me.ui.send

import com.cashu.me.Core.AmountDisplayPrimary
import com.cashu.me.Core.AmountFormatter
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PaymentConfirmationAmountTest {
    private val formatter = AmountFormatter(Locale.US)

    @Test
    fun satsPrimaryLeadsAndTalkBackIncludesFiatAlternate() {
        val presentation = paymentConfirmationAmountPresentation(
            amount = 100_000,
            unit = "sat",
            preferredPrimary = AmountDisplayPrimary.Sats.rawValue,
            showFiat = true,
            btcPrice = 20_000.0,
            currencyCode = "USD",
            useBitcoinSymbol = false,
            formatter = formatter,
        )

        assertEquals("100,000 sat", presentation.primary)
        assertEquals("$20.00", presentation.alternate)
        assertEquals(
            "Payment amount, 100,000 sat. Alternate value, $20.00",
            presentation.talkBackDescription,
        )
    }

    @Test
    fun fiatPrimaryLeadsAndTalkBackIncludesSatsAlternate() {
        val presentation = paymentConfirmationAmountPresentation(
            amount = 100_000,
            unit = "sat",
            preferredPrimary = AmountDisplayPrimary.Fiat.rawValue,
            showFiat = true,
            btcPrice = 20_000.0,
            currencyCode = "USD",
            useBitcoinSymbol = false,
            formatter = formatter,
        )

        assertEquals("$20.00", presentation.primary)
        assertEquals("100,000 sat", presentation.alternate)
        assertEquals(
            "Payment amount, $20.00. Alternate value, 100,000 sat",
            presentation.talkBackDescription,
        )
    }

    @Test
    fun nonSatRequestStaysInItsNativeUnitWithoutBitcoinConversion() {
        val presentation = paymentConfirmationAmountPresentation(
            amount = 1_234,
            unit = "usd",
            preferredPrimary = AmountDisplayPrimary.Sats.rawValue,
            showFiat = true,
            btcPrice = 20_000.0,
            currencyCode = "USD",
            useBitcoinSymbol = false,
            formatter = formatter,
        )

        assertEquals("$12.34", presentation.primary)
        assertNull(presentation.alternate)
        assertEquals("Payment amount, $12.34", presentation.talkBackDescription)
    }
}
