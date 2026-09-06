package com.cashu.me.Core

import com.cashu.me.Models.PaymentMethodKind
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
        assertEquals(1_000L, parsed.amountSats)
    }

    @Test
    fun bolt11AmountParserStopsAtMultiplierUnit() {
        val parsed = LightningRequestParser.parse(
            "lnbc2500u1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpu9qrsgquk0rl77nj30yxdy8j9vdx85fkpmdla2087ne0xh8nhedh8w27kyke0lp53ut353s06fv3qfegext0eh0ymjpf39tuven09sam30g4vgpfna3rh",
        )

        assertEquals(PaymentMethodKind.Bolt11, parsed.method)
        assertEquals(250_000L, parsed.amountSats)
    }

    @Test
    fun rawAndSchemedBolt12PrefixesAreRecognizedByLightningParser() {
        assertTrue(LightningRequestParser.isBolt12(AmountlessBolt12Offer))
        assertTrue(LightningRequestParser.isBolt12("lightning://$AmountlessBolt12Offer"))
        assertEquals(
            PaymentMethodKind.Bolt12,
            LightningRequestParser.parse("lightning:$AmountlessBolt12Offer").method,
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
    fun cdkCompatibleLegacyCashuRequestsNormalizePrefixAndPadding() {
        assertEquals("creqAabc=", PaymentRequestDecoder.cdkCompatibleCashuPaymentRequest("CREQAabc"))
        assertEquals("creqAabc=", PaymentRequestDecoder.cdkCompatibleCashuPaymentRequest("cashu:creqAabc"))
        assertEquals("CREQB1abc", PaymentRequestDecoder.cdkCompatibleCashuPaymentRequest("CREQB1abc"))
    }

    @Test
    fun locallyBuiltLegacyCashuRequestsDecodeWithoutCdkFallback() {
        val encoded = PaymentRequestBuilder.build(
            id = "local-request",
            amount = 7,
            unit = "sat",
            mints = listOf("http://localhost:3339"),
            description = "Local request",
            nostrPubkeyHex = "1".repeat(64),
            relays = emptyList(),
        )

        val decoded = PaymentRequestDecoder.decode(
            encoded,
            includeCashuPaymentRequests = true,
        ) as? PaymentRequestDecodeResult.CashuPaymentRequest

        assertEquals(7L, decoded?.summary?.amount)
        assertEquals("sat", decoded?.summary?.unit)
        assertEquals("Local request", decoded?.summary?.description)
        assertEquals(listOf("http://localhost:3339"), decoded?.summary?.mints)
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
    fun decodeRecognizesRealAmountlessBolt12Offer() {
        val decoded = PaymentRequestDecoder.decode(AmountlessBolt12Offer)

        assertTrue(decoded is PaymentRequestDecodeResult.Bolt12)
        assertEquals(null, (decoded as PaymentRequestDecodeResult.Bolt12).amountSats)
        assertEquals(
            AmountlessBolt12Offer,
            PaymentRequestDecoder.encodedLightningRequest("lightning:$AmountlessBolt12Offer"),
        )
    }

    @Test
    fun bolt12TextEnvelopeNormalizesUppercaseAndContinuation() {
        val continued = AmountlessBolt12Offer.take(32) + "+\n " + AmountlessBolt12Offer.drop(32)
        val compactContinuation = AmountlessBolt12Offer.take(32) + "+" + AmountlessBolt12Offer.drop(32)

        assertEquals(
            AmountlessBolt12Offer,
            PaymentRequestDecoder.encodedLightningRequest(AmountlessBolt12Offer.uppercase()),
        )
        assertEquals(
            AmountlessBolt12Offer,
            PaymentRequestDecoder.encodedLightningRequest(continued),
        )
        assertEquals(
            AmountlessBolt12Offer,
            PaymentRequestDecoder.encodedLightningRequest(compactContinuation),
        )
        assertEquals(
            null,
            PaymentRequestDecoder.encodedLightningRequest("L${AmountlessBolt12Offer.drop(1)}"),
        )
        assertTrue(!LightningRequestParser.isBolt12("lno1ptest"))
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

    private companion object {
        const val AmountlessBolt12Offer =
            "lno1pgqpvggr25nht4nyqrgtnhxltctkdsfrf3myhj008f6fyulf4tplmarx8hxq"
    }
}
