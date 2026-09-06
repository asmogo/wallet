package com.cashu.me.Core.NfcReceive

import kotlinx.coroutines.delay
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import com.cashu.me.Core.CDK.CdkGatewayUnavailable
import com.cashu.me.Core.CDK.ForeignNfcSettlement
import org.cashudevkit.Amount
import org.cashudevkit.CurrencyUnit
import org.cashudevkit.MeltConfirmOptions
import org.cashudevkit.PaymentMethod
import org.cashudevkit.QuoteState
import org.cashudevkit.ReceiveOptions
import org.cashudevkit.SplitTarget
import org.cashudevkit.Token
import org.cashudevkit.WalletRepository
import org.cashudevkit.WalletSqliteDatabase
import org.cashudevkit.proofsTotalAmount

/** CDK implementation of Numo-style foreign-mint settlement. */
internal suspend fun settleForeignNfcTokenWithCdk(
    repository: WalletRepository,
    database: WalletSqliteDatabase,
    tokenString: String,
    settlementMintUrl: String,
): ForeignNfcSettlement {
    val token = Token.decode(tokenString)
    val sourceMint = normalizeMint(token.mintUrl().url)
    val targetMint = normalizeMint(settlementMintUrl)
    require(sourceMint != targetMint) { "Source and settlement mint are the same." }
    require(token.unit() == CurrencyUnit.Sat) { "Foreign-mint conversion supports sat tokens only." }
    val gross = token.value().value.toLong()
    require(gross > 1L) { "Payment is too small to convert." }

    // Secure the incoming token through CDK's receive/swap saga first. Melt
    // compensation assumes its inputs already belong to this wallet and returns
    // them to Unspent, including after a restart before confirmation.
    repository.createWallet(org.cashudevkit.MintUrl(sourceMint), CurrencyUnit.Sat, null)
    val sourceWallet = repository.getWallet(org.cashudevkit.MintUrl(sourceMint), CurrencyUnit.Sat)
    val targetWallet = repository.getWallet(org.cashudevkit.MintUrl(targetMint), CurrencyUnit.Sat)
    val received = sourceWallet.receive(
        token,
        ReceiveOptions(SplitTarget.None, emptyList(), emptyList(), emptyMap()),
    ).value.toLong()
    val receiveFee = gross - received

    val existingTransactionIds = targetWallet.listTransactions(org.cashudevkit.TransactionDirection.INCOMING)
        .map { it.id.hex }
        .toSet()
    val maximumFee = kotlin.math.ceil(gross * 0.05).toLong().coerceAtLeast(1L)
    val estimateAmount = gross - maximumFee
    require(estimateAmount > 0) { "Payment is too small after the conversion fee limit." }

    val estimateQuote = targetWallet.mintQuote(PaymentMethod.Bolt11, Amount(estimateAmount.toULong()), null, null)
    val estimateMelt = sourceWallet.meltQuote(PaymentMethod.Bolt11, estimateQuote.request, null, null)
    val reserve = estimateMelt.feeReserve.value.toLong()
    runCatching { database.removeMintQuote(estimateQuote.id) }
    require(receiveFee + reserve <= maximumFee) { "Foreign mint fee exceeds the 5% safety limit. Received funds remain at the source mint." }

    val minimumOverhead = kotlin.math.ceil(gross * 0.005).toLong().coerceAtLeast(1L)
    val targetAmount = received - reserve - minimumOverhead
    require(targetAmount > 0) { "Payment is too small after conversion fees." }
    val targetQuote = targetWallet.mintQuote(PaymentMethod.Bolt11, Amount(targetAmount.toULong()), null, null)
    val meltQuote = sourceWallet.meltQuote(PaymentMethod.Bolt11, targetQuote.request, null, null)
    require(meltQuote.amount.value.toLong() + meltQuote.feeReserve.value.toLong() <= received) {
        "Foreign mint requires more ecash than was received."
    }
    val prepared = sourceWallet.prepareMelt(meltQuote.id)
    // Selection may include larger proofs from an existing source balance. Its
    // change is retained, but this receipt must cover all of the actual costs.
    val feeBudget = minOf(received - meltQuote.amount.value.toLong(), maximumFee - receiveFee)
    val reserveCost = meltQuote.feeReserve.value
    if (feeBudget < 0 || reserveCost > feeBudget.toULong() ||
        prepared.inputFeeWithoutSwap().value > feeBudget.toULong() - reserveCost
    ) {
        withContext(NonCancellable) { prepared.cancel() }
        throw CdkGatewayUnavailable("Foreign mint fee exceeds the conversion budget. Received funds remain at the source mint.")
    }
    val finalized = prepared.confirmWithOptions(MeltConfirmOptions(skipSwap = true))
    require(finalized.state == QuoteState.PAID) { "Foreign mint did not settle the payment." }

    var checked = targetWallet.checkMintQuote(targetQuote.id)
    for (attempt in 0 until 20) {
        if (checked.state == QuoteState.PAID || checked.state == QuoteState.ISSUED) break
        delay(500)
        checked = targetWallet.checkMintQuote(targetQuote.id)
    }
    val credited = when (checked.state) {
        QuoteState.PAID -> proofsTotalAmount(
            targetWallet.mintUnified(targetQuote.id, SplitTarget.None, null),
        ).value.toLong()
        QuoteState.ISSUED -> targetAmount
        else -> throw CdkGatewayUnavailable("Settlement mint has not credited the paid quote yet.")
    }
    val transactionId = targetWallet.listTransactions(org.cashudevkit.TransactionDirection.INCOMING)
        .firstOrNull { it.id.hex !in existingTransactionIds && it.quoteId == targetQuote.id }
        ?.id?.hex
        ?: throw CdkGatewayUnavailable("CDK did not record the NFC settlement transaction.")
    return ForeignNfcSettlement(
        amountReceived = credited,
        transactionId = transactionId,
        // The difference also includes change kept at the source mint.
        // Include the receive swap as well as the melt's actual cost.
        feePaid = receiveFee + finalized.feePaid.value.toLong(),
        sourceMintUrl = sourceMint,
        settlementMintUrl = targetMint,
    )
}

private fun normalizeMint(url: String): String = url.trim().trimEnd('/')
