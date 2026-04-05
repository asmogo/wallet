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
    @State private var errorMessage: String?
    @State private var showMintPicker = false

    // Token claim detection
    @State private var isCheckingClaim = false
    @State private var tokenClaimed = false
    @State private var checkingTask: Task<Void, Never>?

    // Copy button feedback
    @State private var copyButtonText = "Copy"
    @State private var showShareSheet = false
    @State private var lockWithP2PK = false
    @State private var p2pkPubkeyInput = ""

    @ObservedObject private var priceService = PriceService.shared

    var body: some View {
        NavigationStack {
            Group {
                if let token = generatedToken {
                    tokenDisplayView(token: token)
                } else {
                    sendInputView
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
                    Text(generatedToken != nil ? "Pending Ecash" : "Send Ecash")
                        .font(.headline)
                }

                if generatedToken == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 6) {
                            Button(action: { lockWithP2PK.toggle() }) {
                                Image(systemName: lockWithP2PK ? "lock.fill" : "lock.open")
                                    .font(.caption)
                                    .foregroundStyle(lockWithP2PK ? Color.accentColor : .secondary)
                            }
                            Button(action: { settings.useBitcoinSymbol.toggle() }) {
                                Text(settings.unitLabel)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }

                if generatedToken != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(action: { showShareSheet = true }) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            if !settings.checkSentTokens {
                                Button(action: {
                                    if let token = generatedToken {
                                        Task { await checkTokenClaimNow(token: token) }
                                    }
                                }) {
                                    Label("Check Status", systemImage: "arrow.clockwise")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
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

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }

            Spacer()

            // P2PK section (only when enabled)
            if lockWithP2PK {
                p2pkInputSection
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            // Number pad
            numberPad
                .padding(.horizontal, 24)

            // Send button
            Button(action: generateToken) {
                if isGenerating {
                    ProgressView()
                } else {
                    Text("Send")
                }
            }
            .glassButton()
            .disabled(!canSend || isGenerating)
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
        [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]]
    }

    private func numberKey(_ key: String) -> some View {
        Group {
            if key.isEmpty {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Button(action: { handleKeyPress(key) }) {
                    Group {
                        if key == "⌫" {
                            Image(systemName: "chevron.left").font(.title3)
                        } else {
                            Text(key).font(.title2.weight(.medium))
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
            if !amountString.isEmpty { amountString.removeLast() }
        } else {
            if amountString == "0" { amountString = key } else { amountString.append(key) }
        }
    }

    // MARK: - Mint Selector

    private func mintSelector(mint: MintInfo) -> some View {
        Button(action: { showMintPicker = true }) {
            HStack(spacing: 12) {
                if let iconUrl = mint.iconUrl, let url = URL(string: iconUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "building.columns").foregroundStyle(.secondary)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "building.columns")
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(mint.name).font(.subheadline.weight(.medium))
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
    }

    private var canSend: Bool {
        guard let amount = UInt64(amountString), amount > 0 else { return false }
        guard let mint = walletManager.activeMint else { return false }
        if lockWithP2PK && normalizedP2PKPubkeyInput == nil { return false }
        return amount <= mint.balance
    }

    @ViewBuilder
    private var p2pkInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("02... public key", text: $p2pkPubkeyInput)
                .font(.system(.caption, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                )

            if let ownKey = settings.p2pkKeys.last {
                Button(action: { p2pkPubkeyInput = ownKey.publicKey }) {
                    Text("Use my latest key")
                        .font(.caption)
                }
            }

            if !p2pkPubkeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               normalizedP2PKPubkeyInput == nil {
                Text("Invalid P2PK key format")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Token Display View

    private func tokenDisplayView(token: String) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    // QR Code
                    QRCodeView(content: token)
                        .frame(width: 280, height: 280)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.top, 8)

                    // Amount
                    Text(formattedAmount)
                        .font(.title.bold())

                    // Status
                    if tokenClaimed {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Claimed")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                    } else if isCheckingClaim {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.8)
                            Text("Checking...")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                            Text("Pending")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    }

                    // Details
                    VStack(spacing: 12) {
                        detailRow(icon: "arrow.up.arrow.down", label: "Fee", value: "\(tokenFee) sat")
                        detailRow(icon: "banknote", label: "Unit", value: settings.unitLabel.uppercased())
                        detailRow(icon: "banknote", label: "Fiat",
                                  value: priceService.btcPriceUSD > 0
                                      ? priceService.formatSatsAsFiat(UInt64(amountString) ?? 0) : "$0.00")
                        if let mint = walletManager.activeMint {
                            detailRow(icon: "building.columns", label: "Mint",
                                      value: extractMintHost(mint.url))
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Copy button
            Button(action: { copyToken(token) }) {
                Label(copyButtonText, systemImage: copyButtonText == "Copied" ? "checkmark" : "doc.on.doc")
            }
            .glassButton()
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .onAppear {
            guard settings.checkSentTokens else { return }
            startClaimPolling(token: token)
        }
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private var formattedAmount: String {
        let amount = amountString.isEmpty ? "0" : amountString
        return settings.useBitcoinSymbol ? "₿\(amount)" : "\(amount) sat"
    }

    private func formatBalance(_ sats: UInt64) -> String {
        settings.useBitcoinSymbol ? "₿\(sats)" : "\(sats) sat"
    }

    private func extractMintHost(_ url: String) -> String {
        URL(string: url)?.host ?? url
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
                HapticFeedback.notification(.success)
            } catch {
                errorMessage = error.localizedDescription
                HapticFeedback.notification(.error)
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
        HapticFeedback.notification(.success)

        // Show "COPIED" feedback for 3 seconds
        copyButtonText = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            copyButtonText = "Copy"
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

    @FocusState private var meltAmountFieldFocused: Bool

    private var isHumanReadableAddress: Bool {
        let trimmed = invoice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmed.firstIndex(of: "@") else { return false }
        let user = trimmed[trimmed.startIndex..<atIndex]
        let domain = trimmed[trimmed.index(after: atIndex)...]
        return !user.isEmpty && domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        NavigationStack {
            Group {
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
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }

                ToolbarItem(placement: .principal) {
                    Text("Pay Lightning")
                        .font(.headline)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { settings.useBitcoinSymbol.toggle() }) {
                        Text(settings.unitLabel)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }

    // MARK: - Invoice Input View

    private var invoiceInputView: some View {
        VStack(spacing: 0) {
            // Mint selector
            if let mint = walletManager.activeMint {
                meltMintSelector(mint: mint)
                    .padding(.horizontal)
                    .padding(.top, 12)
            }

            // Invoice input
            HStack(alignment: .top) {
                TextField("Lightning address or invoice", text: $invoice, axis: .vertical)
                    .font(.body)
                    .lineLimit(3...5)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Paste", action: pasteFromClipboard)
                    .font(.subheadline.weight(.medium))
            }
            .padding()
            .liquidGlass(in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 16)

            // Amount field for lightning addresses
            if isHumanReadableAddress {
                VStack(spacing: 4) {
                    TextField("0", text: $amountString)
                        .keyboardType(.numberPad)
                        .focused($meltAmountFieldFocused)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("sat")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)
                .onAppear { meltAmountFieldFocused = true }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 12)
                    .padding(.horizontal)
            }

            Spacer()

            // Get Quote button
            Button(action: getQuote) {
                if isGettingQuote {
                    ProgressView()
                } else {
                    Text("Get Quote")
                }
            }
            .glassButton()
            .disabled(!canGetQuote || isGettingQuote)
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    private func meltMintSelector(mint: MintInfo) -> some View {
        HStack(spacing: 12) {
            if let iconUrl = mint.iconUrl, let url = URL(string: iconUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "building.columns").foregroundStyle(.secondary)
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                Image(systemName: "building.columns")
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(mint.name).font(.subheadline.weight(.medium))
                Text("\(mint.balance) sat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 12))
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    // Amount
                    Text("\(quote.totalAmount) sat")
                        .font(.largeTitle.bold())
                        .padding(.top, 24)

                    // Details
                    VStack(spacing: 12) {
                        meltDetailRow(label: "Amount", value: "\(quote.amount) sat")
                        meltDetailRow(label: "Fee", value: "\(quote.feeReserve) sat")
                        if let mint = walletManager.activeMint {
                            meltDetailRow(label: "Mint", value: URL(string: mint.url)?.host ?? mint.url)
                        }
                    }
                    .padding(.horizontal)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
            }

            Button(action: payInvoice) {
                if isPaying {
                    ProgressView()
                } else {
                    Text("Pay \(quote.totalAmount) sat")
                }
            }
            .glassButton()
            .disabled(isPaying)
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    private func meltDetailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }

    // MARK: - Payment Success View

    private var paymentSuccessView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)

                Text("Payment Sent!")
                    .font(.title2.weight(.semibold))
            }

            Spacer()

            Button(action: { dismiss() }) {
                Text("Done")
            }
            .glassButton()
            .padding(.horizontal)
            .padding(.bottom, 16)
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
                }
                .accessibilityLabel("Close")
            }

            ToolbarItem(placement: .principal) {
                Text("Pay Lightning")
                    .font(.headline)
            }
        }
        .onAppear {
            getQuote()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .tint(.accentColor)

            Text("Getting quote...")
                .font(.headline)

            Spacer()
        }
    }

    private var errorView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text("Failed to get quote")
                .font(.title2)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            Button(action: getQuote) {
                Text("Try Again")
            }
            .glassButton()
            .accessibilityLabel("Try again")
            .accessibilityHint("Retries fetching the payment quote")
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
    }

    private func quoteConfirmView(quote: MeltQuoteInfo) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Text("\(quote.amount)")
                .font(.title.bold())
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("\(quote.amount) sats")

            Text("sat")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                LabeledContent("Amount", value: "\(quote.amount) sat")
                LabeledContent("Fee", value: "\(quote.feeReserve) sat")
                Divider()
                LabeledContent {
                    Text("\(quote.totalAmount) sat")
                        .fontWeight(.bold)
                        .foregroundStyle(Color.accentColor)
                } label: {
                    Text("Total")
                }
            }
            .font(.subheadline)
            .padding(12)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button(action: payInvoice) {
                if isPaying {
                    ProgressView()
                } else {
                    Text("Pay \(quote.totalAmount) sat")
                }
            }
            .glassButton(prominent: true).controlSize(.large)
            .disabled(isPaying)
            .accessibilityLabel(isPaying ? "Processing payment" : "Pay \(quote.totalAmount) sats")
            .accessibilityHint("Sends lightning payment")
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
    }

    private var paymentSuccessView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("Payment Sent!")
                .font(.title)
                .fontWeight(.bold)

            Spacer()

            Button(action: {
                onComplete?()
                dismiss()
            }) {
                Text("Done")
            }
            .glassButton()
            .accessibilityLabel("Done")
            .accessibilityHint("Closes the payment screen")
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

    @FocusState private var addressAmountFieldFocused: Bool

    var body: some View {
        NavigationStack {
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
                }
                .accessibilityLabel("Close")
            }

            ToolbarItem(placement: .principal) {
                Text("Pay Lightning")
                    .font(.headline)
            }
        }
    }

    private var amountInputView: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "bolt.fill")
                .font(.title)
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 12)
                .accessibilityHidden(true)

            Text(address)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
                .accessibilityLabel("Paying to: \(address)")

            VStack(spacing: 4) {
                TextField("0", text: $amountString)
                    .keyboardType(.numberPad)
                    .focused($addressAmountFieldFocused)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("sat")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Payment amount")
            .accessibilityValue("\(amountString.isEmpty ? "0" : amountString) sats")
            .onAppear {
                addressAmountFieldFocused = true
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }

            Spacer()

            Button(action: getQuote) {
                if isGettingQuote {
                    ProgressView()
                } else {
                    Text("Get Quote")
                }
            }
            .glassButton(prominent: true).controlSize(.large)
            .disabled(!canGetQuote || isGettingQuote)
            .accessibilityLabel(isGettingQuote ? "Getting quote" : "Get quote")
            .accessibilityHint("Fetches a payment quote for this address")
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
                .font(.title.bold())
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("\(quote.amount) sats")

            Text("sat")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                LabeledContent("To", value: address)
                LabeledContent("Amount", value: "\(quote.amount) sat")
                LabeledContent("Fee", value: "\(quote.feeReserve) sat")
                Divider()
                LabeledContent {
                    Text("\(quote.totalAmount) sat")
                        .fontWeight(.bold)
                        .foregroundStyle(Color.accentColor)
                } label: {
                    Text("Total")
                }
            }
            .font(.subheadline)
            .padding(12)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button(action: payInvoice) {
                if isPaying {
                    ProgressView()
                } else {
                    Text("Pay \(quote.totalAmount) sat")
                }
            }
            .glassButton(prominent: true).controlSize(.large)
            .disabled(isPaying)
            .accessibilityLabel(isPaying ? "Processing payment" : "Pay \(quote.totalAmount) sats")
            .accessibilityHint("Sends lightning payment to \(address)")
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
    }

    private var paymentSuccessView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("Payment Sent!")
                .font(.title)
                .fontWeight(.bold)

            Spacer()

            Button(action: {
                onComplete?()
                dismiss()
            }) {
                Text("Done")
            }
            .glassButton()
            .accessibilityLabel("Done")
            .accessibilityHint("Closes the payment screen")
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
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close")
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.columns")
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No Mints Available")
                .font(.headline)

            Text("Add a mint from Settings to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var mintListView: some View {
        List(walletManager.mints) { mint in
            Button(action: { selectMint(mint) }) {
                HStack(spacing: 12) {
                    mintIcon(for: mint)
                        .overlay(alignment: .bottomTrailing) {
                            if selectedMint?.id == mint.id {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 12, height: 12)
                                    .overlay(
                                        Circle().stroke(Color(.systemBackground), lineWidth: 2)
                                    )
                                    .offset(x: 2, y: 2)
                            }
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(mint.name)
                            .font(.body.weight(.medium))
                        Text(SettingsManager.shared.formatAmountBalance(mint.balance) + " sat")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if selectedMint?.id == mint.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func mintIcon(for mint: MintInfo) -> some View {
        if let iconUrl = mint.iconUrl, let url = URL(string: iconUrl) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                mintIconPlaceholder
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            mintIconPlaceholder
        }
    }

    private var mintIconPlaceholder: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: "building.columns")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
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
