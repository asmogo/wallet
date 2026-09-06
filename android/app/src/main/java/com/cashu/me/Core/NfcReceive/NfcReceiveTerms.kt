package com.cashu.me.Core.NfcReceive

import com.cashu.me.Models.CashuRequest

internal enum class NfcSettlementRoute { Direct, Foreign }

internal fun CashuRequest.shouldOfferNfcReceive(): Boolean = isEcashRequest || receivedPayments.isEmpty()

internal fun CashuRequest.canReceiveByNfc(): Boolean =
    shouldOfferNfcReceive() && amount?.let { it > 0 } == true

internal fun validateNfcReceiveTerms(
    request: CashuRequest,
    sourceMint: String,
    tokenUnit: String,
    grossAmount: Long,
    settlementMint: String,
): NfcSettlementRoute {
    require(grossAmount > 0) { "The received token has no value." }
    require(tokenUnit.equals(request.unit, ignoreCase = true)) {
        "Expected ${request.unit.uppercase()} but received ${tokenUnit.uppercase()}."
    }
    request.amount?.takeIf { it > 0 }?.let { required ->
        require(grossAmount >= required) { "Expected at least $required ${request.unit}." }
    }
    val source = normalizeNfcMint(sourceMint)
    val target = normalizeNfcMint(settlementMint)
    val allowed = request.mints.map(::normalizeNfcMint)
    if (source == target || source in allowed) return NfcSettlementRoute.Direct
    require(allowed.isEmpty()) { "This request only accepts ecash from the selected mint." }
    require(tokenUnit.equals("sat", ignoreCase = true)) {
        "Foreign-mint conversion is currently available for sat requests only."
    }
    return NfcSettlementRoute.Foreign
}

internal fun normalizeNfcMint(url: String): String = url.trim().trimEnd('/')
