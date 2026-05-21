package org.cashu.wallet.Core

import org.cashu.wallet.Models.MintInfo

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

internal fun normalizedMintUrlForSelection(url: String?): String? {
    val trimmed = url?.trim()?.trimEnd('/') ?: return null
    return trimmed.lowercase().takeIf { it.isNotBlank() }
}
