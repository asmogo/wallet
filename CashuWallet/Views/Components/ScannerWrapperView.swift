import SwiftUI
import AVFoundation
import Cdk
#if canImport(URKit)
import URKit
#endif

class ScannerViewModel: ObservableObject {
    @Published var scanProgress: Double = 0
    @Published var isScanning = true
    @Published var errorMessage: String?
    
    #if canImport(URKit)
    private var decoder = URDecoder()
    #endif
    
    func reset() {
        #if canImport(URKit)
        decoder = URDecoder()
        #endif
        scanProgress = 0
        isScanning = true
        errorMessage = nil
    }
    
    func processFragment(_ fragment: String) -> String? {
        #if canImport(URKit)
        decoder.receivePart(fragment)
        
        DispatchQueue.main.async {
            self.scanProgress = self.decoder.estimatedPercentComplete
        }
        
        if decoder.result != nil {
            guard let result = try? decoder.result?.get() else {
                return nil
            }
            
     
            
            // Fallback: Try .bytes/.text just in case older version
            if case let .bytes(bytesArray) = result.cbor {
                let data = Data(bytesArray)
                return String(data: data, encoding: .utf8)
            }
            
            if case let .text(text) = result.cbor {
                return text
            }
            
            return nil
        }
        return nil
        #else
        DispatchQueue.main.async {
            self.errorMessage = "URKit module missing. Cannot scan animated QR."
        }
        return nil
        #endif
    }
    
    #if canImport(URKit)
    // No manual extraction needed when using URKit's CBOR type
    #endif
}

struct ScannerWrapperView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager

    /// Optional callback. When provided, the scanner short-circuits its default
    /// routing (Receive detail / fresh MeltView) and just returns the raw
    /// scanned string so the caller can decide what to do.
    var onScanned: ((String) -> Void)? = nil

    /// Optional override for the instruction shown under the viewfinder.
    var promptText: String? = nil

    /// When true, only Cashu payment requests are accepted; anything else shows
    /// an inline error and re-arms. Used by Send → Pay Cashu Request so the
    /// labeled action stays honest. Routes the request through the scanner's own
    /// `.fullScreenCover` (on top of the still-open scanner) rather than asking
    /// the caller to dismiss-then-present — which yields a black screen.
    var cashuRequestOnly: Bool = false

    /// Invoked when an internally-routed pay flow completes, so a presenter can
    /// fully tear down (e.g. SendView leaving the whole Send flow back to the
    /// wallet). Nil for the home page, where dismissing the scanner suffices.
    var onComplete: (() -> Void)? = nil

    /// Optional quick-fill chips rendered over the camera (e.g. "Paste",
    /// "Use my latest key"). Tapping one routes its `value` through the same
    /// pipeline as a scanned code. Evaluated once on appear so the caller can
    /// read the clipboard lazily — only when the scanner is actually shown.
    var quickFills: (() -> [ScannerQuickFill])? = nil

    struct ScannerQuickFill: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String
        let value: String
    }

    @StateObject private var scannerModel = ScannerViewModel()
    @State private var resolvedQuickFills: [ScannerQuickFill] = []
    @State private var scannedToken: String?
    @State private var scannedMeltRequest: String?
    @State private var scannedCashuPaymentRequest: CashuPaymentRequestSummary?
    @State private var scannedMeltMode: MeltView.MeltMode = .lightning
    @State private var scannedMeltAutoQuote = false
    @State private var navigateToDetail = false
    @State private var navigateToMelt = false
    @State private var navigateToCashuPaymentRequest = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                LegacyQRScannerView { code in
                    handleScan(code: code)
                }
                .ignoresSafeArea()
                
                // Overlay
                VStack {
                    Spacer()
                    
                    if scannerModel.scanProgress > 0 && scannerModel.scanProgress < 1.0 {
                        // Progress UI for animated QR
                        VStack(spacing: 8) {
                            Text("Scanning Animated QR...")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            ProgressView(value: scannerModel.scanProgress, total: 1.0)
                                .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                                .frame(height: 8)
                                .padding(.horizontal)
                            
                            Text("\(Int(scannerModel.scanProgress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding()
                        .background(Color.black.opacity(0.8))
                        .clipShape(.rect(cornerRadius: 16))
                        .padding(.bottom, 50)
                        .padding(.horizontal, 40)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(resolvedQuickFills) { fill in
                                Button {
                                    HapticFeedback.selection()
                                    processCompleteContent(fill.value)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: fill.systemImage)
                                        Text(fill.title)
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 11)
                                    .background(.ultraThinMaterial, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Use this instead of scanning")
                            }

                            Text(promptText ?? "Scan Cashu Token, Payment Request, or Bitcoin Address")
                                .foregroundStyle(.primary)
                                .font(.caption)
                                .padding()
                                .background(Color.black.opacity(0.6))
                                .clipShape(.rect(cornerRadius: 20))
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 50)
                    }
                }
                
                if let error = scannerModel.errorMessage {
                    VStack {
                        Spacer()
                        Text(error)
                            .foregroundStyle(.primary)
                            .padding()
                            .background(Color.red)
                            .clipShape(.rect(cornerRadius: 10))
                            .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                }
            }
            .onAppear {
                resolvedQuickFills = quickFills?() ?? []
            }
            .sheet(isPresented: $navigateToDetail, onDismiss: {
                // Sheet closed without completing the receive: re-arm the scanner
                // so the next QR code is processed.
                scannedToken = nil
                scannerModel.reset()
            }) {
                if let token = scannedToken {
                    ReceiveTokenDetailView(tokenString: token, onComplete: {
                        // Dismiss the entire scanner sheet
                        dismiss()
                    })
                    .environmentObject(walletManager)
                    .presentationDetents([.medium, .large])
                    .canvasSheetBackground()
                }
            }
            .fullScreenCover(isPresented: $navigateToMelt) {
                if let meltRequest = scannedMeltRequest {
                    MeltView(
                        initialRequest: meltRequest,
                        initialMode: scannedMeltMode,
                        autoQuoteOnAppear: scannedMeltAutoQuote,
                        onComplete: {
                            dismiss()
                        }
                    )
                    .environmentObject(walletManager)
                    .canvasSheetBackground()
                }
            }
            .fullScreenCover(isPresented: $navigateToCashuPaymentRequest) {
                if let request = scannedCashuPaymentRequest {
                    CashuPaymentRequestPayView(request: request, onComplete: {
                        // Mutually exclusive so the Send path fires the same
                        // number of dismissals as the home page: either the
                        // presenter tears down the whole stack, or we just
                        // dismiss the scanner sheet.
                        if let onComplete {
                            onComplete()
                        } else {
                            dismiss()
                        }
                    })
                    .environmentObject(walletManager)
                    .canvasSheetBackground()
                }
            }
        }
    }

    private static func isHumanReadableAddress(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let atIndex = trimmed.firstIndex(of: "@") else { return false }
        let user = trimmed[trimmed.startIndex..<atIndex]
        let domain = trimmed[trimmed.index(after: atIndex)...]
        return !user.isEmpty && domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    private static func parseLightningPaymentRequest(_ content: String) -> String? {
        try? LightningRequestParser.parse(content).request
    }

    private func handleScan(code: String) {
        guard scannerModel.isScanning else { return }
        
        let content = code.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // UR Format Handling
        if content.lowercased().hasPrefix("ur:") {
            if let result = scannerModel.processFragment(content) {
                // Success!
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                processCompleteContent(result)
            }
        } else {
            // Standard QR
            processCompleteContent(content)
        }
    }
    
    private func processCompleteContent(_ content: String) {
        scannerModel.isScanning = false

        // If the caller provided a direct callback (e.g. MeltView's inline
        // scan icon), hand back the raw string and dismiss — no routing.
        if let onScanned {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            onScanned(content)
            dismiss()
            return
        }

        // Restricted intake: the caller (Send → Pay Cashu Request) only accepts
        // Cashu requests. Route a match through the scanner's own cover; reject
        // anything else inline and re-arm so the labeled action stays honest.
        if cashuRequestOnly {
            if case .cashuPaymentRequest(let request) = PaymentRequestDecoder.decode(
                content,
                includeCashuPaymentRequests: true,
                preferCashuPaymentRequests: true
            ) {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                scannedCashuPaymentRequest = request
                navigateToCashuPaymentRequest = true
            } else {
                scannerModel.errorMessage = "That's not a Cashu request."
                HapticFeedback.notification(.error)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    scannerModel.reset()
                }
            }
            return
        }

        // Determine content type: Token (Receive), Cashu request (Pay), or
        // external payment request (Pay/Melt).
        if let token = TokenParser.normalizedToken(from: content) {
            // Handle Ecash Token -> Show Detail View
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            scannedToken = token
            navigateToDetail = true

        } else if case .cashuPaymentRequest(let request) = PaymentRequestDecoder.decode(
            content,
            includeCashuPaymentRequests: true,
            preferCashuPaymentRequests: true
        ), request.isSatUnit || PaymentRequestDecoder.encodedLightningRequest(from: content) == nil {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            scannedCashuPaymentRequest = request
            navigateToCashuPaymentRequest = true
            
        } else {
            let decodedPaymentRequest = PaymentRequestDecoder.decode(content)
            switch decodedPaymentRequest {
            case .bolt11, .bolt12, .onchain:
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                if case .onchain = decodedPaymentRequest {
                    scannedMeltRequest = PaymentRequestParser.normalizeBitcoinRequest(content)
                    scannedMeltMode = .onchain
                    scannedMeltAutoQuote = false
                } else {
                    scannedMeltRequest = PaymentRequestDecoder.encodedLightningRequest(from: content)
                        ?? PaymentRequestParser.normalizeLightningRequest(content)
                    scannedMeltMode = .lightning
                    scannedMeltAutoQuote = true
                }
                navigateToMelt = true

            case .lightningAddress:
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                scannedMeltRequest = content
                scannedMeltMode = .lightning
                scannedMeltAutoQuote = false
                navigateToMelt = true

            case .cashuPaymentRequest, .unrecognized:
                processUnsupportedContent(content)
            }
        }
    }

    private func processUnsupportedContent(_ content: String) {
        if content.lowercased().hasPrefix("https://") && content.contains("mint") {
            // Possibly a mint URL - copy for now, could add mint
            UIPasteboard.general.string = content
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            scannerModel.errorMessage = "Mint URL copied to clipboard"

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.dismiss()
            }
        } else {
            scannerModel.errorMessage = "Unknown QR Code format"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                scannerModel.reset()
            }
        }
    }
}

struct CashuPaymentRequestPayView: View {
    let request: CashuPaymentRequestSummary
    var onComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared

    @State private var customAmountString = ""
    @State private var isPaying = false
    @State private var errorMessage: String?
    @State private var errorSeverity: ErrorSeverity = .error
    @State private var showAuthorizingOverlay = false
    @State private var authorizingState: AuthorizingOverlay.FlowState = .authorizing
    @State private var showingMintPicker = false
    @State private var selectedMint: MintInfo?

    @State private var feeState: FeeState = .idle
    @State private var feeTask: Task<Void, Never>?
    /// Cache of each mint's input-fee ppk so live amount entry doesn't refetch
    /// keysets on every keystroke; ppk doesn't depend on the amount.
    @State private var feePpkByMint: [String: UInt64] = [:]

    /// Resolved fee for the current mint + amount. `.free` is exact (the mint
    /// charges no swap fee); `.amount` is the exact fee for a fee-charging mint.
    private enum FeeState: Equatable {
        case idle        // no amount yet — nothing to price
        case loading
        case free
        case amount(UInt64)
        case unavailable // couldn't determine
    }

    var body: some View {
        NavigationStack {
            // Family-style confirm layout: a centered mint-identity header
            // (icon + name + "Required mint"/"Any mint") sits above the amount
            // hero, with read-only request facts (From / Memo / Fees) beneath.
            VStack(spacing: 0) {
                Spacer()

                if request.isSatUnit {
                    mintHeader
                        .padding(.horizontal)
                        .padding(.bottom, request.amount == nil ? 16 : 24)
                }

                amountSection

                requestDetailsSection

                if !request.isSatUnit {
                    InlineNotice(
                        message: "This wallet can only pay sat-denominated Cashu requests.",
                        severity: .caution
                    )
                    .padding(.top, 12)
                    .padding(.horizontal)
                }

                if let errorMessage {
                    InlineNotice(message: errorMessage, severity: errorSeverity)
                        .padding(.top, 12)
                        .padding(.horizontal)
                }

                Spacer()

                if request.amount == nil {
                    NumberPadAmountInput(amountString: $customAmountString, unit: entryUnit)
                        .padding(.horizontal, 24)
                }

                Button(action: payRequest) {
                    if isPaying {
                        ProgressView()
                    } else {
                        Text("Pay")
                    }
                }
                .glassButton()
                .disabled(!canPay)
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            .navigationTitle("Cashu Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .sheet(isPresented: $showAuthorizingOverlay, onDismiss: resetAuthorizingState) {
                AuthorizingOverlay(
                    amountSats: paymentAmount ?? 0,
                    recipient: recipientLabel,
                    recipientCaption: "Cashu payment request",
                    state: $authorizingState,
                    onDismiss: {
                        showAuthorizingOverlay = false
                        onComplete?()
                        dismiss()
                    }
                )
                .presentationDetents([.height(340)])
                .presentationBackgroundInteraction(.disabled)
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showingMintPicker) {
                MintSelectorSheet(
                    selectedMint: $selectedMint,
                    mints: candidateMints,
                    minimumAmount: paymentAmount,
                    onSelect: { mint in
                        selectedMint = mint
                        errorMessage = nil
                    }
                )
                .environmentObject(walletManager)
                .presentationDetents([.medium])
            }
            .onAppear {
                syncSelectedMint()
                recomputeFee()
            }
            .onChange(of: customAmountString) {
                syncSelectedMint()
            }
            .onChange(of: walletManager.activeMint?.id) {
                syncSelectedMint()
            }
            .onChange(of: selectedPaymentMint?.id) {
                recomputeFee()
            }
            .onChange(of: paymentAmount) {
                recomputeFee()
            }
            .onChange(of: entryUnit) { oldUnit, newUnit in
                customAmountString = AmountFormatter.entryConverted(raw: customAmountString, from: oldUnit, to: newUnit)
            }
            .onDisappear {
                feeTask?.cancel()
            }
        }
    }

    @ViewBuilder
    private var amountSection: some View {
        if let amount = request.amount, request.isSatUnit {
            CurrencyAmountDisplay(
                sats: amount,
                primary: $settings.amountDisplayPrimary
            )
        } else if let amount = request.amount {
            VStack(spacing: 6) {
                Text("\(amount)")
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(request.unit ?? "unknown unit")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        } else {
            CurrencyAmountDisplay(
                sats: customAmountSats,
                primary: $settings.amountDisplayPrimary,
                entryRaw: customAmountString
            )
        }
    }

    /// A requester-supplied memo, shown as a read-only "Memo" row in the
    /// request-details section under the amount. Nil when the request has no
    /// real description — the old screen rendered a hardcoded "Cashu payment"
    /// placeholder, which said nothing.
    private var requestMemo: String? {
        guard let description = request.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !description.isEmpty else { return nil }
        return description
    }

    /// How the request's mint is offered, derived from `request.mints`
    /// (empty = any, 1 = required, ≥2 = alternatives) and what the user holds.
    private enum MintPresentation {
        /// Flexible / multi-mint request with ≥1 qualifying held mint — generic
        /// header plus a switchable From row carrying `selected`.
        case picker(mints: [MintInfo], selected: MintInfo)
        /// Exactly one required mint that the user holds — named in the header,
        /// no From row (there's nothing to switch).
        case fixed(MintInfo)
        /// No usable held mint — warning header, Pay disabled.
        /// `requiredHosts` is the requested mint host(s); empty means an
        /// any-mint request and the user holds no mints at all.
        case unavailable(requiredHosts: [String])
    }

    private var mintPresentation: MintPresentation {
        // `selectedPaymentMint` is nil exactly when `candidateMints` is empty,
        // i.e. no held mint satisfies the request — covers both a required mint
        // we don't hold and a flexible request we can't service.
        guard let selected = selectedPaymentMint else {
            return .unavailable(requiredHosts: request.mints.map(extractMintHost))
        }
        // The count check sits after the nil-guard, so a single required mint we
        // *don't* hold falls through to `.unavailable`, not `.fixed`.
        if request.mints.count == 1 {
            return .fixed(selected)
        }
        return .picker(mints: candidateMints, selected: selected)
    }

    private enum HeaderIcon {
        case mint(MintInfo)   // a mint we hold — show its avatar
        case generic          // any-mint / unavailable — generic mint glyph
    }

    /// The mint-identity header derived from how the request constrains the
    /// mint. `.fixed` shows the pinned mint; `.picker` shows a generic "Any
    /// mint" / "Multiple mints" badge (the actual source sits in the From row);
    /// `.unavailable` shows a warning because the user can't pay.
    private var headerContent: (icon: HeaderIcon, name: String, subtitle: String, isWarning: Bool) {
        switch mintPresentation {
        case .fixed(let mint):
            return (.mint(mint), mint.name, "Required mint", false)
        case .picker:
            if request.mints.isEmpty {
                return (.generic, "Any mint", "Pay from any mint", false)
            } else {
                return (.generic, "Multiple mints", "Pay from one of \(request.mints.count)", false)
            }
        case .unavailable(let hosts):
            if hosts.isEmpty {
                return (.generic, "Any mint", "Add a mint to pay", true)
            } else if hosts.count == 1 {
                return (.generic, hosts[0], "Not in your wallet", true)
            } else {
                return (.generic, "Multiple mints", "You hold none of these", true)
            }
        }
    }

    /// The source mint shown in the From row — only when the user can actually
    /// choose it (a flexible / multi-mint request). For a pinned mint there's
    /// nothing to switch, so the header alone names it.
    private var fromRowMint: MintInfo? {
        if case .picker(_, let selected) = mintPresentation { return selected }
        return nil
    }

    /// Family-style detail rows beneath the amount: the source mint (only when
    /// it's switchable), the requester's memo, and the fee. Only shown for sat
    /// requests; non-sat requests surface their own "unsupported" warning.
    @ViewBuilder
    private var requestDetailsSection: some View {
        if request.isSatUnit {
            let mint = fromRowMint
            let memo = requestMemo

            VStack(spacing: 0) {
                if let mint {
                    fromRow(mint: mint)
                    canvasDivider
                }
                if let memo {
                    detailRow(icon: "quote.bubble", label: "Memo", value: memo)
                    canvasDivider
                }
                feesRow
            }
            .padding(.top, 16)
            .padding(.horizontal)
        }
    }

    /// Centered mint-identity header: icon, name, and a quiet subtitle. Compacts
    /// (smaller icon, tighter type) when the number pad is present so the
    /// any-amount screen still fits.
    private var mintHeader: some View {
        let content = headerContent
        let compact = request.amount == nil

        return VStack(spacing: compact ? 8 : 12) {
            headerIcon(content.icon, size: compact ? 44 : 60)
            VStack(spacing: 3) {
                Text(content.name)
                    .font(compact ? .headline : .title3.weight(.semibold))
                    .foregroundStyle(content.isWarning ? Color.orange : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(content.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(content.isWarning ? Color.orange : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(content.name), \(content.subtitle)")
    }

    @ViewBuilder
    private func headerIcon(_ icon: HeaderIcon, size: CGFloat) -> some View {
        switch icon {
        case .mint(let mint):
            MintAvatarView(iconUrl: mint.iconUrl, name: mint.name, size: size)
        case .generic:
            Circle()
                .fill(.quaternary)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "bitcoinsign.bank.building")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.secondary)
                )
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    /// Source-mint row with a dropdown affordance — only rendered when the mint
    /// is switchable. Tapping opens the same mint picker as before.
    private func fromRow(mint: MintInfo) -> some View {
        Button(action: {
            HapticFeedback.selection()
            showingMintPicker = true
        }) {
            HStack(spacing: 8) {
                Label("From", systemImage: "bitcoinsign.bank.building")
                    .foregroundStyle(.secondary)
                Spacer()
                if let iconUrl = mint.iconUrl, let url = URL(string: iconUrl) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                }
                Text(mint.name)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pay from \(mint.name)")
        .accessibilityHint("Double-tap to choose a different mint")
    }

    /// Fee row. "No fee" is exact (the mint charges no swap fee); a sat value is
    /// the exact fee for a fee-charging mint; "—" before an amount exists.
    private var feesRow: some View {
        HStack {
            Label("Fees", systemImage: "arrow.up.arrow.down")
                .foregroundStyle(.secondary)
            Spacer()
            feeValueText
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var feeValueText: some View {
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

    /// Recompute the fee for the current mint + amount. Uses the cached per-mint
    /// ppk to short-circuit the common zero-fee case without a network call;
    /// only a fee-charging mint triggers the exact `prepareSend` estimate.
    private func recomputeFee() {
        feeTask?.cancel()

        guard request.isSatUnit,
              let mint = selectedPaymentMint,
              let amount = paymentAmount, amount > 0 else {
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
            // Debounce live typing so we don't price every keystroke.
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

            guard let ppk else {
                feeState = .unavailable
                return
            }
            if ppk == 0 {
                feeState = .free
                return
            }

            let fee = await walletManager.estimateCashuPaymentFee(amountSats: amount, mintURL: mintURL)
            if Task.isCancelled { return }
            feeState = fee.map { $0 == 0 ? .free : .amount($0) } ?? .unavailable
        }
    }

    /// Read-only detail row matching the app's `detailRow` vocabulary
    /// (TransactionDetailView, CashuRequestDetailView). Memo text is prose, so it
    /// wraps once and tail-truncates rather than middle-truncating like an ID.
    private func detailRow(icon: String, label: String, value: String) -> some View {
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

    private var canvasDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 0.5)
            .padding(.horizontal, 4)
    }

    /// Host of a mint URL for display when we hold no `MintInfo` for it
    /// (matches ReceiveLightningView / SendView).
    private func extractMintHost(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }

    private var canPay: Bool {
        guard !isPaying, request.isSatUnit else { return false }
        guard let amount = paymentAmount, amount > 0 else { return false }
        guard let mint = selectedPaymentMint else { return false }
        return mint.balance >= amount
    }

    /// The unit the keypad is entering in: fiat only when fiat is primary AND a
    /// price is loaded, else sats (mirrors `CurrencyAmountDisplay.effectivePrimary`).
    private var entryUnit: AmountDisplayPrimary {
        (settings.amountDisplayPrimary == .fiat && priceService.btcPriceUSD > 0) ? .fiat : .sats
    }

    /// Satoshis represented by the typed custom amount, interpreted per `entryUnit`.
    private var customAmountSats: UInt64 {
        AmountFormatter.entrySats(raw: customAmountString, unit: entryUnit)
    }

    private var paymentAmount: UInt64? {
        request.amount ?? (customAmountSats > 0 ? customAmountSats : nil)
    }

    private var recipientLabel: String {
        request.description?.isEmpty == false ? request.description! : "Cashu request"
    }

    private var candidateMints: [MintInfo] {
        guard !request.mints.isEmpty else {
            return walletManager.mints
        }

        let requestedMintURLs = Set(request.mints.map(normalizedMintURL))
        return walletManager.mints.filter {
            requestedMintURLs.contains(normalizedMintURL($0.url))
        }
    }

    private var selectedPaymentMint: MintInfo? {
        if let selectedMint,
           let refreshedMint = candidateMints.first(where: { $0.id == selectedMint.id }) {
            return refreshedMint
        }

        return recommendedPaymentMint()
    }

    private func syncSelectedMint() {
        if let selectedMint,
           candidateMints.contains(where: { $0.id == selectedMint.id }) {
            return
        }

        selectedMint = recommendedPaymentMint()
    }

    private func recommendedPaymentMint() -> MintInfo? {
        guard !candidateMints.isEmpty else { return nil }

        let candidates: [MintInfo]
        if let amount = paymentAmount, amount > 0 {
            let affordable = candidateMints.filter { $0.balance >= amount }
            candidates = affordable.isEmpty ? candidateMints : affordable
        } else {
            candidates = candidateMints
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

    private func normalizedMintURL(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased() else {
            return trimmed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        var normalized = host
        if let port = url.port {
            normalized += ":\(port)"
        }
        normalized += url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return normalized
    }

    private func payRequest() {
        guard canPay, let mint = selectedPaymentMint else { return }

        isPaying = true
        errorMessage = nil
        authorizingState = .authorizing
        showAuthorizingOverlay = true
        HapticFeedback.impact(.medium)

        Task { @MainActor in
            do {
                try await walletManager.payCashuPaymentRequest(
                    encoded: request.encoded,
                    customAmountSats: request.amount == nil ? paymentAmount : nil,
                    preferredMintURL: mint.url
                )
                authorizingState = .sent
            } catch {
                let walletMessage = error.walletMessage
                errorMessage = walletMessage.text
                errorSeverity = walletMessage.severity
                authorizingState = .error(walletMessage.text)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                showAuthorizingOverlay = false
            }

            isPaying = false
        }
    }

    private func resetAuthorizingState() {
        authorizingState = .authorizing
    }
}

struct LegacyQRScannerView: UIViewControllerRepresentable {
    var onResult: (String) -> Void
    
    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }
    
    class Coordinator: NSObject, QRScannerViewControllerDelegate {
        var onResult: (String) -> Void
        
        init(onResult: @escaping (String) -> Void) {
            self.onResult = onResult
        }
        
        func didFound(code: String) {
            onResult(code)
        }
        
        func didFail(error: String) {
            print("Scanner failed: \(error)")
        }
    }
}

protocol QRScannerViewControllerDelegate: AnyObject {
    func didFound(code: String)
    func didFail(error: String)
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: QRScannerViewControllerDelegate?
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var qrCodeFrameView: UIView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.black
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { // Changed to .video
            delegate?.didFail(error: "Your device doesn't support video capture.")
            return
        }
        
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            delegate?.didFail(error: error.localizedDescription)
            return
        }
        
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            delegate?.didFail(error: "Could not add video input.")
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if (captureSession.canAddOutput(metadataOutput)) {
            captureSession.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            delegate?.didFail(error: "Could not add metadata output.")
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        // Initialize QR Code Frame View
        qrCodeFrameView = UIView()
        if let qrCodeFrameView = qrCodeFrameView {
            qrCodeFrameView.layer.borderColor = UIColor.tintColor.cgColor
            qrCodeFrameView.layer.borderWidth = 2
            view.addSubview(qrCodeFrameView)
            view.bringSubviewToFront(qrCodeFrameView)
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let previewLayer = previewLayer {
            previewLayer.frame = view.layer.bounds
        }
        
        // Ensure connection orientation matches
        if let connection = previewLayer?.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait 
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if (captureSession?.isRunning == true) {
            captureSession.stopRunning()
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            
            // Transform the metadata object to the layer coordinates
            if let barCodeObject = previewLayer?.transformedMetadataObject(for: readableObject) {
                qrCodeFrameView?.frame = barCodeObject.bounds
            }
            
            // Vibrate handled in view model/handling
            delegate?.didFound(code: stringValue)
        } else {
             qrCodeFrameView?.frame = CGRect.zero
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
}
