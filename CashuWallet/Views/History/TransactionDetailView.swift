import SwiftUI

struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    let transaction: WalletTransaction
    @ObservedObject var settings = SettingsManager.shared
    
    @State private var copyButtonText = "Copy"
    @State private var showShareSheet = false
    
    /// Returns the content to display as QR code (token for Ecash, payment request for Lightning)
    private var qrContent: String? {
        if let token = transaction.token {
            return token
        }
        if let invoice = transaction.invoice {
            return invoice
        }
        return nil
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
                    
                    // Status badge with icon
                    statusBadge
                    
                    // Info Rows
                    VStack(spacing: 12) {
                        // Show fee for outgoing ecash transactions
                        if transaction.kind == .ecash && transaction.type == .outgoing {
                            LabeledContent("Fee", value: "\(transaction.fee) sat")
                        }
                        LabeledContent("Unit", value: settings.unitLabel.uppercased())
                        LabeledContent("State", value: transaction.status.displayText)
                        if let mintUrl = transaction.mintUrl {
                            LabeledContent("Mint", value: extractMintHost(mintUrl))
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
                            .accessibilityLabel(copyButtonText == "COPIED" ? "Copied" : "Copy \(transaction.kind == .ecash ? "token" : "invoice")")
                            .accessibilityHint("Copies the \(transaction.kind == .ecash ? "ecash token" : "lightning invoice") to clipboard")

                            Button(action: { showShareSheet = true }) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .glassButton()
                            .frame(width: 50)
                            .accessibilityLabel("Share")
                            .accessibilityHint("Opens share sheet for this \(transaction.kind == .ecash ? "token" : "invoice")")
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
                    // For lightning payment requests, share as-is
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
            return "Lightning request"
        case .ecash:
            return transaction.status == .pending ? "Pending Ecash" : "Ecash"
        }
    }
    
    private var kindIcon: String {
        switch transaction.kind {
        case .lightning:
            return "bolt.fill"
        case .ecash:
            return "link.circle"
        }
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
            // Different text based on transaction type and kind
            if transaction.kind == .ecash {
                return transaction.type == .incoming ? "Received!" : "Sent!"
            } else {
                return transaction.type == .incoming ? "Paid!" : "Paid!"
            }
        case .pending:
            return "Pending"
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
    
    private func extractMintHost(_ url: String) -> String {
        if let urlObj = URL(string: url) {
            return urlObj.host ?? url
        }
        return url
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
