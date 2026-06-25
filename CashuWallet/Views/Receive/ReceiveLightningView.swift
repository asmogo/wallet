import SwiftUI
import Cdk

struct ReceiveLightningView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared

    @State private var amountString = ""
    @State private var selectedMethod: PaymentMethodKind = .bolt11
    /// BOLT12 only: when true the offer is amountless (sender chooses).
    @State private var isAmountless = false
    @State private var showMethodPicker = false
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
                } else if shouldShowMethodPicker {
                    // Liquid Glass method switcher. On iOS 26 the toolbar renders
                    // bar buttons as glass, so this reads as a sibling of the
                    // close button by construction. Replaces the old inline
                    // `methodChip` text affordance.
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            HapticFeedback.selection()
                            showMethodPicker = true
                        } label: {
                            Image(systemName: selectedMethod.navSymbol)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .accessibilityLabel("Receive method: \(selectedMethod.friendlyTitle)")
                        .accessibilityHint("Opens the receive method picker")
                    }
                }
            }
            .sheet(isPresented: $showMintPicker) {
                MintSelectorSheet(selectedMint: $walletManager.activeMint)
                    .environmentObject(walletManager)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showMethodPicker) {
                MethodPickerSheet(
                    selectedMethod: $selectedMethod,
                    methods: availableMintMethods,
                    onSelect: { _ in
                        // `onChange(of: selectedMethod)` owns the amountless rule.
                    }
                )
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
                // Reusable invoices open amountless (sender chooses) when no
                // amount is typed; any carried-over amount keeps it off, and
                // every non-BOLT12 method is always amount-bearing.
                isAmountless = (selectedMethod == .bolt12) && amountString.isEmpty
            }
            .onChange(of: entryUnit) { oldUnit, newUnit in
                // Flip (or a price load that changes the effective unit): carry
                // the typed amount across, converted, so it stays equivalent.
                amountString = AmountFormatter.entryConverted(raw: amountString, from: oldUnit, to: newUnit)
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
            return "Reusable Invoice"
        case .onchain:
            return "Bitcoin Address"
        }
    }

    /// The unit the keypad is entering in: fiat only when fiat is primary AND a
    /// price is loaded, else sats (mirrors `CurrencyAmountDisplay.effectivePrimary`).
    private var entryUnit: AmountDisplayPrimary {
        (settings.amountDisplayPrimary == .fiat && priceService.btcPriceUSD > 0) ? .fiat : .sats
    }

    /// Satoshis represented by the typed amount, interpreted per `entryUnit`.
    private var amountSats: UInt64 { AmountFormatter.entrySats(raw: amountString, unit: entryUnit) }

    /// The one path that submits no amount: a BOLT12 offer with "Any amount" lit.
    /// Everything else (BOLT11, on-chain, a BOLT12 offer with a typed amount)
    /// requires a positive value.
    private var isAmountlessOffer: Bool {
        selectedMethod == .bolt12 && isAmountless
    }

    private var canCreateRequest: Bool {
        guard !isCreatingRequest else { return false }
        if isAmountlessOffer { return true }
        return amountSats > 0
    }

    // MARK: - Amount Input View

    private var amountInputView: some View {
        VStack(spacing: 0) {
            if let mint = walletManager.activeMint {
                mintSelector(mint: mint)
                    .padding(.horizontal)
                    .padding(.top, 12)
            }

            Spacer()

            amountHero

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 12)
                    .padding(.horizontal)
            }

            Spacer()

            NumberPadAmountInput(amountString: $amountString, unit: entryUnit)
                .padding(.horizontal, 24)
                .onChange(of: amountString) { _, newValue in
                    // Typing a digit takes over from the amountless offer.
                    if isAmountless && !newValue.isEmpty { isAmountless = false }
                }

            Button(action: createRequest) {
                if isCreatingRequest {
                    ProgressView()
                } else {
                    Text(selectedMethod.createActionTitle)
                }
            }
            .glassButton()
            .disabled(!canCreateRequest)
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
    }

    private var amountHero: some View {
        VStack(spacing: 12) {
            if selectedMethod == .onchain {
                methodBadge
                    .transition(.opacity)
            }

            CurrencyAmountDisplay(
                sats: amountSats,
                primary: $settings.amountDisplayPrimary,
                entryRaw: amountString
            )
            .opacity(isAmountlessOffer ? 0.35 : 1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Request amount: \(amountString.isEmpty ? "0" : amountString) sats")

            if selectedMethod == .bolt12 {
                anyAmountChip
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: isAmountless)
        .animation(.snappy, value: selectedMethod)
    }

    /// All-caps "ON-CHAIN" label sitting above the amount. On-chain receive is
    /// unusual enough to warrant the callout; Lightning and reusable invoices
    /// rely on the nav-bar glyph alone, so this only renders for on-chain.
    private var methodBadge: some View {
        Text(selectedMethod.displayName.uppercased())
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel("Method: \(selectedMethod.friendlyTitle)")
    }

    /// BOLT12-only toggle. Lit = the invoice carries no amount (sender chooses).
    /// Only available while the field is empty: typing a digit clears it (handled
    /// in `amountInputView`) and greys it out until the amount is cleared again.
    private var anyAmountChip: some View {
        Button(action: {
            HapticFeedback.selection()
            withAnimation(.snappy) {
                isAmountless.toggle()
                if isAmountless { amountString = "" }
            }
        }) {
            Text("Any amount")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isAmountless ? .primary : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(.quaternary)
                        .overlay(Capsule().fill(Color.primary.opacity(isAmountless ? 0.12 : 0)))
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!amountString.isEmpty)
        .opacity(amountString.isEmpty ? 1 : 0.35)
        .accessibilityLabel("Any amount")
        .accessibilityHint("The sender chooses the amount")
        .accessibilityAddTraits(isAmountless ? .isSelected : [])
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
            isAmountless = (selectedMethod == .bolt12) && amountString.isEmpty
            return
        }
    }

    // MARK: - Actions

    private func createRequest() {
        let requestMethod = selectedMethod
        // Only a BOLT12 amountless offer submits no amount; BOLT11, on-chain,
        // and a BOLT12 offer with a typed amount all require a positive value.
        let requestAmount: UInt64? = isAmountlessOffer ? nil : (amountSats > 0 ? amountSats : nil)

        if !isAmountlessOffer, (requestAmount ?? 0) == 0 {
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
                errorMessage = "Failed. \(error.userFacingWalletMessage)"
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
                // Payment detected. Finish the UX immediately and mint in the
                // background so a slow/transiently-failing mint never hangs the
                // sheet (the balance credits a beat later).
                await completeReceivedQuote(mintInBackground: true)
            case .issued:
                // Mint already issued the ecash — just refresh + finish.
                await completeReceivedQuote(mintInBackground: false)
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
            await completeReceivedQuote(mintInBackground: false)
        } catch {
            if isAlreadyIssuedMintError(error) {
                await completeReceivedQuote(mintInBackground: false)
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

    /// Finish the receive UX as soon as the payment is *detected*. When
    /// `mintInBackground` is true the quote is `.paid` but not yet minted: we
    /// claim it in a detached task so a slow mint never holds the sheet open.
    /// When false the ecash is already issued and we just refresh.
    @MainActor
    private func completeReceivedQuote(mintInBackground: Bool) async {
        guard !isPaid else { return }

        isPaid = true
        HapticFeedback.notification(.success)
        expiryTimer?.invalidate()

        let quoteId = mintQuote?.id

        // Run the mint/refresh in an UNSTRUCTURED task that outlives this view
        // and the (about-to-be-cancelled) poll task, so it completes after the
        // sheet slides away.
        if mintInBackground, let quoteId {
            Task { await walletManager.claimPaidMintQuote(quoteId: quoteId) }
        } else {
            Task { @MainActor in
                await walletManager.refreshBalance()
                await walletManager.loadTransactions()
            }
        }

        // Fire the home-screen toast (same notification the NPC mint flow
        // posts from WalletManager) so the user sees the receipt on the home
        // screen after dismiss.
        if let amount = mintQuote?.amount {
            NotificationCenter.default.post(
                name: .cashuTokenReceived,
                object: nil,
                userInfo: ["amount": amount]
            )
        }

        // Brief dwell so the user registers the "Payment Received!" badge, then
        // auto-dismiss. Cancel the poll AFTER the dwell — this method runs
        // inside `quoteStatusTask`, so cancelling first would abort the sleep
        // and dismiss instantly. The mint finishes in the background.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        quoteStatusTask?.cancel()
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
