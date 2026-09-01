import Foundation

struct AmountDisplayText {
    let primary: String
    let secondary: String?
    let effectivePrimary: AmountDisplayPrimary

    /// [primary] decomposed, so a hero can subordinate the unit rather than
    /// setting it at the same size, weight and ink as the digits.
    var primaryParts: AmountParts { AmountParts.parse(primary) }
}

/// A money value decomposed into its numerals and its unit.
///
/// The unit is deliberately *not* joined into the numeral string, because a
/// joined string cannot be typeset: the unit ends up at the same size, weight
/// and ink as the digits, occupying about a third of the lockup while carrying
/// none of the information. `AmountLockup` composes the two runs with the unit
/// subordinated; see DESIGN.md, The Lockup Rule.
///
/// [joined] reproduces exactly what the string API returns, which is what lets
/// the split be verified against the existing formatter tests rather than
/// trusted.
struct AmountParts: Equatable {

    /// Where the unit sits, and — because the two coincide throughout this app
    /// — what *kind* of unit it is. A prefix is always a symbol (`₿`, `$`) and a
    /// suffix is always a word (`sat`, `USD`), and the two want opposite
    /// typographic treatment: a symbol stays at full ink tucked tight to the
    /// digits, a word steps down in size, weight and ink.
    enum Affix: Equatable {
        case none
        case prefix(String)
        case suffix(String)
    }

    var value: String
    var affix: Affix

    var joined: String {
        switch affix {
        case .none: value
        case .prefix(let symbol): symbol + value
        case .suffix(let word): value + " " + word
        }
    }

    /// Recovers the split from an already-joined string.
    ///
    /// A compatibility shim, not the preferred path — producers that know the
    /// unit should say so structurally. It exists because some amount strings
    /// arrive already assembled (converted fiat from `PriceService`, mint-unit
    /// amounts from `CurrencyAmount`), and without it those would render with
    /// the unit at full size and ink while every other amount in the app
    /// subordinated it. A quiet inconsistency is worse than a conservative parse.
    ///
    /// Deliberately conservative: a trailing space-delimited run with no digits
    /// is a unit word, a leading run of non-digits that isn't merely a sign is a
    /// symbol, and anything else is left whole.
    static func parse(_ joined: String) -> AmountParts {
        if let space = joined.lastIndex(of: " "), space < joined.index(before: joined.endIndex) {
            let tail = String(joined[joined.index(after: space)...])
            if !tail.contains(where: \.isNumber) {
                return AmountParts(value: String(joined[..<space]), affix: .suffix(tail))
            }
        }
        let lead = String(joined.prefix { !$0.isNumber })
        if !lead.isEmpty, lead.contains(where: { $0 != "-" && $0 != "+" && $0 != " " }) {
            return AmountParts(value: String(joined.dropFirst(lead.count)), affix: .prefix(lead))
        }
        return AmountParts(value: joined, affix: .none)
    }

    /// VoiceOver form. Never reads a bare `₿`, which announces as nothing
    /// useful; the symbol is a visual shorthand for the word.
    var spoken: String {
        switch affix {
        case .none: value
        case .prefix("₿"): "\(value) sats"
        case .prefix(let symbol): "\(symbol)\(value)"
        case .suffix(let word): "\(value) \(word)"
        }
    }
}

enum AmountFormatter {
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter
    }()

    /// Sats decomposed for typesetting. The canonical source; `sats(_:…)` is
    /// this joined back up.
    static func satsParts(_ sats: UInt64, useBitcoinSymbol: Bool) -> AmountParts {
        let formatted = decimalFormatter.string(from: NSNumber(value: sats)) ?? "\(sats)"
        return AmountParts(
            value: formatted,
            affix: useBitcoinSymbol ? .prefix("₿") : .suffix("sat")
        )
    }

    /// - Parameter includeUnit: suppresses the trailing `sat` **word** only.
    ///   The `₿` prefix is the unit in symbol mode and is kept either way, so a
    ///   caller appending its own suffix never renders a doubled unit. This is
    ///   a deliberate contract, pinned by `testNoUnitBitcoinSymbolMode`.
    static func sats(_ sats: UInt64, useBitcoinSymbol: Bool, includeUnit: Bool = true) -> String {
        let parts = satsParts(sats, useBitcoinSymbol: useBitcoinSymbol)
        switch parts.affix {
        case .suffix where !includeUnit:
            return parts.value
        default:
            return parts.joined
        }
    }

    /// Canonical fiat presentation for wallet amounts. A fixed POSIX/US
    /// presentation keeps the ISO currency's symbol and placement stable across
    /// device locales (USD is always "$60.00", never "US$60.00" or "60.00 $").
    static func fiat(_ amount: Double, currencyCode: String) -> String {
        let formatter = currencyFormatter(currencyCode: currencyCode)
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }

    /// Fiat decomposed for typesetting.
    ///
    /// Kept alongside `fiat(_:currencyCode:)` rather than replacing it: a
    /// currency whose symbol trails the number joins without a space, while a
    /// unit *word* like `sat` joins with one, and collapsing both conventions
    /// into `AmountParts.joined` would quietly change the rendered string for
    /// some currency codes. `testFiatPartsJoinMatchesFiat` asserts the two
    /// agree for every currency the app offers, so a divergence fails a test
    /// rather than shipping.
    static func fiatParts(_ amount: Double, currencyCode: String) -> AmountParts {
        let formatter = currencyFormatter(currencyCode: currencyCode)
        let affix = currencyAffix(currencyCode: currencyCode)
        formatter.positivePrefix = ""
        formatter.positiveSuffix = ""
        let number = formatter.string(from: NSNumber(value: amount))
            ?? String(format: "%.2f", amount)
        return AmountParts(value: number, affix: affix)
    }

    /// Where this currency's symbol sits, and what it is.
    static func currencyAffix(currencyCode: String) -> AmountParts.Affix {
        let formatter = currencyFormatter(currencyCode: currencyCode)
        if let prefix = formatter.positivePrefix, !prefix.isEmpty {
            return .prefix(prefix)
        }
        if let suffix = formatter.positiveSuffix, !suffix.isEmpty {
            return .suffix(suffix)
        }
        return .none
    }

    /// Converts sats at the supplied BTC price and formats the selected fiat
    /// currency. A missing/non-positive price produces no conversion, and
    /// neither does a sub-cent result — dust would render as a misleading
    /// "$0.00", so anything under one cent is hidden instead.
    static func fiat(sats: UInt64, btcPrice: Double?, currencyCode: String) -> String? {
        guard let btcPrice, btcPrice > 0 else { return nil }
        let value = Double(sats) / 100_000_000.0 * btcPrice
        guard value >= 0.01 else { return nil }
        return fiat(value, currencyCode: currencyCode)
    }

    /// The single source of truth for primary/secondary wallet amount ordering.
    /// Fiat preference falls back to sats until a live/cached price is available.
    static func displayText(
        amountSats: UInt64,
        preferredPrimary: AmountDisplayPrimary,
        showFiat: Bool,
        btcPrice: Double?,
        currencyCode: String,
        useBitcoinSymbol: Bool
    ) -> AmountDisplayText {
        let fiatText = showFiat
            ? fiat(sats: amountSats, btcPrice: btcPrice, currencyCode: currencyCode)
            : nil
        let satsText = sats(amountSats, useBitcoinSymbol: useBitcoinSymbol)
        let effectivePrimary: AmountDisplayPrimary =
            preferredPrimary == .fiat && fiatText == nil ? .sats : preferredPrimary

        switch effectivePrimary {
        case .fiat:
            return AmountDisplayText(primary: fiatText ?? satsText, secondary: satsText, effectivePrimary: effectivePrimary)
        case .sats:
            return AmountDisplayText(primary: satsText, secondary: fiatText, effectivePrimary: effectivePrimary)
        }
    }

    /// Formats an amount in its native mint unit. Bitcoin-denominated aliases
    /// share the Home balance's sats/fiat ordering; fiat and custom mint units
    /// remain in their native denomination because a BTC spot price cannot
    /// convert them correctly. A positive sub-cent Bitcoin amount uses a
    /// "less than one cent" label so a fiat preference never silently flips
    /// an individual transaction back to sats.
    static func displayMintUnitAmount(
        amount: UInt64,
        unit: String,
        preferredPrimary: AmountDisplayPrimary,
        showFiat: Bool,
        btcPrice: Double?,
        currencyCode: String,
        useBitcoinSymbol: Bool
    ) -> AmountDisplayText {
        guard CurrencyRegistry.isSatoshiUnit(unit) else {
            return AmountDisplayText(
                primary: CurrencyAmount(
                    value: amount,
                    currency: CurrencyRegistry.currency(forMintUnit: unit)
                ).formatted(),
                secondary: nil,
                effectivePrimary: .sats
            )
        }

        let display = displayText(
            amountSats: amount,
            preferredPrimary: preferredPrimary,
            showFiat: showFiat,
            btcPrice: btcPrice,
            currencyCode: currencyCode,
            useBitcoinSymbol: useBitcoinSymbol
        )

        guard showFiat,
              amount > 0,
              let btcPrice,
              btcPrice.isFinite,
              btcPrice > 0,
              Double(amount) / 100_000_000.0 * btcPrice < 0.01 else {
            return display
        }

        let fiatThreshold = "<\(fiat(0.01, currencyCode: currencyCode))"
        let satsText = sats(amount, useBitcoinSymbol: useBitcoinSymbol)
        switch preferredPrimary {
        case .fiat:
            return AmountDisplayText(
                primary: fiatThreshold,
                secondary: satsText,
                effectivePrimary: .fiat
            )
        case .sats:
            return AmountDisplayText(
                primary: satsText,
                secondary: fiatThreshold,
                effectivePrimary: .sats
            )
        }
    }

    // MARK: - Live amount entry (sats or fiat)
    //
    // The keypad writes a single `amountString` that types left-to-right like a
    // normal number: digits build the integer part ("2" -> "21") and the decimal
    // key arms the fraction ("21." -> "21.50"). "21" is therefore twenty-one
    // whole units, never twenty-one minor units. What the string *means* depends
    // on the active entry unit — sats in sats mode, the user's fiat in fiat mode
    // — and these helpers are the single source of truth for that pipeline so
    // every entry screen stays thin.
    //
    // Fiat is just a two-decimal unit, so it delegates to the `decimals:`
    // helpers below rather than carrying a second copy of the accumulator
    // (mirrors Android BitcoinAmountEntry -> UnitAmountEntry).

    /// Fraction digits in a typed fiat amount.
    private static let fiatDecimals = 2

    /// The locale's decimal separator ("," or "."), shown on the keypad's
    /// decimal key and when rendering a partially typed amount.
    static var decimalSeparator: String {
        Locale.current.decimalSeparator ?? "."
    }

    /// The separator stored *inside* a raw entry string, on every locale, so a
    /// raw means the same thing on any device and matches Android byte for byte.
    /// Localization happens at display time.
    static let entrySeparator = "."

    /// Fraction digits the keypad offers for a display-flip entry unit.
    static func entryDecimals(for unit: AmountDisplayPrimary) -> Int {
        switch unit {
        case .sats: return 0
        case .fiat: return fiatDecimals
        }
    }

    /// Locale-aware grouping for the integer part of a typed fiat amount.
    private static let fiatGroupingFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// Satoshis represented by a typed string in the given entry unit.
    @MainActor
    static func entrySats(raw: String, unit: AmountDisplayPrimary) -> UInt64 {
        switch unit {
        case .sats:
            return entryBaseUnits(raw: raw, decimals: 0)
        case .fiat:
            let cents = entryBaseUnits(raw: raw, decimals: fiatDecimals)
            return PriceService.shared.fiatToSats(Double(cents) / 100)
        }
    }

    // MARK: - Live amount entry in an explicit mint unit
    //
    // A mint *account* unit (sat, eur, usd, or a custom string) is entered
    // directly in that unit — no BTC-price conversion. `decimals` comes from the
    // unit's `Currency` (0 for sat/custom, 2 for usd/eur), and is what decides
    // whether the keypad renders a decimal key at all.
    //
    // Raw grammar (the separator is always `entrySeparator`):
    //
    //     raw  := "" | INT | INT "." | INT "." FRAC
    //     INT  := "0" | [1-9][0-9]{0,11}
    //     FRAC := [0-9]{0,decimals}
    //
    // The trailing "." *is* the "fraction armed" state, so a screen needs no
    // extra flag beyond the raw String it already holds.

    /// The integer base-unit value of a typed string for a unit with `decimals`
    /// fraction digits ("21", 2 -> 2100; "21.5", 2 -> 2150; "500", 0 -> 500).
    static func entryBaseUnits(raw: String, decimals: Int) -> UInt64 {
        guard !raw.isEmpty else { return 0 }
        let places = clampDecimals(decimals)
        let ceiling = maxBaseUnits(decimals: places)
        let parts = raw.split(
            separator: Character(entrySeparator),
            omittingEmptySubsequences: false
        )
        let wholeDigits = String((parts.first ?? "").filter(\.isNumber)).drop { $0 == "0" }
        // An over-long raw can only arrive pre-seeded; clamp rather than letting
        // the parse fail into a silent zero.
        guard wholeDigits.count <= maxIntegerDigits else { return ceiling }
        let whole = UInt64(wholeDigits) ?? 0
        guard places > 0 else { return Swift.min(whole, ceiling) }

        let typed = parts.count > 1 ? String(parts[1].filter(\.isNumber)) : ""
        let padded = String((typed + String(repeating: "0", count: places)).prefix(places))
        let value = whole * pow10(places) + (UInt64(padded) ?? 0)
        return Swift.min(value, ceiling)
    }

    /// Append a keypad digit. Digits build the integer part left-to-right; once
    /// the fraction is armed they fill it, up to the unit's precision. Returns
    /// the unchanged string when the key is rejected (so the caller can skip the
    /// haptic).
    static func entryAppendUnit(_ key: String, to raw: String, decimals: Int) -> String {
        guard key.count == 1, let ch = key.first, ch.isNumber else { return raw }
        if let separator = raw.firstIndex(of: Character(entrySeparator)) {
            // Fraction armed: fill it to `decimals` digits, then stop.
            let typed = raw.distance(from: raw.index(after: separator), to: raw.endIndex)
            guard typed < clampDecimals(decimals) else { return raw }
            return raw + key
        }
        // Integer part — a lone leading zero is replaced, never extended.
        guard raw != "0", !raw.isEmpty else { return key }
        guard raw.count < maxIntegerDigits else { return raw }
        return raw + key
    }

    /// Arm the fraction. Inert for a 0-decimal unit (which renders no decimal
    /// key) and for a raw that already carries a separator; on an empty pad it
    /// opens with a leading zero, so "." "5" reads as "0.5".
    static func entryAppendSeparatorUnit(_ raw: String, decimals: Int) -> String {
        guard clampDecimals(decimals) > 0 else { return raw }
        guard !raw.contains(entrySeparator) else { return raw }
        guard !raw.isEmpty else { return "0" + entrySeparator }
        return raw + entrySeparator
    }

    /// Remove the last keypad input. A plain character drop, so the separator
    /// falls off in its turn: "21.5" -> "21." -> "21" -> "2" -> "".
    static func entryBackspaceUnit(_ raw: String) -> String {
        String(raw.dropLast())
    }

    /// The typed-entry string for a base-unit amount — the inverse of
    /// `entryBaseUnits`, in minimal form so a seeded whole amount looks like
    /// something the user could have typed (600, 2 -> "6"; 610, 2 -> "6.10").
    /// Empty for a zero amount so the keypad shows its placeholder.
    static func entryString(baseUnits: UInt64, decimals: Int) -> String {
        guard baseUnits > 0 else { return "" }
        let places = clampDecimals(decimals)
        guard places > 0 else { return String(baseUnits) }
        let scale = pow10(places)
        let whole = baseUnits / scale
        let fraction = baseUnits % scale
        guard fraction > 0 else { return String(whole) }
        let padded = String(format: "%0\(places)d", Int(fraction))
        return "\(whole)\(entrySeparator)\(padded)"
    }

    /// The largest amount the entry grammar can express for a unit.
    static func maxBaseUnits(decimals: Int) -> UInt64 {
        pow10(maxIntegerDigits + clampDecimals(decimals)) - 1
    }

    /// Ceiling on the integer part, so a held key can't run past sane bounds.
    private static let maxIntegerDigits = 12

    /// Keeps `10^(maxIntegerDigits + decimals)` inside `UInt64` for any unit.
    private static let maxDecimals = 6

    private static func clampDecimals(_ decimals: Int) -> Int {
        Swift.min(Swift.max(decimals, 0), maxDecimals)
    }

    private static func pow10(_ exponent: Int) -> UInt64 {
        var value: UInt64 = 1
        for _ in 0..<exponent { value *= 10 }
        return value
    }

    /// Re-express a typed string when the entry unit flips, preserving the
    /// amount through sats so the displayed value stays economically equal.
    @MainActor
    static func entryConverted(raw: String, from: AmountDisplayPrimary, to: AmountDisplayPrimary) -> String {
        guard from != to, !raw.isEmpty else { return raw }
        let sats = entrySats(raw: raw, unit: from)
        guard sats > 0 else { return "" }
        switch to {
        case .sats:
            return String(sats)
        case .fiat:
            return fiatEntryString(PriceService.shared.satsToFiat(sats))
        }
    }

    /// The big primary line for a typed string, formatted live in the entry
    /// unit and partial-aware (a trailing separator and trailing zeros render
    /// exactly as typed). Fiat reuses the locale's symbol position + separators.
    @MainActor
    static func entryPrimary(raw: String, unit: AmountDisplayPrimary, useBitcoinSymbol: Bool) -> String {
        switch unit {
        case .sats:
            return sats(entryBaseUnits(raw: raw, decimals: 0), useBitcoinSymbol: useBitcoinSymbol)
        case .fiat:
            return wrapWithCurrencySymbol(partialFiatNumber(raw))
        }
    }

    /// The live entry hero, decomposed for typesetting.
    @MainActor
    static func entryPrimaryParts(
        raw: String,
        unit: AmountDisplayPrimary,
        useBitcoinSymbol: Bool
    ) -> AmountParts {
        switch unit {
        case .sats:
            return satsParts(entryBaseUnits(raw: raw, decimals: 0), useBitcoinSymbol: useBitcoinSymbol)
        case .fiat:
            return AmountParts(
                value: partialFiatNumber(raw),
                affix: currencyAffix(currencyCode: PriceService.shared.currencyCode)
            )
        }
    }

    /// The numerals of a partially typed fiat amount, grouped but unwrapped.
    /// Partial-aware: a trailing separator and trailing zeros render exactly as
    /// typed, so the hero doesn't jump while the user is still keying.
    /// Raw always carries the canonical `entrySeparator`; the locale's separator
    /// is applied here, at display time. Reading and writing the same character
    /// would collide on comma-decimal locales, where the integer grouping of
    /// 1234 is itself "1.234".
    private static func partialFiatNumber(_ raw: String) -> String {
        let parts = raw.split(
            separator: Character(entrySeparator),
            omittingEmptySubsequences: false
        )
        let intRaw = parts.first.map(String.init) ?? ""
        let intValue = entryBaseUnits(raw: intRaw, decimals: 0)
        let groupedInt = fiatGroupingFormatter.string(from: NSNumber(value: intValue)) ?? "\(intValue)"

        guard raw.contains(entrySeparator) else { return groupedInt }
        let fracRaw = parts.count > 1 ? String(parts[1]) : ""
        return groupedInt + decimalSeparator + fracRaw
    }

    // MARK: - Fiat parsing / formatting helpers

    /// A raw entry string for a fiat value — used when converting sats -> fiat
    /// on a flip. Minimal form, so a round figure seeds as "16", not "16.00".
    private static func fiatEntryString(_ fiat: Double) -> String {
        let cents = (fiat * 100).rounded()
        guard cents.isFinite, cents > 0, cents < Double(UInt64.max) else { return "" }
        return entryString(baseUnits: UInt64(cents), decimals: fiatDecimals)
    }

    /// Wrap a partial numeric entry with the canonical currency prefix/suffix.
    @MainActor
    private static func wrapWithCurrencySymbol(_ number: String) -> String {
        let formatter = currencyFormatter(currencyCode: PriceService.shared.currencyCode)
        return (formatter.positivePrefix ?? "") + number + (formatter.positiveSuffix ?? "")
    }

    private static func currencyFormatter(currencyCode: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode.uppercased()
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        // NumberFormatter can inject a regular or non-breaking space between a
        // currency symbol and the number. Wallet-native currency amounts use a
        // compact affix ("$12.23"), so converted BTC amounts must match it.
        formatter.positivePrefix = formatter.positivePrefix?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        formatter.positiveSuffix = formatter.positiveSuffix?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        formatter.negativePrefix = formatter.negativePrefix?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        formatter.negativeSuffix = formatter.negativeSuffix?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return formatter
    }
}
