package com.cashu.me.Core

import java.text.DecimalFormatSymbols
import java.text.NumberFormat
import java.util.Locale
import com.cashu.me.Core.Protocols.CurrencyDisplay
import com.cashu.me.Core.Protocols.CurrencyAmount
import com.cashu.me.Core.Protocols.CurrencyRegistry

class AmountFormatter(
    private val locale: Locale = Locale.getDefault(),
) : CurrencyDisplay {
    /**
     * The locale's decimal separator ("." or ","), used as the keypad's decimal
     * key label and when rendering a partially typed amount. Raw entry strings
     * are always canonical — see [UnitAmountEntry.SEPARATOR].
     */
    val decimalSeparator: String = decimalSeparator(locale)

    override fun formatSats(amount: Long, includeUnit: Boolean): String {
        return formatSatsValue(amount, includeUnit = includeUnit, useBitcoinSymbol = false)
    }

    fun formatSats(amount: Long, includeUnit: Boolean = true, useBitcoinSymbol: Boolean): String {
        return formatWalletSats(amount, useBitcoinSymbol = useBitcoinSymbol, includeUnit = includeUnit)
    }

    fun formatWalletSats(amount: Long, useBitcoinSymbol: Boolean, includeUnit: Boolean = true): String {
        return formatSatsValue(amount, includeUnit = includeUnit, useBitcoinSymbol = useBitcoinSymbol)
    }

    /**
     * Sats decomposed for typesetting — the canonical source, of which
     * [formatSatsValue] is just the joined form.
     */
    fun satsParts(amount: Long, useBitcoinSymbol: Boolean): AmountParts = AmountParts(
        value = NumberFormat.getIntegerInstance(locale).format(amount),
        affix = if (useBitcoinSymbol) {
            AmountParts.Affix.Prefix("₿")
        } else {
            AmountParts.Affix.Suffix("sat")
        },
    )

    /**
     * @param includeUnit suppresses the trailing `sat` **word** only. In symbol
     *   mode the `₿` prefix *is* the unit and is kept either way, so a caller
     *   appending its own suffix never renders a doubled unit. Deliberate
     *   contract, mirrored on iOS and pinned by `AmountFormatterTest`.
     */
    private fun formatSatsValue(amount: Long, includeUnit: Boolean, useBitcoinSymbol: Boolean): String {
        val parts = satsParts(amount, useBitcoinSymbol)
        return if (parts.affix is AmountParts.Affix.Suffix && !includeUnit) parts.value else parts.joined
    }

    /** Where this currency's symbol sits, and what it is. */
    fun currencyAffix(currencyCode: String): AmountParts.Affix {
        val format = NumberFormat.getCurrencyInstance(Locale.US).apply {
            runCatching { currency = java.util.Currency.getInstance(currencyCode.uppercase()) }
        }
        val decimalFormat = format as? java.text.DecimalFormat
        val prefix = decimalFormat?.positivePrefix?.trim().orEmpty()
        val suffix = decimalFormat?.positiveSuffix?.trim().orEmpty()
        return when {
            prefix.isNotEmpty() -> AmountParts.Affix.Prefix(prefix)
            suffix.isNotEmpty() -> AmountParts.Affix.Suffix(suffix)
            else -> AmountParts.Affix.None
        }
    }

    /**
     * Converted fiat decomposed for typesetting. Null on the same terms as
     * [formatFiat] — no price, or a sub-cent dust result.
     *
     * Kept alongside [formatFiat] rather than replacing it: a trailing currency
     * symbol joins tight while a unit *word* joins with a space, and collapsing
     * both into [AmountParts.joined] would quietly change the rendered string
     * for some currency codes. `fiatPartsJoinMatchesFormatFiat` asserts the two
     * agree across every currency the app offers.
     */
    fun fiatParts(amountSats: Long, btcPrice: Double?, currencyCode: String): AmountParts? {
        val price = btcPrice ?: return null
        val fiat = amountSats.toDouble() / 100_000_000.0 * price
        if (fiat < 0.01) return null
        val affix = currencyAffix(currencyCode)
        val format = NumberFormat.getCurrencyInstance(Locale.US).apply {
            minimumFractionDigits = 2
            maximumFractionDigits = 2
            runCatching { currency = java.util.Currency.getInstance(currencyCode.uppercase()) }
        }
        (format as? java.text.DecimalFormat)?.apply {
            positivePrefix = ""
            positiveSuffix = ""
        }
        return AmountParts(value = format.format(fiat), affix = affix)
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
    ): String = entryParts(raw, isSat, unit, useBitcoinSymbol).joined

    /** The live entry hero, decomposed for typesetting. */
    fun entryParts(
        raw: String,
        isSat: Boolean,
        unit: String,
        useBitcoinSymbol: Boolean,
    ): AmountParts {
        if (isSat) return satsParts(raw.toLongOrNull() ?: 0L, useBitcoinSymbol = useBitcoinSymbol)
        return AmountParts(
            value = partialNumber(raw),
            affix = AmountParts.Affix.Suffix(unit.uppercase()),
        )
    }

    /**
     * The numerals of a partially typed amount, grouped but unwrapped.
     * Partial-aware: a trailing separator and trailing zeroes render exactly as
     * typed, so the hero doesn't jump while the user is still keying.
     *
     * Raw always carries the canonical [UnitAmountEntry.SEPARATOR]; the locale's
     * separator is applied here, at display time. Reading and writing the same
     * character would collide on comma-decimal locales, where the integer
     * grouping of 1234 is itself "1.234".
     */
    private fun partialNumber(raw: String): String {
        val parts = raw.split(UnitAmountEntry.SEPARATOR)
        val intValue = parts.getOrNull(0)?.toLongOrNull() ?: 0L
        val grouped = NumberFormat.getIntegerInstance(locale).format(intValue)
        if (!raw.contains(UnitAmountEntry.SEPARATOR)) return grouped
        return grouped + decimalSeparator + parts.getOrNull(1).orEmpty()
    }

    /**
     * Partial-aware fiat entry presentation. The keypad owns the decimal
     * fraction, so keep its trailing zeroes while applying the saved currency's
     * canonical symbol and integer grouping.
     */
    fun entryFiatDisplay(raw: String, currencyCode: String): String {
        val parts = entryFiatParts(raw, currencyCode)
        // A currency symbol tucks tight on both sides, unlike a unit word.
        return when (val affix = parts.affix) {
            is AmountParts.Affix.None -> parts.value
            is AmountParts.Affix.Prefix -> affix.symbol + parts.value
            is AmountParts.Affix.Suffix -> parts.value + affix.word
        }
    }

    /** The live fiat entry hero, decomposed for typesetting. */
    fun entryFiatParts(raw: String, currencyCode: String): AmountParts = AmountParts(
        value = partialNumber(raw),
        affix = currencyAffix(currencyCode),
    )

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

    companion object {
        /**
         * The decimal separator to *show* for a locale. The keypad labels its
         * decimal key with this; raw entry strings stay canonical.
         */
        fun decimalSeparator(locale: Locale = Locale.getDefault()): String =
            DecimalFormatSymbols.getInstance(locale).decimalSeparator.toString()
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
    /**
     * [primary] decomposed, so a hero can subordinate the unit rather than
     * setting it at the same size, weight and ink as the digits.
     *
     * Defaults to parsing [primary] rather than to null: a hand-constructed
     * value would otherwise render its unit full-size while every amount built
     * through the formatter subordinated it, and that inconsistency would be
     * invisible until someone noticed one screen looked wrong. Producers that
     * know the unit should still pass it explicitly.
     */
    val primaryParts: AmountParts = AmountParts.parse(primary),
)

/**
 * A money value decomposed into its numerals and its unit.
 *
 * The unit is deliberately *not* joined into the numeral string, because a
 * joined string cannot be typeset: the unit ends up at the same size, weight
 * and ink as the digits, occupying roughly a third of the lockup while carrying
 * none of the information. `AmountHero` composes the two runs with the unit
 * subordinated; see DESIGN-ANDROID.md.
 *
 * [joined] reproduces exactly what the string API returns, which is what lets
 * the split be verified against the existing formatter tests rather than
 * trusted.
 */
data class AmountParts(val value: String, val affix: Affix) {

    /**
     * Where the unit sits, and — because the two coincide throughout this app —
     * what *kind* of unit it is. A prefix is always a symbol (`₿`, `$`) and a
     * suffix is always a word (`sat`, `USD`), and the two want opposite
     * typographic treatment: a symbol stays at full ink tucked tight to the
     * digits, a word steps down in size, weight and ink.
     */
    sealed interface Affix {
        data object None : Affix
        data class Prefix(val symbol: String) : Affix
        data class Suffix(val word: String) : Affix
    }

    val joined: String
        get() = when (affix) {
            is Affix.None -> value
            is Affix.Prefix -> affix.symbol + value
            is Affix.Suffix -> "$value ${affix.word}"
        }

    /**
     * TalkBack form. Never reads a bare `₿`, which announces as nothing useful;
     * the symbol is a visual shorthand for the word.
     */
    val spoken: String
        get() = when (affix) {
            is Affix.None -> value
            is Affix.Prefix -> if (affix.symbol == "₿") "$value sats" else "${affix.symbol}$value"
            is Affix.Suffix -> "$value ${affix.word}"
        }

    companion object {
        /**
         * Recovers the split from an already-joined string.
         *
         * A compatibility shim, not the preferred path — producers that know
         * the unit should say so structurally. It exists because
         * [AmountDisplayText] can be constructed by hand (mint-unit amounts,
         * previews, tests), and without it those values would silently render
         * with the unit at full size and ink while every other amount in the
         * app was subordinating it. A quiet inconsistency is worse than a
         * conservative parse.
         *
         * Deliberately conservative: a trailing space-delimited run with no
         * digits is a unit word, a leading run of non-digits that isn't just a
         * sign is a symbol, and anything else is left whole.
         */
        fun parse(joined: String): AmountParts {
            val space = joined.lastIndexOf(' ')
            if (space > 0 && space < joined.lastIndex) {
                val tail = joined.substring(space + 1)
                if (tail.none { it.isDigit() }) {
                    return AmountParts(joined.substring(0, space), Affix.Suffix(tail))
                }
            }
            val lead = joined.takeWhile { !it.isDigit() }
            if (lead.isNotEmpty() && lead.any { it != '-' && it != '+' && it != ' ' }) {
                return AmountParts(joined.removePrefix(lead), Affix.Prefix(lead))
            }
            return AmountParts(joined, Affix.None)
        }
    }
}

fun AmountFormatter.displayText(
    amountSats: Long,
    preferredPrimary: String,
    showFiat: Boolean,
    btcPrice: Double?,
    currencyCode: String,
    useBitcoinSymbol: Boolean,
): AmountDisplayText {
    val price = btcPrice?.takeIf { it > 0 }
    val fiat = if (showFiat) fiatParts(amountSats, price, currencyCode) else null
    val fiatText = fiat?.joined
    val sats = satsParts(amountSats, useBitcoinSymbol = useBitcoinSymbol)
    val satsText = sats.joined
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
            primaryParts = fiat ?: sats,
        )
        AmountDisplayPrimary.Sats -> AmountDisplayText(
            primary = satsText,
            secondary = fiatText,
            effectivePrimary = effective,
            primaryParts = sats,
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
    if (CurrencyRegistry.isSatoshiUnit(unit)) {
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
