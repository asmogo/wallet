package com.cashu.me.Core.Protocols

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
    private val satoshiUnitNames = setOf("sat", "sats", "satoshi", "satoshis")
    private val usdUnitNames = setOf("usd", "dollar", "dollars")
    private val eurUnitNames = setOf("eur", "euro", "euros")

    val supportedCurrencies: List<WalletCurrency> = listOf(
        WalletCurrencies.Satoshi,
        WalletCurrencies.Usd,
        WalletCurrencies.Eur,
    )

    fun currencyForCode(code: String): WalletCurrency? {
        val normalized = code.trim()
        return supportedCurrencies.firstOrNull { it.code.equals(normalized, ignoreCase = true) }
    }

    /**
     * Whether a mint unit represents Bitcoin's satoshi account. History can
     * receive legacy aliases from persisted requests and tokens, so display
     * conversion must use the same classification as the currency registry.
     */
    fun isSatoshiUnit(unit: String): Boolean = normalizedMintUnit(unit) in satoshiUnitNames

    /**
     * Never null: unknown mint units resolve to a generic code-after currency
     * (0 decimals, uppercase code as the unit label), mirroring iOS
     * GenericCurrency so custom-unit mints always format.
     */
    fun currencyForMintUnit(unit: String): WalletCurrency {
        val normalized = normalizedMintUnit(unit)
        return when {
            normalized in satoshiUnitNames -> WalletCurrencies.Satoshi
            normalized in usdUnitNames -> WalletCurrencies.Usd
            normalized in eurUnitNames -> WalletCurrencies.Eur
            else -> genericCurrency(unit)
        }
    }

    private fun normalizedMintUnit(unit: String): String = unit.trim().lowercase()

    private fun genericCurrency(unit: String): WalletCurrency {
        val code = unit.trim().uppercase().ifEmpty { "SAT" }
        return WalletCurrency(
            code = code,
            symbol = "",
            decimals = 0,
            displayName = code,
            symbolPosition = CurrencySymbolPosition.After,
        )
    }
}
