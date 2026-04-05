import SwiftUI

struct ReceiveLightningView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var priceService = PriceService.shared

    @State private var amountString = ""
    @State private var mintQuote: MintQuoteInfo?
    @State private var isCreatingInvoice = false
    @State private var isMinting = false
    @State private var isCheckingPayment = false
    @State private var isPaid = false
    @State private var errorMessage: String?
    @State private var showMintPicker = false
    @State private var copyButtonText = "Copy"
    @State private var pollingTask: Task<Void, Never>?
    @State private var expiryTimeRemaining: TimeInterval = 0
    @State private var expiryTimer: Timer?
    @State private var isExpired = false

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
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }

                ToolbarItem(placement: .principal) {
                    Text(mintQuote != nil ? "Lightning Invoice" : "Receive Lightning")
                        .font(.headline)
                }

                if mintQuote == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { settings.useBitcoinSymbol.toggle() }) {
                            Text(settings.unitLabel)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.accentColor)
                        }
                        .accessibilityLabel("Unit: \(settings.unitLabel)")
                        .accessibilityHint("Toggles display unit")
                    }
                }
            }
            .sheet(isPresented: $showMintPicker) {
                MintSelectorSheet(selectedMint: $walletManager.activeMint)
                    .environmentObject(walletManager)
                    .presentationDetents([.medium])
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
                    .padding(.top, 12)
            }

            Spacer()

            // Amount display
            VStack(spacing: 8) {
                Text(formattedAmount)
                    .font(.largeTitle.bold())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())

                // Fiat conversion
                if priceService.btcPriceUSD > 0, let sats = UInt64(amountString) {
                    Text(priceService.formatSatsAsFiat(sats))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("$0.00")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Invoice amount: \(amountString.isEmpty ? "0" : amountString) sats")

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }

            Spacer()

            // Number pad
            numberPad
                .padding(.horizontal, 24)

            // Create invoice button
            Button(action: createInvoice) {
                if isCreatingInvoice {
                    ProgressView()
                } else {
                    Text("Create Invoice")
                }
            }
            .glassButton()
            .disabled(amountString.isEmpty || amountString == "0" || isCreatingInvoice)
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Number Pad

    private var numberPad: some View {
        VStack(spacing: 8) {
            ForEach(numberRows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        numberKey(key)
                    }
                }
            }
        }
    }

    private var numberRows: [[String]] {
        [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["", "0", "⌫"]
        ]
    }

    private func numberKey(_ key: String) -> some View {
        Group {
            if key.isEmpty {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Button(action: { handleKeyPress(key) }) {
                    Group {
                        if key == "⌫" {
                            Image(systemName: "chevron.left")
                                .font(.title3)
                        } else {
                            Text(key)
                                .font(.title2.weight(.medium))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(key == "⌫" ? "Delete" : key)
            }
        }
        .frame(height: 56)
    }

    private func handleKeyPress(_ key: String) {
        if key == "⌫" {
            if !amountString.isEmpty {
                amountString.removeLast()
            }
        } else {
            // Prevent leading zeros
            if amountString == "0" {
                amountString = key
            } else {
                amountString.append(key)
            }
        }
    }

    // MARK: - Mint Selector

    private func mintSelector(mint: MintInfo) -> some View {
        Button(action: { showMintPicker = true }) {
            HStack(spacing: 12) {
                // Mint icon
                if let iconUrl = mint.iconUrl, let url = URL(string: iconUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "building.columns")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "building.columns")
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(mint.name)
                        .font(.subheadline.weight(.medium))
                    Text(formatBalance(mint.balance))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 12), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mint: \(mint.name)")
        .accessibilityHint("Opens mint selector")
    }

    // MARK: - Invoice Display View

    private func invoiceDisplayView(quote: MintQuoteInfo) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    // QR Code
                    QRCodeView(content: quote.request)
                        .frame(width: 280, height: 280)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.top, 8)

                    // Amount
                    Text(formattedAmount)
                        .font(.title.bold())
                        .accessibilityLabel("Invoice amount: \(amountString) sats")

                    // Status
                    statusBadge

                    // Expiry countdown
                    if !isPaid && !isExpired && expiryTimeRemaining > 0 {
                        expiryView
                    }

                    // Details
                    VStack(spacing: 12) {
                        detailRow(icon: "banknote", label: "Unit", value: settings.unitLabel.uppercased())
                        detailRow(icon: "info.circle", label: "State",
                                  value: isPaid ? "Paid" : (isExpired ? "Expired" : "Pending"))
                        if let mint = walletManager.activeMint {
                            detailRow(icon: "building.columns", label: "Mint",
                                      value: extractMintHost(mint.url))
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Copy button
            Button(action: { copyInvoice(quote.request) }) {
                Label(copyButtonText, systemImage: copyButtonText == "Copied" ? "checkmark" : "doc.on.doc")
            }
            .glassButton()
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .onAppear {
            startPaymentPolling()
            startExpiryCountdown(quote: quote)
        }
    }

    // MARK: - Detail Row

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        if isPaid {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .accessibilityHidden(true)
                Text("Payment Received!")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.green)
        } else if isCheckingPayment || isMinting {
            HStack(spacing: 6) {
                ProgressView()
                    .tint(.accentColor)
                    .scaleEffect(0.8)
                Text(isMinting ? "Minting..." : "Checking...")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else if isExpired {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .accessibilityHidden(true)
                Text("Expired")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.red)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
                Text("Waiting for payment...")
            }
            .font(.subheadline)
            .foregroundStyle(.orange)
        }
    }

    // MARK: - Expiry View

    private var expiryView: some View {
        Label("Expires in \(formatTimeRemaining(expiryTimeRemaining))", systemImage: "timer")
            .font(.caption)
            .foregroundStyle(expiryTimeRemaining < 60 ? .red : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .liquidGlass(in: Capsule())
    }

    // MARK: - Helpers

    private var formattedAmount: String {
        let amount = amountString.isEmpty ? "0" : amountString
        if settings.useBitcoinSymbol {
            return "₿\(amount)"
        }
        return "\(amount) sat"
    }

    private func formatBalance(_ sats: UInt64) -> String {
        if settings.useBitcoinSymbol {
            return "₿\(sats)"
        }
        return "\(sats) sat"
    }

    private func extractMintHost(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }

    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        if seconds <= 0 { return "0:00" }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return minutes > 0 ? String(format: "%d:%02d", minutes, secs) : String(format: "0:%02d", secs)
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
        copyButtonText = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            copyButtonText = "Copy"
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

    private func checkPayment() async {
        guard let quote = mintQuote, !isExpired else { return }

        isCheckingPayment = true
        defer { isCheckingPayment = false }
        isMinting = true
        defer { isMinting = false }

        do {
            let _ = try await walletManager.mintTokens(quoteId: quote.id)
            isPaid = true
            pollingTask?.cancel()
            expiryTimer?.invalidate()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            dismiss()
        } catch {
            // Still unpaid, polling continues
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
