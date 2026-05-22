package org.cashu.wallet.Core.Protocols

import java.text.NumberFormat
import java.util.Locale
import kotlin.math.pow

interface CurrencyDisplay {
    fun formatSats(amount: Long, includeUnit: Boolean = true): String
    fun formatFiat(amountSats: Long, btcPrice: Double?, currencyCode: String): String?
}

enum class CurrencySymbolPosition {
    Before,
    After,
}

data class WalletCurrency(
    val code: String,
    val symbol: String,
    val decimals: Int,
    val displayName: String,
    val symbolPosition: CurrencySymbolPosition,
)

object WalletCurrencies {
    val Satoshi = WalletCurrency(
        code = "SAT",
        symbol = "₿",
        decimals = 0,
        displayName = "Satoshis",
        symbolPosition = CurrencySymbolPosition.Before,
    )
    val Usd = WalletCurrency(
        code = "USD",
        symbol = "$",
        decimals = 2,
        displayName = "US Dollar",
        symbolPosition = CurrencySymbolPosition.Before,
    )
    val Eur = WalletCurrency(
        code = "EUR",
        symbol = "€",
        decimals = 2,
        displayName = "Euro",
        symbolPosition = CurrencySymbolPosition.Before,
    )
}

data class CurrencyAmount(
    val value: Long,
    val currency: WalletCurrency,
) {
    init {
        require(value >= 0) { "Currency amount must be non-negative." }
        require(currency.decimals >= 0) { "Currency decimals must be non-negative." }
    }

    val displayValue: Double
        get() = if (currency.decimals == 0) {
            value.toDouble()
        } else {
            value.toDouble() / 10.0.pow(currency.decimals.toDouble())
        }

    fun formatted(showSymbol: Boolean = true, locale: Locale = Locale.US): String {
        val formatter = NumberFormat.getNumberInstance(locale).apply {
            minimumFractionDigits = this@CurrencyAmount.currency.decimals
            maximumFractionDigits = this@CurrencyAmount.currency.decimals
            isGroupingUsed = true
        }
        val formattedValue = formatter.format(displayValue)
        if (!showSymbol) return formattedValue
        return when (currency.symbolPosition) {
            CurrencySymbolPosition.Before -> "${currency.symbol}$formattedValue"
            CurrencySymbolPosition.After -> "$formattedValue ${currency.code}"
        }
    }

    companion object {
        fun sats(value: Long): CurrencyAmount = CurrencyAmount(value, WalletCurrencies.Satoshi)
        fun usdCents(cents: Long): CurrencyAmount = CurrencyAmount(cents, WalletCurrencies.Usd)
        fun eurCents(cents: Long): CurrencyAmount = CurrencyAmount(cents, WalletCurrencies.Eur)
    }
}

object CurrencyRegistry {
    val supportedCurrencies: List<WalletCurrency> = listOf(
        WalletCurrencies.Satoshi,
        WalletCurrencies.Usd,
        WalletCurrencies.Eur,
    )

    fun currencyForCode(code: String): WalletCurrency? {
        val normalized = code.trim()
        return supportedCurrencies.firstOrNull { it.code.equals(normalized, ignoreCase = true) }
    }

    fun currencyForMintUnit(unit: String): WalletCurrency? {
        return when (unit.trim().lowercase()) {
            "sat", "sats", "satoshi", "satoshis" -> WalletCurrencies.Satoshi
            "usd", "dollar", "dollars" -> WalletCurrencies.Usd
            "eur", "euro", "euros" -> WalletCurrencies.Eur
            else -> null
        }
    }
}
