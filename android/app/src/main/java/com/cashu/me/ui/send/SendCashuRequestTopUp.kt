package com.cashu.me.ui.send

import com.cashu.me.Core.CashuPaymentRequestRoute
import java.net.URI

internal fun isCashuRequestPayEnabled(route: CashuPaymentRequestRoute?): Boolean =
    route == null ||
        route is CashuPaymentRequestRoute.PayWithEcash ||
        route is CashuPaymentRequestRoute.PayBolt11Fallback ||
        (route is CashuPaymentRequestRoute.AcquireThenPay &&
            (route.targetMintUrl != null || route.mintUrls.isNotEmpty()))

internal fun cashuRequestPayButtonText(route: CashuPaymentRequestRoute?, fallback: String): String {
    if (route !is CashuPaymentRequestRoute.AcquireThenPay) return fallback
    if (route.targetMintUrl == null && route.mintUrls.size > 1) return "Add a mint & pay"
    val target = route.targetMintUrl?.let(::cashuRequestMintDisplayName)
    return if (route.addsNewMint) {
        target?.let { "Add $it & pay" } ?: "Add mint & pay"
    } else {
        target?.let { "Fund $it & pay" } ?: "Fund mint & pay"
    }
}

internal fun cashuRequestMintDisplayName(url: String): String =
    runCatching { URI(url).host }
        .getOrNull()
        ?.takeIf { it.isNotBlank() }
        ?: url
