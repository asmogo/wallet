package org.cashu.wallet.Core.Protocols

interface CurrencyDisplay {
    fun formatSats(amount: Long, includeUnit: Boolean = true): String
    fun formatFiat(amountSats: Long, btcPrice: Double?, currencyCode: String): String?
}
