package com.cashu.me.Core

/**
 * Unit-native amount entry (port of the iOS AmountFormatter entry helpers).
 *
 * The keypad types left-to-right like a normal number: digits build the integer
 * part ("2" → "21") and the decimal key arms the fraction ("21." → "21.50"). A
 * raw string therefore means exactly what it reads — "21" is twenty-one whole
 * units, never twenty-one minor units. Units with `decimals == 0` render no
 * decimal key at all, so their raw stays a plain integer.
 *
 * Grammar (the separator is always "."; display localizes it):
 *
 *     raw  := "" | INT | INT "." | INT "." FRAC
 *     INT  := "0" | [1-9][0-9]{0,11}
 *     FRAC := [0-9]{0,decimals}
 *
 * The trailing "." *is* the "fraction armed" state, so a screen needs no extra
 * flag beyond the raw String it already holds.
 */
object UnitAmountEntry {
    /** Canonical separator inside a raw entry string. */
    const val SEPARATOR = "."

    /** Ceiling on the integer part, so a held key can't run past sane bounds. */
    private const val MAX_INTEGER_DIGITS = 12

    /** Keeps `10^(MAX_INTEGER_DIGITS + decimals)` inside Long for any unit. */
    private const val MAX_DECIMALS = 6

    /** Parse the raw entry string into base (minor) units. "5" @2 → 500. */
    fun baseUnits(raw: String, decimals: Int): Long {
        if (raw.isBlank()) return 0
        val d = clampDecimals(decimals)
        val max = maxBaseUnits(d)
        val separator = raw.indexOf(SEPARATOR)
        val wholeDigits = (if (separator < 0) raw else raw.substring(0, separator))
            .filter(Char::isDigit)
            .trimStart('0')
        // A raw longer than the grammar allows can only arrive pre-seeded; clamp
        // rather than letting toLongOrNull() fail into a silent zero.
        if (wholeDigits.length > MAX_INTEGER_DIGITS) return max
        val whole = wholeDigits.toLongOrNull() ?: 0L
        if (d <= 0) return whole.coerceAtMost(max)

        val fraction = (if (separator < 0) "" else raw.substring(separator + 1))
            .filter(Char::isDigit)
            .padEnd(d, '0')
            .take(d)
        val scale = pow10(d)
        return (whole * scale + (fraction.toLongOrNull() ?: 0L)).coerceAtMost(max)
    }

    /** Append one keypad digit, returning the new raw entry string. */
    fun append(key: String, raw: String, decimals: Int): String {
        val digit = key.singleOrNull()?.takeIf(Char::isDigit) ?: return raw
        val separator = raw.indexOf(SEPARATOR)
        if (separator >= 0) {
            // Fraction armed: fill it to `decimals` digits, then stop.
            if (raw.length - separator - 1 >= clampDecimals(decimals)) return raw
            return raw + digit
        }
        // Integer part: a lone leading zero is replaced, never extended.
        if (raw.isEmpty() || raw == "0") return digit.toString()
        if (raw.length >= MAX_INTEGER_DIGITS) return raw
        return raw + digit
    }

    /**
     * Arm the fraction. Inert for 0-decimal units (which show no decimal key)
     * and for a raw that already carries a separator; on an empty pad it opens
     * with a leading zero so "." "5" reads as "0.5".
     */
    fun appendSeparator(raw: String, decimals: Int): String {
        if (clampDecimals(decimals) <= 0) return raw
        if (raw.contains(SEPARATOR)) return raw
        if (raw.isEmpty()) return "0$SEPARATOR"
        return raw + SEPARATOR
    }

    /**
     * Remove the last keypad input. A plain character drop, so the separator
     * falls off in its turn: "21.5" → "21." → "21" → "2" → "".
     */
    fun backspace(raw: String): String = raw.dropLast(1)

    /**
     * Render base units as the raw entry string — the inverse of [baseUnits],
     * in minimal form so a seeded whole amount looks like something the user
     * could have typed: 600 @2 → "6", 610 @2 → "6.10", 0 → "".
     */
    fun entryString(baseUnits: Long, decimals: Int): String {
        if (baseUnits <= 0) return ""
        val d = clampDecimals(decimals)
        if (d <= 0) return baseUnits.toString()
        val scale = pow10(d)
        val whole = baseUnits / scale
        val fraction = baseUnits % scale
        if (fraction == 0L) return whole.toString()
        return "$whole$SEPARATOR${fraction.toString().padStart(d, '0')}"
    }

    /** The largest amount the grammar can express for a unit: 12 integer digits. */
    fun maxBaseUnits(decimals: Int): Long = pow10(MAX_INTEGER_DIGITS + clampDecimals(decimals)) - 1

    private fun clampDecimals(decimals: Int): Int = decimals.coerceIn(0, MAX_DECIMALS)

    private fun pow10(exponent: Int): Long {
        var value = 1L
        repeat(exponent) { value *= 10 }
        return value
    }
}
