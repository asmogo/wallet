package org.cashu.wallet.Core

import org.cashu.wallet.Models.PaymentMethodKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PaymentRequestDecoderTest {
    @Test
    fun lightningSchemeIsNormalized() {
        val request = "lightning:lnbc10u1ptest"
        assertTrue(PaymentRequestParser.normalizeLightningRequest(request).startsWith("lnbc"))
    }

    @Test
    fun lightningDoubleSlashSchemeIsNormalized() {
        val request = "lightning://lnbc10u1ptest"
        assertEquals("lnbc10u1ptest", PaymentRequestParser.normalizeLightningRequest(request))
    }

    @Test
    fun rawBolt11PrefixIsRecognizedByLightningParser() {
        val parsed = LightningRequestParser.parse("lnbc10u1ptest")
        assertEquals(PaymentMethodKind.Bolt11, parsed.method)
        assertEquals("lnbc10u1ptest", parsed.request)
    }

    @Test
    fun rawAndSchemedBolt12PrefixesAreRecognizedByLightningParser() {
        assertTrue(LightningRequestParser.isBolt12("lno1ptest"))
        assertTrue(LightningRequestParser.isBolt12("lightning://lno1ptest"))
        assertEquals(
            PaymentMethodKind.Bolt12,
            LightningRequestParser.parse("lightning:lno1ptest").method,
        )
    }

    @Test
    fun bitcoinUriLightningQueryIsExtracted() {
        val request = "bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080?lightning=lnbc10u1ptest"
        assertTrue(PaymentRequestDecoder.encodedLightningRequest(request)?.startsWith("lnbc") == true)
    }

    @Test
    fun bitcoinUriLightningInvoiceQueryIsExtractedAndDecoded() {
        val request = "bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080?lightninginvoice=lightning%3Alnbc10u1ptest"
        assertEquals("lnbc10u1ptest", PaymentRequestDecoder.encodedLightningRequest(request))
    }

    @Test
    fun cashuPaymentRequestQueryIsExtractedFromBitcoinUri() {
        val request = "bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080?creq=creqa-test"
        assertTrue(PaymentRequestDecoder.encodedCashuPaymentRequest(request) == "creqa-test")
    }

    @Test
    fun rawAndWrappedCashuPaymentRequestsAreExtracted() {
        assertEquals("creqa-test", PaymentRequestDecoder.encodedCashuPaymentRequest("creqa-test"))
        assertEquals("creqb1-test", PaymentRequestDecoder.encodedCashuPaymentRequest("cashu:creqb1-test"))
        assertEquals("creqa-test", PaymentRequestDecoder.encodedCashuPaymentRequest("cashu://creqa-test"))
    }

    @Test
    fun cashuWrappedTokensAreExtracted() {
        assertEquals("cashuA-test-token", TokenParser.extractToken("cashu:cashuA-test-token"))
        assertEquals("cashuB-test-token", TokenParser.extractToken("cashu://cashuB-test-token"))
    }

    @Test
    fun decodeRecognizesHumanReadableLightningAddress() {
        val decoded = PaymentRequestDecoder.decode("alice@example.com")
        assertEquals(PaymentRequestDecodeResult.LightningAddress("alice@example.com"), decoded)
    }

    @Test
    fun decodeRecognizesPlainBitcoinAddress() {
        val decoded = PaymentRequestDecoder.decode("1BoatSLRHtKNngkdXEeobR76b53LETtpyT")
        assertEquals(PaymentRequestDecodeResult.Onchain("1BoatSLRHtKNngkdXEeobR76b53LETtpyT"), decoded)
    }

    @Test
    fun lightningAddressIsNotBitcoinAddress() {
        assertTrue(!PaymentRequestParser.isBitcoinAddress("user@example.com"))
    }
}
