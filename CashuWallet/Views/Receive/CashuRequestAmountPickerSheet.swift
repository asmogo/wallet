import SwiftUI

struct CashuRequestAmountPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared

    /// Current value for the request: `nil` = Any amount, value = fixed amount in sats.
    let currentAmount: UInt64?
    /// Called with the new amount on Done (`nil` = Any). Sheet dismisses afterwards.
    let onSelect: (UInt64?) -> Void

    @State private var amountString: String

    init(currentAmount: UInt64?, onSelect: @escaping (UInt64?) -> Void) {
        self.currentAmount = currentAmount
        self.onSelect = onSelect
        self._amountString = State(initialValue: currentAmount.map { String($0) } ?? "")
    }

    var body: some View {
        // Mirrors the app's other amount-entry surfaces (ReceiveLightningView's
        // `amountEntryView`, SendView): amount centered between two flexible
        // spacers, full-width keypad, action button directly beneath the keypad.
        VStack(spacing: 0) {
            header

            Spacer(minLength: 0)

            CurrencyAmountDisplay(
                sats: UInt64(amountString) ?? 0,
                primary: $settings.amountDisplayPrimary,
                primarySize: 56
            )
            .accessibilityLabel("Request amount: \(amountString.isEmpty ? "0" : amountString) sats")
            .padding(.horizontal)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            NumberPadAmountInput(amountString: $amountString)
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
        let value = UInt64(amountString) ?? 0
        onSelect(value > 0 ? value : nil)
        dismiss()
    }
}
