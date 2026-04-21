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
        if let token = transaction.token {
            return token
        }
        if let invoice = transaction.invoice {
            return invoice
        }
        return nil
    }

    private var qrContentTypeLabel: String {
        switch transaction.kind {
        case .ecash:
            return "token"
        case .lightning:
            return "request"
        case .onchain:
            return "address"
        }
    }

    private var qrContentAccessibilityLabel: String {
        switch transaction.kind {
        case .ecash:
            return "ecash token"
        case .lightning:
            return "payment request"
        case .onchain:
            return "bitcoin address"
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                    // QR Code (for token or lightning payment request)
                    if let content = qrContent {
                        QRCodeView(content: content)
                            .frame(width: 250, height: 250)
                            .padding()
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.top, 20)
                    } else {
                        // Placeholder icon if no QR content
                        Image(systemName: kindIcon)
                            .font(.largeTitle)
        .foregroundStyle(Color.accentColor)
                            .padding(.top, 40)
                            .accessibilityHidden(true)
                    }
                    
                    // Amount
                    Text(settings.formatAmountShort(transaction.amount))
                        .font(.title.bold())
                        .accessibilityLabel("Amount: \(settings.formatAmountShort(transaction.amount)) sats")
                        .accessibilityValue("\(settings.formatAmountShort(transaction.amount)) sats")
                    
                    kindBadge
                    statusBadge
                    
                    // Info Rows
                    VStack(spacing: 12) {
                        if transaction.fee > 0 {
                            LabeledContent("Fee", value: "\(transaction.fee) sat")
                        }
                        LabeledContent("Unit", value: settings.unitLabel.uppercased())
                        LabeledContent("State", value: transaction.displayStatusText)
                        if let mintUrl = transaction.mintUrl {
                            LabeledContent("Mint", value: extractMintHost(mintUrl))
                        }
                        if let request = transaction.invoice {
                            detailValueRow(
                                title: transaction.kind == .onchain ? "Address" : "Request",
                                value: request
                            )
                        }
                        if let paymentProof = transaction.preimage {
                            detailValueRow(
                                title: transaction.kind == .onchain ? "Transaction ID" : "Payment Proof",
                                value: paymentProof,
                                monospaced: true
                            )
                        }
                        if let explorerURL = onchainExplorerURL {
                            Link("View in block explorer", destination: explorerURL)
                                .font(.footnote.weight(.medium))
                        }
                    }
                    .font(.subheadline)
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Copy and Share buttons (if there's content)
                    if let content = qrContent {
                        HStack(spacing: 12) {
                            Button(action: { copyContent(content) }) {
                                HStack {
                                    Image(systemName: copyButtonText == "COPIED" ? "checkmark" : "doc.on.doc")
                                        .accessibilityHidden(true)
                                    Text(copyButtonText)
                                }
                            }
                            .glassButton()
                            .accessibilityLabel(copyButtonText == "COPIED" ? "Copied" : "Copy \(qrContentTypeLabel)")
                            .accessibilityHint("Copies the \(qrContentAccessibilityLabel) to clipboard")

                            Button(action: { showShareSheet = true }) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .glassButton()
                            .frame(width: 50)
                            .accessibilityLabel("Share")
                            .accessibilityHint("Opens share sheet for this \(qrContentTypeLabel)")
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 20)
            }
            .navigationTitle(titleForTransaction)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showShareSheet) {
                if let token = transaction.token {
                    // For ecash tokens, use cashu: URL scheme
                    CashuTokenShareSheet(token: token)
                } else if let invoice = transaction.invoice {
                    ShareSheet(items: [invoice])
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }

                ToolbarItem(placement: .principal) {
                    Text(titleForTransaction)
                        .font(.headline)
                }
            }
        }
    }
    
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
        case .lightning:
            return "bolt.fill"
        case .onchain:
            return "bitcoinsign.circle.fill"
        case .ecash:
            return "link.circle"
        }
    }

    private var kindBadge: some View {
        Label(transaction.kind.displayName, systemImage: kindIcon)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(kindBadgeColor.opacity(0.14), in: Capsule())
            .foregroundStyle(kindBadgeColor)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Payment method: \(transaction.kind.displayName)")
    }
    
    private var statusBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
            Text(statusText)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(statusColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(statusText)")
    }
    
    private var statusIcon: String {
        switch transaction.status {
        case .completed:
            return "checkmark.circle.fill"
        case .pending:
            return "clock.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
    
    private var statusText: String {
        switch transaction.status {
        case .completed:
            switch transaction.kind {
            case .ecash:
                return transaction.type == .incoming ? "Received!" : "Sent!"
            case .lightning:
                return transaction.type == .incoming ? "Received!" : "Paid!"
            case .onchain:
                return transaction.type == .incoming ? "Received!" : "Sent!"
            }
        case .pending:
            return transaction.displayStatusText
        case .failed:
            return "Failed"
        }
    }
    
    private var statusColor: Color {
        switch transaction.status {
        case .completed:
            return Color.accentColor
        case .pending:
            return .orange
        case .failed:
            return .red
        }
    }

    private var kindBadgeColor: Color {
        switch transaction.kind {
        case .ecash:
            return .accentColor
        case .lightning:
            return .yellow
        case .onchain:
            return .orange
        }
    }
    
    private func extractMintHost(_ url: String) -> String {
        if let urlObj = URL(string: url) {
            return urlObj.host ?? url
        }
        return url
    }

    private var onchainExplorerURL: URL? {
        guard transaction.kind == .onchain else {
            return nil
        }

        if let txid = transaction.preimage {
            return OnchainExplorer.transactionWebURL(
                for: txid,
                address: transaction.invoice,
                mintURL: transaction.mintUrl
            )
        }

        guard let address = transaction.invoice else {
            return nil
        }

        return OnchainExplorer.addressWebURL(for: address, mintURL: transaction.mintUrl)
    }

    private func detailValueRow(title: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .font(monospaced ? .system(.footnote, design: .monospaced) : .footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Actions
    
    private func copyContent(_ content: String) {
        UIPasteboard.general.string = content
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Show "COPIED" feedback for 3 seconds
        copyButtonText = "COPIED"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            copyButtonText = "Copy"
        }
    }
}

// ShareSheet is defined in SendView.swift
