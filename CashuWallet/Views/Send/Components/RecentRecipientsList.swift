import SwiftUI

/// A short list of the user's most recent outgoing Lightning/on-chain
/// destinations. Tapping a row fills the destination input upstream.
struct RecentRecipientsList: View {
    let recipients: [Recipient]
    let onTap: (Recipient) -> Void

    struct Recipient: Identifiable, Equatable {
        let id: String
        let invoice: String
        let kind: WalletTransaction.TransactionKind
        let amount: UInt64
        let date: Date

        var iconName: String {
            switch kind {
            case .lightning: return "bolt.fill"
            case .onchain: return "bitcoinsign.circle"
            case .ecash: return "banknote"
            }
        }

        var shortInvoice: String {
            if PaymentRequestParser.isHumanReadableLightningAddress(invoice) {
                return invoice
            }
            guard invoice.count > 16 else { return invoice }
            return "\(invoice.prefix(8))…\(invoice.suffix(6))"
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(recipients.enumerated()), id: \.element.id) { index, recipient in
                    Button(action: { onTap(recipient) }) {
                        row(for: recipient)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel(for: recipient))

                    if index < recipients.count - 1 {
                        Divider().padding(.leading, 50)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func row(for recipient: Recipient) -> some View {
        HStack(spacing: 12) {
            Image(systemName: recipient.iconName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .background(.tertiary.opacity(0.4), in: Circle())

            Text(recipient.shortInvoice)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(recipient.amount) sat")
                    .font(.subheadline.weight(.medium))
                Text(Self.relativeFormatter.localizedString(for: recipient.date, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func accessibilityLabel(for recipient: Recipient) -> String {
        let when = Self.relativeFormatter.localizedString(for: recipient.date, relativeTo: Date())
        return "Recent \(recipient.kind.displayName) payment to \(recipient.shortInvoice), \(recipient.amount) sats, \(when)"
    }
}
