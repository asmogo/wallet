import SwiftUI

/// The selected mint's role in the value flow. Requiring the role at each call
/// site prevents a receiving mint from being described as the payment source.
enum MintSelectorDirection {
    case source
    case destination

    var label: String {
        switch self {
        case .source: "From"
        case .destination: "To"
        }
    }
}

/// Shared metrics for the unboxed mint selector used throughout value flows.
enum FlowRowMetrics {
    static let minHeight: CGFloat = 48
    static let gap: CGFloat = 8
    static let actionInset: CGFloat = 8
    static let verticalPadding: CGFloat = 6

    /// The chevron's drawn width. A 48pt frame around an ~12pt glyph left 18pt
    /// of dead space on each side, which is what pushed the glyph a third of
    /// the way in from the trailing margin while inflating its gap to Send Max
    /// to three times the gap inside the identity. The hit area stays 44pt via
    /// `hitSlop`; only the layout box shrinks.
    static let chevronBox: CGFloat = 20

    /// Added to a control's hit area without costing layout width.
    static let hitSlop: CGFloat = 12
}

extension View {
    /// Grow a control's touch target beyond its drawn box: pad, claim the
    /// padded region as the hit shape, then undo the padding's layout cost.
    /// Lets a small glyph sit on the margin while still being comfortably
    /// tappable.
    func hitSlop(_ inset: CGFloat) -> some View {
        self
            .padding(.horizontal, inset)
            .contentShape(Rectangle())
            .padding(.horizontal, -inset)
    }
}

/// The one mint selector for every value flow, on both platforms: a quiet mint
/// identity with an optional "Send Max" action and picker chevron. The row
/// deliberately has no fill, border, or divider so the amount remains the
/// screen's focal point.
///
/// The direction label is not drawn — the mint name, balance and chevron say
/// what the row is. It survives in the accessibility label, so `direction` is
/// still required and a receiving flow cannot describe its mint as a source.
///
/// `onChooseMint` is nil when the wallet holds a single mint. In that state the
/// chevron disappears and the identity becomes information rather than a
/// control. `showsBalance` is reserved for amount-entry screens.
struct MintSelectorRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let direction: MintSelectorDirection
    let mint: MintInfo
    let balanceText: String
    var showsBalance: Bool
    var onUseMax: (() -> Void)?
    var onChooseMint: (() -> Void)?

    init(
        direction: MintSelectorDirection,
        mint: MintInfo,
        balanceText: String,
        showsBalance: Bool = false,
        onUseMax: (() -> Void)? = nil,
        onChooseMint: (() -> Void)? = nil
    ) {
        self.direction = direction
        self.mint = mint
        self.balanceText = balanceText
        self.showsBalance = showsBalance
        self.onUseMax = onUseMax
        self.onChooseMint = onChooseMint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 2 : 0) {
            HStack(spacing: 0) {
                identity()
                if let onUseMax {
                    sendMaxAction(action: onUseMax)
                }
                if let onChooseMint {
                    chevron(action: onChooseMint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func identityContent() -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FlowRowMetrics.gap) {
            if showsBalance && dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    mintName
                    balance
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: FlowRowMetrics.gap) {
                    mintName
                    if showsBalance {
                        balance
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // The row speaks in one voice: mint name, balance and Send Max all share
    // `.textLink` + semibold + primary ink, so the whole row is a single
    // treatment rather than three competing ones. Mirrors Android's
    // MintSelectorRow.
    private var mintName: some View {
        Text(mint.name)
            .cashuText(.textLink)
            .fontWeight(.semibold)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var balance: some View {
        Text(balanceText)
            .cashuText(.textLink)
            .fontWeight(.semibold)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private func identity() -> some View {
        let content = identityContent()
            .padding(.vertical, FlowRowMetrics.verticalPadding)
            .frame(minHeight: FlowRowMetrics.minHeight)
            .contentShape(Rectangle())

        if let onChooseMint {
            Button(action: onChooseMint) { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint("Double-tap to choose a different mint")
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private func sendMaxAction(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Send Max")
                .cashuText(.textLink)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.leading, FlowRowMetrics.actionInset)
                .frame(minHeight: FlowRowMetrics.minHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send maximum")
        .accessibilityHint("Fill the amount with your full mint balance")
    }

    private func chevron(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: FlowRowMetrics.chevronBox, height: FlowRowMetrics.minHeight)
                .hitSlop(FlowRowMetrics.hitSlop)
        }
        .buttonStyle(.plain)
        // The identity already exposes the picker as one coherent control.
        .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        if showsBalance {
            return "\(direction.label) \(mint.name), balance \(balanceText)"
        }
        return "\(direction.label) \(mint.name)"
    }
}
