import SwiftUI

struct ReceiveLightningView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var npcService = NPCService.shared
    
    @State private var amountString = ""
    @State private var mintQuote: MintQuoteInfo?
    @State private var isCreatingInvoice = false
    @State private var isMinting = false
    @State private var isCheckingPayment = false
    @State private var isPaid = false
    @State private var errorMessage: String?
    @State private var showMintPicker = false
    @State private var copyButtonText = "COPY"
    @State private var pollingTask: Task<Void, Never>?
    @State private var lightningAddressCopied = false
    @State private var expiryTimeRemaining: TimeInterval = 0
    @State private var expiryTimer: Timer?
    @State private var isExpired = false
    @FocusState private var amountFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            Group {
                if let quote = mintQuote {
                    invoiceDisplayView(quote: quote)
                } else {
                    amountInputView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }

                ToolbarItem(placement: .principal) {
                    Text("Receive Lightning")
                        .font(.headline)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Text("SAT")
                        .font(.caption)
                        .fontWeight(.bold)
    .foregroundStyle(Color.accentColor)
                }
            }
            .sheet(isPresented: $showMintPicker) {
                MintSelectorSheet(selectedMint: $walletManager.activeMint)
                    .environmentObject(walletManager)
                    .presentationDetents([.medium])
            }
            .onAppear {
                amountFieldFocused = true
            }
            .onDisappear {
                pollingTask?.cancel()
                expiryTimer?.invalidate()
                pollingTask = nil
                expiryTimer = nil
            }
        }
    }
    
    // MARK: - Amount Input View
    
    private var amountInputView: some View {
        VStack(spacing: 0) {
            // Mint selector
            if let mint = walletManager.activeMint {
                mintSelector(mint: mint)
                    .padding(.horizontal)
                    .padding(.top, 16)
            }
            
            // Lightning address card (if available)
            if npcService.isEnabled && !npcService.lightningAddress.isEmpty {
                lightningAddressCard
                    .padding(.horizontal)
                    .padding(.top, 12)
            }
            
            Spacer()
            
            // Amount display
            VStack(spacing: 4) {
                TextField("0", text: $amountString)
                    .keyboardType(.numberPad)
                    .focused($amountFieldFocused)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text("sat")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Invoice amount")
            .accessibilityValue("\(amountString.isEmpty ? "0" : amountString) sats")
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }
            
            Spacer()

            // Create invoice button
            Button(action: createInvoice) {
                if isCreatingInvoice {
                    ProgressView()
                    } else {
                    Text("CREATE INVOICE")
                }
            }
            .buttonStyle(.bordered).controlSize(.large)
            .disabled(amountString.isEmpty || amountString == "0" || isCreatingInvoice)
            .accessibilityLabel(isCreatingInvoice ? "Creating invoice" : "Create invoice")
            .accessibilityHint("Creates a lightning invoice for \(amountString.isEmpty ? "0" : amountString) sats")
            .padding(.horizontal)
            .padding(.vertical, 30)
        }
    }
    
    // MARK: - Lightning Address Card
    
    private var lightningAddressCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Lightning Address", systemImage: "bolt.fill")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Button(action: copyLightningAddress) {
                    HStack {
                        Text(npcService.lightningAddress)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        Spacer()

                        Image(systemName: lightningAddressCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                            .foregroundColor(lightningAddressCopied ? .accentColor : .secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Lightning address: \(npcService.lightningAddress)")
                .accessibilityHint("Copies lightning address to clipboard")
                .accessibilityValue(lightningAddressCopied ? "Copied" : "")

                Text("Anyone can send sats to this address")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func copyLightningAddress() {
        UIPasteboard.general.string = npcService.lightningAddress
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        lightningAddressCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            lightningAddressCopied = false
        }
    }
    
    private func mintSelector(mint: MintInfo) -> some View {
        Button(action: { showMintPicker = true }) {
            GroupBox {
                HStack(spacing: 12) {
                    Image(systemName: "building.columns")
                        .foregroundColor(.gray)
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(mint.name)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("\(mint.balance) sat available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mint: \(mint.name), \(mint.balance) sats available")
        .accessibilityHint("Opens mint selector")
    }
    
    // MARK: - Invoice Display View
    
    private func invoiceDisplayView(quote: MintQuoteInfo) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // QR Code with border
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .frame(width: 280, height: 280)
                    
                    QRCodeView(content: quote.request)
                        .frame(width: 250, height: 250)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .padding(.top, 20)
                
                // Amount
                Text("\(quote.amount) sat")
                    .font(.title2.bold())
                    .accessibilityLabel("Invoice amount: \(quote.amount) sats")
                
                // Status
                statusBadge
                
                // Expiry countdown (if not paid and not expired)
                if !isPaid && !isExpired && quote.expiry != nil {
                    expiryView
                }
                
                // Details
                VStack(spacing: 12) {
                    LabeledContent("Fee", value: "0 sat")
                    LabeledContent("Unit", value: "SAT")
                    LabeledContent("State", value: isPaid ? "Paid" : (isExpired ? "Expired" : "Pending"))
                    if let mint = walletManager.activeMint {
                        LabeledContent("Mint", value: extractMintHost(mint.url))
                    }
                }
                .font(.subheadline)
                .padding(.horizontal)
                
                Spacer(minLength: 20)
                
                // Copy button
                Button(action: { copyInvoice(quote.request) }) {
                    HStack {
                        Image(systemName: copyButtonText == "COPIED" ? "checkmark" : "doc.on.doc")
                            .accessibilityHidden(true)
                        Text(copyButtonText)
                    }
                }
                .buttonStyle(.bordered).controlSize(.large)
                .accessibilityLabel(copyButtonText == "COPIED" ? "Copied" : "Copy invoice")
                .accessibilityHint("Copies the lightning invoice to clipboard")
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            startPaymentPolling()
            startExpiryCountdown(quote: quote)
        }
    }
    
    // MARK: - Expiry View
    
    private var expiryView: some View {
        Label("Expires in \(formatTimeRemaining(expiryTimeRemaining))", systemImage: "timer")
            .font(.caption)
            .foregroundColor(expiryTimeRemaining < 60 ? .red : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
    
    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        if seconds <= 0 {
            return "0:00"
        }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, secs)
        } else {
            return String(format: "0:%02d", secs)
        }
    }
    
    private func startExpiryCountdown(quote: MintQuoteInfo) {
        guard let expiry = quote.expiry else { return }
        
        let expiryDate = Date(timeIntervalSince1970: Double(expiry))
        expiryTimeRemaining = expiryDate.timeIntervalSince(Date())
        
        if expiryTimeRemaining <= 0 {
            isExpired = true
            return
        }
        
        expiryTimer?.invalidate()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            expiryTimeRemaining -= 1
            if expiryTimeRemaining <= 0 {
                isExpired = true
                expiryTimer?.invalidate()
                pollingTask?.cancel()
            }
        }
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        if isPaid {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .accessibilityHidden(true)
                Text("Payment Received!")
            }
            .font(.subheadline)
            .fontWeight(.medium)
.foregroundStyle(Color.accentColor)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Payment received")
        } else if isCheckingPayment || isMinting {
            HStack(spacing: 6) {
                ProgressView()
                    .tint(.accentColor)
                    .scaleEffect(0.8)
                Text(isMinting ? "Minting..." : "Checking...")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isMinting ? "Minting tokens" : "Checking payment status")
        } else {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
                Text("Waiting for payment...")
            }
            .font(.subheadline)
            .foregroundStyle(.orange)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Waiting for payment")
        }
    }
    
    private func extractMintHost(_ url: String) -> String {
        if let urlObj = URL(string: url) {
            return urlObj.host ?? url
        }
        return url
    }
    
    // MARK: - Actions
    
    private func createInvoice() {
        guard let amountValue = UInt64(amountString), amountValue > 0 else { return }
        
        isCreatingInvoice = true
        errorMessage = nil
        isPaid = false
        isExpired = false
        expiryTimeRemaining = 0
        pollingTask?.cancel()
        expiryTimer?.invalidate()
        
        Task { @MainActor in
            do {
                let quote = try await walletManager.createMintQuote(amount: amountValue)
                mintQuote = quote
            } catch {
                errorMessage = "Failed: \(error.localizedDescription)"
            }
            isCreatingInvoice = false
        }
    }
    
    private func copyInvoice(_ invoice: String) {
        UIPasteboard.general.string = invoice
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Show "COPIED" feedback for 3 seconds
        copyButtonText = "COPIED"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            copyButtonText = "COPY"
        }
    }
    
    private func checkPayment() async {
        guard let quote = mintQuote else { return }
        guard !isExpired else { return }
        
        isCheckingPayment = true
        defer { isCheckingPayment = false }
        isMinting = true
        defer { isMinting = false }
        
        do {
            let _ = try await walletManager.mintTokens(quoteId: quote.id)
            isPaid = true
            pollingTask?.cancel()
            expiryTimer?.invalidate()
            
            // Wait and dismiss
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            dismiss()
        } catch {
            // Quote is still likely unpaid; polling continues with backoff.
        }
    }
    
    private func startPaymentPolling() {
        pollingTask?.cancel()
        
        pollingTask = Task {
            let maxInterval: UInt64 = 15_000_000_000
            var interval: UInt64 = 5_000_000_000
            
            while !Task.isCancelled && !isPaid && mintQuote != nil && !isExpired {
                try? await Task.sleep(nanoseconds: interval)
                if !Task.isCancelled && !isPaid && !isCheckingPayment && !isExpired {
                    await checkPayment()
                }
                interval = min(interval + 1_000_000_000, maxInterval)
            }
        }
    }
}

#Preview {
    ReceiveLightningView()
        .environmentObject(WalletManager())
}
