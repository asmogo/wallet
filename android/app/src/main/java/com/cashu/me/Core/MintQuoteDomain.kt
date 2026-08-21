package com.cashu.me.Core

import com.cashu.me.Models.MintQuoteInfo
import com.cashu.me.Models.MintQuoteState
import com.cashu.me.Models.PaymentMethodKind

internal const val LOCAL_NEVER_EXPIRES_EPOCH_SECONDS: Long = 253_402_300_799L

internal fun mintQuoteLocalStorageExpiry(
    expiryEpochSeconds: Long,
    paymentMethod: PaymentMethodKind,
): Long =
    if (paymentMethod == PaymentMethodKind.Bolt12 && expiryEpochSeconds == 0L) {
        LOCAL_NEVER_EXPIRES_EPOCH_SECONDS
    } else {
        expiryEpochSeconds
    }

internal fun mintQuoteDisplayExpiry(expiryEpochSeconds: Long?): Long? =
    expiryEpochSeconds?.takeIf { it > 0 && it != LOCAL_NEVER_EXPIRES_EPOCH_SECONDS }

internal fun mintQuoteAmountForDomain(
    quoteAmount: Long?,
    fallbackAmount: Long?,
    amountPaid: Long,
    amountIssued: Long,
): Long? =
    quoteAmount
        ?: amountPaid.takeIf { it > 0 }
        ?: fallbackAmount?.takeIf { it > 0 }
        ?: amountIssued.takeIf { it > 0 }

internal fun mintQuoteStateForDomain(
    paymentMethod: PaymentMethodKind,
    storedState: MintQuoteState,
    amountPaid: Long,
    amountIssued: Long,
): MintQuoteState {
    if (amountPaid > 0 && amountIssued >= amountPaid) return MintQuoteState.Issued
    if (amountPaid > amountIssued) return MintQuoteState.Paid
    if (paymentMethod != PaymentMethodKind.Bolt11) return MintQuoteState.Pending
    return storedState
}

/**
 * Finds the long-lived, amountless BOLT12 offer for one mint wallet, matching
 * the requested [description] exactly (null → only the plain, description-less
 * offer). BOLT12 quotes remain in CDK's unissued list even after payments, so
 * deliberately do not filter by quote state here. The description match keeps
 * reuse unambiguous once several amountless offers exist (offers are
 * immutable, so a changed description always mints a fresh one).
 */
internal fun findExistingAmountlessBolt12Offer(
    quotes: List<MintQuoteInfo>,
    mintUrl: String,
    unit: String,
    description: String? = null,
): MintQuoteInfo? = quotes.firstOrNull { quote ->
    quote.paymentMethod == PaymentMethodKind.Bolt12 &&
        quote.isAmountless &&
        quote.mintUrl == mintUrl &&
        quote.unit.equals(unit, ignoreCase = true) &&
        quote.description == description
}
