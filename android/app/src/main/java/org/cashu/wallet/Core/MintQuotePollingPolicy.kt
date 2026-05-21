package org.cashu.wallet.Core

import org.cashu.wallet.Models.MintQuoteState

internal fun shouldPollMintQuote(
    state: MintQuoteState,
    expiryEpochSeconds: Long?,
    nowEpochSeconds: Long,
): Boolean {
    if (state == MintQuoteState.Paid || state == MintQuoteState.Issued || state == MintQuoteState.Failed) {
        return false
    }
    val expiry = expiryEpochSeconds?.takeIf { it > 0 } ?: return true
    return nowEpochSeconds < expiry
}
