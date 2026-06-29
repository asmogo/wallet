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
                            // Hero mirrors the list's directional-arrow language
                            // (down = received, up = sent), muted on a soft
                            // circle — same recipe as TransactionIcon, scaled up.
                            Image(systemName: transaction.type == .incoming ? "arrow.down" : "arrow.up")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 72, height: 72)
                                .background(Color(.secondarySystemFill), in: Circle())
                                .padding(.top, 32)
                                .accessibilityHidden(true)
                        }

                        // Amount — onchain is always sats; others get the fiat toggle.
                        if transaction.kind == .onchain {
                            Text(AmountFormatter.sats(transaction.amount, useBitcoinSymbol: settings.useBitcoinSymbol))
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .accessibilityLabel("Amount: \(transaction.amount) sats")
                        } else {
                            CurrencyAmountDisplay(
                                sats: transaction.amount,
                                primary: $settings.amountDisplayPrimary,
                                primarySize: 32
                            )
                            .accessibilityLabel("Amount: \(transaction.amount) sats")
                        }

                        // Animated status.
                        statusBadge

                        // Detail rows on canvas with hairline dividers. Type and
                        // State are intentionally omitted — the nav title already
                        // names the kind/direction and the status badge above
                        // carries the state.
                        VStack(spacing: 0) {
                            if transaction.fee > 0 {
                                detailRow(icon: "arrow.up.arrow.down", label: "Fee",
                                          value: "\(transaction.fee) sat")
                                canvasDivider
                            }
                            if transaction.kind == .onchain {
                                if let mintUrl = transaction.mintUrl {
                                    detailRow(icon: "bitcoinsign.bank.building", label: "Mint",
                                              value: extractMintHost(mintUrl))
                                }
                                if let request = transaction.invoice {
                                    if transaction.mintUrl != nil { canvasDivider }
                                    detailRow(icon: "qrcode", label: "Address", value: request)
                                }
                                if let preimage = transaction.preimage {
                                    canvasDivider
                                    detailRow(icon: "checkmark.seal", label: "Transaction ID", value: preimage)
                                }
                            } else {
                                detailRow(icon: "banknote", label: "Unit",
                                          value: settings.unitLabel.uppercased())
                                if let mintUrl = transaction.mintUrl {
                                    canvasDivider
                                    detailRow(icon: "bitcoinsign.bank.building", label: "Mint",
                                              value: extractMintHost(mintUrl))
                                }
                                if let request = transaction.invoice {
                                    canvasDivider
                                    detailRow(icon: "doc.text", label: "Request", value: request)
                                }
                                if let preimage = transaction.preimage {
                                    canvasDivider
                                    detailRow(icon: "key", label: "Payment Proof", value: preimage)
                                }
                            }
                        }
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal)
                }

                if let explorerURL = onchainExplorerURL {
                    Link("View in block explorer", destination: explorerURL)
                        .textLinkButton()
                        .padding(.vertical, 12)
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
                    Text(transaction.displayTitle).font(.headline)
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
