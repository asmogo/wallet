import SwiftUI

/// Family-style two-line amount display.
///
/// Renders the active amount in either fiat or sats as the primary (large) line,
/// with the alternate unit underneath. Tapping the secondary line or the `↕`
/// affordance flips which side is primary and persists the choice.
struct CurrencyAmountDisplay: View {
    let sats: UInt64
    @Binding var primary: AmountDisplayPrimary
    /// The rung of the amount ladder this instance sits on. A role, never a
    /// point size: six sizes serving this one job is how the same number ended
    /// up rendering in two typefaces on adjacent screens.
    var role: CashuTextRole = .amountHero
    /// Live-entry mode: the raw typed string. When set, the primary line renders
    /// the typed value verbatim (partial decimals included) instead of deriving
    /// from `sats`; the secondary line still shows `sats` converted. Display-only
    /// call sites omit this and are unchanged.
    var entryRaw: String? = nil
    /// Dims the primary amount (e.g. while the typed value exceeds spendable balance).
    var isDimmed: Bool = false

    @ObservedObject private var priceService = PriceService.shared
    @ObservedObject private var settings = SettingsManager.shared

    /// Display-mode fiat string; nil when no price is loaded or the amount
    /// converts to under one cent (sub-cent fiat is never displayed).
    private var displayFiat: String? {
        priceService.formatSatsAsFiat(sats)
    }

    private var fiatAvailable: Bool {
        // Entry mode only needs a live price — the primary unit and flip control
        // must stay put while the user types through small values. Display
        // mode also drops fiat for sub-cent amounts.
        if entryRaw != nil { return priceService.btcPriceUSD > 0 }
        return displayFiat != nil
    }

    private var effectivePrimary: AmountDisplayPrimary {
        // If user picked fiat but price isn't loaded yet, fall back to sats so we
        // never show "$0.00" as the headline number.
        if primary == .fiat && !fiatAvailable { return .sats }
        return primary
    }

    private var primaryParts: AmountParts {
        if let entryRaw {
            return AmountFormatter.entryPrimaryParts(
                raw: entryRaw,
                unit: effectivePrimary,
                useBitcoinSymbol: settings.useBitcoinSymbol
            )
        }
        let satsParts = AmountFormatter.satsParts(sats, useBitcoinSymbol: settings.useBitcoinSymbol)
        switch effectivePrimary {
        case .fiat: return displayFiat.map(AmountParts.parse) ?? satsParts
        case .sats: return satsParts
        }
    }

    private var primaryText: String { primaryParts.joined }

    private var secondaryText: String {
        switch effectivePrimary {
        case .fiat: return AmountFormatter.sats(sats, useBitcoinSymbol: settings.useBitcoinSymbol)
        case .sats:
            // Entry mode keeps the raw conversion (even "$0.00") so the control
            // doesn't blink in and out while typing through small values.
            return displayFiat ?? AmountFormatter.fiat(priceService.satsToFiat(sats), currencyCode: priceService.currencyCode)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            AmountLockup(
                parts: primaryParts,
                role: role,
                value: Double(sats),
                isDimmed: isDimmed
            )
            .animation(.snappy, value: effectivePrimary)
            .animation(.snappy, value: isDimmed)

            // The secondary affordance is only meaningful when fiat is available —
            // otherwise there's no second unit to flip into, and we'd render
            // a placeholder "$0.00" that fragments the eye.
            if fiatAvailable {
                Button(action: flip) {
                    HStack(spacing: 6) {
                        Text(secondaryText)
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(sats)))
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Flip primary currency")
                .accessibilityHint("Currently showing \(primaryText), tap to switch to \(secondaryText)")
            }
        }
    }

    private func flip() {
        guard fiatAvailable else { return }
        HapticFeedback.selection()
        withAnimation(.snappy) {
            primary.toggle()
        }
    }
}
