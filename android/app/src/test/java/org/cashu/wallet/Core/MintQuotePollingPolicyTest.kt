package org.cashu.wallet.Core

import org.cashu.wallet.Models.MintQuoteState
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MintQuotePollingPolicyTest {
    @Test
    fun pollsOpenQuotesBeforeExpiry() {
        assertTrue(
            shouldPollMintQuote(
                state = MintQuoteState.Unpaid,
                expiryEpochSeconds = 200,
                nowEpochSeconds = 100,
            ),
        )
        assertTrue(
            shouldPollMintQuote(
                state = MintQuoteState.Pending,
                expiryEpochSeconds = 200,
                nowEpochSeconds = 100,
            ),
        )
    }

    @Test
    fun pollsUnknownQuotesWithoutExpiry() {
        assertTrue(
            shouldPollMintQuote(
                state = MintQuoteState.Unknown,
                expiryEpochSeconds = null,
                nowEpochSeconds = 100,
            ),
        )
    }

    @Test
    fun stopsPollingTerminalStatesAndExpiredQuotes() {
        assertFalse(shouldPollMintQuote(MintQuoteState.Paid, expiryEpochSeconds = 200, nowEpochSeconds = 100))
        assertFalse(shouldPollMintQuote(MintQuoteState.Issued, expiryEpochSeconds = 200, nowEpochSeconds = 100))
        assertFalse(shouldPollMintQuote(MintQuoteState.Failed, expiryEpochSeconds = 200, nowEpochSeconds = 100))
        assertFalse(shouldPollMintQuote(MintQuoteState.Unpaid, expiryEpochSeconds = 100, nowEpochSeconds = 100))
    }
}
