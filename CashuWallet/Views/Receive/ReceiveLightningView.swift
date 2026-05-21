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
    @State private var monitoredQuoteId: String?

    var body: some View {
        NavigationStack {
            Group {
                if let quote = mintQuote {
                    requestDisplayView(quote: quote)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                } else {
                    amountInputView
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .animation(.snappy(duration: 0.35), value: mintQuote != nil)
            .navigationBarTitleDisplayMode(.inline)
            // No nav bar chrome — the title + close button float over the
            // black canvas. This kills the secondary gray bar the user was
            // (rightly) complaining about. The content has enough top
            // padding to clear the safe-area inset so nothing overlaps.
            .toolbarBackground(.hidden, for: .navigationBar)
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

                if let quote = mintQuote {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: quote.request) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share request")
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
                monitoredQuoteId = nil
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
                NumberPadAmountInput(amountString: $amountString)
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
        HStack(spacing: 8) {
            ForEach(availableMintMethods, id: \.self) { method in
                methodPill(method: method)
            }
        }
        .padding(4)
        .background(.thinMaterial, in: Capsule())
        .accessibilityLabel("Payment method")
    }

    private func methodPill(method: PaymentMethodKind) -> some View {
        let isSelected = selectedMethod == method
        return Button(action: {
            guard selectedMethod != method else { return }
            HapticFeedback.selection()
            withAnimation(.snappy) { selectedMethod = method }
        }) {
            Text(method.displayName)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(isSelected ? Color.primary.opacity(0.12) : Color.clear)
                )
                .foregroundStyle(isSelected ? .primary : .secondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var bolt12AmountModePicker: some View {
        HStack(spacing: 8) {
            ForEach(Bolt12OfferAmountMode.allCases) { mode in
                bolt12ModePill(mode: mode)
            }
        }
        .padding(4)
        .background(.thinMaterial, in: Capsule())
        .accessibilityLabel("BOLT12 offer amount mode")
    }

    private func bolt12ModePill(mode: Bolt12OfferAmountMode) -> some View {
        let isSelected = bolt12OfferAmountMode == mode
        return Button(action: {
            guard bolt12OfferAmountMode != mode else { return }
            HapticFeedback.selection()
            withAnimation(.snappy) { bolt12OfferAmountMode = mode }
        }) {
            Text(mode.title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(isSelected ? Color.primary.opacity(0.12) : Color.clear)
                )
                .foregroundStyle(isSelected ? .primary : .secondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var amountDisplaySection: some View {
        CurrencyAmountDisplay(
            sats: UInt64(amountString) ?? 0,
            primary: $settings.amountDisplayPrimary
        )
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
                VStack(spacing: 24) {
                    QRCodeView(content: quote.request, showControls: false, staticOnly: true)
                        .frame(width: 280, height: 280)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                        .padding(.top, 8)
                        .contextMenu {
                            Button(action: { copyRequest(quote.request) }) {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            ShareLink(item: quote.request) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }

                    amountSummary(for: quote)

                    statusBadge

                    if !isPaid && !isExpired && expiryTimeRemaining > 0 {
                        // Plain caption, no pill — fewer surfaces.
                        HStack(spacing: 5) {
                            Image(systemName: "timer")
                                .font(.caption2)
                            Text("Expires in \(formatTimeRemaining(expiryTimeRemaining))")
                                .font(.footnote)
                        }
                        .foregroundStyle(expiryTimeRemaining < 60 ? Color.red : Color.primary.opacity(0.5))
                    }

                    if let explorerURL = blockExplorerURL(for: quote) {
                        Link(blockExplorerLabel(for: quote), destination: explorerURL)
                            .font(.subheadline.weight(.medium))
                    }

                    // Detail rows live directly on the canvas — no gray card.
                    // Hairline dividers separate them; eye flows down the
                    // page without competing surfaces.
                    VStack(spacing: 0) {
                        detailRow(
                            icon: "number",
                            label: "Amount",
                            value: quote.amount.map { formattedAmount(sats: $0) } ?? "Set by sender"
                        )
                        canvasDivider
                        detailRow(icon: "info.circle", label: "State", value: quoteStateText(for: quote))
                        if let mint = walletManager.activeMint {
                            canvasDivider
                            detailRow(
                                icon: "bitcoinsign.bank.building",
                                label: "Mint",
                                value: extractMintHost(mint.url)
                            )
                        }
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal)
            }

            Button(action: { copyRequest(quote.request) }) {
                Text(copyButtonTitle(for: quote))
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
                // Smaller than the QR — the QR is the focal element on this
                // screen; the amount confirms it.
                CurrencyAmountDisplay(
                    sats: amount,
                    primary: $settings.amountDisplayPrimary,
                    primarySize: 32
                )
                .accessibilityLabel("Request amount: \(amount) sats")
            } else {
                Text("Amount set by sender")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
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
                .lineLimit(1)
                .truncationMode(.middle)
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

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        Group {
            if isPaid {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolEffect(.bounce, value: isPaid)
                        .accessibilityHidden(true)
                    Text("Payment Received!")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
            } else if isCheckingPayment || isMinting {
                HStack(spacing: 6) {
                    ProgressView()
                        .tint(.accentColor)
                        .scaleEffect(0.8)
                    Text(isMinting ? "Minting..." : "Checking...")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .transition(.opacity)
            } else if isExpired {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .accessibilityHidden(true)
                    Text("Expired")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)
                .transition(.opacity)
            } else if mintQuote?.state == .paid || mintQuote?.state == .issued {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .symbolEffect(.bounce, value: mintQuote?.state)
                        .accessibilityHidden(true)
                    Text("Payment detected")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .symbolEffect(.pulse, options: .repeating)
                        .accessibilityHidden(true)
                    Text(pendingStatusText)
                }
                .font(.subheadline)
                .foregroundStyle(.orange)
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isPaid)
        .animation(.easeInOut(duration: 0.2), value: isCheckingPayment)
        .animation(.easeInOut(duration: 0.2), value: isMinting)
        .animation(.easeInOut(duration: 0.2), value: isExpired)
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

    // MARK: - Helpers

    private func formattedAmount(sats: UInt64?) -> String {
        let amount = sats ?? 0
        if settings.useBitcoinSymbol {
            return "₿\(amount)"
        }
        return "\(amount) sat"
    }

    private func formatBalance(_ sats: UInt64) -> String {
        AmountFormatter.sats(sats, useBitcoinSymbol: settings.useBitcoinSymbol)
    }

    private func extractMintHost(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }

    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "Expired" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours >= 1 {
            // 23h 59m — under-an-hour precision isn't useful at this scale
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes >= 1 {
            // 12m 30s — seconds matter once we're under the hour
            return "\(minutes)m \(secs)s"
        }
        // Sub-minute, urgency: just seconds
        return "\(secs)s"
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
        monitoredQuoteId = nil
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
        HapticFeedback.notification(.success)
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
        guard monitoredQuoteId != quote.id else { return }

        monitoredQuoteId = quote.id
        quoteStatusTask?.cancel()
        quoteStatusTask = Task { @MainActor in
            switch quote.paymentMethod {
            case .bolt11:
                await pollMintQuote(quoteId: quote.id, initialInterval: 5, maxInterval: 15)
            case .bolt12:
                await monitorMintQuoteViaSubscription(quoteId: quote.id, paymentMethod: .bolt12)
            case .onchain:
                await refreshMintQuoteStatus()
                await monitorMintQuoteViaSubscription(quoteId: quote.id, paymentMethod: .onchain)
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
                    case .mintQuoteOnchainUpdate(let quoteUpdate):
                        guard quoteUpdate.quote == quoteId else { continue }
                        await refreshMintQuoteStatus()
                    case .proofState, .meltQuoteUpdate, .meltQuoteOnchainUpdate:
                        continue
                    }
                }
                return
            }
        } catch {
            // Fall back to polling when subscriptions are unavailable or fail.
        }

        let initialInterval: UInt64 = paymentMethod == .onchain ? 30 : 10
        await pollMintQuote(quoteId: quoteId, initialInterval: initialInterval, maxInterval: 30)
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
            if isAlreadyIssuedMintError(error) {
                await completeReceivedQuote(refreshWalletState: true)
                return
            }

            if quote.paymentMethod == .onchain {
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
        HapticFeedback.notification(.success)
        quoteStatusTask?.cancel()
        expiryTimer?.invalidate()

        if refreshWalletState {
            await walletManager.refreshBalance()
            await walletManager.loadTransactions()
        }

        // Fire the home-screen toast (same notification the NPC mint flow
        // posts from WalletManager). Without this the user lands on the
        // home screen after dismiss with no confirmation that the mint
        // succeeded.
        if let amount = mintQuote?.amount {
            NotificationCenter.default.post(
                name: .cashuTokenReceived,
                object: nil,
                userInfo: ["amount": amount]
            )
        }

        // Brief dwell so the user sees the "Payment Received!" badge flip
        // before the sheet dismisses and the home-screen toast appears.
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        dismiss()
    }

    private func isAlreadyIssuedMintError(_ error: Error) -> Bool {
        let errorString = "\(error.localizedDescription) \(String(describing: error))".lowercased()

        if errorString.contains("already being minted")
            || errorString.contains("not issued")
            || errorString.contains("not yet")
            || errorString.contains("unissued") {
            return false
        }

        return errorString.contains("already issued")
            || errorString.contains("already minted")
            || errorString.contains("quote is issued")
            || errorString.contains("state=issued")
    }
}

#Preview {
    ReceiveLightningView()
        .environmentObject(WalletManager())
}
