import Foundation

enum AmountFormatter {
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter
    }()

    static func sats(_ sats: UInt64, useBitcoinSymbol: Bool, includeUnit: Bool = true) -> String {
        let formatted = decimalFormatter.string(from: NSNumber(value: sats)) ?? "\(sats)"
        if useBitcoinSymbol {
            return "₿\(formatted)"
        }
        return includeUnit ? "\(formatted) sat" : formatted
    }

    // MARK: - Live amount entry (sats or fiat)
    //
    // The keypad writes a single `amountString`; what it *means* depends on the
    // active entry unit. In sats mode it's an integer; in fiat mode it's a
    // locale-formatted decimal (cents) that converts to sats at the live price.
    // These helpers are the single source of truth for that pipeline so every
    // entry screen stays thin.

    /// The locale's decimal separator ("," or "."), used as the keypad's
    /// fiat-only decimal key and when parsing/formatting typed fiat.
    static var decimalSeparator: String {
        Locale.current.decimalSeparator ?? "."
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
            return UInt64(raw) ?? 0
        case .fiat:
            return PriceService.shared.fiatToSats(parseFiat(raw))
        }
    }

    /// Append a keypad key under entry rules: digits always; the decimal
    /// separator only in fiat mode; reject a second separator and a third
    /// fraction digit; collapse leading zeros. Returns the new raw string
    /// (unchanged if the key is rejected, so the caller can skip the haptic).
    static func entryAppend(_ key: String, to raw: String, unit: AmountDisplayPrimary) -> String {
        let sep = decimalSeparator

        if key == sep {
            guard unit == .fiat, !raw.contains(sep) else { return raw }
            return raw.isEmpty ? "0" + sep : raw + sep
        }

        guard key.count == 1, let ch = key.first, ch.isNumber else { return raw }

        // Typing into the fractional part: cap at 2 digits.
        if unit == .fiat, let sepIndex = raw.firstIndex(of: Character(sep)) {
            let fraction = raw[raw.index(after: sepIndex)...]
            return fraction.count >= 2 ? raw : raw + key
        }

        // Integer part — collapse a lone leading zero ("0" + "5" -> "5").
        return raw == "0" ? key : raw + key
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
            return sats(UInt64(raw) ?? 0, useBitcoinSymbol: useBitcoinSymbol)
        case .fiat:
            let sep = decimalSeparator
            let parts = raw.split(separator: Character(sep), omittingEmptySubsequences: false)
            let intRaw = parts.first.map(String.init) ?? ""
            let intValue = UInt64(intRaw) ?? 0
            let groupedInt = fiatGroupingFormatter.string(from: NSNumber(value: intValue)) ?? "\(intValue)"

            var number = groupedInt
            if raw.contains(sep) {
                let fracRaw = parts.count > 1 ? String(parts[1]) : ""
                number += sep + fracRaw
            }
            return wrapWithCurrencySymbol(number)
        }
    }

    // MARK: - Fiat parsing / formatting helpers

    /// Parse a typed fiat string (locale separator) into a `Double`.
    private static func parseFiat(_ raw: String) -> Double {
        guard !raw.isEmpty else { return 0 }
        var normalized = raw.replacingOccurrences(of: decimalSeparator, with: ".")
        if normalized.hasSuffix(".") { normalized.removeLast() }
        return Double(normalized) ?? 0
    }

    /// A raw entry string (locale separator, two decimals, no grouping/symbol)
    /// for a fiat value — used when converting sats -> fiat on a flip.
    private static func fiatEntryString(_ fiat: Double) -> String {
        let cents = (fiat * 100).rounded()
        guard cents.isFinite, cents > 0, cents < Double(UInt64.max) else { return "" }
        let total = UInt64(cents)
        return "\(total / 100)\(decimalSeparator)\(String(format: "%02d", total % 100))"
    }

    /// Wrap a numeric string with the selected currency's symbol in the locale's
    /// position, by extracting the prefix/suffix from a narrow-currency template.
    @MainActor
    private static func wrapWithCurrencySymbol(_ number: String) -> String {
        let code = PriceService.shared.currencyCode
        let template = Decimal(0).formatted(
            .currency(code: code).presentation(.narrow).precision(.fractionLength(0))
        )
        guard let zero = template.range(of: "0") else { return number }
        let prefix = String(template[..<zero.lowerBound])
        let suffix = String(template[zero.upperBound...])
        return prefix + number + suffix
    }
}
