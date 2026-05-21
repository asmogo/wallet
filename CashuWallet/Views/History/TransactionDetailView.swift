import SwiftUI

struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    let transaction: WalletTransaction
    @ObservedObject var settings = SettingsManager.shared

    @State private var copyButtonText = "Copy"
    @State private var showShareSheet = false

    /// Returns the content to display as a QR code.
    private var qrContent: String? {
        if let token = transaction.token { return token }
        if let invoice = transaction.invoice { return invoice }
        return nil
    }

    private var qrContentTypeLabel: String {
        switch transaction.kind {
        case .ecash:     return "token"
        case .lightning: return "request"
        case .onchain:   return "address"
        }
    }

    private var qrContentAccessibilityLabel: String {
        switch transaction.kind {
        case .ecash:     return "ecash token"
        case .lightning: return "payment request"
        case .onchain:   return "bitcoin address"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // QR (if there's content to show).
                        if let content = qrContent {
                            QRCodeView(
                                content: content,
                                showControls: false,
                                // Lightning invoices and Bitcoin addresses are
                                // standard QR formats; ecash tokens can be
                                // long and benefit from UR-animated encoding.
                                staticOnly: transaction.kind != .ecash
                            )
                            .frame(width: 280, height: 280)
                            .padding(16)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                            .padding(.top, 8)
                            .contextMenu {
                                Button(action: { copyContent(content) }) {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                Button(action: { showShareSheet = true }) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                            }
                        } else {
                            Image(systemName: kindIcon)
                                .font(.system(size: 64))
                                .foregroundStyle(Color.accentColor)
                                .padding(.top, 32)
                                .accessibilityHidden(true)
                        }

                        // Amount — same scale as Lightning Invoice / Pending Ecash.
                        CurrencyAmountDisplay(
                            sats: transaction.amount,
                            primary: $settings.amountDisplayPrimary,
                            primarySize: 32
                        )
                        .accessibilityLabel("Amount: \(transaction.amount) sats")

                        // Animated status.
                        statusBadge

                        // Detail rows on canvas with hairline dividers.
                        VStack(spacing: 0) {
                            detailRow(icon: "arrow.left.arrow.right", label: "Type",
                                      value: transaction.kind.displayName)
                            if transaction.fee > 0 {
                                canvasDivider
                                detailRow(icon: "arrow.up.arrow.down", label: "Fee",
                                          value: "\(transaction.fee) sat")
                            }
                            canvasDivider
                            detailRow(icon: "banknote", label: "Unit",
                                      value: settings.unitLabel.uppercased())
                            canvasDivider
                            detailRow(icon: "info.circle", label: "State",
                                      value: transaction.displayStatusText)
                            if let mintUrl = transaction.mintUrl {
                                canvasDivider
                                detailRow(icon: "bitcoinsign.bank.building", label: "Mint",
                                          value: extractMintHost(mintUrl))
                            }
                            if let request = transaction.invoice {
                                canvasDivider
                                detailRow(
                                    icon: transaction.kind == .onchain ? "qrcode" : "doc.text",
                                    label: transaction.kind == .onchain ? "Address" : "Request",
                                    value: request
                                )
                            }
                            if let preimage = transaction.preimage {
                                canvasDivider
                                detailRow(
                                    icon: transaction.kind == .onchain ? "checkmark.seal" : "key",
                                    label: transaction.kind == .onchain ? "Transaction ID" : "Payment Proof",
                                    value: preimage
                                )
                            }
                        }
                        .padding(.top, 8)
                        .padding(.horizontal, 4)

                        if let explorerURL = onchainExplorerURL {
                            Link("View in block explorer", destination: explorerURL)
                                .font(.subheadline.weight(.medium))
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal)
                }

                // Single primary action — Copy. Share lives at top-right in
                // the toolbar (with a doubled QR context-menu entry for
                // long-press discovery). See DESIGN.md → Share-At-Top Rule.
                if let content = qrContent {
                    Button(action: { copyContent(content) }) {
                        Text(copyButtonText)
                    }
                    .glassButton()
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                    .accessibilityLabel(copyButtonText == "Copied" ? "Copied" : "Copy \(qrContentTypeLabel)")
                    .accessibilityHint("Copies the \(qrContentAccessibilityLabel) to clipboard")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .principal) {
                    Text(titleForTransaction).font(.headline)
                }
                if qrContent != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showShareSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share")
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let token = transaction.token {
                    CashuTokenShareSheet(token: token)
                } else if let invoice = transaction.invoice {
                    ShareSheet(items: [invoice])
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon)
                .modifier(StatusSymbolEffect(status: transaction.status))
            Text(statusText)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(statusColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(statusText)")
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
    }

    private var canvasDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 0.5)
            .padding(.leading, 28)
    }

    // MARK: - Helpers

    private var titleForTransaction: String {
        switch transaction.kind {
        case .lightning:
            return transaction.type == .incoming ? "Lightning request" : "Lightning payment"
        case .onchain:
            return transaction.type == .incoming ? "On-chain receive" : "On-chain payment"
        case .ecash:
            return transaction.status == .pending ? "Pending Ecash" : "Ecash"
        }
    }

    private var kindIcon: String {
        switch transaction.kind {
        case .lightning: return "bolt.fill"
        case .onchain:   return "bitcoinsign.circle.fill"
        case .ecash:     return "link.circle"
        }
    }

    private var statusIcon: String {
        switch transaction.status {
        case .completed: return "checkmark.circle.fill"
        case .pending:   return "clock"
        case .failed:    return "xmark.circle.fill"
        }
    }

    private var statusText: String {
        switch transaction.status {
        case .completed:
            switch transaction.kind {
            case .ecash:     return transaction.type == .incoming ? "Received" : "Sent"
            case .lightning: return transaction.type == .incoming ? "Received" : "Paid"
            case .onchain:   return transaction.type == .incoming ? "Received" : "Sent"
            }
        case .pending: return transaction.displayStatusText
        case .failed:  return "Failed"
        }
    }

    private var statusColor: Color {
        switch transaction.status {
        case .completed: return .green
        case .pending:   return .orange
        case .failed:    return .red
        }
    }

    private func extractMintHost(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }

    private var onchainExplorerURL: URL? {
        guard transaction.kind == .onchain else { return nil }
        if let txid = transaction.preimage {
            return OnchainExplorer.transactionWebURL(
                for: txid,
                address: transaction.invoice,
                mintURL: transaction.mintUrl
            )
        }
        guard let address = transaction.invoice else { return nil }
        return OnchainExplorer.addressWebURL(for: address, mintURL: transaction.mintUrl)
    }

    // MARK: - Actions

    private func copyContent(_ content: String) {
        UIPasteboard.general.string = content
        HapticFeedback.notification(.success)
        copyButtonText = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            copyButtonText = "Copy"
        }
    }
}

/// Applies the right SF Symbol effect for the transaction status:
/// pulsing clock while pending, bouncing checkmark on success.
private struct StatusSymbolEffect: ViewModifier {
    let status: WalletTransaction.TransactionStatus

    func body(content: Content) -> some View {
        switch status {
        case .pending:
            content.symbolEffect(.pulse, options: .repeating)
        case .completed:
            content.symbolEffect(.bounce, value: status)
        case .failed:
            content
        }
    }
}
