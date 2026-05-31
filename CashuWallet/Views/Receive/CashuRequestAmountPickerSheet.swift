import SwiftUI

struct CashuRequestAmountPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared

    /// Current value for the request: `nil` = Any amount, value = fixed amount in sats.
    let currentAmount: UInt64?
    /// Called with the new amount on Done (`nil` = Any). Sheet dismisses afterwards.
    let onSelect: (UInt64?) -> Void

    @State private var amountString: String

    // The sheet sizes itself to its content rather than a fixed `.medium` detent,
    // so the amount + keypad + Done always fit exactly — on an iPhone 12 just as on
    // a Pro Max. `contentHeight` is the laid-out content; `bottomInset` is the home
    // indicator, which a `.height(_:)` detent insets the content by and must be added
    // back so Done clears the indicator. Seeded with a sane default to avoid a
    // first-frame collapse before measurement lands.
    @State private var contentHeight: CGFloat = 460
    @State private var bottomInset: CGFloat = 0

    init(currentAmount: UInt64?, onSelect: @escaping (UInt64?) -> Void) {
        self.currentAmount = currentAmount
        self.onSelect = onSelect
        self._amountString = State(initialValue: currentAmount.map { String($0) } ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            CurrencyAmountDisplay(
                sats: UInt64(amountString) ?? 0,
                primary: $settings.amountDisplayPrimary,
                primarySize: 44
            )
            .accessibilityLabel("Request amount: \(amountString.isEmpty ? "0" : amountString) sats")
            .padding(.vertical, 24)

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
        .background {
            // Measures the intrinsic content height (inside the safe area).
            GeometryReader { proxy in
                Color.clear
                    .onAppear { contentHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newValue in contentHeight = newValue }
            }
        }
        .background {
            // Reads the home-indicator inset. `.ignoresSafeArea()` lets this probe
            // span into the safe area so `safeAreaInsets.bottom` reports the real value.
            GeometryReader { proxy in
                Color.clear
                    .onAppear { bottomInset = proxy.safeAreaInsets.bottom }
                    .onChange(of: proxy.safeAreaInsets.bottom) { _, newValue in bottomInset = newValue }
            }
            .ignoresSafeArea()
        }
        .presentationDetents([.height(contentHeight + bottomInset)])
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
