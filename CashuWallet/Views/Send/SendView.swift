import SwiftUI

struct SendView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared

    @State private var amountString = ""
    @State private var memo = ""
    @State private var generatedToken: String?
    @State private var generatedTokenMintURL: String?
    @State private var tokenFee: UInt64 = 0
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showMintPicker = false
    @State private var selectedSendMint: MintInfo?

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
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                } else {
                    sendInputView
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .animation(.snappy(duration: 0.35), value: generatedToken != nil)
            .navigationBarTitleDisplayMode(.inline)
            // Match the Lightning Invoice screen: float the title + chrome
            // over the black canvas, no secondary gray strip.
            .toolbarBackground(.hidden, for: .navigationBar)
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
                        Button(action: {
                            HapticFeedback.selection()
                            lockWithP2PK.toggle()
                        }) {
                            Image(systemName: lockWithP2PK ? "lock.fill" : "lock.open")
                                .font(.caption)
                                .foregroundStyle(lockWithP2PK ? Color.accentColor : .secondary)
                        }
                        .accessibilityLabel(lockWithP2PK ? "P2PK lock on" : "P2PK lock off")
                        .accessibilityHint("Locks this token to a recipient public key")
                    }
                }

                if generatedToken != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showShareSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share token")
                    }
                }
            }
            .sheet(isPresented: $showMintPicker) {
                MintSelectorSheet(
                    selectedMint: sendMintSelection,
                    minimumAmount: amountSats > 0 ? amountSats : nil,
                    onSelect: selectSendMint
                )
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
            .onChange(of: entryUnit) { oldUnit, newUnit in
                amountString = AmountFormatter.entryConverted(raw: amountString, from: oldUnit, to: newUnit)
            }
        }
    }

    // MARK: - Send Input View

    private var sendInputView: some View {
        VStack(spacing: 0) {
            // Mint selector
            if let mint = displaySendMint {
                mintSelector(mint: mint)
                    .padding(.horizontal)
                    .padding(.top, 12)
            }

            Spacer()

            // Amount display — fiat-primary with tap-to-flip ↕ pill
            CurrencyAmountDisplay(
                sats: amountSats,
                primary: $settings.amountDisplayPrimary,
                entryRaw: amountString
            )

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .scale))
            }

            Spacer()

            // P2PK section (only when enabled)
            if lockWithP2PK {
                p2pkInputSection
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            // Number pad
            NumberPadAmountInput(amountString: $amountString, unit: entryUnit)
                .padding(.horizontal, 24)

            Button(action: {
                HapticFeedback.impact(.light)
                generateToken()
            }) {
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

    // MARK: - Mint Selector

    private func mintSelector(mint: MintInfo) -> some View {
        HStack(spacing: 12) {
            Button(action: { showMintPicker = true }) {
                HStack(spacing: 12) {
                    if let iconUrl = mint.iconUrl, let url = URL(string: iconUrl) {
                        CachedAsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "bitcoinsign.bank.building").foregroundStyle(.secondary)
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "bitcoinsign.bank.building")
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 40)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(mint.name).font(.subheadline.weight(.medium))
                        Text(formatBalance(mint.balance))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: { useMax(mint: mint) }) {
                Text("Use Max")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Fill the amount with your full mint balance")
        }
        .padding(12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 12), interactive: true)
    }

    /// The unit the keypad is entering in: fiat only when fiat is primary AND a
    /// price is loaded, else sats (mirrors `CurrencyAmountDisplay.effectivePrimary`).
    private var entryUnit: AmountDisplayPrimary {
        (settings.amountDisplayPrimary == .fiat && priceService.btcPriceUSD > 0) ? .fiat : .sats
    }

    /// Satoshis represented by the typed amount, interpreted per `entryUnit`.
    private var amountSats: UInt64 { AmountFormatter.entrySats(raw: amountString, unit: entryUnit) }

    private func useMax(mint: MintInfo) {
        HapticFeedback.impact(.light)
        // Balance is sats; express it in the current entry unit so the keypad
        // string keeps its meaning.
        amountString = AmountFormatter.entryConverted(raw: String(mint.balance), from: .sats, to: entryUnit)
    }

    private var canSend: Bool {
        let amount = amountSats
        guard amount > 0 else { return false }
        guard let mint = displaySendMint else { return false }
        if lockWithP2PK && normalizedP2PKPubkeyInput == nil { return false }
        return amount <= mint.balance
    }

    private var availableSendMints: [MintInfo] {
        var mints = walletManager.mints
        if let activeMint = walletManager.activeMint,
           !mints.contains(where: { $0.id == activeMint.id }) {
            mints.insert(activeMint, at: 0)
        }
        return mints
    }

    private var resolvedSelectedSendMint: MintInfo? {
        guard let selectedSendMint else { return nil }
        return availableSendMints.first { $0.id == selectedSendMint.id } ?? selectedSendMint
    }

    private var displaySendMint: MintInfo? {
        resolvedSelectedSendMint ?? recommendedSendMint(minimumAmount: amountSats > 0 ? amountSats : nil)
    }

    private var sendMintSelection: Binding<MintInfo?> {
        Binding(
            get: { displaySendMint },
            set: { newMint in
                if let newMint {
                    selectSendMint(newMint)
                } else {
                    selectedSendMint = nil
                }
            }
        )
    }

    private func recommendedSendMint(minimumAmount: UInt64?) -> MintInfo? {
        guard !availableSendMints.isEmpty else { return nil }

        let candidates: [MintInfo]
        if let minimumAmount, minimumAmount > 0 {
            let affordable = availableSendMints.filter { $0.balance >= minimumAmount }
            candidates = affordable.isEmpty ? availableSendMints : affordable
        } else {
            candidates = availableSendMints
        }

        if let activeMint = walletManager.activeMint,
           let activeCandidate = candidates.first(where: { $0.id == activeMint.id }) {
            return activeCandidate
        }

        return candidates.sorted { lhs, rhs in
            if lhs.balance == rhs.balance {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.balance > rhs.balance
        }.first
    }

    private func selectSendMint(_ mint: MintInfo) {
        selectedSendMint = mint
        errorMessage = nil
        HapticFeedback.selection()
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
                VStack(spacing: 24) {
                    // QR Code — same dimensions and corner radius as the
                    // Lightning Invoice screen for visual consistency.
                    // Cashu tokens often exceed a single QR's capacity so
                    // UR encoding stays on, but the SPEED/SIZE dev HUD is
                    // suppressed from production.
                    QRCodeView(content: token, showControls: false)
                        .frame(width: 280, height: 280)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                        .padding(.top, 8)
                        .contextMenu {
                            Button(action: { copyToken(token) }) {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            Button(action: { showShareSheet = true }) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            if !settings.checkSentTokens {
                                Button(action: {
                                    Task { await checkTokenClaimNow(token: token) }
                                }) {
                                    Label("Check Status", systemImage: "arrow.clockwise")
                                }
                            }
                        }

                    // Amount
                    CurrencyAmountDisplay(
                        sats: amountSats,
                        primary: $settings.amountDisplayPrimary,
                        primarySize: 32
                    )

                    // Status — inline badge transition, then dismiss + toast.
                    Group {
                        if tokenClaimed {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .symbolEffect(.bounce, value: tokenClaimed)
                                Text("Claimed")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                        } else if isCheckingClaim {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.8)
                                Text("Checking...")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .symbolEffect(.pulse, options: .repeating)
                                Text("Pending")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .transition(.opacity)
                        }
                    }
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: tokenClaimed)
                    .animation(.easeInOut(duration: 0.2), value: isCheckingClaim)

                    // Detail rows on canvas with hairline dividers — same
                    // pattern as the Lightning Invoice screen.
                    VStack(spacing: 0) {
                        detailRow(icon: "arrow.up.arrow.down", label: "Fee", value: "\(tokenFee) sat")
                        canvasDivider
                        detailRow(icon: "banknote", label: "Unit", value: settings.unitLabel.uppercased())
                        canvasDivider
                        detailRow(icon: "banknote", label: "Fiat",
                                  value: priceService.btcPriceUSD > 0
                                      ? priceService.formatSatsAsFiat(amountSats) : "—")
                        if let mintURL = generatedTokenMintURL {
                            canvasDivider
                            detailRow(icon: "bitcoinsign.bank.building", label: "Mint",
                                      value: extractMintHost(mintURL))
                        }
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal)
            }

            Button(action: { copyToken(token) }) {
                Text(copyButtonText)
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
            Text(value)
                .fontWeight(.medium)
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

    private func formatBalance(_ sats: UInt64) -> String {
        AmountFormatter.sats(sats, useBitcoinSymbol: settings.useBitcoinSymbol)
    }

    private func extractMintHost(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }

    // MARK: - Actions

    private func generateToken() {
        let amount = amountSats
        guard amount > 0 else { return }
        guard let mint = displaySendMint else {
            errorMessage = "No mint available."
            return
        }
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
                    p2pkPubkey: selectedP2PKPubkey,
                    mintUrl: mint.url
                )
                generatedToken = result.token
                generatedTokenMintURL = mint.url
                tokenFee = result.fee
                HapticFeedback.notification(.success)
            } catch {
                errorMessage = error.userFacingWalletMessage
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
                        // Brief dwell so the user sees the "Claimed" badge
                        // flip; the home-screen toast carries the celebration
                        // from there.
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

// MARK: - Melt View

struct MeltView: View {
    enum MeltMode: String, CaseIterable {
        case lightning
        case onchain

        var displayName: String {
            switch self {
            case .lightning:
                return "Lightning"
            case .onchain:
                return "On-chain"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared

    private let autoQuoteOnAppear: Bool
    private let initialAutoQuoteRequest: String
    private let onComplete: (() -> Void)?

    @State private var requestInput: String
    @State private var decodedRequestSource = ""
    @State private var decodedRequestResult: PaymentRequestDecodeResult = .unrecognized
    @State private var isDecodingRequest = false
    @State private var didPerformInitialAutoQuote = false
    @State private var amountString: String
    @State private var meltMode: MeltMode
    @State private var meltQuote: MeltQuoteInfo?
    @State private var isGettingQuote = false
    @State private var isPaying = false
    @State private var isPaid = false
    @State private var errorMessage: String?

    // Authorizing overlay state
    @State private var showAuthorizingOverlay = false
    @State private var authorizingState: AuthorizingOverlay.FlowState = .authorizing

    // Inline scan + clipboard suggestion
    @State private var showingScanner = false
    @State private var showingMintPicker = false
    @State private var selectedMeltMint: MintInfo?
    @State private var clipboardSuggestion: PaymentRequestDecodeResult?
    @State private var clipboardSuggestionRaw: String?
    @State private var dismissedClipboardSuggestion = false
    @State private var suggestionTask: Task<Void, Never>?
    @State private var quoteTask: Task<Void, Never>?

    private var meltViewStateKey: String {
        if isPaid { return "paid" }
        if meltQuote != nil { return "quote" }
        return "input"
    }

    private var shortRecipient: String {
        let trimmed = requestInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 24 else { return trimmed }
        let prefix = trimmed.prefix(10)
        let suffix = trimmed.suffix(10)
        return "\(prefix)…\(suffix)"
    }

    private func handleAuthorizingDismiss() {
        // Reset state so the overlay can be presented again cleanly next time.
        authorizingState = .authorizing
    }

    init(
        initialRequest: String = "",
        initialAmount: String = "",
        initialMode: MeltMode = .lightning,
        autoQuoteOnAppear: Bool = false,
        onComplete: (() -> Void)? = nil
    ) {
        self.autoQuoteOnAppear = autoQuoteOnAppear
        self.initialAutoQuoteRequest = initialRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        self.onComplete = onComplete
        _requestInput = State(initialValue: initialRequest)
        _amountString = State(initialValue: initialAmount)
        _meltMode = State(initialValue: initialMode)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isPaid {
                    paymentSuccessView
                        .transition(.scale.combined(with: .opacity))
                } else if let quote = meltQuote {
                    quoteConfirmView(quote: quote)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                } else {
                    requestInputView
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .animation(.snappy(duration: 0.35), value: meltViewStateKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: close) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }

                ToolbarItem(placement: .principal) {
                    Text(screenTitle)
                        .font(.headline)
                }
            }
            .sheet(isPresented: $showAuthorizingOverlay, onDismiss: handleAuthorizingDismiss) {
                AuthorizingOverlay(
                    amountSats: meltQuote?.amount ?? 0,
                    recipient: shortRecipient,
                    recipientCaption: meltQuote.map { $0.paymentMethod.displayName },
                    state: $authorizingState,
                    onDismiss: { showAuthorizingOverlay = false }
                )
                .presentationDetents([.height(340)])
                .presentationBackgroundInteraction(.disabled)
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showingScanner) {
                ScannerWrapperView(onScanned: handleScannedRequest)
                    .environmentObject(walletManager)
            }
            .sheet(isPresented: $showingMintPicker) {
                MintSelectorSheet(
                    selectedMint: meltMintSelection,
                    paymentMethod: selectedMeltPaymentMethod,
                    minimumAmount: knownPaymentAmount,
                    onSelect: selectMeltMint
                )
                    .environmentObject(walletManager)
                    .presentationDetents([.medium])
            }
            .onAppear {
                syncMeltModeWithAvailableMints()
                syncSelectedMeltMint()
                detectClipboardSuggestion()
            }
            .onDisappear(perform: cancelTransientTasks)
            .onChange(of: walletManager.activeMint?.id) {
                syncMeltModeWithAvailableMints()
                if meltQuote == nil {
                    syncSelectedMeltMint()
                    errorMessage = nil
                }
            }
            .onChange(of: meltMode) {
                errorMessage = nil
                if meltMode == .onchain {
                    requestInput = PaymentRequestParser.normalizeBitcoinRequest(requestInput)
                }
                syncSelectedMeltMint()
            }
            .onChange(of: requestInput) {
                syncSelectedMeltMint()
            }
            .task(id: trimmedRequestInput) { [input = trimmedRequestInput] in
                await updateRequestDecode(for: input)
            }
            .onChange(of: entryUnit) { oldUnit, newUnit in
                amountString = AmountFormatter.entryConverted(raw: amountString, from: oldUnit, to: newUnit)
            }
        }
    }

    private var supportsOnchainMelt: Bool {
        availableMeltMints.contains { $0.supportedMeltMethods.contains(.onchain) }
    }

    private var availableMeltMints: [MintInfo] {
        if walletManager.mints.isEmpty {
            return walletManager.activeMint.map { [$0] } ?? []
        }
        return walletManager.mints
    }

    private var trimmedRequestInput: String {
        requestInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var requestDecodeResult: PaymentRequestDecodeResult {
        let trimmed = trimmedRequestInput
        guard !trimmed.isEmpty, decodedRequestSource == trimmed else {
            return .unrecognized
        }
        return decodedRequestResult
    }

    private var selectedMeltPaymentMethod: PaymentMethodKind {
        if meltMode == .onchain {
            return .onchain
        }

        if isHumanReadableAddress {
            return .bolt11
        }

        switch requestDecodeResult {
        case .bolt11:
            return .bolt11
        case .bolt12:
            return .bolt12
        case .onchain:
            return .onchain
        case .lightningAddress, .cashuPaymentRequest, .unrecognized:
            return .bolt11
        }
    }

    /// The unit the keypad is entering in: fiat only when fiat is primary AND a
    /// price is loaded, else sats (mirrors `CurrencyAmountDisplay.effectivePrimary`).
    private var entryUnit: AmountDisplayPrimary {
        (settings.amountDisplayPrimary == .fiat && priceService.btcPriceUSD > 0) ? .fiat : .sats
    }

    /// Satoshis represented by the typed amount, interpreted per `entryUnit`.
    private var amountSats: UInt64 { AmountFormatter.entrySats(raw: amountString, unit: entryUnit) }

    private var knownPaymentAmount: UInt64? {
        let entered = amountSats
        if entered > 0 {
            return entered
        }

        switch requestDecodeResult {
        case .bolt11(let amount, _), .bolt12(let amount, _):
            return amount
        case .lightningAddress, .onchain, .cashuPaymentRequest, .unrecognized:
            return nil
        }
    }

    private var resolvedSelectedMeltMint: MintInfo? {
        guard let selectedMeltMint else { return nil }
        return availableMeltMints.first { $0.id == selectedMeltMint.id } ?? selectedMeltMint
    }

    private var displayMeltMint: MintInfo? {
        if let mint = resolvedSelectedMeltMint,
           mint.supportedMeltMethods.contains(selectedMeltPaymentMethod) {
            return mint
        }

        return recommendedMeltMint(
            for: selectedMeltPaymentMethod,
            minimumAmount: knownPaymentAmount
        )
    }

    private var meltMintSelection: Binding<MintInfo?> {
        Binding(
            get: { displayMeltMint },
            set: { newMint in
                if let newMint {
                    selectMeltMint(newMint)
                } else {
                    selectedMeltMint = nil
                }
            }
        )
    }

    private var screenTitle: String {
        meltMode == .onchain ? "Pay On-chain" : "Pay Lightning"
    }

    private var isHumanReadableAddress: Bool {
        meltMode == .lightning && PaymentRequestParser.isHumanReadableLightningAddress(trimmedRequestInput)
    }

    private var isBitcoinAddress: Bool {
        PaymentRequestParser.isBitcoinAddress(trimmedRequestInput)
    }

    private var amountRequired: Bool {
        meltMode == .onchain || isHumanReadableAddress
    }

    private var canGetQuote: Bool {
        guard !trimmedRequestInput.isEmpty else { return false }

        if amountRequired {
            guard amountSats > 0 else { return false }
        }

        if meltMode == .onchain {
            return isBitcoinAddress
        }

        return true
    }

    @MainActor
    private func updateRequestDecode(for input: String) async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            applyRequestDecode(source: "", result: .unrecognized, isDecoding: false)
            syncSelectedMeltMint()
            return
        }

        applyRequestDecode(source: decodedRequestSource, result: decodedRequestResult, isDecoding: true)

        do {
            try await Task.sleep(nanoseconds: 120_000_000)
        } catch {
            return
        }

        let result = await CdkRuntime.shared.decodePaymentRequest(trimmed)
        guard !Task.isCancelled, trimmedRequestInput == trimmed else { return }

        applyRequestDecode(source: trimmed, result: result, isDecoding: false)
        syncSelectedMeltMint()
        performInitialAutoQuoteIfNeeded(for: result)
    }

    @MainActor
    private func applyRequestDecode(
        source: String,
        result: PaymentRequestDecodeResult,
        isDecoding: Bool
    ) {
        if decodedRequestSource != source {
            decodedRequestSource = source
        }
        if decodedRequestResult != result {
            decodedRequestResult = result
        }
        if isDecodingRequest != isDecoding {
            isDecodingRequest = isDecoding
        }
    }

    @MainActor
    private func performInitialAutoQuoteIfNeeded(for result: PaymentRequestDecodeResult) {
        guard autoQuoteOnAppear,
              !didPerformInitialAutoQuote,
              !initialAutoQuoteRequest.isEmpty,
              trimmedRequestInput == initialAutoQuoteRequest else { return }

        switch result {
        case .bolt11, .bolt12:
            didPerformInitialAutoQuote = true
            getQuote()
        case .lightningAddress, .onchain, .cashuPaymentRequest, .unrecognized:
            break
        }
    }

    private static func suggestedMode(for result: PaymentRequestDecodeResult) -> MeltMode? {
        switch result {
        case .onchain:
            return .onchain
        case .bolt11, .bolt12, .lightningAddress:
            return .lightning
        case .cashuPaymentRequest, .unrecognized:
            return nil
        }
    }

    private func cancelTransientTasks() {
        suggestionTask?.cancel()
        quoteTask?.cancel()
        suggestionTask = nil
        quoteTask = nil
    }

    private func mintInfo(for quote: MeltQuoteInfo) -> MintInfo? {
        walletManager.mints.first { $0.url == quote.mintUrl }
            ?? (walletManager.activeMint?.url == quote.mintUrl ? walletManager.activeMint : nil)
    }

    private func mintDisplayName(for quote: MeltQuoteInfo) -> String {
        mintInfo(for: quote)?.name
            ?? URL(string: quote.mintUrl)?.host
            ?? quote.mintUrl
    }

    private func hasSufficientBalance(for quote: MeltQuoteInfo) -> Bool {
        guard let balance = mintInfo(for: quote)?.balance else { return true }
        return balance >= quote.totalAmount
    }

    private var requestPlaceholder: String {
        switch meltMode {
        case .lightning:
            return "Lightning address, invoice, or BOLT12 offer"
        case .onchain:
            return "Bitcoin address"
        }
    }

    private var requestInputView: some View {
        VStack(spacing: 0) {
            if let mint = displayMeltMint {
                meltMintSelector(mint: mint)
                    .padding(.horizontal)
                    .padding(.top, 12)
            }

            if supportsOnchainMelt {
                meltModePicker
                    .padding(.horizontal)
                    .padding(.top, 12)
            }

            if displayMeltMint == nil, !availableMeltMints.isEmpty {
                Text("No mint supports \(selectedMeltPaymentMethod.displayName) payments.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
                    .padding(.top, 12)
            }

            HStack(alignment: .top, spacing: 12) {
                TextField(requestPlaceholder, text: $requestInput, axis: .vertical)
                    .font(.body)
                    .lineLimit(3...5)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack(spacing: 6) {
                    Button(action: openScanner) {
                        Image(systemName: "viewfinder")
                            .font(.title3)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scan QR code")

                    Button(action: pasteFromClipboard) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.title3)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Paste from clipboard")
                }
            }
            .padding()
            .liquidGlass(in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 16)

            liveDecodeFeedback
                .padding(.top, 6)
                .padding(.horizontal)

            if amountRequired {
                amountEntrySection
                    .padding(.top, 16)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 12)
                    .padding(.horizontal)
            }

            if amountRequired {
                NumberPadAmountInput(amountString: $amountString, unit: entryUnit)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            } else {
                launchpadSection
                    .padding(.top, 16)
                    .padding(.horizontal)
                Spacer(minLength: 0)
            }

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
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Launchpad (clipboard chip + recent recipients)

    @ViewBuilder
    private var launchpadSection: some View {
        VStack(spacing: 12) {
            if let suggestion = clipboardSuggestion,
               let raw = clipboardSuggestionRaw,
               !dismissedClipboardSuggestion,
               requestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ClipboardPaymentChip(
                    raw: raw,
                    result: suggestion,
                    onTap: {
                        suggestionTask?.cancel()
                        suggestionTask = Task { @MainActor in
                            await applyDecodedSuggestion(suggestion, raw: raw)
                        }
                    },
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            dismissedClipboardSuggestion = true
                        }
                    }
                )
            }

            if requestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !recentRecipients.isEmpty {
                RecentRecipientsList(
                    recipients: recentRecipients,
                    onTap: applyRecentRecipient
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: requestInput.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: dismissedClipboardSuggestion)
    }

    @ViewBuilder
    private var liveDecodeFeedback: some View {
        if !trimmedRequestInput.isEmpty {
            if isDecodingRequest {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.65)
                    Text("Checking...")
                        .font(.caption)
                }
                .foregroundStyle(Color.secondary)
                .transition(.opacity)
                .accessibilityLabel("Checking payment request")
            } else {
                let result = requestDecodeResult
                HStack(spacing: 6) {
                    Image(systemName: result == .unrecognized ? "exclamationmark.circle" : "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                    Text(liveDecodeText(for: result))
                        .font(.caption)
                }
                .foregroundStyle(result == .unrecognized ? Color.red : Color.secondary)
                .transition(.opacity)
                .accessibilityLabel(liveDecodeText(for: result))
            }
        }
    }

    private func liveDecodeText(for result: PaymentRequestDecodeResult) -> String {
        switch result {
        case .lightningAddress:
            return "Lightning address"
        case .bolt11(let amount, _):
            return amount.map { "BOLT11 invoice — \($0) sat" } ?? "BOLT11 invoice — set amount"
        case .bolt12(let amount, _):
            return amount.map { "BOLT12 offer — \($0) sat" } ?? "BOLT12 offer — set amount"
        case .onchain:
            return "Bitcoin address"
        case .cashuPaymentRequest:
            return "Cashu payment request"
        case .unrecognized:
            return "Unrecognized — try a Lightning address, invoice, or Bitcoin address"
        }
    }

    private var recentRecipients: [RecentRecipientsList.Recipient] {
        var seen = Set<String>()
        var out: [RecentRecipientsList.Recipient] = []
        for tx in walletManager.transactions {
            guard tx.type == .outgoing,
                  tx.kind == .lightning || tx.kind == .onchain,
                  let invoice = tx.invoice,
                  !invoice.isEmpty,
                  !seen.contains(invoice) else { continue }
            seen.insert(invoice)
            out.append(RecentRecipientsList.Recipient(
                id: tx.id,
                invoice: invoice,
                kind: tx.kind,
                amount: tx.amount,
                date: tx.date
            ))
            if out.count >= 3 { break }
        }
        return out
    }

    private var meltModePicker: some View {
        HStack(spacing: 8) {
            modePill(mode: .lightning, icon: "bolt.fill")
            modePill(mode: .onchain, icon: "bitcoinsign.circle")
        }
        .padding(4)
        .background(.thinMaterial, in: Capsule())
        .accessibilityLabel("Payment mode")
    }

    private func modePill(mode: MeltMode, icon: String) -> some View {
        let isSelected = meltMode == mode
        return Button(action: {
            guard meltMode != mode else { return }
            HapticFeedback.selection()
            withAnimation(.snappy) { meltMode = mode }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                Text(mode.displayName)
                    .font(.subheadline.weight(.semibold))
            }
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

    private var amountEntrySection: some View {
        CurrencyAmountDisplay(
            sats: amountSats,
            primary: $settings.amountDisplayPrimary,
            primarySize: 48,
            entryRaw: amountString
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Payment amount")
        .accessibilityValue("\(amountString.isEmpty ? "0" : amountString) sats")
    }

    private func meltMintSelector(mint: MintInfo) -> some View {
        Button(action: {
            HapticFeedback.selection()
            showingMintPicker = true
        }) {
            HStack(spacing: 12) {
                if let iconUrl = mint.iconUrl, let url = URL(string: iconUrl) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "bitcoinsign.bank.building").foregroundStyle(.secondary)
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
                    Text("\(mint.balance) sat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Paying mint: \(mint.name), \(mint.balance) sats")
        .accessibilityHint("Double-tap to choose the mint to pay from")
    }

    private func quoteConfirmView(quote: MeltQuoteInfo) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    if let mint = mintInfo(for: quote) {
                        meltMintSelector(mint: mint)
                            .padding(.horizontal)
                            .padding(.top, 12)
                    }

                    CurrencyAmountDisplay(
                        sats: quote.amount,
                        primary: $settings.amountDisplayPrimary
                    )
                    .padding(.top, 24)

                    VStack(spacing: 0) {
                        meltDetailRow(label: "Method", value: quote.paymentMethod.displayName)
                        Divider().padding(.leading)
                        if quote.paymentMethod == .onchain {
                            meltDetailRow(
                                label: "To",
                                value: PaymentRequestParser.normalizeBitcoinRequest(requestInput)
                            )
                            Divider().padding(.leading)
                        }
                        meltDetailRow(label: "Amount", value: "\(quote.amount) sat")
                        Divider().padding(.leading)
                        meltDetailRow(label: "Max fee", value: "\(quote.feeReserve) sat")
                        if quote.feeReserve > 0 {
                            Divider().padding(.leading)
                            meltDetailRow(label: "Required balance", value: "\(quote.totalAmount) sat")
                        }
                        Divider().padding(.leading)
                        meltDetailRow(label: "Mint", value: mintDisplayName(for: quote))
                    }
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)

                    if !hasSufficientBalance(for: quote),
                       let balance = mintInfo(for: quote)?.balance {
                        Text("Selected mint has \(balance) sat; this quote can reserve up to \(quote.totalAmount) sat.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
            }

            Button(action: payRequest) {
                if isPaying {
                    ProgressView()
                } else {
                    Text("Pay \(quote.amount) sat")
                }
            }
            .glassButton()
            .disabled(isPaying || !hasSufficientBalance(for: quote))
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
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var paymentSuccessView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: isPaid)

                Text("Payment Sent!")
                    .font(.title2.weight(.semibold))
            }

            Spacer()

            Button(action: close) {
                Text("Done")
            }
            .glassButton()
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    private func syncMeltModeWithAvailableMints() {
        guard supportsOnchainMelt || meltMode != .onchain else {
            meltMode = .lightning
            errorMessage = "No mint supports On-chain payments."
            return
        }
    }

    private func syncSelectedMeltMint() {
        if let mint = resolvedSelectedMeltMint,
           mint.supportedMeltMethods.contains(selectedMeltPaymentMethod) {
            return
        }

        selectedMeltMint = recommendedMeltMint(
            for: selectedMeltPaymentMethod,
            minimumAmount: knownPaymentAmount
        )
    }

    private func recommendedMeltMint(
        for paymentMethod: PaymentMethodKind,
        minimumAmount: UInt64?
    ) -> MintInfo? {
        let compatible = availableMeltMints.filter {
            $0.supportedMeltMethods.contains(paymentMethod)
        }

        guard !compatible.isEmpty else {
            return nil
        }

        let affordable = compatible.filter { mint in
            guard let minimumAmount else { return true }
            return mint.balance >= minimumAmount
        }
        let candidates = affordable.isEmpty ? compatible : affordable

        if let activeMint = walletManager.activeMint,
           candidates.contains(where: { $0.id == activeMint.id }) {
            return activeMint
        }

        return candidates.sorted { lhs, rhs in
            if lhs.balance == rhs.balance {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.balance > rhs.balance
        }.first
    }

    private func selectMeltMint(_ mint: MintInfo) {
        selectedMeltMint = mint
        if meltQuote != nil {
            meltQuote = nil
        }
        errorMessage = nil
        HapticFeedback.selection()
    }

    private func pasteFromClipboard() {
        guard let content = UIPasteboard.general.string else { return }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        HapticFeedback.selection()
        suggestionTask?.cancel()
        suggestionTask = Task { @MainActor in
            await decodeAndApplySuggestion(raw: trimmed)
        }
    }

    private func openScanner() {
        HapticFeedback.selection()
        showingScanner = true
    }

    private func handleScannedRequest(_ scanned: String) {
        let trimmed = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        suggestionTask?.cancel()
        suggestionTask = Task { @MainActor in
            await decodeAndApplySuggestion(raw: trimmed)
        }
    }

    private func detectClipboardSuggestion() {
        guard !dismissedClipboardSuggestion,
              clipboardSuggestion == nil,
              requestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let content = UIPasteboard.general.string else { return }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        suggestionTask?.cancel()
        suggestionTask = Task { @MainActor in
            let result = await CdkRuntime.shared.decodePaymentRequest(trimmed)
            guard !Task.isCancelled,
                  result != .unrecognized,
                  requestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            clipboardSuggestion = result
            clipboardSuggestionRaw = trimmed
        }
    }

    @MainActor
    private func decodeAndApplySuggestion(raw: String) async {
        let result = await CdkRuntime.shared.decodePaymentRequest(raw)
        guard !Task.isCancelled else { return }
        await applyDecodedSuggestion(result, raw: raw)
    }

    @MainActor
    private func applyDecodedSuggestion(
        _ result: PaymentRequestDecodeResult,
        raw: String,
        autoQuoteAmountLocked: Bool = true
    ) async {
        // Choose mode based on suggestion (if we can switch).
        if let suggested = Self.suggestedMode(for: result),
           suggested != meltMode,
           suggested != .onchain || supportsOnchainMelt {
            withAnimation(.snappy) { meltMode = suggested }
        }

        // Fill input with normalized request.
        switch result {
        case .onchain:
            requestInput = PaymentRequestParser.normalizeBitcoinRequest(raw)
        case .bolt11, .bolt12:
            requestInput = await CdkRuntime.shared.normalizedLightningRequest(from: raw)
                ?? PaymentRequestParser.normalizeLightningRequest(raw)
        case .lightningAddress, .cashuPaymentRequest, .unrecognized:
            requestInput = raw
        }

        let decodedSource = requestInput.trimmingCharacters(in: .whitespacesAndNewlines)
        applyRequestDecode(source: decodedSource, result: result, isDecoding: false)
        syncSelectedMeltMint()

        // Hide the chip after a tap.
        dismissedClipboardSuggestion = true
        errorMessage = nil

        // Auto-quote when amount is locked.
        if autoQuoteAmountLocked, PaymentRequestDecoder.amountLocked(result) {
            getQuote()
        }
    }

    private func applyRecentRecipient(_ recipient: RecentRecipientsList.Recipient) {
        HapticFeedback.selection()
        suggestionTask?.cancel()
        suggestionTask = Task { @MainActor in
            let result = await CdkRuntime.shared.decodePaymentRequest(recipient.invoice)
            guard !Task.isCancelled else { return }
            // Reuse the same routing as suggestion tap, but never auto-quote:
            // the user is reusing a destination at a (likely) new amount.
            await applyDecodedSuggestion(
                result,
                raw: recipient.invoice,
                autoQuoteAmountLocked: false
            )
        }
    }

    private func getQuote() {
        let trimmedInput = requestInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        if meltMode == .lightning, isBitcoinAddress {
            guard supportsOnchainMelt else {
                errorMessage = "No mint supports On-chain payments."
                return
            }

            meltMode = .onchain
            syncSelectedMeltMint()
            errorMessage = "Switched to On-chain. Enter an amount to continue."
            requestInput = PaymentRequestParser.normalizeBitcoinRequest(trimmedInput)
            return
        }

        guard let quoteMint = displayMeltMint else {
            errorMessage = "No mint supports \(selectedMeltPaymentMethod.displayName) payments."
            return
        }

        let quoteMode = meltMode
        let quoteSource = trimmedInput
        let quoteAmount = amountSats
        let quoteMintURL = quoteMint.url
        let quoteIsHumanReadableAddress = isHumanReadableAddress

        quoteTask?.cancel()
        isGettingQuote = true
        errorMessage = nil

        quoteTask = Task { @MainActor in
            defer { isGettingQuote = false }

            do {
                switch quoteMode {
                case .lightning:
                    if quoteIsHumanReadableAddress {
                        guard quoteAmount > 0 else { return }
                        let quote = try await walletManager.createHumanReadableMeltQuote(
                            address: quoteSource,
                            amount: quoteAmount,
                            preferredMintURL: quoteMintURL
                        )
                        guard !Task.isCancelled,
                              trimmedRequestInput == quoteSource,
                              amountSats == quoteAmount else { return }
                        setMeltQuote(quote)
                    } else {
                        let request = await CdkRuntime.shared.normalizedLightningRequest(from: quoteSource)
                            ?? quoteSource
                        let quote = try await walletManager.createMeltQuote(
                            request: request,
                            preferredMintURL: quoteMintURL
                        )
                        guard !Task.isCancelled,
                              trimmedRequestInput == quoteSource else { return }
                        setMeltQuote(quote)
                    }
                case .onchain:
                    guard quoteAmount > 0 else { return }
                    let quote = try await walletManager.createOnchainMeltQuote(
                        address: quoteSource,
                        amount: quoteAmount,
                        preferredMintURL: quoteMintURL
                    )
                    guard !Task.isCancelled,
                          trimmedRequestInput == quoteSource,
                          amountSats == quoteAmount else { return }
                    setMeltQuote(quote)
                }
            } catch {
                errorMessage = error.userFacingWalletMessage
            }
        }
    }

    private func setMeltQuote(_ quote: MeltQuoteInfo) {
        meltQuote = quote
        if let mint = mintInfo(for: quote) {
            selectedMeltMint = mint
        }
    }

    private func payRequest() {
        guard let quote = meltQuote else { return }

        isPaying = true
        errorMessage = nil
        HapticFeedback.impact(.medium)
        authorizingState = .authorizing
        showAuthorizingOverlay = true

        Task { @MainActor in
            do {
                let _ = try await walletManager.meltTokens(quoteId: quote.id, mintUrl: quote.mintUrl)
                authorizingState = .sent
                // Overlay calls onDismiss after 1.2s; flip isPaid then so the
                // underlying view transitions to success while the sheet dismisses.
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                isPaid = true
                showAuthorizingOverlay = false
            } catch {
                let message = error.userFacingWalletMessage
                authorizingState = .error(message)
                errorMessage = message
                // Let the user read the error in the sheet, then dismiss after 2s.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                showAuthorizingOverlay = false
            }
            isPaying = false
        }
    }

    private func close() {
        onComplete?()
        dismiss()
    }
}

// MARK: - Melt View With Pre-filled Invoice

struct MeltViewWithInvoice: View {
    let invoice: String
    var onComplete: (() -> Void)?

    var body: some View {
        MeltView(
            initialRequest: invoice,
            initialMode: .lightning,
            autoQuoteOnAppear: true,
            onComplete: onComplete
        )
    }
}

// MARK: - Melt View With Pre-filled Address

struct MeltViewWithAddress: View {
    let address: String
    var onComplete: (() -> Void)?

    var body: some View {
        MeltView(
            initialRequest: address,
            initialMode: .onchain,
            onComplete: onComplete
        )
    }
}

// MARK: - Mint Selector Sheet (for Send/Receive flows)

struct MintSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @Binding private var selectedMint: MintInfo?
    private let mints: [MintInfo]?
    private let paymentMethod: PaymentMethodKind?
    private let minimumAmount: UInt64?
    private let onSelect: ((MintInfo) -> Void)?

    init(
        selectedMint: Binding<MintInfo?>,
        mints: [MintInfo]? = nil,
        paymentMethod: PaymentMethodKind? = nil,
        minimumAmount: UInt64? = nil,
        onSelect: ((MintInfo) -> Void)? = nil
    ) {
        _selectedMint = selectedMint
        self.mints = mints
        self.paymentMethod = paymentMethod
        self.minimumAmount = minimumAmount
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            if sourceMints.isEmpty {
                emptyStateView
            } else if displayMints.isEmpty {
                noCompatibleMintsView
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
            Image(systemName: "bitcoinsign.bank.building")
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

    private var noCompatibleMintsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("No Compatible Mints")
                .font(.headline)

            if let paymentMethod {
                Text("None of your mints support \(paymentMethod.displayName) payments.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    private var displayMints: [MintInfo] {
        let filteredMints: [MintInfo]
        if let paymentMethod {
            filteredMints = sourceMints.filter {
                $0.supportedMeltMethods.contains(paymentMethod)
            }
        } else {
            filteredMints = sourceMints
        }

        return filteredMints
            .sorted { lhs, rhs in
                let lhsSelected = selectedMint?.id == lhs.id
                let rhsSelected = selectedMint?.id == rhs.id
                if lhsSelected != rhsSelected { return lhsSelected }

                if let minimumAmount {
                    let lhsCanPay = lhs.balance >= minimumAmount
                    let rhsCanPay = rhs.balance >= minimumAmount
                    if lhsCanPay != rhsCanPay { return lhsCanPay }
                }

                if lhs.balance == rhs.balance {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.balance > rhs.balance
            }
    }

    private var sourceMints: [MintInfo] {
        mints ?? walletManager.mints
    }

    private var mintListView: some View {
        List(displayMints) { mint in
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
                        Text(mintSubtitle(for: mint))
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

    private func mintSubtitle(for mint: MintInfo) -> String {
        let balance = SettingsManager.shared.formatAmountBalance(mint.balance) + " sat"
        if let minimumAmount, mint.balance < minimumAmount {
            return "\(balance) - below amount"
        }

        guard paymentMethod != nil else {
            return balance
        }

        let methods = mint.supportedMeltMethods
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.displayName)
            .joined(separator: ", ")
        return "\(balance) - \(methods)"
    }

    @ViewBuilder
    private func mintIcon(for mint: MintInfo) -> some View {
        if let iconUrl = mint.iconUrl, let url = URL(string: iconUrl) {
            CachedAsyncImage(url: url) { image in
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
                Image(systemName: "bitcoinsign.bank.building")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
    }

    private func selectMint(_ mint: MintInfo) {
        if let onSelect {
            selectedMint = mint
            onSelect(mint)
            dismiss()
            return
        }

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

// MARK: - Method Picker Sheet

/// Medium-detent picker for choosing a receive/send rail. Mirrors
/// `MintSelectorSheet`: plain rows with a friendly title + descriptor and a
/// trailing checkmark, dismiss-on-select. Detent is applied by the caller.
struct MethodPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// The live option, for the accent glyph + VoiceOver `.isSelected`. Read-only:
    /// the parent owns the (method, isAmountless) state this maps to, so the
    /// parent can react to a pick with side effects (e.g. auto-create) race-free.
    let selectedOption: ReceiveMethodOption
    let options: [ReceiveMethodOption]
    var onSelect: (ReceiveMethodOption) -> Void

    var body: some View {
        NavigationStack {
            List(options) { option in
                Button(action: { select(option) }) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.friendlyTitle)
                                .font(.body.weight(.medium))
                            Text(option.friendlyDescriptor)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Glyph teaches the nav-bar mapping and carries selection:
                        // accent when chosen, muted otherwise. The row's
                        // `.isSelected` trait conveys state to VoiceOver.
                        Image(systemName: option.navSymbol)
                            .foregroundStyle(selectedOption == option ? Color.accentColor : .secondary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(option.friendlyTitle). \(option.friendlyDescriptor)")
                .accessibilityAddTraits(selectedOption == option ? .isSelected : [])
            }
            .listStyle(.plain)
            .navigationTitle("Receive with")
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
    }

    private func select(_ option: ReceiveMethodOption) {
        if option != selectedOption {
            HapticFeedback.selection()
        }
        onSelect(option)   // parent mutates state + may auto-create
        dismiss()
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
