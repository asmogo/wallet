package com.cashu.me.ui.send

import com.cashu.me.Core.CashuPaymentRequestRoute
import com.cashu.me.Core.PaymentRequestDecodeResult
import com.cashu.me.Models.MeltPaymentResult
import com.cashu.me.Models.MeltQuoteInfo
import com.cashu.me.Models.MeltSettlement
import com.cashu.me.Models.MintInfo
import java.net.URI

/** The rail the unified destination field locked onto. */
internal sealed interface LockedRail {
    val raw: String

    data class Melt(
        override val raw: String,
        val decoded: PaymentRequestDecodeResult,
        val knownAmount: Long?,
    ) : LockedRail

    data class Creq(
        override val raw: String,
        val decoded: PaymentRequestDecodeResult.CashuPaymentRequest,
        val knownAmount: Long?,
        // Arrived pre-formed (scan/deep link) vs. typed/pasted — iOS shows the
        // raw request string only in the latter case (mirrors UnifiedSendView).
        val fromScan: Boolean = false,
    ) : LockedRail
}

/** Stable identity and order for facts shown throughout a payment attempt. */
internal enum class SendPaymentDetailKey {
    Method,
    Destination,
    Amount,
    NetworkFee,
    InputFee,
    Mint,
    Memo,
    Route,
}

/** Typed values prevent unresolved fees from being formatted as zero. */
internal sealed interface SendPaymentDetailValue {
    data class Text(val text: String) : SendPaymentDetailValue
    data class Sats(
        val amount: Long,
        val isUpperBound: Boolean = false,
    ) : SendPaymentDetailValue
    data object Pending : SendPaymentDetailValue
    data object Unavailable : SendPaymentDetailValue
}

internal data class SendPaymentDetailRow(
    val key: SendPaymentDetailKey,
    val label: String,
    val value: SendPaymentDetailValue,
    val valueMonospaced: Boolean = false,
)

/**
 * Immutable payment-fact snapshot carried by processing, success, and failure.
 *
 * The row keys are fixed when Pay is tapped. Values may become more precise
 * (a pending fallback fee can resolve, or a settled melt can replace its fee
 * upper bound with the actual fee), but rows are never inserted or removed
 * between terminal phases.
 */
internal data class SendPaymentDetails(
    val rows: List<SendPaymentDetailRow>,
) {
    init {
        require(rows.map { it.key }.distinct().size == rows.size) {
            "Payment detail keys must be unique."
        }
    }

    val keys: List<SendPaymentDetailKey> get() = rows.map { it.key }

    fun withNetworkFeeUpperBound(amountSats: Long): SendPaymentDetails =
        replacing(SendPaymentDetailKey.NetworkFee, SendPaymentDetailValue.Sats(amountSats, isUpperBound = true))

    fun withMintName(name: String): SendPaymentDetails =
        replacing(SendPaymentDetailKey.Mint, SendPaymentDetailValue.Text(name))

    fun withMeltResult(result: MeltPaymentResult): SendPaymentDetails {
        val feeValue = if (result.settlement == MeltSettlement.Pending) {
            SendPaymentDetailValue.Sats(result.feePaid, isUpperBound = true)
        } else {
            SendPaymentDetailValue.Sats(result.feePaid)
        }
        return replacing(SendPaymentDetailKey.NetworkFee, feeValue)
    }

    fun resolvingFailed(): SendPaymentDetails = copy(
        rows = rows.map { row ->
            if (row.value == SendPaymentDetailValue.Pending) {
                row.copy(value = SendPaymentDetailValue.Unavailable)
            } else {
                row
            }
        },
    )

    private fun replacing(
        key: SendPaymentDetailKey,
        value: SendPaymentDetailValue,
    ): SendPaymentDetails {
        if (rows.none { it.key == key }) return this
        return copy(rows = rows.map { row -> if (row.key == key) row.copy(value = value) else row })
    }
}

/**
 * Documents the unified Send terminal row contract:
 *
 * - Melt rails: Method, on-chain Destination when applicable, Amount,
 *   Network fee, and Mint.
 * - Cashu Request: Method, Amount, Input/Network fee context, Mint when known,
 *   Memo when supplied, and a Route row when payment changes rails or needs a top-up.
 */
internal fun buildSendPaymentDetails(
    rail: LockedRail,
    cashuRoute: CashuPaymentRequestRoute?,
    amountSats: Long,
    mint: MintInfo?,
    meltQuote: MeltQuoteInfo?,
    cashuInputFeeSats: Long? = null,
): SendPaymentDetails {
    val rows = when (rail) {
        is LockedRail.Melt -> buildMeltDetails(
            rail = rail,
            amountSats = amountSats,
            mint = mint,
            quote = meltQuote,
        )
        is LockedRail.Creq -> buildCashuRequestDetails(
            rail = rail,
            route = cashuRoute,
            amountSats = amountSats,
            mint = mint,
            inputFeeSats = cashuInputFeeSats,
        )
    }
    return SendPaymentDetails(rows)
}

private fun buildMeltDetails(
    rail: LockedRail.Melt,
    amountSats: Long,
    mint: MintInfo?,
    quote: MeltQuoteInfo?,
): List<SendPaymentDetailRow> = buildList {
    add(textRow(SendPaymentDetailKey.Method, "Method", meltMethodName(rail, quote)))
    if (rail.decoded is PaymentRequestDecodeResult.Onchain) {
        add(
            textRow(
                SendPaymentDetailKey.Destination,
                "To",
                rail.decoded.address,
                valueMonospaced = true,
            ),
        )
    }
    add(satsRow(SendPaymentDetailKey.Amount, "Amount", quote?.amount ?: amountSats))
    add(
        SendPaymentDetailRow(
            key = SendPaymentDetailKey.NetworkFee,
            label = "Network fee",
            value = quote?.let {
                SendPaymentDetailValue.Sats(it.feeReserve, isUpperBound = true)
            } ?: SendPaymentDetailValue.Pending,
            valueMonospaced = true,
        ),
    )
    val quoteMintUrl = quote?.mintUrl?.takeIf { it.isNotBlank() }
    val mintName = if (quoteMintUrl != null) {
        mint
            ?.takeIf { sameMintUrl(it.url, quoteMintUrl) }
            ?.name
            ?.takeIf { it.isNotBlank() }
            ?: mintDisplayName(quoteMintUrl)
    } else {
        mint?.name?.takeIf { it.isNotBlank() }
    }
    if (mintName != null) {
        add(textRow(SendPaymentDetailKey.Mint, "Mint", mintName))
    }
}

private fun buildCashuRequestDetails(
    rail: LockedRail.Creq,
    route: CashuPaymentRequestRoute?,
    amountSats: Long,
    mint: MintInfo?,
    inputFeeSats: Long?,
): List<SendPaymentDetailRow> = buildList {
    add(textRow(SendPaymentDetailKey.Method, "Method", "Cashu Request"))
    add(satsRow(SendPaymentDetailKey.Amount, "Amount", amountSats))

    val networkRoute = route is CashuPaymentRequestRoute.PayBolt11Fallback ||
        route is CashuPaymentRequestRoute.AcquireThenPay
    add(
        SendPaymentDetailRow(
            key = if (networkRoute) SendPaymentDetailKey.NetworkFee else SendPaymentDetailKey.InputFee,
            label = if (networkRoute) "Network fee" else "Input fee",
            value = if (networkRoute) {
                SendPaymentDetailValue.Pending
            } else {
                inputFeeSats
                    ?.let(SendPaymentDetailValue::Sats)
                    ?: SendPaymentDetailValue.Unavailable
            },
            valueMonospaced = true,
        ),
    )

    cashuRequestMintValue(route, mint)?.let {
        add(
            SendPaymentDetailRow(
                key = SendPaymentDetailKey.Mint,
                label = "Mint",
                value = it,
            ),
        )
    }
    rail.decoded.summary.description
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
        ?.let { add(textRow(SendPaymentDetailKey.Memo, "Memo", it)) }
    cashuRequestRouteName(route)?.let {
        add(textRow(SendPaymentDetailKey.Route, "Route", it))
    }
}

private fun meltMethodName(
    rail: LockedRail.Melt,
    quote: MeltQuoteInfo?,
): String = quote?.paymentMethod?.displayName ?: when (rail.decoded) {
    is PaymentRequestDecodeResult.Bolt12 -> "BOLT12"
    is PaymentRequestDecodeResult.Onchain -> "On-chain"
    is PaymentRequestDecodeResult.Bolt11,
    is PaymentRequestDecodeResult.LightningAddress -> "BOLT11"
    is PaymentRequestDecodeResult.CashuPaymentRequest,
    PaymentRequestDecodeResult.Unrecognized -> "Payment"
}

private fun cashuRequestMintValue(
    route: CashuPaymentRequestRoute?,
    mint: MintInfo?,
): SendPaymentDetailValue? = when (route) {
    is CashuPaymentRequestRoute.PayWithEcash ->
        SendPaymentDetailValue.Text(route.mint.name)
    is CashuPaymentRequestRoute.AcquireThenPay ->
        route.targetMintUrl?.let(::mintDisplayName)?.let(SendPaymentDetailValue::Text)
    is CashuPaymentRequestRoute.PayBolt11Fallback -> SendPaymentDetailValue.Pending
    is CashuPaymentRequestRoute.UnsupportedUnit,
    CashuPaymentRequestRoute.MissingAmount,
    null -> mint?.name?.takeIf { it.isNotBlank() }?.let(SendPaymentDetailValue::Text)
}

private fun cashuRequestRouteName(route: CashuPaymentRequestRoute?): String? = when (route) {
    is CashuPaymentRequestRoute.PayBolt11Fallback -> "Lightning fallback"
    is CashuPaymentRequestRoute.AcquireThenPay ->
        if (route.addsNewMint) "Add requested mint" else "Fund target mint"
    is CashuPaymentRequestRoute.PayWithEcash,
    is CashuPaymentRequestRoute.UnsupportedUnit,
    CashuPaymentRequestRoute.MissingAmount,
    null -> null
}

private fun mintDisplayName(url: String): String =
    runCatching { URI(url).host }
        .getOrNull()
        ?.takeIf { it.isNotBlank() }
        ?: url

private fun sameMintUrl(left: String, right: String): Boolean =
    left.trim().trimEnd('/').lowercase() == right.trim().trimEnd('/').lowercase()

private fun textRow(
    key: SendPaymentDetailKey,
    label: String,
    value: String,
    valueMonospaced: Boolean = false,
) = SendPaymentDetailRow(
    key = key,
    label = label,
    value = SendPaymentDetailValue.Text(value),
    valueMonospaced = valueMonospaced,
)

private fun satsRow(
    key: SendPaymentDetailKey,
    label: String,
    value: Long,
) = SendPaymentDetailRow(
    key = key,
    label = label,
    value = SendPaymentDetailValue.Sats(value),
    valueMonospaced = true,
)
