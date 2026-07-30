package com.cashu.me.ui.send

import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry
import com.cashu.me.Core.shortenMintUrl

internal data class SendEcashReceiptDetails(
    val amount: String,
    val fee: String?,
    val mint: String,
)

internal fun buildSendEcashReceiptDetails(
    amountLabel: String,
    fee: Long,
    unit: String,
    mintUrl: String,
): SendEcashReceiptDetails = SendEcashReceiptDetails(
    amount = amountLabel,
    fee = formatSendEcashFee(fee, unit),
    mint = shortenMintUrl(mintUrl),
)

internal fun formatSendEcashFee(fee: Long, unit: String): String? =
    fee.takeIf { it > 0L }?.let { nonzeroFee ->
        if (unit.equals("sat", ignoreCase = true)) {
            "$nonzeroFee sat"
        } else {
            CurrencyAmount(
                nonzeroFee,
                CurrencyRegistry.currencyForMintUnit(unit),
            ).formatted()
        }
    }
