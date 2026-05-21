package org.cashu.wallet.Core

import org.cashu.wallet.Models.PaymentMethodKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BitcoinAddressValidatorTest {
    @Test
    fun acceptsBase58MainnetAndTestnetAddresses() {
        assertTrue(BitcoinAddressValidator.isValidAddress("1BoatSLRHtKNngkdXEeobR76b53LETtpyT"))
        assertTrue(BitcoinAddressValidator.isValidAddress("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"))
        assertTrue(BitcoinAddressValidator.isValidAddress("mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn"))
        assertTrue(BitcoinAddressValidator.isValidAddress("2NBFNJTktNa7GZusGbDbGKRZTxdK9VVez3n"))
    }

    @Test
    fun acceptsBech32AndBech32mAddresses() {
        assertTrue(BitcoinAddressValidator.isValidAddress("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"))
        assertTrue(BitcoinAddressValidator.isValidAddress("tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7"))
        assertTrue(BitcoinAddressValidator.isValidAddress("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0"))
    }

    @Test
    fun rejectsInvalidOrAmbiguousAddresses() {
        assertFalse(BitcoinAddressValidator.isValidAddress("user@example.com"))
        assertFalse(BitcoinAddressValidator.isValidAddress("bc1QW508d6qejxtdg4y5r3zarvary0c5xw7kygt080"))
        assertFalse(BitcoinAddressValidator.isValidAddress("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080"))
        assertFalse(BitcoinAddressValidator.isValidAddress("1BoatSLRHtKNngkdXEeobR76b53LETtpy0"))
        assertFalse(BitcoinAddressValidator.isValidAddress("ltc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080"))
    }

    @Test
    fun parserNormalizesBitcoinUriAndClassifiesOnchain() {
        val request = "bitcoin:1BoatSLRHtKNngkdXEeobR76b53LETtpyT?amount=0.01"

        assertEquals("1BoatSLRHtKNngkdXEeobR76b53LETtpyT", PaymentRequestParser.normalizeBitcoinRequest(request))
        assertEquals(PaymentMethodKind.Onchain, PaymentRequestParser.paymentMethod(request))

        val decoded = PaymentRequestDecoder.decode(request)
        assertTrue(decoded is PaymentRequestDecodeResult.Onchain)
        assertEquals(
            "1BoatSLRHtKNngkdXEeobR76b53LETtpyT",
            (decoded as PaymentRequestDecodeResult.Onchain).address,
        )
    }
}
