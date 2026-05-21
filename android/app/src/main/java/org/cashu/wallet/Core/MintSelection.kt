package org.cashu.wallet.Core

import org.cashu.wallet.Models.MintInfo
import org.cashu.wallet.Models.PaymentMethodKind

internal fun mintsIncludingActive(
    mints: List<MintInfo>,
    activeMint: MintInfo?,
): List<MintInfo> =
    if (activeMint != null && mints.none { normalizedMintUrlForSelection(it.url) == normalizedMintUrlForSelection(activeMint.url) }) {
        listOf(activeMint) + mints
    } else {
        mints
    }

internal fun recommendedSendMint(
    mints: List<MintInfo>,
    activeMintUrl: String?,
    minimumAmount: Long?,
): MintInfo? {
    val candidates = affordableOrAll(mints, minimumAmount)
    val active = normalizedMintUrlForSelection(activeMintUrl)
    return candidates.firstOrNull { normalizedMintUrlForSelection(it.url) == active }
        ?: candidates.sortedWith(mintBalanceNameComparator()).firstOrNull()
}

internal fun compatibleMintsForMeltPayment(
    mints: List<MintInfo>,
    paymentMethod: PaymentMethodKind,
): List<MintInfo> =
    mints.filter { paymentMethod in it.supportedMeltMethods }

internal fun selectMintForMeltPayment(
    mints: List<MintInfo>,
    selectedMintUrl: String?,
    activeMintUrl: String?,
    paymentMethod: PaymentMethodKind,
    minimumAmount: Long?,
): MintInfo? {
    val compatible = compatibleMintsForMeltPayment(mints, paymentMethod)
    val candidates = affordableOrAll(compatible, minimumAmount)
    val selected = normalizedMintUrlForSelection(selectedMintUrl)
    val active = normalizedMintUrlForSelection(activeMintUrl)
    return candidates.firstOrNull { normalizedMintUrlForSelection(it.url) == selected }
        ?: candidates.firstOrNull { normalizedMintUrlForSelection(it.url) == active }
        ?: candidates.sortedWith(mintBalanceNameComparator()).firstOrNull()
}

internal fun rankedMintsForDisplay(
    mints: List<MintInfo>,
    selectedMintUrl: String?,
    minimumAmount: Long?,
): List<MintInfo> {
    val selected = normalizedMintUrlForSelection(selectedMintUrl)
    return mints.sortedWith(
        compareByDescending<MintInfo> { normalizedMintUrlForSelection(it.url) == selected }
            .thenByDescending { minimumAmount == null || it.balance >= minimumAmount }
            .then(mintBalanceNameComparator()),
    )
}

internal fun mintCanCoverAmount(mint: MintInfo?, minimumAmount: Long?): Boolean =
    mint != null && (minimumAmount == null || mint.balance >= minimumAmount)

internal fun mintBalanceNameComparator(): Comparator<MintInfo> =
    compareByDescending<MintInfo> { it.balance }
        .thenBy { it.name.lowercase() }

private fun affordableOrAll(mints: List<MintInfo>, minimumAmount: Long?): List<MintInfo> {
    val amount = minimumAmount?.takeIf { it > 0 } ?: return mints
    val affordable = mints.filter { it.balance >= amount }
    return affordable.ifEmpty { mints }
}
