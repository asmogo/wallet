import SwiftUI

struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    let transaction: WalletTransaction
    @ObservedObject var settings = SettingsManager.shared
    
    @State private var copyButtonText = "COPY"
    @State private var showShareSheet = false
    
    /// Returns the content to display as QR code (token for Ecash, invoice for Lightning)
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
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // QR Code (for token or lightning invoice)
                    if let content = qrContent {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .frame(width: 280, height: 280)
                            
                            QRCodeView(content: content)
                                .frame(width: 250, height: 250)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.cashuMutedText.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.top, 20)
                    } else {
                        // Placeholder icon if no QR content
                        Image(systemName: kindIcon)
                            .font(.system(size: 80))
                            .foregroundColor(settings.accentColor)
                            .padding(.top, 40)
                    }
                    
                    // Amount
                    Text(settings.formatAmountShort(transaction.amount))
                        .font(.cashuBalanceMedium)
                        .foregroundColor(.white)
                    
                    // Status badge with icon
                    statusBadge
                    
                    // Info Rows
                    VStack(spacing: 16) {
                        // Show fee for outgoing ecash transactions
                        if transaction.kind == .ecash && transaction.type == .outgoing {
                            detailRow(icon: "arrow.up.arrow.down", label: "Fee", value: "\(transaction.fee) sat")
                        }
                        detailRow(icon: "camera.viewfinder", label: "Unit", value: settings.unitLabel.uppercased())
                        detailRow(icon: "info.circle", label: "State", value: transaction.status.displayText, valueColor: statusColor)
                        if let mintUrl = transaction.mintUrl {
                            detailRow(icon: "building.columns", label: "Mint", value: extractMintHost(mintUrl))
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Copy and Share buttons (if there's content)
                    if let content = qrContent {
                        HStack(spacing: 12) {
                            Button(action: { copyContent(content) }) {
                                HStack {
                                    Image(systemName: copyButtonText == "COPIED" ? "checkmark" : "doc.on.doc")
                                    Text(copyButtonText)
                                }
                            }
                            .buttonStyle(CashuPrimaryButtonStyle())
                            
                            Button(action: { showShareSheet = true }) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(CashuSecondaryButtonStyle())
                            .frame(width: 50)
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 20)
                }
            }
            .navigationTitle(titleForTransaction)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showShareSheet) {
                if let token = transaction.token {
                    // For ecash tokens, use cashu: URL scheme
                    CashuTokenShareSheet(token: token)
                } else if let invoice = transaction.invoice {
                    // For lightning invoices, share as-is
                    ShareSheet(items: [invoice])
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text(titleForTransaction)
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    private var titleForTransaction: String {
        switch transaction.kind {
        case .lightning:
            return "Lightning invoice"
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
                .foregroundColor(statusColor)
            Text(statusText)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(statusColor)
        }
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
            return settings.accentColor
        case .pending:
            return .cashuWarning
        case .failed:
            return .cashuError
        }
    }
    
    private func detailRow(icon: String, label: String, value: String, valueColor: Color = .white) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)
                Text(label)
                    .foregroundColor(.cashuMutedText)
            }
            Spacer()
            Text(value)
                .foregroundColor(valueColor)
        }
        .font(.subheadline)
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
            copyButtonText = "COPY"
        }
    }
}

// ShareSheet is defined in SendView.swift
