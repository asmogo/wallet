package org.cashu.wallet.Core

import org.cashu.wallet.Models.MintQuoteState
import org.cashu.wallet.Models.PaymentMethodKind

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
