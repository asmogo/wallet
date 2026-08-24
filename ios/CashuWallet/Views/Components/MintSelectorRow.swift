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
    static let avatar: CGFloat = 28
    static let gap: CGFloat = 8
    static let actionInset: CGFloat = 8
    static let verticalPadding: CGFloat = 6
}

/// The one mint selector for every value flow, on both platforms: a quiet
/// directional label and mint identity, with an optional "Send Max" action and
/// picker chevron. The row deliberately has no fill, border, or divider so the
/// amount remains the screen's focal point.
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
            if dynamicTypeSize.isAccessibilitySize {
                Text(direction.label)
                    .cashuText(.textLink)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 0) {
                identity(showsDirection: !dynamicTypeSize.isAccessibilitySize)
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

    private func identityContent(showsDirection: Bool) -> some View {
        HStack(spacing: FlowRowMetrics.gap) {
            if showsDirection {
                Text(direction.label)
                    .cashuText(.textLink)
                    .foregroundStyle(.secondary)
            }

            MintAvatarView(
                iconUrl: mint.iconUrl,
                name: mint.name,
                size: FlowRowMetrics.avatar
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(mint.name)
                    .cashuText(.textLink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if showsBalance {
                    Text(balanceText)
                        .cashuText(.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func identity(showsDirection: Bool) -> some View {
        let content = identityContent(showsDirection: showsDirection)
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
                .padding(.horizontal, FlowRowMetrics.actionInset)
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
                .frame(width: FlowRowMetrics.minHeight, height: FlowRowMetrics.minHeight)
                .contentShape(Rectangle())
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
