package com.cashu.me.Core

import java.text.NumberFormat
import java.util.Locale
import com.cashu.me.Core.Protocols.CurrencyDisplay
import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry

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

    /**
     * Inline display string for a *live* amount-entry hero — the unit is baked
     * into the number (`₿1,234` / `1,234 sat`) exactly like iOS
     * `AmountFormatter.entryPrimary`, so entry screens need no separate unit
     * caption. Sats parse-then-format (which adds grouping); non-sat units keep
     * the typed fraction verbatim and append the unit code.
     */
    fun entryDisplay(
        raw: String,
        isSat: Boolean,
        unit: String,
        useBitcoinSymbol: Boolean,
    ): String {
        if (isSat) {
            return formatWalletSats(raw.toLongOrNull() ?: 0L, useBitcoinSymbol = useBitcoinSymbol)
        }
        val sep = "."
        val parts = raw.split(sep)
        val intValue = parts.getOrNull(0)?.toLongOrNull() ?: 0L
        val grouped = NumberFormat.getIntegerInstance(locale).format(intValue)
        val number = if (raw.contains(sep)) grouped + sep + parts.getOrNull(1).orEmpty() else grouped
        return "$number ${unit.uppercase()}"
    }

    /**
     * Partial-aware fiat entry presentation. The keypad owns the decimal
     * fraction, so keep its trailing zeroes while applying the saved currency's
     * canonical symbol and integer grouping.
     */
    fun entryFiatDisplay(raw: String, currencyCode: String): String {
        val parts = raw.split(".")
        val intValue = parts.getOrNull(0)?.toLongOrNull() ?: 0L
        val grouped = NumberFormat.getIntegerInstance(locale).format(intValue)
        val number = if (raw.contains(".")) {
            "$grouped.${parts.getOrNull(1).orEmpty()}"
        } else {
            grouped
        }
        val format = NumberFormat.getCurrencyInstance(Locale.US).apply {
            runCatching { currency = java.util.Currency.getInstance(currencyCode.uppercase()) }
        }
        val decimalFormat = format as? java.text.DecimalFormat
        val prefix = decimalFormat?.positivePrefix?.trim().orEmpty()
        val suffix = decimalFormat?.positiveSuffix?.trim().orEmpty()
        return "$prefix$number$suffix"
    }

    fun formatBitcoin(amountSats: Long, useBitcoinSymbol: Boolean): String {
        val btc = amountSats.toDouble() / 100_000_000.0
        val symbol = if (useBitcoinSymbol) "₿" else "BTC"
        return "%,.8f %s".format(locale, btc, symbol)
    }

    override fun formatFiat(amountSats: Long, btcPrice: Double?, currencyCode: String): String? {
        val price = btcPrice ?: return null
        val fiat = amountSats.toDouble() / 100_000_000.0 * price
        // Sub-cent conversions are never displayed — dust would render as a
        // misleading "$0.00". Mirrors iOS AmountFormatter.fiat(sats:btcPrice:).
        if (fiat < 0.01) return null
        // Wallet amounts use one stable currency presentation regardless of the
        // device locale. In particular, USD must be "$60.00", not "US$60.00"
        // or "60.00 $" on devices whose locale is outside the US.
        val format = NumberFormat.getCurrencyInstance(Locale.US).apply {
            minimumFractionDigits = 2
            maximumFractionDigits = 2
        }
        runCatching { format.currency = java.util.Currency.getInstance(currencyCode.uppercase()) }
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

/** Format an amount in its native mint unit; BTC-price conversion only applies to sats. */
fun AmountFormatter.displayMintUnitAmount(
    amount: Long,
    unit: String,
    preferredPrimary: String,
    showFiat: Boolean,
    btcPrice: Double?,
    currencyCode: String,
    useBitcoinSymbol: Boolean,
): AmountDisplayText {
    if (unit.equals("sat", ignoreCase = true)) {
        return displayText(
            amountSats = amount,
            preferredPrimary = preferredPrimary,
            showFiat = showFiat,
            btcPrice = btcPrice,
            currencyCode = currencyCode,
            useBitcoinSymbol = useBitcoinSymbol,
        )
    }
    return AmountDisplayText(
        primary = CurrencyAmount(amount, CurrencyRegistry.currencyForMintUnit(unit)).formatted(),
        secondary = null,
        effectivePrimary = AmountDisplayPrimary.Sats,
    )
}
