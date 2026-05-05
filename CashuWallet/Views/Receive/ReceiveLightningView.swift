import SwiftUI
import CashuDevKit

private enum Bolt12OfferAmountMode: String, CaseIterable, Identifiable {
    case amountless
    case fixedAmount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .amountless:
            return "Amountless"
        case .fixedAmount:
            return "Set Amount"
        }
    }
}

struct ReceiveLightningView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared

    @State private var amountString = ""
    @State private var selectedMethod: PaymentMethodKind = .bolt11
    @State private var bolt12OfferAmountMode: Bolt12OfferAmountMode = .amountless
    @State private var mintQuote: MintQuoteInfo?
    @State private var isCreatingRequest = false
    @State private var isMinting = false
    @State private var isCheckingPayment = false
    @State private var isPaid = false
    @State private var errorMessage: String?
    @State private var showMintPicker = false
    @State private var copiedRequest = false
    @State private var quoteStatusTask: Task<Void, Never>?
    @State private var expiryTimeRemaining: TimeInterval = 0
    @State private var expiryTimer: Timer?
    @State private var isExpired = false
    @State private var onchainObservation: OnchainPaymentObservation?
    @State private var quoteCreatedAt: Date?

    var body: some View {
        NavigationStack {
            Group {
                if let quote = mintQuote {
                    requestDisplayView(quote: quote)
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
                    Text(screenTitle)
                        .font(.headline)
                }

                if mintQuote == nil && showsAmountEntry {
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
            .onAppear {
                syncSelectedMethodWithActiveMint()
            }
            .onChange(of: walletManager.activeMint?.id) {
                syncSelectedMethodWithActiveMint()
            }
            .onChange(of: selectedMethod) {
                errorMessage = nil
                onchainObservation = nil
            }
            .onDisappear {
                quoteStatusTask?.cancel()
                expiryTimer?.invalidate()
                quoteStatusTask = nil
                expiryTimer = nil
            }
        }
    }

    // MARK: - Computed Properties

    private var availableMintMethods: [PaymentMethodKind] {
        let methods = walletManager.activeMint?.supportedMintMethods ?? [.bolt11]
        let orderedMethods = PaymentMethodKind.allCases.filter { methods.contains($0) }
        return orderedMethods.isEmpty ? [.bolt11] : orderedMethods
    }

    private var shouldShowMethodPicker: Bool {
        availableMintMethods.count > 1
    }

    private var screenTitle: String {
        guard let quote = mintQuote else { return "Receive" }

        switch quote.paymentMethod {
        case .bolt11:
            return "Lightning Invoice"
        case .bolt12:
            return "BOLT12 Offer"
        case .onchain:
            return "Bitcoin Address"
        }
    }

    private var canCreateRequest: Bool {
        if showsAmountEntry {
            guard let amount = UInt64(amountString), amount > 0 else { return false }
        }
        return !isCreatingRequest
    }

    private var showsAmountEntry: Bool {
        selectedMethod.requiresMintAmount
            || (selectedMethod.supportsOptionalMintAmount && bolt12OfferAmountMode == .fixedAmount)
    }

    private var formattedInputAmount: String {
        formattedAmount(sats: UInt64(amountString))
    }

    // MARK: - Amount Input View

    private var amountInputView: some View {
        VStack(spacing: 0) {
            if let mint = walletManager.activeMint {
                mintSelector(mint: mint)
                    .padding(.horizontal)
                    .padding(.top, 12)
            }

            if shouldShowMethodPicker {
                paymentMethodPicker
                    .padding(.horizontal)
                    .padding(.top, 12)
            }

            if selectedMethod.supportsOptionalMintAmount {
                bolt12AmountModePicker
                    .padding(.horizontal)
                    .padding(.top, 12)
            }

            Spacer()

            if showsAmountEntry {
                amountDisplaySection
            } else {
                amountlessOfferSection
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 12)
                    .padding(.horizontal)
            }

            Spacer()

            if showsAmountEntry {
                numberPad
                    .padding(.horizontal, 24)
            }

            Button(action: createRequest) {
                if isCreatingRequest {
                    ProgressView()
                } else {
                    Text("Create \(selectedMethod.requestDisplayName)")
                }
            }
            .glassButton()
            .disabled(!canCreateRequest)
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
    }

    private var paymentMethodPicker: some View {
        Picker("Payment Method", selection: $selectedMethod) {
            ForEach(availableMintMethods, id: \.self) { method in
                Text(method.displayName).tag(method)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Payment method")
    }

    private var bolt12AmountModePicker: some View {
        Picker("Offer Amount", selection: $bolt12OfferAmountMode) {
            ForEach(Bolt12OfferAmountMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("BOLT12 offer amount mode")
    }

    private var amountDisplaySection: some View {
        VStack(spacing: 8) {
            Text(formattedInputAmount)
                .font(.largeTitle.bold())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())

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
        .accessibilityLabel("Request amount: \(amountString.isEmpty ? "0" : amountString) sats")
    }

    private var amountlessOfferSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("Amountless Offer")
                .font(.title3.weight(.semibold))

            Text("Sender sets amount")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Amountless BOLT12 offer. The sender chooses the amount.")
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
            ["", "0", "\u{232B}"]
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
                        if key == "\u{232B}" {
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
                .accessibilityLabel(key == "\u{232B}" ? "Delete" : key)
            }
        }
        .frame(height: 56)
    }

    private func handleKeyPress(_ key: String) {
        if key == "\u{232B}" {
            if !amountString.isEmpty {
                amountString.removeLast()
            }
        } else if amountString == "0" {
            amountString = key
        } else {
            amountString.append(key)
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
                        Image(systemName: "bitcoinsign.bank.building")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "bitcoinsign.bank.building")
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

    // MARK: - Request Display View

    private func requestDisplayView(quote: MintQuoteInfo) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    QRCodeView(content: quote.request)
                        .frame(width: 280, height: 280)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.top, 8)

                    amountSummary(for: quote)

                    statusBadge

                    if let explorerURL = blockExplorerURL(for: quote) {
                        Link(blockExplorerLabel(for: quote), destination: explorerURL)
                            .font(.subheadline.weight(.medium))
                    }

                    if !isPaid && !isExpired && expiryTimeRemaining > 0 {
                        expiryView
                    }

                    VStack(spacing: 12) {
                        detailRow(icon: "arrow.left.arrow.right", label: "Type", value: quote.paymentMethod.displayName)
                        detailRow(icon: "banknote", label: "Unit", value: settings.unitLabel.uppercased())
                        detailRow(
                            icon: "number",
                            label: "Amount",
                            value: quote.amount.map { formattedAmount(sats: $0) } ?? "Set by sender"
                        )
                        detailRow(icon: "info.circle", label: "State", value: quoteStateText(for: quote))
                        if let mint = walletManager.activeMint {
                            detailRow(
                                icon: "bitcoinsign.bank.building",
                                label: "Mint",
                                value: extractMintHost(mint.url)
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }

            Button(action: { copyRequest(quote.request) }) {
                Label(copyButtonTitle(for: quote), systemImage: copiedRequest ? "checkmark" : "doc.on.doc")
            }
            .glassButton()
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .onAppear {
            startQuoteMonitoring(for: quote)
            startExpiryCountdown(quote: quote)
        }
    }

    private func amountSummary(for quote: MintQuoteInfo) -> some View {
        VStack(spacing: 6) {
            if let amount = quote.amount {
                Text(formattedAmount(sats: amount))
                    .font(.title.bold())
                    .accessibilityLabel("Request amount: \(amount) sats")
            } else {
                Text("Amount set by sender")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
            }

            Text(quote.paymentMethod.requestDisplayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
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
                .multilineTextAlignment(.trailing)
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
        } else if mintQuote?.state == .paid || mintQuote?.state == .issued {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .accessibilityHidden(true)
                Text("Payment detected")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.green)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
                Text(pendingStatusText)
            }
            .font(.subheadline)
            .foregroundStyle(.orange)
        }
    }

    private var pendingStatusText: String {
        guard let quote = mintQuote else {
            return "Waiting for payment..."
        }

        switch quote.paymentMethod {
        case .bolt11, .bolt12:
            return "Waiting for payment..."
        case .onchain:
            if let observation = onchainObservation {
                return "\(observation.statusText). Trying to mint..."
            }
            return "Waiting for on-chain payment..."
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

    private func formattedAmount(sats: UInt64?) -> String {
        let amount = sats ?? 0
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

    private func quoteStateText(for quote: MintQuoteInfo) -> String {
        if isPaid { return "Paid" }
        if isExpired { return "Expired" }
        if quote.paymentMethod == .onchain,
           quote.state == .pending,
           let observation = onchainObservation {
            return observation.statusText
        }

        switch quote.state {
        case .issued:
            return "Issued"
        case .paid:
            return "Paid"
        case .pending:
            return "Pending"
        }
    }

    private func copyButtonTitle(for quote: MintQuoteInfo) -> String {
        copiedRequest ? "Copied" : "Copy \(quote.paymentMethod.requestDisplayName)"
    }

    private func blockExplorerURL(for quote: MintQuoteInfo) -> URL? {
        guard quote.paymentMethod == .onchain else { return nil }

        if let txid = onchainObservation?.txid {
            return OnchainExplorer.transactionWebURL(
                for: txid,
                address: quote.request,
                mintURL: walletManager.activeMint?.url
            )
        }

        return OnchainExplorer.addressWebURL(for: quote.request, mintURL: walletManager.activeMint?.url)
    }

    private func blockExplorerLabel(for quote: MintQuoteInfo) -> String {
        guard quote.paymentMethod == .onchain else {
            return "View in block explorer"
        }

        return onchainObservation == nil
            ? "View address in block explorer"
            : "View transaction in block explorer"
    }

    private func syncSelectedMethodWithActiveMint() {
        guard availableMintMethods.contains(selectedMethod) else {
            selectedMethod = availableMintMethods.first ?? .bolt11
            return
        }
    }

    // MARK: - Actions

    private func createRequest() {
        let amountValue = UInt64(amountString)
        let requestMethod = selectedMethod
        let requestAmount = showsAmountEntry ? amountValue : nil

        if showsAmountEntry, (amountValue ?? 0) == 0 {
            return
        }

        isCreatingRequest = true
        errorMessage = nil
        isPaid = false
        isExpired = false
        copiedRequest = false
        onchainObservation = nil
        quoteCreatedAt = nil
        expiryTimeRemaining = 0
        quoteStatusTask?.cancel()
        expiryTimer?.invalidate()

        Task { @MainActor in
            do {
                let quote = try await walletManager.createMintQuote(
                    amount: requestAmount,
                    method: requestMethod
                )
                quoteCreatedAt = Date()
                mintQuote = quote
            } catch {
                errorMessage = "Failed: \(error.localizedDescription)"
            }
            isCreatingRequest = false
        }
    }

    private func copyRequest(_ request: String) {
        UIPasteboard.general.string = request
        copiedRequest = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            copiedRequest = false
        }
    }

    private func startExpiryCountdown(quote: MintQuoteInfo) {
        expiryTimer?.invalidate()
        expiryTimer = nil

        guard let expiry = quote.expiry, expiry > 0 else {
            expiryTimeRemaining = 0
            isExpired = false
            return
        }

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
                quoteStatusTask?.cancel()
            }
        }
    }

    private func startQuoteMonitoring(for quote: MintQuoteInfo) {
        quoteStatusTask?.cancel()
        quoteStatusTask = Task { @MainActor in
            switch quote.paymentMethod {
            case .bolt11:
                await pollMintQuote(quoteId: quote.id, initialInterval: 5, maxInterval: 15)
            case .bolt12:
                await monitorMintQuoteViaSubscription(quoteId: quote.id, paymentMethod: .bolt12)
            case .onchain:
                await refreshMintQuoteStatus()
                await pollMintQuote(quoteId: quote.id, initialInterval: 30, maxInterval: 30)
            }
        }
    }

    @MainActor
    private func monitorMintQuoteViaSubscription(
        quoteId: String,
        paymentMethod: PaymentMethodKind
    ) async {
        do {
            if let subscription = try await walletManager.subscribeToMintQuote(
                quoteId: quoteId,
                paymentMethod: paymentMethod
            ) {
                while !Task.isCancelled && !isPaid && !isExpired {
                    let notification = try await subscription.recv()
                    guard !Task.isCancelled else { break }

                    switch notification {
                    case .mintQuoteUpdate(let quoteUpdate):
                        guard quoteUpdate.quote == quoteId else { continue }
                        await refreshMintQuoteStatus()
                    case .proofState, .meltQuoteUpdate:
                        continue
                    }
                }
                return
            }
        } catch {
            // Fall back to polling when subscriptions are unavailable or fail.
        }

        await pollMintQuote(quoteId: quoteId, initialInterval: 10, maxInterval: 30)
    }

    @MainActor
    private func pollMintQuote(
        quoteId: String,
        initialInterval: UInt64,
        maxInterval: UInt64
    ) async {
        var interval = initialInterval

        while !Task.isCancelled && !isPaid && !isExpired && mintQuote?.id == quoteId {
            try? await Task.sleep(nanoseconds: interval * 1_000_000_000)

            guard !Task.isCancelled, !isPaid, !isExpired, mintQuote?.id == quoteId else { break }
            await refreshMintQuoteStatus()

            if interval < maxInterval {
                interval = min(interval + 1, maxInterval)
            }
        }
    }

    @MainActor
    private func refreshMintQuoteStatus() async {
        guard let quote = mintQuote, !isExpired, !isMinting else { return }

        isCheckingPayment = true
        defer { isCheckingPayment = false }

        do {
            let updatedQuote = try await walletManager.checkMintQuote(quoteId: quote.id)
            mintQuote = updatedQuote

            if updatedQuote.paymentMethod == .onchain, updatedQuote.state == .pending {
                await refreshOnchainObservation(for: updatedQuote)
                AppLogger.wallet.info(
                    "Attempting to mint pending on-chain quote \(updatedQuote.id, privacy: .public); the mint will reject it if confirmations are not ready"
                )
                await mintQuoteIfReady(updatedQuote)
                return
            } else {
                onchainObservation = nil
            }

            switch updatedQuote.state {
            case .pending:
                return
            case .paid:
                await mintQuoteIfReady(updatedQuote)
            case .issued:
                await completeReceivedQuote(refreshWalletState: true)
            }
        } catch {
            // Ignore transient polling failures and keep monitoring.
        }
    }

    @MainActor
    private func refreshOnchainObservation(for quote: MintQuoteInfo) async {
        guard quote.paymentMethod == .onchain,
              let amount = quote.amount,
              let createdAt = quoteCreatedAt,
              let mintURL = walletManager.activeMint?.url else {
            onchainObservation = nil
            return
        }

        onchainObservation = await OnchainExplorer.observePayment(
            for: quote.request,
            mintURL: mintURL,
            expectedAmount: amount,
            createdAfter: createdAt
        )
    }

    @MainActor
    private func mintQuoteIfReady(_ quote: MintQuoteInfo) async {
        guard !isMinting else { return }

        isMinting = true
        defer { isMinting = false }

        do {
            let _ = try await walletManager.mintTokens(quoteId: quote.id)
            await completeReceivedQuote(refreshWalletState: false)
        } catch {
            let errorString = error.localizedDescription.lowercased()
            if errorString.contains("issued") || errorString.contains("already") {
                await completeReceivedQuote(refreshWalletState: true)
                return
            }

            if quote.paymentMethod == .onchain {
                AppLogger.wallet.info(
                    "On-chain quote \(quote.id, privacy: .public) is not mintable yet: \(String(describing: error), privacy: .public)"
                )
                return
            }

            AppLogger.wallet.error(
                "Failed to mint quote \(quote.id, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    @MainActor
    private func completeReceivedQuote(refreshWalletState: Bool) async {
        guard !isPaid else { return }

        isPaid = true
        quoteStatusTask?.cancel()
        expiryTimer?.invalidate()

        if refreshWalletState {
            await walletManager.refreshBalance()
            await walletManager.loadTransactions()
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        dismiss()
    }
}

#Preview {
    ReceiveLightningView()
        .environmentObject(WalletManager())
}
