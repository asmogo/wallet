import SwiftUI

struct SendView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared
    
    @State private var amountString = ""
    @State private var memo = ""
    @State private var generatedToken: String?
    @State private var tokenFee: UInt64 = 0
    @State private var isGenerating = false
    @State private var showMeltView = false
    @State private var showPaymentRequestPay = false
    @State private var errorMessage: String?
    @State private var showMintPicker = false
    
    // Token claim detection
    @State private var isCheckingClaim = false
    @State private var tokenClaimed = false
    @State private var checkingTask: Task<Void, Never>?
    
    // Copy button feedback
    @State private var copyButtonText = "COPY"
    @State private var showShareSheet = false
    @State private var lockWithP2PK = false
    @State private var p2pkPubkeyInput = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()
                
                if let token = generatedToken {
                    tokenDisplayView(token: token)
                } else {
                    sendInputView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Send Ecash")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        Image(systemName: lockWithP2PK ? "lock.fill" : "lock.open")
                            .font(.caption)
                            .foregroundColor(lockWithP2PK ? .cashuAccent : .cashuMutedText)
                        Text(lockWithP2PK ? "P2PK" : "SAT")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(lockWithP2PK ? .cashuAccent : .cashuMutedText)
                    }
                }
            }
            .fullScreenCover(isPresented: $showMeltView) {
                MeltView()
                    .environmentObject(walletManager)
            }
            .fullScreenCover(isPresented: $showPaymentRequestPay) {
                PaymentRequestPayView()
                    .environmentObject(walletManager)
            }
            .sheet(isPresented: $showMintPicker) {
                MintSelectorSheet(selectedMint: $walletManager.activeMint)
                    .environmentObject(walletManager)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showShareSheet) {
                if let token = generatedToken {
                    CashuTokenShareSheet(token: token)
                }
            }
            .onDisappear {
                // Cancel any running polling task when view disappears
                checkingTask?.cancel()
            }
        }
    }
    
    // MARK: - Send Input View
    
    private var sendInputView: some View {
        VStack(spacing: 0) {
            // Mint selector
            if let mint = walletManager.activeMint {
                mintSelector(mint: mint)
                    .padding(.horizontal)
                    .padding(.top, 16)
            }
            
            Spacer()
            
            // Amount display
            VStack(spacing: 4) {
                Text(amountString.isEmpty ? "0" : amountString)
                    .font(.cashuBalance)
                    .foregroundColor(.white)
                
                Text("sat")
                    .font(.title3)
                    .foregroundColor(.cashuMutedText)
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.cashuError)
                    .padding(.top, 8)
            }
            
            Spacer()

            p2pkLockSection
                .padding(.horizontal)
                .padding(.bottom, 8)
            
            // Numeric keypad
            NumericKeyboard(text: $amountString)
                .padding(.horizontal, 20)
            
            // Send button
            Button(action: generateToken) {
                if isGenerating {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text("SEND")
                }
            }
            .buttonStyle(CashuPrimaryButtonStyle(isDisabled: !canSend))
            .disabled(!canSend || isGenerating)
            .padding(.horizontal)
            .padding(.vertical, 20)
            
            VStack(spacing: 10) {
                Button(action: { showMeltView = true }) {
                    HStack {
                        Image(systemName: "bolt.fill")
                        Text("Pay Lightning Request")
                    }
                    .font(.subheadline)
                    .foregroundColor(.cashuAccent)
                }

                if settings.enablePaymentRequests {
                    Button(action: { showPaymentRequestPay = true }) {
                        HStack {
                            Image(systemName: "arrow.up.doc.fill")
                            Text("Pay Cashu Payment Request")
                        }
                        .font(.subheadline)
                        .foregroundColor(.cashuAccent)
                    }
                }
            }
            .padding(.bottom, 30)
        }
    }
    
    private func mintSelector(mint: MintInfo) -> some View {
        Button(action: { showMintPicker = true }) {
            HStack(spacing: 12) {
                // Mint icon
                Circle()
                    .fill(Color.cashuCardBackground)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "building.columns")
                            .foregroundColor(.gray)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(mint.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    
                    Text("\(mint.balance) sat available")
                        .font(.caption)
                        .foregroundColor(.cashuMutedText)
                }
                
                Spacer()
                
                Image(systemName: "chevron.down")
                    .foregroundColor(.cashuMutedText)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.cashuCardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.cashuBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var canSend: Bool {
        guard let amount = UInt64(amountString), amount > 0 else { return false }
        guard let mint = walletManager.activeMint else { return false }
        if lockWithP2PK && normalizedP2PKPubkeyInput == nil { return false }
        return amount <= mint.balance
    }

    private var p2pkLockSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $lockWithP2PK.animation(.easeInOut(duration: 0.2))) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lock ecash to P2PK key")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Text("Receiver must have the matching private key to claim this token.")
                        .font(.caption2)
                        .foregroundColor(.cashuMutedText)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))

            if lockWithP2PK {
                TextField("02... P2PK public key", text: $p2pkPubkeyInput)
                    .font(.system(.caption, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.cashuSecondaryBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.cashuBorder, lineWidth: 1)
                            )
                    )
                    .foregroundColor(.white)

                HStack {
                    if let ownKey = settings.p2pkKeys.last {
                        Button(action: { p2pkPubkeyInput = ownKey.publicKey }) {
                            Text("Use my latest key")
                                .font(.caption)
                                .foregroundColor(settings.accentColor)
                        }
                    }

                    Spacer()
                }

                if !p2pkPubkeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   normalizedP2PKPubkeyInput == nil {
                    Text("Invalid P2PK key format")
                        .font(.caption2)
                        .foregroundColor(.cashuError)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.cashuCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.cashuBorder, lineWidth: 1)
                )
        )
    }
    
    // MARK: - Token Display View
    
    private func tokenDisplayView(token: String) -> some View {
        VStack(spacing: 16) {
            // Status header
            if tokenClaimed {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.cashuAccent)
                    Text("Sent Ecash")
                        .foregroundColor(.cashuAccent)
                }
                .font(.headline)
                .padding(.top, 8)
            } else {
                HStack(spacing: 8) {
                    if isCheckingClaim {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.cashuWarning)
                    } else {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.cashuWarning)
                    }
                    Text("Pending Ecash")
                        .foregroundColor(.cashuWarning)
                }
                .font(.headline)
                .padding(.top, 8)

                if !settings.checkSentTokens {
                    Text("Automatic status checks are off. Use CHECK STATUS to verify redemption.")
                        .font(.caption)
                        .foregroundColor(.cashuMutedText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            // QR Code with border
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .frame(width: 280, height: 280)
                
                QRCodeView(content: token)
                    .frame(width: 250, height: 250)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.cashuMutedText.opacity(0.3), lineWidth: 1)
            )
            
            // Checking progress bar
            if isCheckingClaim && !tokenClaimed {
                ProgressView()
                    .progressViewStyle(LinearProgressViewStyle(tint: .cashuAccent))
                    .frame(width: 280)
            }
            
            // Amount
            Text("\(amountString) sat")
                .font(.cashuBalanceSmall)
                .foregroundColor(.white)
            
            // Details
            VStack(spacing: 12) {
                detailRow(icon: "arrow.up.arrow.down", label: "Fee", value: "\(tokenFee) sat")
                detailRow(icon: "square.grid.2x2", label: "Unit", value: "SAT")
                detailRow(icon: "clock", label: "Status", value: tokenClaimed ? "Claimed" : "Pending")
                if let mint = walletManager.activeMint {
                    detailRow(icon: "building.columns", label: "Mint", value: extractMintHost(mint.url))
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Action buttons
            if tokenClaimed {
                // Token was claimed - show done button
                Button(action: { dismiss() }) {
                    Text("DONE")
                }
                .buttonStyle(CashuPrimaryButtonStyle())
                .padding(.horizontal)
                .padding(.bottom, 30)
            } else {
                // Show copy and share buttons
                if !settings.checkSentTokens {
                    Button(action: {
                        Task { await checkTokenClaimNow(token: token) }
                    }) {
                        if isCheckingClaim {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("CHECK STATUS")
                        }
                    }
                    .buttonStyle(CashuSecondaryButtonStyle())
                    .padding(.horizontal)
                }

                HStack(spacing: 12) {
                    Button(action: { copyToken(token) }) {
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
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            guard settings.checkSentTokens else { return }
            startClaimPolling(token: token)
        }
    }
    
    private func detailRow(icon: String, label: String, value: String) -> some View {
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
                .foregroundColor(.white)
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
    
    private func generateToken() {
        guard let amount = UInt64(amountString), amount > 0 else { return }
        let selectedP2PKPubkey = lockWithP2PK ? normalizedP2PKPubkeyInput : nil
        guard !lockWithP2PK || selectedP2PKPubkey != nil else {
            errorMessage = "Please enter a valid P2PK key."
            return
        }
        
        isGenerating = true
        errorMessage = nil
        
        Task { @MainActor in
            do {
                let result = try await walletManager.sendTokens(
                    amount: amount,
                    memo: memo.isEmpty ? nil : memo,
                    p2pkPubkey: selectedP2PKPubkey
                )
                generatedToken = result.token
                tokenFee = result.fee
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    private var normalizedP2PKPubkeyInput: String? {
        let trimmed = p2pkPubkeyInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        let allHex = trimmed.unicodeScalars.allSatisfy { hexChars.contains($0) }

        if trimmed.count == 64 && allHex {
            return "02\(trimmed)"
        }

        guard trimmed.count == 66,
              (trimmed.hasPrefix("02") || trimmed.hasPrefix("03")),
              allHex else {
            return nil
        }

        return trimmed
    }
    
    private func copyToken(_ token: String) {
        UIPasteboard.general.string = token
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Show "COPIED" feedback for 3 seconds
        copyButtonText = "COPIED"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            copyButtonText = "COPY"
        }
    }
    
    // MARK: - Token Claim Detection
    
    private func startClaimPolling(token: String) {
        // Cancel any existing task
        checkingTask?.cancel()
        
        isCheckingClaim = true
        
        checkingTask = Task {
            let maxChecks = 10
            let maxInterval: UInt64 = 15_000_000_000
            var checkCount = 0
            var interval: UInt64 = 5_000_000_000
            
            while !Task.isCancelled && !tokenClaimed && checkCount < maxChecks {
                try? await Task.sleep(nanoseconds: interval)
                
                guard !Task.isCancelled else { break }
                
                // Check if token has been spent
                let isSpent = await walletManager.checkTokenSpendable(token: token)
                
                if isSpent {
                    await MainActor.run {
                        tokenClaimed = true
                        isCheckingClaim = false
                        
                        // Haptic feedback for success
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }
                    
                    // Remove from pending and reload transactions so HistoryView updates
                    // We need to find the pending token ID - it's stored when we create the token
                    await walletManager.markTokenAsClaimed(token: token)
                    
                    await MainActor.run {
                        // Auto-dismiss after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            dismiss()
                        }
                    }
                    break
                }
                
                checkCount += 1
                interval = min(interval + 1_000_000_000, maxInterval)
            }
            
            await MainActor.run {
                isCheckingClaim = false
            }
        }
    }

    private func checkTokenClaimNow(token: String) async {
        await MainActor.run {
            isCheckingClaim = true
        }

        let isSpent = await walletManager.checkTokenSpendable(token: token)
        if isSpent {
            await MainActor.run {
                tokenClaimed = true
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
            await walletManager.markTokenAsClaimed(token: token)
            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    dismiss()
                }
            }
        }

        await MainActor.run {
            isCheckingClaim = false
        }
    }
}

// MARK: - Melt View (Lightning Payment)

struct MeltView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager

    @State private var invoice = ""
    @State private var amountString = ""
    @State private var meltQuote: MeltQuoteInfo?
    @State private var isGettingQuote = false
    @State private var isPaying = false
    @State private var isPaid = false
    @State private var preimage: String?
    @State private var errorMessage: String?

    private var isHumanReadableAddress: Bool {
        let trimmed = invoice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmed.firstIndex(of: "@") else { return false }
        let user = trimmed[trimmed.startIndex..<atIndex]
        let domain = trimmed[trimmed.index(after: atIndex)...]
        return !user.isEmpty && domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()

                if isPaid {
                    paymentSuccessView
                } else if let quote = meltQuote {
                    quoteConfirmView(quote: quote)
                } else {
                    invoiceInputView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Pay Lightning")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Invoice Input View

    private var invoiceInputView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bolt.fill")
                .font(.system(size: 48))
                .foregroundColor(.cashuAccent)

            Text("Pay Lightning Request")
                .font(.title2)
                .foregroundColor(.white)

            Text("Paste a Lightning invoice/offer or BIP 353 address")
                .font(.subheadline)
                .foregroundColor(.cashuMutedText)

            TextEditor(text: $invoice)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .frame(height: 100)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.cashuCardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.cashuBorder, lineWidth: 1)
                        )
                )
                .padding(.horizontal)

            if isHumanReadableAddress {
                VStack(spacing: 4) {
                    Text(amountString.isEmpty ? "0" : amountString)
                        .font(.cashuBalance)
                        .foregroundColor(.white)
                    Text("sat")
                        .font(.title3)
                        .foregroundColor(.cashuMutedText)
                }
                NumericKeyboard(text: $amountString)
                    .padding(.horizontal, 20)
            }

            Button(action: pasteFromClipboard) {
                HStack {
                    Image(systemName: "doc.on.clipboard")
                    Text("Paste from Clipboard")
                }
            }
            .buttonStyle(CashuSecondaryButtonStyle())
            .padding(.horizontal)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.cashuError)
            }

            if !isHumanReadableAddress {
                Spacer()
            }

            Button(action: getQuote) {
                if isGettingQuote {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text("GET QUOTE")
                }
            }
            .buttonStyle(CashuPrimaryButtonStyle(isDisabled: !canGetQuote))
            .disabled(!canGetQuote || isGettingQuote)
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
    }

    private var canGetQuote: Bool {
        if isHumanReadableAddress {
            guard let amount = UInt64(amountString), amount > 0 else { return false }
            return true
        }
        return !invoice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Quote Confirm View
    
    private func quoteConfirmView(quote: MeltQuoteInfo) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            Text("\(quote.amount)")
                .font(.cashuBalanceMedium)
                .foregroundColor(.cashuAccent)
            
            Text("sat")
                .font(.title3)
                .foregroundColor(.cashuMutedText)
            
            VStack(spacing: 16) {
                detailRow(label: "Amount", value: "\(quote.amount) sat")
                detailRow(label: "Fee", value: "\(quote.feeReserve) sat")
                Divider()
                    .background(Color.cashuBorder)
                detailRow(label: "Total", value: "\(quote.totalAmount) sat", highlight: true)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.cashuCardBackground)
            )
            .padding(.horizontal)
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.cashuError)
            }
            
            Spacer()
            
            Button(action: payInvoice) {
                if isPaying {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text("PAY \(quote.totalAmount) SAT")
                }
            }
            .buttonStyle(CashuPrimaryButtonStyle())
            .disabled(isPaying)
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
    }
    
    private func detailRow(label: String, value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.cashuMutedText)
            Spacer()
            Text(value)
                .fontWeight(highlight ? .bold : .regular)
                .foregroundColor(highlight ? .cashuAccent : .white)
        }
        .font(.subheadline)
    }
    
    // MARK: - Payment Success View
    
    private var paymentSuccessView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.cashuAccent)
            
            Text("Payment Sent!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Text("DONE")
            }
            .buttonStyle(CashuPrimaryButtonStyle())
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
    }
    
    // MARK: - Actions
    
    private func pasteFromClipboard() {
        if let content = UIPasteboard.general.string {
            invoice = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    private func getQuote() {
        let trimmedInvoice = invoice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInvoice.isEmpty else { return }

        isGettingQuote = true
        errorMessage = nil

        Task { @MainActor in
            do {
                if isHumanReadableAddress {
                    guard let amount = UInt64(amountString), amount > 0 else { return }
                    let quote = try await walletManager.createHumanReadableMeltQuote(address: trimmedInvoice, amount: amount)
                    meltQuote = quote
                } else {
                    let quote = try await walletManager.createMeltQuote(request: trimmedInvoice)
                    meltQuote = quote
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isGettingQuote = false
        }
    }

    private func payInvoice() {
        guard let quote = meltQuote else { return }

        isPaying = true
        errorMessage = nil

        Task { @MainActor in
            do {
                preimage = try await walletManager.meltTokens(quoteId: quote.id)
                isPaid = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isPaying = false
        }
    }
}

// MARK: - Melt View With Pre-filled Invoice (from QR scan)

struct MeltViewWithInvoice: View {
    let invoice: String
    var onComplete: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    
    @State private var meltQuote: MeltQuoteInfo?
    @State private var isGettingQuote = true
    @State private var isPaying = false
    @State private var isPaid = false
    @State private var preimage: String?
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()
                
                if isPaid {
                    paymentSuccessView
                } else if let quote = meltQuote {
                    quoteConfirmView(quote: quote)
                } else if isGettingQuote {
                    loadingView
                } else {
                    errorView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { 
                        onComplete?()
                        dismiss() 
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Pay Lightning")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .onAppear {
                getQuote()
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.5)
                .tint(.cashuAccent)
            
            Text("Getting quote...")
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
        }
    }
    
    private var errorView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.cashuError)
            
            Text("Failed to get quote")
                .font(.title2)
                .foregroundColor(.white)
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            Button(action: getQuote) {
                Text("TRY AGAIN")
            }
            .buttonStyle(CashuPrimaryButtonStyle())
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
    }
    
    private func quoteConfirmView(quote: MeltQuoteInfo) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            Text("\(quote.amount)")
                .font(.cashuBalanceMedium)
                .foregroundColor(.cashuAccent)
            
            Text("sat")
                .font(.title3)
                .foregroundColor(.cashuMutedText)
            
            VStack(spacing: 16) {
                detailRow(label: "Amount", value: "\(quote.amount) sat")
                detailRow(label: "Fee", value: "\(quote.feeReserve) sat")
                Divider()
                    .background(Color.cashuBorder)
                detailRow(label: "Total", value: "\(quote.totalAmount) sat", highlight: true)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.cashuCardBackground)
            )
            .padding(.horizontal)
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.cashuError)
            }
            
            Spacer()
            
            Button(action: payInvoice) {
                if isPaying {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text("PAY \(quote.totalAmount) SAT")
                }
            }
            .buttonStyle(CashuPrimaryButtonStyle())
            .disabled(isPaying)
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
    }
    
    private func detailRow(label: String, value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.cashuMutedText)
            Spacer()
            Text(value)
                .fontWeight(highlight ? .bold : .regular)
                .foregroundColor(highlight ? .cashuAccent : .white)
        }
        .font(.subheadline)
    }
    
    private var paymentSuccessView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.cashuAccent)
            
            Text("Payment Sent!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: { 
                onComplete?()
                dismiss() 
            }) {
                Text("DONE")
            }
            .buttonStyle(CashuPrimaryButtonStyle())
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
    }
    
    private func getQuote() {
        isGettingQuote = true
        errorMessage = nil
        
        Task { @MainActor in
            do {
                let quote = try await walletManager.createMeltQuote(request: invoice)
                meltQuote = quote
            } catch {
                errorMessage = error.localizedDescription
            }
            isGettingQuote = false
        }
    }
    
    private func payInvoice() {
        guard let quote = meltQuote else { return }
        
        isPaying = true
        errorMessage = nil
        
        Task { @MainActor in
            do {
                preimage = try await walletManager.meltTokens(quoteId: quote.id)
                isPaid = true
                
                // Auto-dismiss after 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                onComplete?()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isPaying = false
        }
    }
}

// MARK: - Melt View With Pre-filled Address (from QR scan)

struct MeltViewWithAddress: View {
    let address: String
    var onComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager

    @State private var amountString = ""
    @State private var meltQuote: MeltQuoteInfo?
    @State private var isGettingQuote = false
    @State private var isPaying = false
    @State private var isPaid = false
    @State private var preimage: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()

                if isPaid {
                    paymentSuccessView
                } else if let quote = meltQuote {
                    quoteConfirmView(quote: quote)
                } else {
                    amountInputView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        onComplete?()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Pay Lightning")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }
    }

    private var amountInputView: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "bolt.fill")
                .font(.system(size: 48))
                .foregroundColor(.cashuAccent)
                .padding(.bottom, 12)

            Text(address)
                .font(.subheadline)
                .foregroundColor(.cashuMutedText)
                .padding(.bottom, 24)

            VStack(spacing: 4) {
                Text(amountString.isEmpty ? "0" : amountString)
                    .font(.cashuBalance)
                    .foregroundColor(.white)
                Text("sat")
                    .font(.title3)
                    .foregroundColor(.cashuMutedText)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.cashuError)
                    .padding(.top, 8)
            }

            Spacer()

            NumericKeyboard(text: $amountString)
                .padding(.horizontal, 20)

            Button(action: getQuote) {
                if isGettingQuote {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text("GET QUOTE")
                }
            }
            .buttonStyle(CashuPrimaryButtonStyle(isDisabled: !canGetQuote))
            .disabled(!canGetQuote || isGettingQuote)
            .padding(.horizontal)
            .padding(.vertical, 20)
        }
    }

    private var canGetQuote: Bool {
        guard let amount = UInt64(amountString), amount > 0 else { return false }
        return true
    }

    private func quoteConfirmView(quote: MeltQuoteInfo) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Text("\(quote.amount)")
                .font(.cashuBalanceMedium)
                .foregroundColor(.cashuAccent)

            Text("sat")
                .font(.title3)
                .foregroundColor(.cashuMutedText)

            VStack(spacing: 16) {
                detailRow(label: "To", value: address)
                detailRow(label: "Amount", value: "\(quote.amount) sat")
                detailRow(label: "Fee", value: "\(quote.feeReserve) sat")
                Divider()
                    .background(Color.cashuBorder)
                detailRow(label: "Total", value: "\(quote.totalAmount) sat", highlight: true)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.cashuCardBackground)
            )
            .padding(.horizontal)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.cashuError)
            }

            Spacer()

            Button(action: payInvoice) {
                if isPaying {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text("PAY \(quote.totalAmount) SAT")
                }
            }
            .buttonStyle(CashuPrimaryButtonStyle())
            .disabled(isPaying)
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
    }

    private func detailRow(label: String, value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.cashuMutedText)
            Spacer()
            Text(value)
                .fontWeight(highlight ? .bold : .regular)
                .foregroundColor(highlight ? .cashuAccent : .white)
        }
        .font(.subheadline)
    }

    private var paymentSuccessView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.cashuAccent)

            Text("Payment Sent!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Spacer()

            Button(action: {
                onComplete?()
                dismiss()
            }) {
                Text("DONE")
            }
            .buttonStyle(CashuPrimaryButtonStyle())
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
    }

    private func getQuote() {
        guard let amount = UInt64(amountString), amount > 0 else { return }

        isGettingQuote = true
        errorMessage = nil

        Task { @MainActor in
            do {
                let quote = try await walletManager.createHumanReadableMeltQuote(address: address, amount: amount)
                meltQuote = quote
            } catch {
                errorMessage = error.localizedDescription
            }
            isGettingQuote = false
        }
    }

    private func payInvoice() {
        guard let quote = meltQuote else { return }

        isPaying = true
        errorMessage = nil

        Task { @MainActor in
            do {
                preimage = try await walletManager.meltTokens(quoteId: quote.id)
                isPaid = true

                try? await Task.sleep(nanoseconds: 2_000_000_000)
                onComplete?()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isPaying = false
        }
    }
}

// MARK: - Mint Selector Sheet (for Send/Receive flows)

struct MintSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @Binding var selectedMint: MintInfo?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()
                
                if walletManager.mints.isEmpty {
                    emptyStateView
                } else {
                    mintListView
                }
            }
            .navigationTitle("Select Mint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.cashuMutedText)
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.columns")
                .font(.system(size: 48))
                .foregroundColor(.cashuMutedText)
            
            Text("No Mints Available")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Add a mint from Settings to get started")
                .font(.subheadline)
                .foregroundColor(.cashuMutedText)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var mintListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(walletManager.mints) { mint in
                    mintRow(mint: mint)
                }
            }
            .padding(.top, 8)
        }
    }
    
    private func mintRow(mint: MintInfo) -> some View {
        VStack(spacing: 0) {
            Button(action: { selectMint(mint) }) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.cashuCardBackground)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "building.columns")
                                .foregroundColor(.gray)
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mint.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        
                        Text(formatBalance(mint))
                            .font(.subheadline)
                            .foregroundColor(.cashuMutedText)
                    }
                    
                    Spacer()
                    
                    if selectedMint?.id == mint.id {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(SettingsManager.shared.accentColor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    selectedMint?.id == mint.id 
                        ? SettingsManager.shared.accentColor.opacity(0.1) 
                        : Color.clear
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            Divider()
                .background(Color.cashuBorder)
                .padding(.leading, 76)
        }
    }
    
    private func formatBalance(_ mint: MintInfo) -> String {
        let formatted = SettingsManager.shared.formatAmountBalance(mint.balance)
        return "\(formatted) sat available"
    }
    
    private func selectMint(_ mint: MintInfo) {
        Task {
            do {
                try await walletManager.setActiveMint(mint)
                await MainActor.run {
                    selectedMint = mint
                    dismiss()
                }
            } catch {
                print("Failed to set active mint: \(error)")
                await MainActor.run {
                    selectedMint = mint
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Cashu Token Share Sheet

/// Share sheet that formats cashu tokens with the cashu: URL scheme
struct CashuTokenShareSheet: UIViewControllerRepresentable {
    let token: String
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Format token with cashu: URL scheme for easy sharing
        let cashuUrl = "cashu:\(token)"
        return UIActivityViewController(activityItems: [cashuUrl], applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SendView()
        .environmentObject(WalletManager())
}
