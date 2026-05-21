package org.cashu.wallet.Core

import java.text.NumberFormat
import java.util.Locale
import org.cashu.wallet.Core.Protocols.CurrencyDisplay

class AmountFormatter(
    private val locale: Locale = Locale.getDefault(),
) : CurrencyDisplay {
    override fun formatSats(amount: Long, includeUnit: Boolean): String {
        return formatSatsValue(amount, includeUnit = includeUnit, useBitcoinSymbol = false)
    }

    fun formatSats(amount: Long, includeUnit: Boolean = true, useBitcoinSymbol: Boolean): String {
        return formatWalletSats(amount, useBitcoinSymbol = useBitcoinSymbol, includeUnit = includeUnit)
    }

    fun formatWalletSats(amount: Long, useBitcoinSymbol: Boolean, includeUnit: Boolean = true): String {
        return formatSatsValue(amount, includeUnit = includeUnit, useBitcoinSymbol = useBitcoinSymbol)
    }

    private fun formatSatsValue(amount: Long, includeUnit: Boolean, useBitcoinSymbol: Boolean): String {
        val formatted = NumberFormat.getIntegerInstance(locale).format(amount)
        return if (useBitcoinSymbol) {
            "₿$formatted"
        } else if (includeUnit) {
            "$formatted sat"
        } else {
            formatted
        }
    }

    fun formatBitcoin(amountSats: Long, useBitcoinSymbol: Boolean): String {
        val btc = amountSats.toDouble() / 100_000_000.0
        val symbol = if (useBitcoinSymbol) "₿" else "BTC"
        return "%,.8f %s".format(locale, btc, symbol)
    }

    override fun formatFiat(amountSats: Long, btcPrice: Double?, currencyCode: String): String? {
        val price = btcPrice ?: return null
        val fiat = amountSats.toDouble() / 100_000_000.0 * price
        val format = NumberFormat.getCurrencyInstance(locale)
        runCatching { format.currency = java.util.Currency.getInstance(currencyCode) }
        return format.format(fiat)
    }

    fun compactSats(amount: Long): String = when {
        amount >= 1_000_000 -> "${amount / 1_000_000}M sat"
        amount >= 1_000 -> "${amount / 1_000}k sat"
        else -> formatSats(amount)
    }
}

enum class AmountDisplayPrimary(val rawValue: String, val label: String) {
    Fiat("fiat", "Fiat"),
    Sats("sats", "Sats");

    companion object {
        fun fromRaw(value: String?): AmountDisplayPrimary {
            val normalized = value?.trim().orEmpty()
            return entries.firstOrNull { it.rawValue.equals(normalized, ignoreCase = true) } ?: Fiat
        }
    }
}

data class AmountDisplayText(
    val primary: String,
    val secondary: String?,
    val effectivePrimary: AmountDisplayPrimary,
)

fun AmountFormatter.displayText(
    amountSats: Long,
    preferredPrimary: String,
    showFiat: Boolean,
    btcPrice: Double?,
    currencyCode: String,
    useBitcoinSymbol: Boolean,
): AmountDisplayText {
    val fiatText = if (showFiat) formatFiat(amountSats, btcPrice?.takeIf { it > 0 }, currencyCode) else null
    val satsText = formatWalletSats(amountSats, useBitcoinSymbol = useBitcoinSymbol)
    val preferred = AmountDisplayPrimary.fromRaw(preferredPrimary)
    val effective = if (preferred == AmountDisplayPrimary.Fiat && fiatText == null) {
        AmountDisplayPrimary.Sats
    } else {
        preferred
    }
    return when (effective) {
        AmountDisplayPrimary.Fiat -> AmountDisplayText(
            primary = fiatText ?: satsText,
            secondary = satsText,
            effectivePrimary = effective,
        )
        AmountDisplayPrimary.Sats -> AmountDisplayText(
            primary = satsText,
            secondary = fiatText,
            effectivePrimary = effective,
        )
    }
}
