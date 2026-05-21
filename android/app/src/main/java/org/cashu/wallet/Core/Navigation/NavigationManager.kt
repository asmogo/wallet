package org.cashu.wallet.Core.Navigation

import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.cashu.wallet.Core.PaymentRequestDecoder
import org.cashu.wallet.Core.PaymentRequestDecodeResult
import org.cashu.wallet.Core.TokenParser

sealed class CashuRoute(val route: String) {
    data object Main : CashuRoute("main")
    data object Receive : CashuRoute("receive")
    data object Send : CashuRoute("send")
    data object History : CashuRoute("history")
    data object Mints : CashuRoute("mints")
    data object Settings : CashuRoute("settings")
    data object Scanner : CashuRoute("scanner")
    data object Contactless : CashuRoute("contactless")
}

data class DeepLinkResult(
    val route: CashuRoute,
    val payload: String? = null,
)

class NavigationManager {
    private val mutablePendingDeepLink = MutableStateFlow<DeepLinkResult?>(null)
    val pendingDeepLink: StateFlow<DeepLinkResult?> = mutablePendingDeepLink.asStateFlow()

    fun handleDeepLink(uri: String?) {
        mutablePendingDeepLink.value = uri?.let(::routeForDeepLink)
    }

    fun consumeDeepLink() {
        mutablePendingDeepLink.value = null
    }

    companion object {
        fun routeForDeepLink(uri: String): DeepLinkResult? {
            val trimmed = uri.trim()
            val payload = normalizeCashuPayload(trimmed) ?: return null
            TokenParser.extractToken(payload)?.let { token ->
                return DeepLinkResult(CashuRoute.Receive, token)
            }
            PaymentRequestDecoder.encodedCashuPaymentRequest(payload)?.let {
                return DeepLinkResult(CashuRoute.Send, payload)
            }
            return when (PaymentRequestDecoder.decode(payload, includeCashuPaymentRequests = true, preferCashuPaymentRequests = true)) {
                is PaymentRequestDecodeResult.CashuPaymentRequest,
                is PaymentRequestDecodeResult.Bolt11,
                is PaymentRequestDecodeResult.Bolt12,
                is PaymentRequestDecodeResult.LightningAddress,
                is PaymentRequestDecodeResult.Onchain -> DeepLinkResult(CashuRoute.Send, payload)
                PaymentRequestDecodeResult.Unrecognized -> null
            }
        }

        private fun normalizeCashuPayload(uri: String): String? {
            val withoutScheme = when {
                uri.startsWith("cashu://", ignoreCase = true) -> uri.drop("cashu://".length)
                uri.startsWith("cashu:", ignoreCase = true) -> uri.drop("cashu:".length)
                else -> return null
            }
            return withoutScheme.decodeUrlComponent().trim().takeIf { it.isNotEmpty() }
        }

        private fun String.decodeUrlComponent(): String =
            runCatching { URLDecoder.decode(this, StandardCharsets.UTF_8.name()) }.getOrDefault(this)
    }
}
