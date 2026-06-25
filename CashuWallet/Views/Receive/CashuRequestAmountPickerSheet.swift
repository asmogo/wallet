import SwiftUI

struct CashuRequestAmountPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared

    /// Current value for the request: `nil` = Any amount, value = fixed amount in sats.
    let currentAmount: UInt64?
    /// Called with the new amount on Done (`nil` = Any). Sheet dismisses afterwards.
    let onSelect: (UInt64?) -> Void

    @State private var amountString: String

    init(currentAmount: UInt64?, onSelect: @escaping (UInt64?) -> Void) {
        self.currentAmount = currentAmount
        self.onSelect = onSelect
        // Seed the keypad string in whatever unit entry is currently in, so a
        // sats `currentAmount` isn't misread as fiat.
        let unit: AmountDisplayPrimary =
            (SettingsManager.shared.amountDisplayPrimary == .fiat && PriceService.shared.btcPriceUSD > 0)
                ? .fiat : .sats
        let seed = currentAmount.map {
            AmountFormatter.entryConverted(raw: String($0), from: .sats, to: unit)
        } ?? ""
        self._amountString = State(initialValue: seed)
    }

    /// The unit the keypad is entering in: fiat only when fiat is primary AND a
    /// price is loaded, else sats (mirrors `CurrencyAmountDisplay.effectivePrimary`).
    private var entryUnit: AmountDisplayPrimary {
        (settings.amountDisplayPrimary == .fiat && priceService.btcPriceUSD > 0) ? .fiat : .sats
    }

    /// Satoshis represented by the typed amount, interpreted per `entryUnit`.
    private var amountSats: UInt64 { AmountFormatter.entrySats(raw: amountString, unit: entryUnit) }

    var body: some View {
        // Mirrors the app's other amount-entry surfaces (ReceiveLightningView's
        // `amountEntryView`, SendView): amount centered between two flexible
        // spacers, full-width keypad, action button directly beneath the keypad.
        VStack(spacing: 0) {
            header

            Spacer(minLength: 0)

            CurrencyAmountDisplay(
                sats: amountSats,
                primary: $settings.amountDisplayPrimary,
                primarySize: 56,
                entryRaw: amountString
            )
            .accessibilityLabel("Request amount: \(amountString.isEmpty ? "0" : amountString) sats")
            .padding(.horizontal)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            NumberPadAmountInput(amountString: $amountString, unit: entryUnit)
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
            amountString = AmountFormatter.entryConverted(raw: amountString, from: oldUnit, to: newUnit)
        }
    }

    private var header: some View {
        ZStack {
            Text("Amount")
                .font(.headline)

            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close")

                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private func confirm() {
        HapticFeedback.selection()
        let value = amountSats
        onSelect(value > 0 ? value : nil)
        dismiss()
    }
}
