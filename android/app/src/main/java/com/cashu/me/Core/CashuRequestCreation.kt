package com.cashu.me.Core

import com.cashu.me.Models.CashuRequest

/**
 * Creates a Nostr-delivered NUT-18 request.
 *
 * New requests are deliberately unrestricted unless the user explicitly picks
 * a mint. Keeping that choice in this API prevents ambient wallet state (such
 * as the active mint) from silently narrowing who can pay the request.
 */
internal fun CashuRequestStore.createNostrCashuRequest(
    id: String = CashuRequest.newId(),
    amount: Long? = null,
    unit: String = "sat",
    selectedMintUrl: String? = null,
    memo: String? = null,
    nostrPubkeyHex: String,
    relays: List<String>,
): CashuRequest {
    val mints = listOfNotNull(selectedMintUrl?.trim()?.takeIf { it.isNotEmpty() })
    val encoded = PaymentRequestBuilder.build(
        id = id,
        amount = amount,
        unit = unit,
        mints = mints,
        description = memo,
        nostrPubkeyHex = nostrPubkeyHex,
        relays = relays,
    )
    return createNew(
        id = id,
        amount = amount,
        unit = unit,
        mints = mints,
        memo = memo,
        encoded = encoded,
    )
}
