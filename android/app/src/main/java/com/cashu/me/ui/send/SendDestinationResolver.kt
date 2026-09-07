package com.cashu.me.ui.send

import com.cashu.me.Core.PaymentRequestDecodeResult
import com.cashu.me.Core.PaymentRequestDecoder
import com.cashu.me.Core.TokenParser
import com.cashu.me.Core.compatibleMintsForCashuPaymentRequest
import com.cashu.me.Models.MintInfo

internal const val AmountlessBolt11Hint =
    "This BOLT11 invoice doesn't include an amount. Ask for an amount-specific invoice before paying."

internal sealed interface SendDestinationResolution {
    data class Hint(val message: String) : SendDestinationResolution
    data class Melt(
        val request: String,
        val decoded: PaymentRequestDecodeResult,
        val knownAmount: Long?,
        val requiresAmountEntry: Boolean,
    ) : SendDestinationResolution
    data class CashuRequest(
        val request: String,
        val decoded: PaymentRequestDecodeResult.CashuPaymentRequest,
        val knownAmount: Long?,
        val requiresAmountEntry: Boolean,
    ) : SendDestinationResolution
    data class EcashToken(val token: String) : SendDestinationResolution
    data object Unrecognized : SendDestinationResolution
}

internal fun resolveSendDestination(
    raw: String,
    walletMints: List<MintInfo>,
): SendDestinationResolution {
    val trimmed = raw.trim()
    if (trimmed.isEmpty()) return SendDestinationResolution.Unrecognized
    var decoded = PaymentRequestDecoder.decode(
        trimmed,
        includeCashuPaymentRequests = true,
        preferCashuPaymentRequests = true,
    )
    var request = trimmed
    if (decoded is PaymentRequestDecodeResult.CashuPaymentRequest &&
        compatibleMintsForCashuPaymentRequest(decoded.summary, walletMints).isEmpty()
    ) {
        val fallback = PaymentRequestDecoder.decode(trimmed)
        if (fallback !is PaymentRequestDecodeResult.Unrecognized) {
            decoded = fallback
            request = PaymentRequestDecoder.encodedLightningRequest(trimmed) ?: trimmed
        }
    }
    return when (decoded) {
        is PaymentRequestDecodeResult.Bolt11 -> {
            val known = decoded.amountSats
            if (known == null || known <= 0L) {
                SendDestinationResolution.Hint(AmountlessBolt11Hint)
            } else {
                SendDestinationResolution.Melt(
                    PaymentRequestDecoder.encodedLightningRequest(request) ?: request,
                    decoded,
                    known,
                    requiresAmountEntry = false,
                )
            }
        }
        is PaymentRequestDecodeResult.Bolt12 -> {
            val known = decoded.amountSats?.takeIf { it > 0L }
            SendDestinationResolution.Melt(
                request = PaymentRequestDecoder.encodedLightningRequest(request) ?: request,
                decoded = decoded,
                knownAmount = known,
                requiresAmountEntry = known == null,
            )
        }
        is PaymentRequestDecodeResult.LightningAddress,
        is PaymentRequestDecodeResult.Onchain -> SendDestinationResolution.Melt(
            request = request,
            decoded = decoded,
            knownAmount = null,
            requiresAmountEntry = true,
        )
        is PaymentRequestDecodeResult.CashuPaymentRequest -> {
            val known = decoded.summary.amount?.takeIf { it > 0 }
            SendDestinationResolution.CashuRequest(
                request = request,
                decoded = decoded,
                knownAmount = known,
                requiresAmountEntry = decoded.summary.isSatUnit && known == null,
            )
        }
        PaymentRequestDecodeResult.Unrecognized -> {
            TokenParser.extractToken(trimmed)
                ?.let(SendDestinationResolution::EcashToken)
                ?: SendDestinationResolution.Unrecognized
        }
    }
}
