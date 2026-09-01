package com.cashu.me.Core

import com.cashu.me.Models.MintInfo

internal sealed interface CashuPaymentRequestRoute {
    data class PayWithEcash(val mint: MintInfo, val amountSats: Long) : CashuPaymentRequestRoute
    data class PayBolt11Fallback(val lightningRequest: String) : CashuPaymentRequestRoute
    data class AcquireThenPay(
        val mintUrls: List<String>,
        val targetMintUrl: String?,
        val amountSats: Long,
        val addsNewMint: Boolean,
    ) : CashuPaymentRequestRoute
    data class UnsupportedUnit(val unit: String?) : CashuPaymentRequestRoute
    data object MissingAmount : CashuPaymentRequestRoute
}

internal fun compatibleMintsForCashuPaymentRequest(
    request: CashuPaymentRequestSummary,
    mints: List<MintInfo>,
): List<MintInfo> {
    val accepted = request.mints
        .mapNotNull(::normalizedMintUrlForSelection)
        .toSet()
    if (accepted.isEmpty()) return mints
    return mints.filter { mint -> normalizedMintUrlForSelection(mint.url) in accepted }
}

internal fun selectMintForCashuPaymentRequest(
    request: CashuPaymentRequestSummary,
    mints: List<MintInfo>,
    selectedMintUrl: String?,
    activeMintUrl: String?,
    amountSats: Long?,
): MintInfo? {
    val compatible = compatibleMintsForCashuPaymentRequest(request, mints)
    val amount = amountSats?.takeIf { it > 0 }
    val candidates = if (amount == null) {
        compatible
    } else {
        compatible.filter { it.balance >= amount }
    }
    if (candidates.isEmpty()) return null

    val selected = normalizedMintUrlForSelection(selectedMintUrl)
    val active = normalizedMintUrlForSelection(activeMintUrl)
    return candidates.firstOrNull { normalizedMintUrlForSelection(it.url) == selected }
        ?: candidates.firstOrNull { normalizedMintUrlForSelection(it.url) == active }
        ?: candidates.sortedWith(mintBalanceNameComparator()).firstOrNull()
}

internal fun routeForCashuPaymentRequest(
    rawRequest: String,
    request: CashuPaymentRequestSummary,
    mints: List<MintInfo>,
    selectedMintUrl: String?,
    activeMintUrl: String?,
    amountSats: Long?,
    selectedTargetMintUrl: String? = null,
): CashuPaymentRequestRoute {
    if (!request.isSatUnit) {
        return CashuPaymentRequestRoute.UnsupportedUnit(request.unit)
    }
    val amount = request.amount?.takeIf { it > 0 } ?: amountSats?.takeIf { it > 0 }
        ?: return CashuPaymentRequestRoute.MissingAmount

    selectMintForCashuPaymentRequest(
        request = request,
        mints = mints,
        selectedMintUrl = selectedMintUrl,
        activeMintUrl = activeMintUrl,
        amountSats = amount,
    )?.let { mint ->
        return CashuPaymentRequestRoute.PayWithEcash(mint = mint, amountSats = amount)
    }

    PaymentRequestDecoder.encodedLightningRequest(rawRequest)?.let { fallback ->
        return CashuPaymentRequestRoute.PayBolt11Fallback(fallback)
    }

    val requestedMintUrls = request.mints
        .filter { normalizedMintUrlForSelection(it) != null }
        .distinctBy(::normalizedMintUrlForSelection)
    val trackedCompatible = compatibleMintsForCashuPaymentRequest(request, mints)

    val trackedTarget = trackedCompatible.firstOrNull { mint ->
        normalizedMintUrlForSelection(mint.url) == normalizedMintUrlForSelection(selectedMintUrl)
    }?.url ?: trackedCompatible.firstOrNull { mint ->
        normalizedMintUrlForSelection(mint.url) == normalizedMintUrlForSelection(activeMintUrl)
    }?.url ?: trackedCompatible.maxByOrNull { it.balance }?.url

    val selectedRequestedTarget = requestedMintUrls.firstOrNull {
        normalizedMintUrlForSelection(it) == normalizedMintUrlForSelection(selectedTargetMintUrl)
    }
    val requestedTarget = selectedRequestedTarget ?: requestedMintUrls.singleOrNull()
    val targetMintUrl = trackedTarget ?: requestedTarget

    return CashuPaymentRequestRoute.AcquireThenPay(
        mintUrls = requestedMintUrls,
        targetMintUrl = targetMintUrl,
        amountSats = amount,
        addsNewMint = trackedTarget == null && targetMintUrl != null,
    )
}

internal fun normalizedMintUrlForSelection(url: String?): String? {
    val trimmed = url?.trim()?.trimEnd('/') ?: return null
    return trimmed.lowercase().takeIf { it.isNotBlank() }
}
