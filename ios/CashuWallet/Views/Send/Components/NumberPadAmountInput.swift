import SwiftUI

/// Horizontal gutter every amount-entry screen lays its number pad on, and the
/// one the mint selector above it aligns to. The pad is the widest, heaviest
/// block on these screens, so it — not the narrower bottom CTA — is what the
/// eye reads the row's left and right edges against.
enum NumberPadMetrics {
    static let gutter: CGFloat = 24
}

/// Family-style digit-only number pad.
///
/// Used to drive a `UInt64`-shaped amount string for both Ecash and Melt flows.
/// Per-keypress selection haptics, long-press on delete clears the whole value.
struct NumberPadAmountInput: View {
    @Binding var amountString: String

    /// How keystrokes are interpreted:
    /// - `.display`: sats or the user's fiat — the sats↔fiat display flip.
    /// - `.mintUnit`: a mint account unit entered directly, with `decimals`
    ///   fraction digits (0 → integer like sats, 2 → a fraction like fiat).
    /// Either way it reduces to a fraction-digit count, which is what decides
    /// whether the bottom-left slot carries a decimal key or stays blank.
    private enum Mode {
        case display(AmountDisplayPrimary)
        case mintUnit(decimals: Int)
    }
    private let mode: Mode

    /// Fraction digits this pad can enter. Zero means no decimal key: sats are
    /// indivisible here, so a fraction would only produce a rounding surprise.
    private var decimals: Int {
        switch mode {
        case .display(let unit): return AmountFormatter.entryDecimals(for: unit)
        case .mintUnit(let decimals): return decimals
        }
    }

    /// Bottom-left key label — the locale's separator, or blank when the active
    /// unit has no fraction. The slot is reserved either way, so the grid never
    /// shifts when the user flips sats↔fiat.
    private var separatorKey: String {
        decimals > 0 ? AmountFormatter.decimalSeparator : ""
    }

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
            [separatorKey, "0", "⌫"]
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
        } else if key == separatorKey {
            Button(action: appendSeparator) {
                Text(key)
                    .cashuText(.numberPadKey)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: keyHeight)
            .accessibilityLabel("Decimal point")
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
        apply(AmountFormatter.entryAppendUnit(key, to: amountString, decimals: decimals))
    }

    private func appendSeparator() {
        apply(AmountFormatter.entryAppendSeparatorUnit(amountString, decimals: decimals))
    }

    private func backspace() {
        apply(AmountFormatter.entryBackspaceUnit(amountString))
    }

    /// A rejected key leaves the string untouched, so it gets no haptic either.
    private func apply(_ updated: String) {
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
