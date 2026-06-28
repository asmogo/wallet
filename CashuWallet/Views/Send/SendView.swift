import SwiftUI
import CoreNFC

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

    // More-options flows (Pay Cashu Request / Lock Ecash)
    @State private var showPayRequestScanner = false
    @State private var showLockScanner = false

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
                        Menu {
                            Button {
                                HapticFeedback.selection()
                                showPayRequestScanner = true
                            } label: {
                                Label("Pay Cashu Request", systemImage: "qrcode.viewfinder")
                            }

                            Button {
                                HapticFeedback.selection()
                                showLockScanner = true
                            } label: {
                                Label("Lock Ecash", systemImage: "lock")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("More options")
                        .accessibilityHint("Pay a Cashu request or lock ecash to a public key")
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
                    .canvasSheetBackground()
            }
            .sheet(isPresented: $showShareSheet) {
                if let token = generatedToken {
                    CashuTokenShareSheet(token: token)
                }
            }
            .sheet(isPresented: $showPayRequestScanner) {
                // Pay Cashu Request routes the request through the scanner's own
                // cover (on top of the still-open scanner), mirroring the home
                // page. `onComplete` dismisses the whole Send flow so Pay "takes
                // over" and returns to the wallet. Presenting the pay cover from
                // SendView after dismissing this sheet yielded a black screen.
                ScannerWrapperView(
                    promptText: "Scan a Cashu request",
                    cashuRequestOnly: true,
                    onComplete: { dismiss() },
                    quickFills: payRequestQuickFills
                )
                .environmentObject(walletManager)
                .canvasSheetBackground()
            }
            .sheet(isPresented: $showLockScanner) {
                ScannerWrapperView(
                    onScanned: handleScannedPubkey,
                    promptText: "Scan a public key to lock to",
                    quickFills: lockQuickFills
                )
                .environmentObject(walletManager)
                .canvasSheetBackground()
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

            // Locked-to-key indicator (when the token will be P2PK-locked)
            if lockWithP2PK, let locked = normalizedP2PKPubkeyInput {
                lockedKeyChip(key: locked)
                    .padding(.horizontal)
                    .padding(.top, 10)
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
        .animation(.snappy(duration: 0.3), value: lockWithP2PK)
    }

    // MARK: - Mint Selector

    private func mintSelector(mint: MintInfo) -> some View {
        MintAmountSelectorRow(
            mint: mint,
            balanceText: formatBalance(mint.balance),
            onChooseMint: { showMintPicker = true },
            onUseMax: { useMax(mint: mint) }
        )
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

    /// Compact, removable indicator that the token will be P2PK-locked. Tapping
    /// the body reopens the scanner to change the key; the × clears the lock.
    /// Mirrors `ClipboardPaymentChip`'s visual language.
    private func lockedKeyChip(key: String) -> some View {
        HStack(spacing: 12) {
            Button(action: {
                HapticFeedback.selection()
                showLockScanner = true
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)
                        .background(.thinMaterial, in: Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Locked to")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Text(shortKey(key))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Locked to public key")
            .accessibilityHint("Double-tap to change the key")

            Button(action: {
                HapticFeedback.selection()
                lockWithP2PK = false
                p2pkPubkeyInput = ""
            }) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove lock")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func shortKey(_ key: String) -> String {
        guard key.count > 16 else { return key }
        return "\(key.prefix(10))…\(key.suffix(6))"
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
        Self.normalizeP2PKPubkey(p2pkPubkeyInput)
    }

    /// Normalizes a P2PK public key string: accepts a 66-char `02`/`03`-prefixed
    /// hex key, or bare 64-char hex (auto-prefixed `02`). Returns nil for anything
    /// else — including Nostr `npub`s, which this scheme can't lock to.
    static func normalizeP2PKPubkey(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

    // MARK: - More Options (Pay Cashu Request / Lock Ecash)

    /// Lock-flow intake: a scanned/pasted public key arms P2PK locking for the
    /// next send; invalid input (junk, or an `npub`) is rejected.
    private func handleScannedPubkey(_ scanned: String) {
        guard let normalized = Self.normalizeP2PKPubkey(scanned) else {
            errorMessage = "That's not a valid public key."
            HapticFeedback.notification(.error)
            return
        }
        p2pkPubkeyInput = normalized
        lockWithP2PK = true
        errorMessage = nil
        HapticFeedback.notification(.success)
    }

    private func payRequestQuickFills() -> [ScannerWrapperView.ScannerQuickFill] {
        guard let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clip.isEmpty,
              case .cashuPaymentRequest = PaymentRequestDecoder.decode(
                clip,
                includeCashuPaymentRequests: true,
                preferCashuPaymentRequests: true
              )
        else { return [] }
        return [.init(title: "Paste request", systemImage: "doc.on.clipboard", value: clip)]
    }

    private func lockQuickFills() -> [ScannerWrapperView.ScannerQuickFill] {
        var fills: [ScannerWrapperView.ScannerQuickFill] = []
        if let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           Self.normalizeP2PKPubkey(clip) != nil {
            fills.append(.init(title: "Paste key", systemImage: "doc.on.clipboard", value: clip))
        }
        if let ownKey = settings.p2pkKeys.last {
            fills.append(.init(title: "Use my latest key", systemImage: "key", value: ownKey.publicKey))
        }
        return fills
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

// MARK: - Mint + amount selector row

/// The shared amount-entry mint row used by every keypad screen (Create ecash and
/// the unified Send amount step). A tappable mint identity (avatar + balance) on the
/// left, then a "Use Max" pill, then the mint-picker chevron at the far right — so
/// the dropdown affordance reads clearly without crowding the balance.
struct MintAmountSelectorRow: View {
    let mint: MintInfo
    let balanceText: String
    let onChooseMint: () -> Void
    let onUseMax: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onChooseMint) {
                HStack(spacing: 12) {
                    MintAvatarView(iconUrl: mint.iconUrl, name: mint.name, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mint.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(balanceText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Paying mint: \(mint.name), \(balanceText)")

            Spacer(minLength: 8)

            Button(action: onUseMax) {
                Text("Use Max")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Fill the amount with your full mint balance")

            Button(action: onChooseMint) {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose a different mint")
        }
        .padding(12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 12), interactive: true)
    }
}

// MARK: - Unified destination-first Send

/// The single entry point for sending — one grounded screen modeled on the Family
/// wallet. The title "Send" and a pinned "To [recipient]" pill stay put; only the
/// area below transitions through steps: input → amount keypad → confirm(fee) →
/// sending → sent. A "Send to" field accepts a Lightning address, BOLT11 invoice,
/// BOLT12 offer, on-chain address, or Cashu request; detecting a valid destination
/// advances automatically (paste/scan/recent immediately, hand-typing after a short
/// settle). The pay/confirm logic mirrors `MeltView` and `CashuPaymentRequestPayView`
/// (same `walletManager` calls) but is hosted in-place so the screen stays grounded.
/// A pasted bearer *token* routes out to the Receive-this claim screen.
struct UnifiedSendView: View {
    let onClose: () -> Void
    /// CTA out of the zero-balance empty state — opens the Receive chooser.
    let onReceive: () -> Void
    /// "Add custom mint URL" out of the no-mints empty state.
    let onAddCustomMint: () -> Void
    /// Start the NFC tap-to-pay session (dismisses this sheet first).
    let onContactless: () -> Void

    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared

    // Step machine
    @State private var step: Step = .input
    @State private var destination = ""
    @State private var locked: LockedDestination?

    // Amount + melt quote
    @State private var amountString = ""
    @State private var meltQuote: MeltQuoteInfo?
    @State private var selectedMint: MintInfo?

    // Cashu-request live fee (ported from CashuPaymentRequestPayView)
    @State private var feeState: FeeState = .idle
    @State private var feePpkByMint: [String: UInt64] = [:]
    @State private var feeTask: Task<Void, Never>?

    // Flow control
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var inputHint: String?
    @State private var autoAdvanceTask: Task<Void, Never>?
    /// Set when the user taps the pill to edit: auto-advance stays suppressed while
    /// the field text equals this value, so a still-valid recipient doesn't bounce
    /// straight back forward. Cleared the instant the text differs.
    @State private var suppressedValue: String?

    // Routes that genuinely leave this flow + scanner / mint picker / empty state
    @State private var route: SendRoute?
    @State private var showingScanner = false
    @State private var showingMintPicker = false
    @State private var addMintError: String?

    enum Step: Equatable { case input, amount, confirm, sending, sent }

    enum LockedDestination: Equatable {
        case melt(request: String, mode: MeltView.MeltMode, decoded: PaymentRequestDecodeResult)
        case cashuRequest(CashuPaymentRequestSummary)
    }

    /// Resolved fee for the current creq mint + amount.
    private enum FeeState: Equatable { case idle, loading, free, amount(UInt64), unavailable }

    /// The two destinations that leave the Send flow entirely (presented full-screen,
    /// each keeping its own NavigationStack).
    private enum SendRoute: Identifiable {
        case receiveToken(String)
        case ecash
        var id: String {
            switch self {
            case .receiveToken(let token): return "token-\(token.prefix(48))"
            case .ecash: return "ecash"
            }
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let locked, step != .input {
                    toPill(locked)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Group {
                    switch step {
                    case .input: inputContent
                    case .amount: amountStep
                    case .confirm: confirmStep
                    case .sending: sendingStep
                    case .sent: sentStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.snappy(duration: 0.35), value: step)
            .animation(.snappy(duration: 0.35), value: locked != nil)
            .navigationTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .sheet(isPresented: $showingScanner) {
                ScannerWrapperView(onScanned: handleScannedDestination)
                    .environmentObject(walletManager)
                    .canvasSheetBackground()
            }
            .sheet(isPresented: $showingMintPicker) { mintPickerSheet.canvasSheetBackground() }
            .fullScreenCover(item: $route) { routeView($0).canvasSheetBackground() }
            .onChange(of: destination) { handleDestinationChange() }
            .onChange(of: entryUnit) { oldUnit, newUnit in
                amountString = AmountFormatter.entryConverted(raw: amountString, from: oldUnit, to: newUnit)
            }
            .onDisappear {
                autoAdvanceTask?.cancel()
                feeTask?.cancel()
            }
        }
    }

    // MARK: Input step

    @ViewBuilder
    private var inputContent: some View {
        if walletManager.mints.isEmpty {
            noMintsState
        } else if walletManager.balance == 0 {
            noBalanceState
        } else {
            inputForm
        }
    }

    private var inputForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                destinationField
                    .padding(.horizontal)
                    .padding(.top, 12)

                if let inputHint {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.caption.weight(.semibold))
                        Text(inputHint)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }

                // Two (or three) plain action rows, generously spaced — no header,
                // no divider.
                VStack(alignment: .leading, spacing: 14) {
                    actionRow(
                        icon: "qrcode.viewfinder",
                        title: "Scan QR Code",
                        subtitle: "Pay or receive by scanning",
                        action: openScanner
                    )

                    actionRow(
                        icon: "banknote",
                        title: "Create ecash",
                        subtitle: "Generate a bearer token to share",
                        action: {
                            HapticFeedback.selection()
                            route = .ecash
                        }
                    )

                    if NFCNDEFReaderSession.readingAvailable {
                        actionRow(
                            icon: "wave.3.right.circle.fill",
                            title: "Contactless",
                            subtitle: "Tap to pay nearby",
                            action: {
                                HapticFeedback.selection()
                                onContactless()
                            }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.top, 40)

                if destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !recentRecipients.isEmpty {
                    RecentRecipientsList(recipients: recentRecipients, onTap: applyRecentRecipient)
                        .padding(.horizontal)
                        .padding(.top, 24)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var destinationField: some View {
        HStack(alignment: .top, spacing: 12) {
            TextField("Address, invoice, or Cashu request", text: $destination, axis: .vertical)
                .font(.body)
                .lineLimit(1...4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if UIPasteboard.general.hasStrings {
                    Button("Paste", action: pasteFromClipboard)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Paste from clipboard")
                }
            } else {
                Button {
                    HapticFeedback.selection()
                    destination = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding()
        .liquidGlass(in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Pinned "To" pill

    private func toPill(_ locked: LockedDestination) -> some View {
        Button(action: editFromPill) {
            HStack(spacing: 10) {
                Text("To")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(pillValue(locked))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .liquidGlass(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(step == .sending || step == .sent)
        .accessibilityLabel("Recipient \(pillValue(locked))")
        .accessibilityHint("Double-tap to change the recipient")
    }

    private func pillValue(_ locked: LockedDestination) -> String {
        switch locked {
        case .melt(let request, _, let decoded):
            if case .lightningAddress(let addr) = decoded { return addr }
            return PaymentRequestDecoder.shortRepresentation(request, result: decoded)
        case .cashuRequest(let summary):
            if let memo = summary.description?.trimmingCharacters(in: .whitespacesAndNewlines), !memo.isEmpty {
                return memo
            }
            if let host = summary.mints.first.flatMap({ URL(string: $0)?.host }) {
                return host
            }
            return "Cashu request"
        }
    }

    private func editFromPill() {
        HapticFeedback.selection()
        suppressedValue = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        meltQuote = nil
        feeTask?.cancel()
        feeState = .idle
        errorMessage = nil
        withAnimation { step = .input }
    }

    // MARK: Auto-advance

    private func handleDestinationChange() {
        autoAdvanceTask?.cancel()
        inputHint = nil
        guard step == .input else { return }
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suppressed = suppressedValue {
            if trimmed == suppressed { return }   // unchanged after a pill-edit — don't bounce
            suppressedValue = nil                  // text genuinely changed — resume
        }
        guard !trimmed.isEmpty else { return }
        autoAdvanceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, step == .input,
                  destination.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
            let result = PaymentRequestDecoder.decode(
                trimmed, includeCashuPaymentRequests: true, preferCashuPaymentRequests: true
            )
            advance(result, raw: trimmed)
        }
    }

    /// Skip the typing debounce — used for paste, scan, and recents (discrete,
    /// high-confidence events).
    private func advanceNow(raw: String) {
        autoAdvanceTask?.cancel()
        let result = PaymentRequestDecoder.decode(
            raw, includeCashuPaymentRequests: true, preferCashuPaymentRequests: true
        )
        advance(result, raw: raw)
    }

    /// Lock the destination and move to the right step. Setting `step` away from
    /// `.input` makes any in-flight debounce bail on its own re-check.
    private func advance(_ result: PaymentRequestDecodeResult, raw: String) {
        switch result {
        case .bolt11, .bolt12:
            let request = PaymentRequestDecoder.encodedLightningRequest(from: raw)
                ?? PaymentRequestParser.normalizeLightningRequest(raw)
            lockMelt(request: request, mode: .lightning, decoded: result)
            startMeltConfirm()   // amount carried by the invoice (amountless → quote errors, handled)
        case .lightningAddress(let address):
            lockMelt(request: address, mode: .lightning, decoded: result)
            goToAmount()
        case .onchain:
            lockMelt(request: PaymentRequestParser.normalizeBitcoinRequest(raw), mode: .onchain, decoded: result)
            goToAmount()
        case .cashuPaymentRequest(let summary):
            locked = .cashuRequest(summary)
            selectedMint = nil
            errorMessage = nil
            HapticFeedback.selection()
            if summary.amount != nil {
                withAnimation { step = .confirm }
                recomputeFee()
            } else {
                goToAmount()
            }
        case .unrecognized:
            if let token = TokenParser.normalizedToken(from: raw) {
                HapticFeedback.selection()
                route = .receiveToken(token)
            } else {
                inputHint = "Unrecognized — try a Lightning address, invoice, Bitcoin address, or Cashu request"
            }
        }
    }

    private func lockMelt(request: String, mode: MeltView.MeltMode, decoded: PaymentRequestDecodeResult) {
        locked = .melt(request: request, mode: mode, decoded: decoded)
        selectedMint = nil
        meltQuote = nil
        errorMessage = nil
    }

    private func goToAmount() {
        amountString = ""
        HapticFeedback.selection()
        withAnimation { step = .amount }
    }

    private func startMeltConfirm() {
        HapticFeedback.selection()
        withAnimation { step = .confirm }
        fetchMeltQuote()
    }

    // MARK: Amount step

    private var amountStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    CurrencyAmountDisplay(
                        sats: amountSats,
                        primary: $settings.amountDisplayPrimary,
                        entryRaw: amountString
                    )
                    .padding(.top, 24)

                    if let mint = currentAmountMint {
                        amountMintRow(mint)
                            .padding(.horizontal)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                }
            }

            NumberPadAmountInput(amountString: $amountString, unit: entryUnit)
                .padding(.horizontal, 24)

            Button(action: continueFromAmount) {
                Text("Continue")
            }
            .glassButton()
            .disabled(amountSats == 0)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    private func amountMintRow(_ mint: MintInfo) -> some View {
        MintAmountSelectorRow(
            mint: mint,
            balanceText: AmountFormatter.sats(mint.balance, useBitcoinSymbol: settings.useBitcoinSymbol),
            onChooseMint: {
                HapticFeedback.selection()
                showingMintPicker = true
            },
            onUseMax: useMax
        )
    }

    private func useMax() {
        guard let mint = currentAmountMint else { return }
        HapticFeedback.selection()
        amountString = AmountFormatter.entryConverted(raw: String(mint.balance), from: .sats, to: entryUnit)
    }

    private func continueFromAmount() {
        guard amountSats > 0 else { return }
        HapticFeedback.selection()
        switch locked {
        case .melt:
            withAnimation { step = .confirm }
            fetchMeltQuote()
        case .cashuRequest:
            withAnimation { step = .confirm }
            recomputeFee()
        case nil:
            break
        }
    }

    // MARK: Confirm step

    @ViewBuilder
    private var confirmStep: some View {
        switch locked {
        case .melt:
            meltConfirmBody
        case .cashuRequest(let summary):
            creqConfirmBody(summary)
        case nil:
            EmptyView()
        }
    }

    /// Melt confirm: the amount is the only prominent element; the mint, fee, and
    /// (on-chain) destination sit beneath as equal-weight detail rows.
    private var meltConfirmBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    if let quote = meltQuote {
                        CurrencyAmountDisplay(sats: quote.amount, primary: $settings.amountDisplayPrimary)
                            .padding(.top, 32)

                        meltConfirmRows(quote)

                        if !hasSufficientBalance(for: quote),
                           let balance = mintInfo(for: quote)?.balance {
                            Text("Selected mint has \(balance) sat; this quote can reserve up to \(quote.totalAmount) sat.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.center)
                                .padding(.top, 12)
                                .padding(.horizontal)
                        }
                    } else if isWorking {
                        ProgressView()
                            .padding(.top, 80)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                            .padding(.horizontal)
                    }
                }
                .padding(.top, 12)
            }

            if let quote = meltQuote {
                Button(action: payMelt) {
                    Text("Pay \(quote.amount) sat")
                }
                .glassButton()
                .disabled(isWorking || !hasSufficientBalance(for: quote))
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
    }

    private var meltCompatibleMints: [MintInfo] {
        availableMeltMints.filter { $0.supportedMeltMethods.contains(meltPaymentMethod) }
    }

    /// Read-only summary rows: the source mint (switchable when there's a choice),
    /// the on-chain destination (where the pill truncates), the network fee, and the
    /// total that leaves the balance — all equal-weight details beneath the amount.
    private func meltConfirmRows(_ quote: MeltQuoteInfo) -> some View {
        VStack(spacing: 0) {
            if let mint = mintInfo(for: quote) ?? activeMeltMint {
                mintDetailRow(label: "From", mint: mint, switchable: meltCompatibleMints.count > 1)
                creqDivider
            }
            if quote.paymentMethod == .onchain, case let .melt(request, _, _) = locked {
                creqDetailRow(icon: "arrow.up.right", label: "To", value: request)
                creqDivider
            }
            creqDetailRow(
                icon: "arrow.up.arrow.down",
                label: "Network fee",
                value: AmountFormatter.sats(quote.feeReserve, useBitcoinSymbol: settings.useBitcoinSymbol)
            )
            creqDivider
            creqDetailRow(
                icon: "creditcard",
                label: "Total",
                value: AmountFormatter.sats(quote.totalAmount, useBitcoinSymbol: settings.useBitcoinSymbol)
            )
        }
        .padding(.top, 16)
        .padding(.horizontal)
    }

    /// Shared mint detail row (used by both the melt and Cashu-request confirms):
    /// a "From"/"Mint" label, the mint avatar + name, and a chevron when the mint
    /// can be switched. Tapping a switchable row opens the mint picker.
    @ViewBuilder
    private func mintDetailRow(label: String, mint: MintInfo, switchable: Bool) -> some View {
        let content = HStack(spacing: 8) {
            Label(label, systemImage: "bitcoinsign.bank.building")
                .foregroundStyle(.secondary)
            Spacer()
            MintAvatarView(iconUrl: mint.iconUrl, name: mint.name, size: 22)
            Text(mint.name)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if switchable {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)

        if switchable {
            Button(action: {
                HapticFeedback.selection()
                showingMintPicker = true
            }) {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pay from \(mint.name)")
            .accessibilityHint("Double-tap to choose a different mint")
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(label): \(mint.name)")
        }
    }

    // MARK: Sending / sent

    private var sendingStep: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Sending…")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var sentStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: step)
            Text("Payment Sent")
                .font(.title2.weight(.semibold))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Melt quote + pay

    private func fetchMeltQuote() {
        guard case let .melt(request, mode, decoded) = locked else { return }
        guard let mint = activeMeltMint else {
            errorMessage = "No mint supports \(meltPaymentMethod.displayName) payments."
            return
        }
        isWorking = true
        errorMessage = nil
        meltQuote = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let quote: MeltQuoteInfo
                switch mode {
                case .onchain:
                    let amount = amountSats
                    guard amount > 0 else { return }
                    quote = try await walletManager.createOnchainMeltQuote(
                        address: request, amount: amount, preferredMintURL: mint.url
                    )
                case .lightning:
                    if case .lightningAddress = decoded {
                        let amount = amountSats
                        guard amount > 0 else { return }
                        quote = try await walletManager.createHumanReadableMeltQuote(
                            address: request, amount: amount, preferredMintURL: mint.url
                        )
                    } else {
                        quote = try await walletManager.createMeltQuote(
                            request: request, preferredMintURL: mint.url
                        )
                    }
                }
                meltQuote = quote
                if let resolved = mintInfo(for: quote) { selectedMint = resolved }
            } catch {
                errorMessage = error.userFacingWalletMessage
            }
        }
    }

    private func payMelt() {
        guard let quote = meltQuote else { return }
        HapticFeedback.impact(.medium)
        errorMessage = nil
        withAnimation { step = .sending }
        Task { @MainActor in
            do {
                _ = try await walletManager.meltTokens(quoteId: quote.id, mintUrl: quote.mintUrl)
                HapticFeedback.notification(.success)
                withAnimation { step = .sent }
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                onClose()
            } catch {
                HapticFeedback.notification(.error)
                errorMessage = error.userFacingWalletMessage
                withAnimation { step = .confirm }
            }
        }
    }

    // MARK: Melt mint helpers (mirror MeltView)

    private var availableMeltMints: [MintInfo] {
        walletManager.mints.isEmpty
            ? (walletManager.activeMint.map { [$0] } ?? [])
            : walletManager.mints
    }

    private var meltPaymentMethod: PaymentMethodKind {
        guard case let .melt(_, mode, decoded) = locked else { return .bolt11 }
        if mode == .onchain { return .onchain }
        if case .bolt12 = decoded { return .bolt12 }
        return .bolt11
    }

    private var meltMinAmount: UInt64? { amountSats > 0 ? amountSats : nil }

    private var activeMeltMint: MintInfo? {
        let compatible = availableMeltMints.filter { $0.supportedMeltMethods.contains(meltPaymentMethod) }
        if let selectedMint, let match = compatible.first(where: { $0.id == selectedMint.id }) {
            return match
        }
        return recommendedMeltMint(for: meltPaymentMethod, minimumAmount: meltMinAmount)
    }

    private func recommendedMeltMint(for paymentMethod: PaymentMethodKind, minimumAmount: UInt64?) -> MintInfo? {
        let compatible = availableMeltMints.filter { $0.supportedMeltMethods.contains(paymentMethod) }
        guard !compatible.isEmpty else { return nil }
        let affordable = compatible.filter { mint in
            guard let minimumAmount else { return true }
            return mint.balance >= minimumAmount
        }
        let candidates = affordable.isEmpty ? compatible : affordable
        if let active = walletManager.activeMint, candidates.contains(where: { $0.id == active.id }) {
            return active
        }
        return candidates.sorted { lhs, rhs in
            lhs.balance == rhs.balance
                ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                : lhs.balance > rhs.balance
        }.first
    }

    private func mintInfo(for quote: MeltQuoteInfo) -> MintInfo? {
        walletManager.mints.first { $0.url == quote.mintUrl }
            ?? (walletManager.activeMint?.url == quote.mintUrl ? walletManager.activeMint : nil)
    }

    private func mintDisplayName(for quote: MeltQuoteInfo) -> String {
        mintInfo(for: quote)?.name ?? URL(string: quote.mintUrl)?.host ?? quote.mintUrl
    }

    private func hasSufficientBalance(for quote: MeltQuoteInfo) -> Bool {
        guard let balance = mintInfo(for: quote)?.balance else { return true }
        return balance >= quote.totalAmount
    }

    // MARK: Shared amount-entry helpers

    private var entryUnit: AmountDisplayPrimary {
        (settings.amountDisplayPrimary == .fiat && priceService.btcPriceUSD > 0) ? .fiat : .sats
    }

    private var amountSats: UInt64 { AmountFormatter.entrySats(raw: amountString, unit: entryUnit) }

    private var currentAmountMint: MintInfo? {
        switch locked {
        case .melt: return activeMeltMint
        case .cashuRequest: return selectedPaymentMint
        case nil: return nil
        }
    }

    // MARK: Mint picker (branches on the locked destination)

    @ViewBuilder
    private var mintPickerSheet: some View {
        switch locked {
        case .melt:
            MintSelectorSheet(
                selectedMint: $selectedMint,
                paymentMethod: meltPaymentMethod,
                minimumAmount: meltMinAmount,
                onSelect: { mint in
                    selectedMint = mint
                    errorMessage = nil
                    if step == .confirm { fetchMeltQuote() }
                }
            )
            .environmentObject(walletManager)
            .presentationDetents([.medium])
        case .cashuRequest:
            MintSelectorSheet(
                selectedMint: $selectedMint,
                mints: candidateMints,
                minimumAmount: paymentAmountForCreq,
                onSelect: { mint in
                    selectedMint = mint
                    errorMessage = nil
                    recomputeFee()
                }
            )
            .environmentObject(walletManager)
            .presentationDetents([.medium])
        case nil:
            EmptyView()
        }
    }

    // MARK: Cashu-request confirm (ported from CashuPaymentRequestPayView)

    private var currentCreq: CashuPaymentRequestSummary? {
        if case .cashuRequest(let summary) = locked { return summary }
        return nil
    }

    private func creqConfirmBody(_ creq: CashuPaymentRequestSummary) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    CurrencyAmountDisplay(
                        sats: paymentAmountForCreq ?? 0,
                        primary: $settings.amountDisplayPrimary
                    )
                    .padding(.top, 32)

                    creqRequestDetails(creq)

                    if !creq.isSatUnit {
                        Text("This wallet can only pay sat-denominated Cashu requests.")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                            .padding(.horizontal)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                            .padding(.horizontal)
                    }
                }
                .padding(.top, 12)
            }

            Button(action: payCreq) {
                Text("Pay")
            }
            .glassButton()
            .disabled(!creqCanPay)
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    private func payCreq() {
        guard let creq = currentCreq, creqCanPay, let mint = selectedPaymentMint else { return }
        HapticFeedback.impact(.medium)
        errorMessage = nil
        withAnimation { step = .sending }
        Task { @MainActor in
            do {
                try await walletManager.payCashuPaymentRequest(
                    encoded: creq.encoded,
                    customAmountSats: creq.amount == nil ? paymentAmountForCreq : nil,
                    preferredMintURL: mint.url
                )
                HapticFeedback.notification(.success)
                withAnimation { step = .sent }
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                onClose()
            } catch {
                HapticFeedback.notification(.error)
                errorMessage = error.userFacingWalletMessage
                withAnimation { step = .confirm }
            }
        }
    }

    private var paymentAmountForCreq: UInt64? {
        guard let creq = currentCreq else { return nil }
        return creq.amount ?? (amountSats > 0 ? amountSats : nil)
    }

    private var creqCanPay: Bool {
        guard let creq = currentCreq, creq.isSatUnit, !isWorking else { return false }
        guard let amount = paymentAmountForCreq, amount > 0 else { return false }
        guard let mint = selectedPaymentMint else { return false }
        return mint.balance >= amount
    }

    private var candidateMints: [MintInfo] {
        guard let creq = currentCreq else { return [] }
        guard !creq.mints.isEmpty else { return walletManager.mints }
        let requested = Set(creq.mints.map(normalizedMintURL))
        return walletManager.mints.filter { requested.contains(normalizedMintURL($0.url)) }
    }

    private var selectedPaymentMint: MintInfo? {
        if let selectedMint, let match = candidateMints.first(where: { $0.id == selectedMint.id }) {
            return match
        }
        return recommendedPaymentMint()
    }

    private func recommendedPaymentMint() -> MintInfo? {
        guard !candidateMints.isEmpty else { return nil }
        let candidates: [MintInfo]
        if let amount = paymentAmountForCreq, amount > 0 {
            let affordable = candidateMints.filter { $0.balance >= amount }
            candidates = affordable.isEmpty ? candidateMints : affordable
        } else {
            candidates = candidateMints
        }
        if let active = walletManager.activeMint, let match = candidates.first(where: { $0.id == active.id }) {
            return match
        }
        return candidates.sorted { lhs, rhs in
            lhs.balance == rhs.balance
                ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                : lhs.balance > rhs.balance
        }.first
    }

    private func normalizedMintURL(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            return trimmed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        var normalized = host
        if let port = url.port { normalized += ":\(port)" }
        normalized += url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return normalized
    }

    private func extractMintHost(_ url: String) -> String { URL(string: url)?.host ?? url }

    // creq fee

    private func recomputeFee() {
        feeTask?.cancel()
        guard let creq = currentCreq, creq.isSatUnit,
              let mint = selectedPaymentMint,
              let amount = paymentAmountForCreq, amount > 0 else {
            feeState = .idle
            return
        }
        if let ppk = feePpkByMint[mint.url], ppk == 0 {
            feeState = .free
            return
        }
        feeState = .loading
        let mintURL = mint.url
        feeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            let ppk: UInt64?
            if let cached = feePpkByMint[mintURL] {
                ppk = cached
            } else {
                ppk = await walletManager.mintInputFeePpk(mintURL: mintURL)
                if let ppk { feePpkByMint[mintURL] = ppk }
            }
            if Task.isCancelled { return }
            guard let ppk else { feeState = .unavailable; return }
            if ppk == 0 { feeState = .free; return }
            let fee = await walletManager.estimateCashuPaymentFee(amountSats: amount, mintURL: mintURL)
            if Task.isCancelled { return }
            feeState = fee.map { $0 == 0 ? .free : .amount($0) } ?? .unavailable
        }
    }

    // creq mint-identity header + detail rows

    private enum CreqMintPresentation {
        case picker(selected: MintInfo)
        case fixed(MintInfo)
        case unavailable(requiredHosts: [String])
    }

    private func creqMintPresentation(_ creq: CashuPaymentRequestSummary) -> CreqMintPresentation {
        guard let selected = selectedPaymentMint else {
            return .unavailable(requiredHosts: creq.mints.map(extractMintHost))
        }
        if creq.mints.count == 1 { return .fixed(selected) }
        return .picker(selected: selected)
    }

    private func creqMemo(_ creq: CashuPaymentRequestSummary) -> String? {
        guard let description = creq.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !description.isEmpty else { return nil }
        return description
    }

    /// Detail rows beneath the amount: the source mint (switchable when the request
    /// accepts more than one), the memo, and the live fee — equal-weight details, no
    /// prominent header.
    @ViewBuilder
    private func creqRequestDetails(_ creq: CashuPaymentRequestSummary) -> some View {
        if creq.isSatUnit {
            VStack(spacing: 0) {
                creqMintRow(creq)
                creqDivider
                if let memo = creqMemo(creq) {
                    creqDetailRow(icon: "quote.bubble", label: "Memo", value: memo)
                    creqDivider
                }
                creqFeesRow
            }
            .padding(.top, 16)
            .padding(.horizontal)
        }
    }

    /// The mint as a detail row: switchable for an any-/multi-mint request, read-only
    /// for a required mint, or a warning when the user holds none of the requested mints.
    @ViewBuilder
    private func creqMintRow(_ creq: CashuPaymentRequestSummary) -> some View {
        switch creqMintPresentation(creq) {
        case .picker(let selected):
            mintDetailRow(label: "From", mint: selected, switchable: true)
        case .fixed(let mint):
            mintDetailRow(label: "Mint", mint: mint, switchable: false)
        case .unavailable(let hosts):
            HStack(spacing: 8) {
                Label("Mint", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Spacer()
                Text(hosts.isEmpty ? "Add a mint to pay"
                        : (hosts.count == 1 ? hosts[0] : "You hold none of these"))
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.subheadline)
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
            .accessibilityElement(children: .combine)
        }
    }

    private var creqFeesRow: some View {
        HStack {
            Label("Fees", systemImage: "arrow.up.arrow.down")
                .foregroundStyle(.secondary)
            Spacer()
            creqFeeValueText
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var creqFeeValueText: some View {
        switch feeState {
        case .loading:
            ProgressView().controlSize(.mini)
        case .free:
            Text("No fee").fontWeight(.medium)
        case .amount(let fee):
            Text(AmountFormatter.sats(fee, useBitcoinSymbol: settings.useBitcoinSymbol))
                .fontWeight(.medium)
        case .idle, .unavailable:
            Text("—").foregroundStyle(.secondary)
        }
    }

    private func creqDetailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private var creqDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 0.5)
            .padding(.horizontal, 4)
    }

    // MARK: Recents

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

    private func applyRecentRecipient(_ recipient: RecentRecipientsList.Recipient) {
        HapticFeedback.selection()
        destination = recipient.invoice
        advanceNow(raw: recipient.invoice)
    }

    // MARK: Action row + input actions

    private func actionRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openScanner() {
        HapticFeedback.selection()
        showingScanner = true
    }

    private func handleScannedDestination(_ scanned: String) {
        let trimmed = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        destination = trimmed
        advanceNow(raw: trimmed)
    }

    private func pasteFromClipboard() {
        guard let content = UIPasteboard.general.string else { return }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        HapticFeedback.selection()
        destination = trimmed
        advanceNow(raw: trimmed)
    }

    @ViewBuilder
    private func routeView(_ route: SendRoute) -> some View {
        switch route {
        case .receiveToken(let token):
            ReceiveTokenDetailView(
                tokenString: token,
                onComplete: { self.route = nil; onClose() }
            )
            .environmentObject(walletManager)
        case .ecash:
            SendView()
                .environmentObject(walletManager)
        }
    }

    // MARK: Empty states (reproduced from the old send chooser)

    private var noMintsState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect a mint first")
                        .font(.title3.weight(.medium))
                    Text("Mints issue the ecash you send and receive. Add one to get started.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                SuggestedMintsSection(
                    existingURLs: Set(walletManager.mints.map(\.url)),
                    onAdd: addMint
                )

                if let addMintError {
                    Text(addMintError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                Button(action: onAddCustomMint) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Add custom mint URL")
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
                .textLinkButton()
                .padding(.top, 4)
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    private var noBalanceState: some View {
        VStack(spacing: 16) {
            Image(systemName: "banknote")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Nothing to send yet")
                    .font(.title3.weight(.medium))
                Text("Receive some ecash before you can send.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Receive", action: onReceive)
                .glassButton()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private func addMint(_ url: String) {
        addMintError = nil
        Task {
            do {
                try await walletManager.addMint(url: url)
            } catch {
                addMintError = "Couldn't connect to that mint. Try another."
            }
        }
    }
}

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
    private let onComplete: (() -> Void)?

    @State private var requestInput: String
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
                    .canvasSheetBackground()
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
                    .canvasSheetBackground()
            }
            .onAppear {
                syncMeltModeWithAvailableMints()
                syncSelectedMeltMint()
                detectClipboardSuggestion()
                if autoQuoteOnAppear,
                   !requestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !amountRequired {
                    getQuote()
                }
            }
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

    private var selectedMeltPaymentMethod: PaymentMethodKind {
        if meltMode == .onchain {
            return .onchain
        }

        if isHumanReadableAddress {
            return .bolt11
        }

        return PaymentRequestParser.paymentMethod(for: requestInput) ?? .bolt11
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

        switch PaymentRequestDecoder.decode(requestInput) {
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
        meltMode == .lightning && PaymentRequestParser.isHumanReadableLightningAddress(requestInput)
    }

    private var isBitcoinAddress: Bool {
        PaymentRequestParser.isBitcoinAddress(requestInput)
    }

    private var amountRequired: Bool {
        meltMode == .onchain || isHumanReadableAddress
    }

    private var canGetQuote: Bool {
        guard !requestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        if amountRequired {
            guard amountSats > 0 else { return false }
        }

        if meltMode == .onchain {
            return isBitcoinAddress
        }

        return true
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
                    onTap: { applyDecodedSuggestion(suggestion, raw: raw) },
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
        let trimmed = requestInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let result = PaymentRequestDecoder.decode(trimmed)
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
        let result = PaymentRequestDecoder.decode(trimmed)
        applyDecodedSuggestion(result, raw: trimmed)
    }

    private func openScanner() {
        HapticFeedback.selection()
        showingScanner = true
    }

    private func handleScannedRequest(_ scanned: String) {
        let trimmed = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let result = PaymentRequestDecoder.decode(trimmed)
        applyDecodedSuggestion(result, raw: trimmed)
    }

    private func detectClipboardSuggestion() {
        guard !dismissedClipboardSuggestion,
              clipboardSuggestion == nil,
              requestInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let content = UIPasteboard.general.string else { return }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let result = PaymentRequestDecoder.decode(trimmed)
        guard result != .unrecognized else { return }
        clipboardSuggestion = result
        clipboardSuggestionRaw = trimmed
    }

    private func applyDecodedSuggestion(_ result: PaymentRequestDecodeResult, raw: String) {
        // Choose mode based on suggestion (if we can switch).
        if let suggested = PaymentRequestDecoder.suggestedMode(result),
           suggested != meltMode,
           suggested != .onchain || supportsOnchainMelt {
            withAnimation(.snappy) { meltMode = suggested }
        }

        // Fill input with normalized request.
        switch result {
        case .onchain:
            requestInput = PaymentRequestParser.normalizeBitcoinRequest(raw)
        case .bolt11, .bolt12:
            requestInput = PaymentRequestDecoder.encodedLightningRequest(from: raw)
                ?? PaymentRequestParser.normalizeLightningRequest(raw)
        case .lightningAddress, .cashuPaymentRequest, .unrecognized:
            requestInput = raw
        }

        // Hide the chip after a tap.
        dismissedClipboardSuggestion = true
        errorMessage = nil

        // Auto-quote when amount is locked.
        if PaymentRequestDecoder.amountLocked(result) {
            getQuote()
        }
    }

    private func applyRecentRecipient(_ recipient: RecentRecipientsList.Recipient) {
        HapticFeedback.selection()
        let result = PaymentRequestDecoder.decode(recipient.invoice)
        // Reuse the same routing as suggestion tap, but never auto-quote: the
        // user is reusing a destination at a (likely) new amount.
        if let suggested = PaymentRequestDecoder.suggestedMode(result),
           suggested != meltMode,
           suggested != .onchain || supportsOnchainMelt {
            withAnimation(.snappy) { meltMode = suggested }
        }
        switch result {
        case .onchain:
            requestInput = PaymentRequestParser.normalizeBitcoinRequest(recipient.invoice)
        case .bolt11, .bolt12:
            requestInput = PaymentRequestDecoder.encodedLightningRequest(from: recipient.invoice)
                ?? PaymentRequestParser.normalizeLightningRequest(recipient.invoice)
        case .lightningAddress, .cashuPaymentRequest, .unrecognized:
            requestInput = recipient.invoice
        }
        errorMessage = nil
    }

    private func getQuote() {
        let trimmedInput = requestInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        if meltMode == .lightning,
           PaymentRequestParser.paymentMethod(for: trimmedInput) == .onchain {
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

        isGettingQuote = true
        errorMessage = nil

        Task { @MainActor in
            defer { isGettingQuote = false }

            do {
                switch meltMode {
                case .lightning:
                    if isHumanReadableAddress {
                        let amount = amountSats
                        guard amount > 0 else { return }
                        let quote = try await walletManager.createHumanReadableMeltQuote(
                            address: trimmedInput,
                            amount: amount,
                            preferredMintURL: quoteMint.url
                        )
                        setMeltQuote(quote)
                    } else {
                        let request = PaymentRequestDecoder.encodedLightningRequest(from: trimmedInput) ?? trimmedInput
                        let quote = try await walletManager.createMeltQuote(
                            request: request,
                            preferredMintURL: quoteMint.url
                        )
                        setMeltQuote(quote)
                    }
                case .onchain:
                    let amount = amountSats
                    guard amount > 0 else { return }
                    let quote = try await walletManager.createOnchainMeltQuote(
                        address: trimmedInput,
                        amount: amount,
                        preferredMintURL: quoteMint.url
                    )
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
