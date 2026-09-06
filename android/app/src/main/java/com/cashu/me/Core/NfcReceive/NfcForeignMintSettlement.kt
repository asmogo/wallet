package com.cashu.me.Core.NfcReceive

import kotlinx.coroutines.delay
import com.cashu.me.Core.CDK.CdkGatewayUnavailable
import com.cashu.me.Core.CDK.ForeignNfcSettlement
import org.cashudevkit.Amount
import org.cashudevkit.CurrencyUnit
import org.cashudevkit.KeySetInfo
import org.cashudevkit.KeysetLoadPolicy
import org.cashudevkit.MeltConfirmOptions
import org.cashudevkit.PaymentMethod
import org.cashudevkit.QuoteState
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

    // Use the seed-backed repository database: CDK persists external proofs, the
    // melt saga, and returned change here. Startup recovery can then finish a
    // conversion even if the NFC session or process disappears after mint acceptance.
    repository.createWallet(org.cashudevkit.MintUrl(sourceMint), CurrencyUnit.Sat, null)
    val sourceWallet = repository.getWallet(org.cashudevkit.MintUrl(sourceMint), CurrencyUnit.Sat)
    val targetWallet = repository.getWallet(org.cashudevkit.MintUrl(targetMint), CurrencyUnit.Sat)
    val keysets = sourceWallet.keysets(KeysetLoadPolicy.REFRESH).map {
        KeySetInfo(id = it.id, unit = it.unit, active = it.active ?: false, inputFeePpk = it.inputFeePpk)
    }
    val proofs = token.proofs(keysets)
    require(proofs.isNotEmpty()) { "The foreign-mint token contains no proofs." }

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
    require(reserve <= maximumFee) { "Foreign mint fee exceeds the 5% safety limit." }

    val minimumOverhead = kotlin.math.ceil(gross * 0.005).toLong().coerceAtLeast(1L)
    val targetAmount = gross - reserve - minimumOverhead
    require(targetAmount > 0) { "Payment is too small after conversion fees." }
    val targetQuote = targetWallet.mintQuote(PaymentMethod.Bolt11, Amount(targetAmount.toULong()), null, null)
    val meltQuote = sourceWallet.meltQuote(PaymentMethod.Bolt11, targetQuote.request, null, null)
    require(meltQuote.amount.value.toLong() + meltQuote.feeReserve.value.toLong() <= gross) {
        "Foreign mint requires more ecash than was received."
    }
    val finalized = sourceWallet.prepareMeltProofs(meltQuote.id, proofs)
        .confirmWithOptions(MeltConfirmOptions(skipSwap = true))
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
        // CDK's finalized fee is the actual conversion cost.
        feePaid = finalized.feePaid.value.toLong(),
        sourceMintUrl = sourceMint,
        settlementMintUrl = targetMint,
    )
}

private fun normalizeMint(url: String): String = url.trim().trimEnd('/')
