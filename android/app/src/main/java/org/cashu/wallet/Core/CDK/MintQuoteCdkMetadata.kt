package org.cashu.wallet.Core.CDK

import org.cashu.wallet.Core.mintQuoteLocalStorageExpiry
import org.cashu.wallet.Models.PaymentMethodKind
import org.cashudevkit.Amount as CdkAmount
import org.cashudevkit.MintQuote as CdkMintQuote
import org.cashudevkit.PaymentMethod as CdkPaymentMethod

internal fun CdkMintQuote.withLocalMintQuoteMetadata(
    method: PaymentMethodKind,
    fallbackAmount: Long? = null,
): CdkMintQuote {
    val localExpiry = mintQuoteLocalStorageExpiry(expiry.toLong(), method)
    val localAmount = localMintQuoteAmount(method, fallbackAmount)
    return if (localExpiry == expiry.toLong() && localAmount == amount) {
        this
    } else {
        copy(expiry = localExpiry.toULong(), amount = localAmount)
    }
}

internal fun CdkMintQuote.preservingLocalMetadataFrom(existingQuote: CdkMintQuote): CdkMintQuote {
    val request = request.ifEmpty { existingQuote.request }
    val amount = amount ?: existingQuote.amount
    val expiry = if (expiry.toLong() == 0L && existingQuote.expiry.toLong() != 0L) {
        existingQuote.expiry
    } else {
        expiry
    }
    val paymentMethod = if (paymentMethod.isUnknownCustomMethod()) {
        existingQuote.paymentMethod
    } else {
        paymentMethod
    }

    return copy(
        request = request,
        amount = amount,
        expiry = expiry,
        paymentMethod = paymentMethod,
        estimatedBlocks = estimatedBlocks ?: existingQuote.estimatedBlocks,
        secretKey = secretKey ?: existingQuote.secretKey,
        usedByOperation = usedByOperation ?: existingQuote.usedByOperation,
    )
}

internal fun CdkMintQuote.clearingReservation(): CdkMintQuote =
    if (usedByOperation == null) this else copy(usedByOperation = null)

internal fun CdkMintQuote.hasUnissuedOnchainCredit(): Boolean =
    amountPaid.value > amountIssued.value

private fun CdkMintQuote.localMintQuoteAmount(
    method: PaymentMethodKind,
    fallbackAmount: Long?,
): CdkAmount? {
    if (method != PaymentMethodKind.Onchain || amount != null) return amount

    val resolvedAmount = amountPaid.value.takeIf { it > 0uL }
        ?: amountIssued.value.takeIf { it > 0uL }
        ?: fallbackAmount?.takeIf { it > 0 }?.toULong()
        ?: return null

    return CdkAmount(resolvedAmount)
}

private fun CdkPaymentMethod.isUnknownCustomMethod(): Boolean =
    this is CdkPaymentMethod.Custom && PaymentMethodKind.fromRaw(method) == null
