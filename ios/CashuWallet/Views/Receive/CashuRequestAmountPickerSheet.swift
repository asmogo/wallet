import SwiftUI

struct CashuRequestAmountPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared

    /// Current value for the request: `nil` = Any amount, value = fixed amount in
    /// the request's own unit base units (sats for `sat`, cents for usd/eur,
    /// integer for a custom unit).
    let currentAmount: UInt64?
    /// The request's unit ("sat", "usd", "eur", or a custom unit string). Drives
    /// whether entry is the sats↔fiat display flip or direct unit entry.
    let unit: String
    /// Called with the new amount on Done (`nil` = Any), in `unit`'s base units.
    /// Sheet dismisses afterwards.
    let onSelect: (UInt64?) -> Void

    @State private var amountString: String

    init(currentAmount: UInt64?, unit: String, onSelect: @escaping (UInt64?) -> Void) {
        self.currentAmount = currentAmount
        self.unit = unit
        self.onSelect = onSelect
        // Seed the keypad string in the request's own unit so an existing amount
        // round-trips exactly — sats convert to the current display flip, other
        // units seed their minor-unit entry string directly.
        if unit.lowercased() == "sat" {
            let entry: AmountDisplayPrimary =
                (SettingsManager.shared.amountDisplayPrimary == .fiat && PriceService.shared.btcPriceUSD > 0)
                    ? .fiat : .sats
            let seed = currentAmount.map {
                AmountFormatter.entryConverted(raw: String($0), from: .sats, to: entry)
            } ?? ""
            self._amountString = State(initialValue: seed)
        } else {
            let decimals = CurrencyRegistry.currency(forMintUnit: unit).decimals
            let seed = currentAmount.map {
                AmountFormatter.entryString(baseUnits: $0, decimals: decimals)
            } ?? ""
            self._amountString = State(initialValue: seed)
        }
    }

    private var isSat: Bool { unit.lowercased() == "sat" }
    private var unitCurrency: any Currency { CurrencyRegistry.currency(forMintUnit: unit) }
    private var unitDecimals: Int { unitCurrency.decimals }

    /// The unit the sats keypad is entering in: fiat only when fiat is primary AND
    /// a price is loaded, else sats (mirrors `CurrencyAmountDisplay.effectivePrimary`).
    /// Unused for non-sat requests, which enter directly in their own unit.
    private var entryUnit: AmountDisplayPrimary {
        (settings.amountDisplayPrimary == .fiat && priceService.btcPriceUSD > 0) ? .fiat : .sats
    }

    /// The typed amount in the request's base units — sats for a sat request
    /// (interpreted per `entryUnit`), else the unit's own minor units.
    private var amountBaseUnits: UInt64 {
        isSat
            ? AmountFormatter.entrySats(raw: amountString, unit: entryUnit)
            : AmountFormatter.entryBaseUnits(raw: amountString, decimals: unitDecimals)
    }

    var body: some View {
        // Mirrors the app's other amount-entry surfaces (ReceiveLightningView's
        // `amountHero`, SendView): amount centered between two flexible spacers,
        // full-width keypad, action button directly beneath the keypad.
        VStack(spacing: 0) {
            header

            Spacer(minLength: 0)

            amountDisplay
                .padding(.horizontal)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            Group {
                if isSat {
                    NumberPadAmountInput(amountString: $amountString, unit: entryUnit)
                } else {
                    NumberPadAmountInput(amountString: $amountString, decimals: unitDecimals)
                }
            }
            .padding(.horizontal, 24)

            Button(action: confirm) {
                Text("Done")
            }
            .glassButton()
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: entryUnit) { oldUnit, newUnit in
            // Only the sats keypad flips between fiat and sats; a non-sat request
            // stays in its own unit regardless of the display setting.
            guard isSat else { return }
            amountString = AmountFormatter.entryConverted(raw: amountString, from: oldUnit, to: newUnit)
        }
    }

    @ViewBuilder
    private var amountDisplay: some View {
        if isSat {
            CurrencyAmountDisplay(
                sats: amountBaseUnits,
                primary: $settings.amountDisplayPrimary,
                role: .amountHero,
                entryRaw: amountString
            )
            .accessibilityLabel("Request amount: \(amountString.isEmpty ? "0" : amountString) sats")
        } else {
            // Non-sat mint unit: show it directly, no BTC-price flip.
            Text(CurrencyAmount(value: amountBaseUnits, currency: unitCurrency).formatted())
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(amountBaseUnits)))
                .animation(.snappy, value: amountBaseUnits)
                .accessibilityLabel("Request amount: \(amountString.isEmpty ? "0" : amountString) \(unit)")
        }
    }

    private var header: some View {
        ZStack {
            Text("Amount")
                .font(.headline)

            HStack {
                SheetCloseButton()
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private func confirm() {
        HapticFeedback.selection()
        let value = amountBaseUnits
        onSelect(value > 0 ? value : nil)
        dismiss()
    }
}
