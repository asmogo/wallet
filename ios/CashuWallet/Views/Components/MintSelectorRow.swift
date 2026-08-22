import SwiftUI

/// Shared metrics for the flow-top mint row.
///
/// A quiet row, not a card: 20pt avatar, one line, 48pt tall. The 64pt block it
/// replaces (40pt avatar over a balance line) outweighed both the toolbar above
/// it and the amount hero it exists to qualify.
enum FlowRowMetrics {
    static let corner: CGFloat = 12
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 10
    static let minHeight: CGFloat = 48
    static let avatar: CGFloat = 20
    static let gap: CGFloat = 8
}

/// The one mint selector for every value flow, on both platforms: mint identity
/// on the left, an optional "Send Max" chip and the picker chevron on the right.
/// Tapping anywhere except the chip opens the picker.
///
/// `onChooseMint` is nil when the wallet holds a single mint — there is nothing
/// to choose between, so the row drops its chevron and stops being a control and
/// becomes a label. `balanceText` is deliberately not rendered; it lives in the
/// accessibility label and reappears on screen only in the insufficient-balance
/// notice.
struct MintSelectorRow: View {
    let mint: MintInfo
    let balanceText: String
    var onUseMax: (() -> Void)?
    var onChooseMint: (() -> Void)?

    init(
        mint: MintInfo,
        balanceText: String,
        onUseMax: (() -> Void)? = nil,
        onChooseMint: (() -> Void)? = nil
    ) {
        self.mint = mint
        self.balanceText = balanceText
        self.onUseMax = onUseMax
        self.onChooseMint = onChooseMint
    }

    var body: some View {
        // Whichever element sits last owns the row's right inset, so no region
        // ends flush against the glass and no strip of it is a dead zone.
        let identityTrailing = (onUseMax == nil && onChooseMint == nil)
            ? FlowRowMetrics.horizontalPadding : 0
        let chipTrailing = onChooseMint == nil ? FlowRowMetrics.horizontalPadding : 0

        HStack(spacing: 0) {
            identity(trailingInset: identityTrailing)
            if let onUseMax {
                sendMaxChip(action: onUseMax, trailingInset: chipTrailing)
            }
            if let onChooseMint {
                chevron(action: onChooseMint)
            }
        }
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: FlowRowMetrics.corner),
            interactive: onChooseMint != nil
        )
    }

    private var identityContent: some View {
        HStack(spacing: FlowRowMetrics.gap) {
            MintAvatarView(
                iconUrl: mint.iconUrl,
                name: mint.name,
                size: FlowRowMetrics.avatar
            )
            Text(mint.name)
                .cashuText(.textLink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
        }
    }

    /// The identity region absorbs the row's spare width, so the padding ring is
    /// part of the tap target rather than a dead edge — the half of `c121fe87`
    /// that the keypad and confirm rows never got.
    @ViewBuilder
    private func identity(trailingInset: CGFloat) -> some View {
        let padded = identityContent
            .padding(.leading, FlowRowMetrics.horizontalPadding)
            .padding(.trailing, trailingInset)
            .padding(.vertical, FlowRowMetrics.verticalPadding)
            .frame(minHeight: FlowRowMetrics.minHeight)
            .contentShape(Rectangle())

        if let onChooseMint {
            Button(action: onChooseMint) { padded }
                .buttonStyle(.plain)
                .accessibilityLabel("Mint: \(mint.name), balance \(balanceText)")
                .accessibilityHint("Double-tap to choose a different mint")
        } else {
            padded
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Mint: \(mint.name), balance \(balanceText)")
        }
    }

    private func sendMaxChip(action: @escaping () -> Void, trailingInset: CGFloat) -> some View {
        Button(action: action) {
            Text("Send Max")
                .cashuText(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .padding(.leading, FlowRowMetrics.gap)
                .padding(.trailing, trailingInset)
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
                .padding(.leading, FlowRowMetrics.gap)
                .padding(.trailing, FlowRowMetrics.horizontalPadding)
                .frame(minHeight: FlowRowMetrics.minHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The identity region already announces this action.
        .accessibilityHidden(true)
    }
}
