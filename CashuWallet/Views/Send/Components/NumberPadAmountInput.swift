import SwiftUI

/// Family-style digit-only number pad.
///
/// Used to drive a `UInt64`-shaped amount string for both Ecash and Melt flows.
/// Per-keypress selection haptics, long-press on delete clears the whole value.
struct NumberPadAmountInput: View {
    @Binding var amountString: String
    /// The active entry unit. In fiat mode the empty bottom-left slot becomes a
    /// locale decimal-separator key; in sats mode it stays blank (integer only).
    var unit: AmountDisplayPrimary = .sats

    @ScaledMetric(relativeTo: .title) private var keyHeight: CGFloat = 64

    private var decimalKey: String {
        unit == .fiat ? AmountFormatter.decimalSeparator : ""
    }

    private var rows: [[String]] {
        [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            [decimalKey, "0", "⌫"]
        ]
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { key in
                        keyView(key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyView(_ key: String) -> some View {
        if key.isEmpty {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: keyHeight)
        } else if key == "⌫" {
            Button(action: backspace) {
                Image(systemName: "delete.left")
                    .font(.title2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in clearAll() }
            )
            .frame(height: keyHeight)
            .accessibilityLabel("Delete")
            .accessibilityHint("Long press to clear")
        } else {
            Button(action: { append(key) }) {
                Text(key)
                    .font(.title.weight(.regular))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: keyHeight)
            .accessibilityLabel(key == AmountFormatter.decimalSeparator ? "decimal separator" : key)
        }
    }

    private func append(_ key: String) {
        let updated = AmountFormatter.entryAppend(key, to: amountString, unit: unit)
        guard updated != amountString else { return }
        HapticFeedback.selection()
        amountString = updated
    }

    private func backspace() {
        guard !amountString.isEmpty else { return }
        HapticFeedback.selection()
        amountString.removeLast()
    }

    private func clearAll() {
        guard !amountString.isEmpty else { return }
        HapticFeedback.impact(.light)
        amountString = ""
    }
}
