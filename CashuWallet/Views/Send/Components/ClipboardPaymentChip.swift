import SwiftUI

/// A Family-style "on clipboard" suggestion chip shown above the destination
/// input when the system clipboard holds a recognized payment request. Tap
/// fills the request; the trailing × dismisses.
struct ClipboardPaymentChip: View {
    let raw: String
    let result: PaymentRequestDecodeResult
    let onTap: () -> Void
    let onDismiss: () -> Void

    private var amountSats: UInt64? {
        switch result {
        case .bolt11(let amount, _), .bolt12(let amount, _):
            return amount
        case .lightningAddress, .onchain, .unrecognized:
            return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Image(systemName: PaymentRequestDecoder.iconName(result))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)
                        .background(.thinMaterial, in: Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text("On clipboard")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.5)

                            if let sats = amountSats {
                                Text("· \(sats) sat")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(PaymentRequestDecoder.shortRepresentation(raw, result: result))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Double-tap to use this payment request")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss clipboard suggestion")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var accessibilityLabel: String {
        let type = PaymentRequestDecoder.typeLabel(result)
        if let sats = amountSats {
            return "Clipboard contains a \(type) for \(sats) sats"
        }
        return "Clipboard contains a \(type)"
    }
}
