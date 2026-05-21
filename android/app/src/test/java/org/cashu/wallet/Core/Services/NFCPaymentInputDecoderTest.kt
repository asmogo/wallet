package org.cashu.wallet.Core.Services

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class NFCPaymentInputDecoderTest {
    @Test
    fun routesBitcoinLightningQueryToLightningRequest() {
        val decoded = NFCPaymentInputDecoder.decode(
            "bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080?lightning=lnbc10u1ptest",
        )

        assertTrue(decoded is NFCPaymentInput.LightningRequest)
        assertEquals("lnbc10u1ptest", (decoded as NFCPaymentInput.LightningRequest).request)
    }

    @Test
    fun routesRawLightningRequestToLightningRequest() {
        val decoded = NFCPaymentInputDecoder.decode("lnbc10u1ptest")

        assertTrue(decoded is NFCPaymentInput.LightningRequest)
        assertEquals("lnbc10u1ptest", (decoded as NFCPaymentInput.LightningRequest).request)
    }

    @Test
    fun routesLightningSchemeToLightningRequest() {
        val decoded = NFCPaymentInputDecoder.decode("lightning://lnbc10u1ptest")

        assertTrue(decoded is NFCPaymentInput.LightningRequest)
        assertEquals("lnbc10u1ptest", (decoded as NFCPaymentInput.LightningRequest).request)
    }

    @Test
    fun routesSingleColonLightningSchemeToLightningRequest() {
        val decoded = NFCPaymentInputDecoder.decode("lightning:lnbc10u1ptest")

        assertTrue(decoded is NFCPaymentInput.LightningRequest)
        assertEquals("lnbc10u1ptest", (decoded as NFCPaymentInput.LightningRequest).request)
    }

    @Test
    fun routesBolt12LightningSchemeToLightningRequest() {
        val decoded = NFCPaymentInputDecoder.decode("lightning:lno1ptest")

        assertTrue(decoded is NFCPaymentInput.LightningRequest)
        assertEquals("lno1ptest", (decoded as NFCPaymentInput.LightningRequest).request)
    }

    @Test
    fun rejectsEmptyAndUnsupportedPayloads() {
        assertThrows(IllegalArgumentException::class.java) {
            NFCPaymentInputDecoder.decode(" ")
        }
        assertThrows(IllegalArgumentException::class.java) {
            NFCPaymentInputDecoder.decode("bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080")
        }
    }
}
