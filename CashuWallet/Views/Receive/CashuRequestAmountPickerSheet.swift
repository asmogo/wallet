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
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                CurrencyAmountDisplay(
                    sats: UInt64(amountString) ?? 0,
                    primary: $settings.amountDisplayPrimary
                )
                .accessibilityLabel("Request amount: \(amountString.isEmpty ? "0" : amountString) sats")

                Spacer()

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
            .navigationTitle("Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    private func confirm() {
        HapticFeedback.selection()
        let value = UInt64(amountString) ?? 0
        onSelect(value > 0 ? value : nil)
        dismiss()
    }
}
