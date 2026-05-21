package org.cashu.wallet.Core.Services

import org.cashu.wallet.Core.PaymentRequestDecoder
import org.cashu.wallet.Core.PaymentRequestDecodeResult
import org.cashu.wallet.Core.LightningRequestParser
import org.cashu.wallet.Core.WalletManager
import org.cashu.wallet.Core.selectMintForCashuPaymentRequest

data class NFCPaymentState(
    val isReading: Boolean = false,
    val isAuthorizing: Boolean = false,
    val request: String? = null,
    val preparedToken: String? = null,
    val error: String? = null,
)

sealed interface NFCPaymentInput {
    data class CashuRequest(val summary: org.cashu.wallet.Core.CashuPaymentRequestSummary) : NFCPaymentInput
    data class LightningRequest(val request: String) : NFCPaymentInput
}

object NFCPaymentInputDecoder {
    fun decode(payload: String): NFCPaymentInput {
        val trimmed = payload.trim()
        require(trimmed.isNotEmpty()) { "Empty payment request." }

        val lightningFallback = PaymentRequestDecoder.encodedLightningRequest(trimmed)
            ?: runCatching { LightningRequestParser.parse(trimmed).request }.getOrNull()
        val cashuRequest = PaymentRequestDecoder.cashuPaymentRequestSummary(trimmed)
        if (cashuRequest != null && (cashuRequest.isSatUnit || lightningFallback == null)) {
            return NFCPaymentInput.CashuRequest(cashuRequest)
        }

        if (lightningFallback != null) return NFCPaymentInput.LightningRequest(lightningFallback)

        throw IllegalArgumentException("No supported NFC payment request.")
    }
}

class NFCPaymentService(
    private val walletManager: WalletManager,
) {
    fun decodeRequest(payload: String): PaymentRequestDecodeResult =
        PaymentRequestDecoder.decode(payload, includeCashuPaymentRequests = true, preferCashuPaymentRequests = true)

    fun decodePaymentInput(payload: String): NFCPaymentInput = NFCPaymentInputDecoder.decode(payload)

    suspend fun preparePayment(payload: String): String {
        return when (val input = decodePaymentInput(payload)) {
            is NFCPaymentInput.CashuRequest -> prepareCashuRequest(input.summary)
            is NFCPaymentInput.LightningRequest -> {
                throw IllegalStateException("Lightning NFC requests should be routed to Send.")
            }
        }
    }

    fun tokenRecord(token: String) = NDEFTextRecordCoder.encode(token)

    private suspend fun prepareCashuRequest(summary: org.cashu.wallet.Core.CashuPaymentRequestSummary): String {
        val amount = summary.amount?.takeIf { it > 0 }
            ?: throw IllegalArgumentException("Cashu payment request requires an amount.")
        require(summary.isSatUnit) { "Only sat Cashu payment requests are supported." }
        val state = walletManager.state.value
        val selectedMint = selectMintForCashuPaymentRequest(
            request = summary,
            mints = state.mints,
            selectedMintUrl = state.activeMint?.url,
            activeMintUrl = state.activeMint?.url,
            amountSats = amount,
        ) ?: throw IllegalArgumentException("No compatible mint has enough balance.")

        return walletManager.sendTokens(
            amount = amount,
            memo = null,
            p2pkPubkey = null,
            mintUrl = selectedMint.url,
        ).token
    }
}
