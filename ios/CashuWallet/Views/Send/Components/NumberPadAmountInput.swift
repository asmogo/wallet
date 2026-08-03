import SwiftUI

/// Family-style digit-only number pad.
///
/// Used to drive a `UInt64`-shaped amount string for both Ecash and Melt flows.
/// Per-keypress selection haptics, long-press on delete clears the whole value.
struct NumberPadAmountInput: View {
    @Binding var amountString: String

    /// How keystrokes are interpreted:
    /// - `.display`: sats (integer) or fiat (a cents accumulator, digits shift in
    ///   from the right) — the sats↔fiat display flip.
    /// - `.mintUnit`: a mint account unit entered directly, with `decimals`
    ///   fraction digits (0 → integer like sats, 2 → cents like fiat).
    /// Either way the bottom-left slot stays blank — there is no decimal key.
    private enum Mode {
        case display(AmountDisplayPrimary)
        case mintUnit(decimals: Int)
    }
    private let mode: Mode

    /// Sats/fiat display-flip entry (existing call sites).
    init(amountString: Binding<String>, unit: AmountDisplayPrimary = .sats) {
        self._amountString = amountString
        self.mode = .display(unit)
    }

    /// Direct entry in a mint account unit with the given fraction-digit count.
    init(amountString: Binding<String>, decimals: Int) {
        self._amountString = amountString
        self.mode = .mintUnit(decimals: decimals)
    }

    @ScaledMetric(relativeTo: .title) private var keyHeight: CGFloat = 64

    private var rows: [[String]] {
        [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["", "0", "⌫"]
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
                    // Tabular, so a key's label doesn't shift width between
                    // digits — and the same family as the number it produces.
                    .cashuText(.numberPadKey)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: keyHeight)
            .accessibilityLabel(key)
        }
    }

    private func append(_ key: String) {
        let updated: String
        switch mode {
        case .display(let unit):
            updated = AmountFormatter.entryAppend(key, to: amountString, unit: unit)
        case .mintUnit(let decimals):
            updated = AmountFormatter.entryAppendUnit(key, to: amountString, decimals: decimals)
        }
        guard updated != amountString else { return }
        HapticFeedback.selection()
        amountString = updated
    }

    private func backspace() {
        let updated: String
        switch mode {
        case .display(let unit):
            updated = AmountFormatter.entryBackspace(amountString, unit: unit)
        case .mintUnit(let decimals):
            updated = AmountFormatter.entryBackspaceUnit(amountString, decimals: decimals)
        }
        guard updated != amountString else { return }
        HapticFeedback.selection()
        amountString = updated
    }

    private func clearAll() {
        guard !amountString.isEmpty else { return }
        HapticFeedback.impact(.light)
        amountString = ""
    }
}
