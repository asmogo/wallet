package com.cashu.me.Core.CDK

import com.cashu.me.Models.PaymentMethodKind
import org.cashudevkit.CurrencyUnit as CdkCurrencyUnit
import org.cashudevkit.Nuts as CdkNuts
import org.cashudevkit.PaymentMethod as CdkPaymentMethod

/**
 * NUT-04 mint rails exactly as reported by the mint: an empty list stays empty
 * (reported-absent — the detail screen hides the direction). The unknown /
 * never-fetched compatibility default lives on `MintInfo.effectiveMintMethods`,
 * not here. Unknown custom rails are dropped, never remapped (iOS `compactMap`).
 */
internal fun CdkNuts.reportedMintMethods(): List<PaymentMethodKind> =
    nut04.methods
        .mapNotNull { it.method.toKnownPaymentMethodKind() }
        .distinct()
        .sortedBy { it.sortOrder }

/**
 * True when any NUT-04 bolt12 method advertises `description: true`. Null or
 * false on every bolt12 method (or no bolt12 method at all) fails closed —
 * the Receive Description row must not appear unless the mint said so.
 */
internal fun CdkNuts.reportsBolt12MintDescription(): Boolean =
    nut04.methods.any {
        it.method.toKnownPaymentMethodKind() == PaymentMethodKind.Bolt12 &&
            it.description == true
    }

/**
 * NUT-05 melt rails exactly as reported, sat-only (pay-side non-sat is
 * deferred). Same reported-empty semantics as [reportedMintMethods].
 */
internal fun CdkNuts.reportedMeltMethods(): List<PaymentMethodKind> =
    nut05.methods
        .filter { it.unit == CdkCurrencyUnit.Sat }
        .mapNotNull { it.method.toKnownPaymentMethodKind() }
        .distinct()
        .sortedBy { it.sortOrder }

private fun CdkPaymentMethod.toKnownPaymentMethodKind(): PaymentMethodKind? = when (this) {
    CdkPaymentMethod.Bolt11 -> PaymentMethodKind.Bolt11
    CdkPaymentMethod.Bolt12 -> PaymentMethodKind.Bolt12
    CdkPaymentMethod.Onchain -> PaymentMethodKind.Onchain
    is CdkPaymentMethod.Custom -> PaymentMethodKind.fromRaw(method)
}
