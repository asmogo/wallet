import SwiftUI

private enum AmountMode: String, CaseIterable, Identifiable {
    case anyAmount
    case fixedAmount

    var id: String { rawValue }
    var title: String {
        switch self {
        case .anyAmount: return "Any"
        case .fixedAmount: return "Set Amount"
        }
    }
}

struct CashuRequestAmountPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared

    /// Current value for the request: `nil` = Any amount, value = fixed amount in sats.
    let currentAmount: UInt64?
    /// Called with the new amount on Done (`nil` = Any). Sheet dismisses afterwards.
    let onSelect: (UInt64?) -> Void

    @State private var mode: AmountMode
    @State private var amountString: String

    init(currentAmount: UInt64?, onSelect: @escaping (UInt64?) -> Void) {
        self.currentAmount = currentAmount
        self.onSelect = onSelect
        self._mode = State(initialValue: currentAmount == nil ? .anyAmount : .fixedAmount)
        self._amountString = State(initialValue: currentAmount.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modePicker
                    .padding(.horizontal)
                    .padding(.top, 12)

                Spacer()

                if mode == .fixedAmount {
                    CurrencyAmountDisplay(
                        sats: UInt64(amountString) ?? 0,
                        primary: $settings.amountDisplayPrimary
                    )
                    .accessibilityLabel("Request amount: \(amountString.isEmpty ? "0" : amountString) sats")
                } else {
                    anyAmountIllustration
                }

                Spacer()

                if mode == .fixedAmount {
                    NumberPadAmountInput(amountString: $amountString)
                        .padding(.horizontal, 24)
                }

                Button(action: confirm) {
                    Text("Done")
                }
                .glassButton()
                .disabled(mode == .fixedAmount && (UInt64(amountString) ?? 0) == 0)
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
            .animation(.snappy, value: mode)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(AmountMode.allCases) { m in
                modePill(mode: m)
            }
        }
        .padding(4)
        .background(.thinMaterial, in: Capsule())
        .accessibilityLabel("Amount mode")
    }

    private func modePill(mode m: AmountMode) -> some View {
        let isSelected = mode == m
        return Button(action: {
            guard mode != m else { return }
            HapticFeedback.selection()
            mode = m
        }) {
            Text(m.title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(isSelected ? Color.primary.opacity(0.12) : Color.clear)
                )
                .foregroundStyle(isSelected ? .primary : .secondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var anyAmountIllustration: some View {
        VStack(spacing: 12) {
            Image(systemName: "infinity")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("Any Amount")
                .font(.title3.weight(.semibold))

            Text("Sender chooses how much to send")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func confirm() {
        HapticFeedback.selection()
        let amount: UInt64? = {
            switch mode {
            case .anyAmount: return nil
            case .fixedAmount:
                let value = UInt64(amountString) ?? 0
                return value > 0 ? value : nil
            }
        }()
        onSelect(amount)
        dismiss()
    }
}
