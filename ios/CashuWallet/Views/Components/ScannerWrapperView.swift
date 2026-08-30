import SwiftUI
import AVFoundation
import Cdk

class ScannerViewModel: ObservableObject {
    @Published var scanProgress: Double = 0
    @Published var isScanning = true
    @Published var errorMessage: String?
    /// Severity of `errorMessage`. `.error` paints the alarm-red toast; `.info`
    /// renders a neutral material so a success confirmation (e.g. "copied") isn't
    /// styled as a failure.
    // Caution, not error: a QR that isn't what we wanted didn't break
    // anything. Genuine failures raise this explicitly.
    @Published var noticeSeverity: ErrorSeverity = .caution

    /// NUT-16 animated-QR decoder from CDK: fountain-coded `ur:bytes` frames
    /// arrive in any order and reassemble into a Cashu token.
    private var decoder = TokenUrDecoder()

    func reset() {
        decoder = TokenUrDecoder()
        scanProgress = 0
        isScanning = true
        errorMessage = nil
        noticeSeverity = .caution
    }

    func processFragment(_ fragment: String) -> String? {
        do {
            try decoder.receive(part: fragment)
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Couldn't read that animated QR frame."
            }
            return nil
        }

        DispatchQueue.main.async {
            let total = self.decoder.fragmentCount()
            if total > 0, let resolved = self.decoder.resolvedFragmentCount() {
                self.scanProgress = min(Double(resolved) / Double(total), 0.99)
            }
        }

        guard decoder.complete() else { return nil }

        do {
            guard let token = try decoder.token() else { return nil }
            return try token.encode()
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "That animated QR doesn't contain a Cashu token."
            }
            return nil
        }
    }
}

private enum CameraAuthorizationState: Equatable {
    case checking
    case requesting
    case authorized
    case denied
    case restricted
}

private struct ScannerCameraStatusView: View {
    let title: String
    let message: String
    var actionTitle: String?
    var showsProgress = false
    var action: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 42))
                    .accessibilityHidden(true)

                Text(title)
                    .font(.title2.weight(.semibold))

                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.75))

                if showsProgress {
                    ProgressView()
                        .tint(.white)
                        .accessibilityLabel("Requesting camera access")
                }

                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .frame(maxWidth: 320)
                }
            }
            .foregroundStyle(.white)
            .padding(32)
            .frame(maxWidth: 440)
            .accessibilityElement(children: .contain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScannerWrapperView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    /// Delivers an accepted payload to the caller. The scanner then dismisses
    /// itself — it never presents the follow-up surface, so it can never be
    /// left open underneath one.
    var onScanned: (String) -> Void

    /// Optional override for the instruction shown under the viewfinder.
    var promptText: String? = nil

    /// Optional gate run before a payload is delivered. `.accept` hands it to
    /// `onScanned` and self-dismisses; `.reject` shows the message inline and
    /// re-arms (junk QR stays scannable); `.notice` shows a neutral toast and
    /// closes without delivering (any side effect, e.g. copying a mint URL,
    /// belongs to the classifier). Nil accepts everything.
    var classify: ((String) -> ScanIntake)? = nil

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
    @State private var cameraAuthorizationState: CameraAuthorizationState = .checking
    @State private var cameraFailureMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch cameraAuthorizationState {
                case .checking, .requesting:
                    ScannerCameraStatusView(
                        title: "Camera Access",
                        message: "Waiting for permission to use the camera.",
                        showsProgress: true
                    )
                case .authorized:
                    if let cameraFailureMessage {
                        ScannerCameraStatusView(
                            title: "Camera Unavailable",
                            message: cameraFailureMessage,
                            actionTitle: "Try Again",
                            action: retryCamera
                        )
                    } else {
                        LegacyQRScannerView(
                            onResult: { code in
                                handleScan(code: code)
                            },
                            onFailure: { error in
                                cameraFailureMessage = error
                            },
                            onAppear: {
                                // A visible scanner must be an armed scanner.
                                // The camera surface can (re)appear without a
                                // fresh model — a cancelled interactive sheet
                                // dismissal, a stacked cover closing, or SwiftUI
                                // reusing retained sheet state — and without this
                                // reset the preview looks live while `isScanning`
                                // stays false and every scan is silently dropped.
                                scannerModel.reset()
                            }
                        )
                        .ignoresSafeArea()
                    }
                case .denied:
                    ScannerCameraStatusView(
                        title: "Camera Access Needed",
                        message: "Camera access is turned off. Enable it in Settings to scan QR codes.",
                        actionTitle: "Open Settings",
                        action: openCameraSettings
                    )
                case .restricted:
                    ScannerCameraStatusView(
                        title: "Camera Unavailable",
                        message: "Camera access is restricted on this device. Check Screen Time or device-management settings."
                    )
                }

                // Overlay
                if cameraAuthorizationState == .authorized && cameraFailureMessage == nil {
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
                }
                
                if let error = scannerModel.errorMessage {
                    VStack {
                        Spacer()
                        // Floats over the camera preview, so it is the floating
                        // channel's own component. This screen used to hand-roll
                        // the banner's exact body — material, glyph, combined
                        // accessibility element — which is how it drifted to a
                        // solid red slab in the first place. Position it; don't
                        // restyle it.
                        ErrorBannerView(
                            message: error,
                            severity: scannerModel.noticeSeverity
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    SheetCloseButton()
                        .foregroundStyle(.white)
                }
            }
            .onAppear {
                resolvedQuickFills = quickFills?() ?? []
                refreshCameraAuthorization()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refreshCameraAuthorization()
                }
            }
        }
    }

    private func refreshCameraAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorizationState = .authorized
        case .notDetermined:
            requestCameraAuthorization()
        case .denied:
            cameraAuthorizationState = .denied
        case .restricted:
            cameraAuthorizationState = .restricted
        @unknown default:
            cameraAuthorizationState = .restricted
        }
    }

    private func requestCameraAuthorization() {
        guard cameraAuthorizationState != .requesting else { return }
        cameraAuthorizationState = .requesting
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                cameraAuthorizationState = granted ? .authorized : .denied
            }
        }
    }

    private func openCameraSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(settingsURL)
    }

    private func retryCamera() {
        cameraFailureMessage = nil
        refreshCameraAuthorization()
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

        switch classify?(content) ?? .accept {
        case .accept:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            onScanned(content)
            dismiss()
        case .reject(let message):
            scannerModel.errorMessage = message
            HapticFeedback.notification(.error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                scannerModel.reset()
            }
        case .notice(let message):
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            // A confirmation, not a failure — render it on a neutral toast.
            scannerModel.noticeSeverity = .info
            scannerModel.errorMessage = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.dismiss()
            }
        }
    }
}

/// Native detail row used whenever a Cashu Request changes rail or enters a
/// recovery route. Grouping keeps VoiceOver's route label and value together.
struct CashuRequestRouteExplanationRow: View {
    let explanation: CashuRequestRouteExplanation

    var body: some View {
        HStack {
            Text("Route")
                .foregroundStyle(.secondary)
            Spacer()
            Text(explanation.localizedValue)
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
    /// Drives the full-screen processing → success → failure status screen.
    /// nil while the user is still on the confirm screen.
    @State private var paymentPhase: PaymentStatusView.Phase?
    @State private var activeRouteExplanation: CashuRequestRouteExplanation?
    @State private var showingMintPicker = false
    @State private var selectedMint: MintInfo?

    /// Which requested mint URL to add & fund when the request can't be paid from
    /// current ecash and it names more than one mint (the user picks).
    @State private var selectedAddMintURL: String?
    @State private var addMintChooserPresented = false
    /// Set when no held mint can fund the transfer — drives the Lightning top-up QR.
    @State private var topUpContext: TopUpContext?

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
            Group {
              if let paymentPhase {
                statusView(paymentPhase)
                    .transition(.opacity)
              } else {
                // Family-style confirm layout. Any/multi-mint requests get a top mint
                // pill (matching Pay Lightning) and just the amount hero; a request
                // pinned to one required mint keeps the centered mint-identity header
                // above the amount. Read-only request facts (Memo / Fees) sit beneath.
                // Shared Pay-flow scaffold (see `PayFlowScaffold`) so the request
                // facts sit at the same Y here as on the processing / success
                // screens. Any/multi-mint requests show the switchable mint pill as
                // the top accessory; a required mint keeps its centered identity
                // header inside the hero band, above the amount.
                PayFlowScaffold {
                    VStack(spacing: 12) {
                        if request.isSatUnit, pickerSelectedMint == nil {
                            mintHeader
                                .padding(.horizontal)
                        }
                        amountSection
                    }
                } details: {
                    requestDetailsSection

                    // Transient warnings sit below the request facts (flexible zone)
                    // so they never push the details anchor.
                    if !request.isSatUnit {
                        InlineNotice(
                            message: "This wallet can only pay sat-denominated Cashu Requests.",
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
                } footer: {
                    VStack(spacing: 16) {
                        if request.amount == nil {
                            NumberPadAmountInput(amountString: $customAmountString, unit: entryUnit)
                                .padding(.horizontal, NumberPadMetrics.gutter)
                        }

                        Button(action: payRequest) {
                            if isPaying {
                                ProgressView()
                            } else {
                                Text(payButtonTitle)
                            }
                        }
                        .glassButton()
                        .disabled(!canPay)
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                        .sheet(isPresented: $addMintChooserPresented) {
                            AddMintToPaySheet(mints: request.mints) { mintURL in
                                selectedAddMintURL = mintURL
                                if let amount = paymentAmount, amount > 0 {
                                    runAcquireAndPay(targetMintURL: mintURL, amount: amount)
                                }
                            }
                            .environmentObject(walletManager)
                        }
                    }
                } topAccessory: {
                    if request.isSatUnit, let selected = pickerSelectedMint {
                        MintSelectorRow(
                            direction: .source,
                            mint: selected,
                            balanceText: AmountFormatter.sats(
                                selected.balance,
                                useBitcoinSymbol: settings.useBitcoinSymbol
                            ),
                            onChooseMint: candidateMints.count > 1 ? {
                                HapticFeedback.selection()
                                showingMintPicker = true
                            } : nil
                        )
                        // Aligned to the number pad below, not the CTA.
                        .padding(.horizontal, NumberPadMetrics.gutter)
                        .padding(.top, 8)
                    }
                }
              }
            }
            .animation(.smooth(duration: 0.3), value: paymentPhase != nil)
            .navigationTitle("Pay Cashu Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // No dismissing mid-authorization (payment is in flight).
                    if paymentPhase != .processing {
                        SheetCloseButton()
                    }
                }
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
            .sheet(item: $topUpContext) { context in
                CashuTopUpInvoiceSheet(context: context, onComplete: {
                    topUpContext = nil
                    onComplete?()
                    dismiss()
                })
                .environmentObject(walletManager)
                .canvasSheetBackground()
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
                    .cashuAmount(.amountHero, value: Double(amount))
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
            if needsAcquire {
                return (.mint(mint), mint.name, "Balance too low — fund to pay", false)
            }
            return (.mint(mint), mint.name, "Required mint", false)
        case .picker:
            // Unreachable — the any/multi case now renders the top mint pill, not
            // this header (mintHeader is only shown when pickerSelectedMint == nil).
            // Kept for switch exhaustiveness.
            if request.mints.isEmpty {
                return (.generic, "Any mint", "Pay from any mint", false)
            } else {
                return (.generic, "Multiple mints", "Pay from one of \(request.mints.count)", false)
            }
        case .unavailable(let hosts):
            // Recoverable: we can add the required mint and fund it — not a warning.
            if needsAcquire {
                if hosts.count == 1, let host = hosts.first {
                    return (.generic, host, "Tap Add & pay to fund it", false)
                }
                return (.generic, "Add a mint", "This request accepts \(hosts.count) mints", false)
            }
            if hosts.isEmpty {
                return (.generic, "Any mint", "Add a mint to pay", true)
            } else if hosts.count == 1 {
                return (.generic, hosts[0], "Not in your wallet", true)
            } else {
                return (.generic, "Multiple mints", "You hold none of these", true)
            }
        }
    }

    /// The selected paying mint for an any/multi-mint (`.picker`) request — the
    /// mint shown in the top pill. Non-nil iff the request isn't pinned to a
    /// single mint; also gates the centered header (shown only when this is nil).
    private var pickerSelectedMint: MintInfo? {
        if case .picker(_, let selected) = mintPresentation { return selected }
        return nil
    }

    /// Family-style detail rows beneath the amount: the requester's memo and the
    /// fee. Only shown for sat requests; non-sat requests surface their own
    /// "unsupported" warning. (Mint selection lives in the top pill / header.)
    @ViewBuilder
    private var requestDetailsSection: some View {
        if request.isSatUnit {
            let memo = requestMemo

            VStack(spacing: 0) {
                if let routeExplanation {
                    CashuRequestRouteExplanationRow(explanation: routeExplanation)
                }
                if let memo {
                    detailRow(label: "Memo", value: memo)
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

    /// Fee row. "No fee" is exact (the mint charges no swap fee); a sat value is
    /// the exact fee for a fee-charging mint; "—" before an amount exists.
    private var feesRow: some View {
        HStack {
            Text("Fees")
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
        if needsAcquire {
            // Funding the mint routes over Lightning, which always carries a fee;
            // the exact reserve is confirmed during the transfer and in History.
            Text("Network fee").fontWeight(.medium).foregroundStyle(.secondary)
        } else {
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
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
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

    /// Host of a mint URL for display when we hold no `MintInfo` for it
    /// (matches ReceiveLightningView / SendView).
    private func extractMintHost(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }

    /// The mint URL to acquire ecash at when the request can't be paid from
    /// current ecash: a held-but-underfunded required mint → that mint; no held
    /// mint → a requested mint to add (the user's pick, else the first). Nil when
    /// already payable, or when there's no mint to target (any-mint request with
    /// nothing held).
    private var acquireTargetURL: String? {
        guard request.isSatUnit, let amount = paymentAmount, amount > 0 else { return nil }
        if let mint = selectedPaymentMint {
            return mint.balance >= amount ? nil : mint.url
        }
        guard !request.mints.isEmpty else { return nil }
        if request.mints.count == 1 { return request.mints.first }
        return selectedAddMintURL ?? request.mints.first
    }

    private var acquireTargetHost: String? { acquireTargetURL.map(extractMintHost) }

    /// The dead-end is recoverable — we can add/fund the target mint and pay.
    private var needsAcquire: Bool { acquireTargetURL != nil }

    /// Whether the target mint isn't in the wallet yet (affects CTA wording).
    private var acquireAddsNewMint: Bool { selectedPaymentMint == nil }

    private var routeExplanation: CashuRequestRouteExplanation? {
        guard request.isSatUnit, paymentAmount != nil else {
            return CashuRequestRouteExplanation(state: .unavailable)
        }
        guard needsAcquire else {
            return CashuRequestRouteExplanation(state: .compatibleMint)
        }
        let state: CashuRequestRouteExplanation.State = acquireAddsNewMint
            ? .addRequestedMint(targetMintURL: acquireTargetURL)
            : .topUpTargetMint(targetMintURL: acquireTargetURL)
        return CashuRequestRouteExplanation(state: state)
    }

    private var payButtonTitle: String {
        guard needsAcquire else { return "Pay" }
        if acquireAddsNewMint {
            if request.mints.count > 1 && selectedAddMintURL == nil {
                return "Add a mint & pay"
            }
            return acquireTargetHost.map { "Add \($0) & pay" } ?? "Add mint & pay"
        }
        return acquireTargetHost.map { "Fund \($0) & pay" } ?? "Fund mint & pay"
    }

    private var canPay: Bool {
        guard !isPaying, request.isSatUnit else { return false }
        guard let amount = paymentAmount, amount > 0 else { return false }
        if needsAcquire { return true }
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
        // Can't pay from current ecash — add/fund the target mint, then pay.
        if needsAcquire {
            if acquireAddsNewMint, request.mints.count > 1, selectedAddMintURL == nil {
                addMintChooserPresented = true   // let the user pick which mint to add
                return
            }
            guard let target = acquireTargetURL, let amount = paymentAmount, amount > 0 else { return }
            runAcquireAndPay(targetMintURL: target, amount: amount)
            return
        }

        guard canPay, let mint = selectedPaymentMint else { return }

        activeRouteExplanation = routeExplanation
        isPaying = true
        errorMessage = nil
        HapticFeedback.impact(.medium)
        withAnimation(.smooth(duration: 0.3)) { paymentPhase = .processing }

        Task { @MainActor in
            do {
                try await walletManager.payCashuPaymentRequest(
                    encoded: request.encoded,
                    customAmountSats: request.amount == nil ? paymentAmount : nil,
                    preferredMintURL: mint.url
                )
                // The consistency fix: every creq payment now lands on the shared
                // full-screen success screen, same as Lightning/on-chain.
                withAnimation(.smooth(duration: 0.3)) { paymentPhase = .success }
            } catch {
                let walletMessage = error.walletMessage
                errorMessage = walletMessage.text
                errorSeverity = walletMessage.severity
                withAnimation(.smooth(duration: 0.3)) {
                    paymentPhase = .failure(
                        message: walletMessage.text,
                        isCaution: walletMessage.severity == .caution,
                        isTerminal: walletMessage.recoverability == .terminal
                    )
                }
            }

            isPaying = false
        }
    }

    /// Add/fund the target mint over Lightning, then pay the request. Falls back
    /// to a top-up QR (`NeedsExternalTopUp`) when no held mint can bankroll it.
    private func runAcquireAndPay(targetMintURL: String, amount: UInt64) {
        activeRouteExplanation = routeExplanation
        isPaying = true
        errorMessage = nil
        HapticFeedback.impact(.medium)
        withAnimation(.smooth(duration: 0.3)) { paymentPhase = .processing }

        Task { @MainActor in
            do {
                try await walletManager.addMintAndPayCashuRequest(
                    request,
                    amount: amount,
                    targetMintURL: targetMintURL,
                    onStage: { _ in }
                )
                withAnimation(.smooth(duration: 0.3)) { paymentPhase = .success }
            } catch let topUp as NeedsExternalTopUp {
                // No held mint can fund it — clear the status screen first, then show
                // the Lightning top-up invoice sheet.
                withAnimation(.smooth(duration: 0.3)) { paymentPhase = nil }
                try? await Task.sleep(nanoseconds: 350_000_000)
                topUpContext = TopUpContext(
                    summary: request,
                    amount: amount,
                    targetMintURL: topUp.targetMintURL,
                    quote: topUp.targetQuote
                )
            } catch is MintSettling {
                let text = "Still settling — your balance will update shortly. Try again in a moment."
                errorMessage = text
                errorSeverity = .caution
                withAnimation(.smooth(duration: 0.3)) { paymentPhase = .failure(message: text, isCaution: true) }
            } catch {
                let walletMessage = error.walletMessage
                errorMessage = walletMessage.text
                errorSeverity = walletMessage.severity
                withAnimation(.smooth(duration: 0.3)) {
                    paymentPhase = .failure(
                        message: walletMessage.text,
                        isCaution: walletMessage.severity == .caution,
                        isTerminal: walletMessage.recoverability == .terminal
                    )
                }
            }

            isPaying = false
        }
    }

    /// Full-screen processing → success → failure status. Preserves the payment
    /// facts (amount / mint / fee / memo) as rows. onDone completes like the old
    /// overlay's onDismiss did; onRetry returns to the confirm screen.
    private func statusView(_ phase: PaymentStatusView.Phase) -> some View {
        // Fixed slot order — every row is present from the first frame, so values that
        // resolve late (the fee, or the mint in the acquire path) fill their reserved
        // slot in place instead of inserting and shoving the rows below them.
        var rows: [PaymentStatusView.DetailRow] = [
            .init(
                label: "Amount",
                value: paymentAmount.map { "\($0) sat" } ?? "",
                isPending: paymentAmount == nil
            ),
            statusMintRow,
        ]
        if let explanation = activeRouteExplanation {
            rows.append(.init(
                label: "Route",
                value: explanation.localizedValue
            ))
        }
        rows.append(statusFeeRow)
        if let memo = requestMemo {
            rows.append(.init(label: "Memo", value: memo))
        }
        return PaymentStatusView(
            details: rows,
            phase: phase,
            onDone: {
                onComplete?()
                dismiss()
            },
            onRetry: { withAnimation(.smooth(duration: 0.3)) { paymentPhase = nil } }
        )
    }

    /// The paying mint as a detail row, always present so its slot is reserved. Shows
    /// the held mint's name; in the acquire path (mint not held yet) it shows the
    /// target host so the slot still has a real value, and only spins if neither is known.
    private var statusMintRow: PaymentStatusView.DetailRow {
        if let mint = selectedPaymentMint {
            return .init(label: "Mint", value: mint.name)
        }
        if let host = acquireTargetHost {
            return .init(label: "Mint", value: host)
        }
        return .init(label: "Mint", value: "", isPending: true)
    }

    /// The swap fee as a detail row, always present so its slot is reserved. Mirrors
    /// the confirm screen's `feeValueText`: a spinner while the fee computes, then the
    /// value; acquiring a mint routes over Lightning, whose reserve is confirmed later.
    private var statusFeeRow: PaymentStatusView.DetailRow {
        if needsAcquire {
            return .init(label: "Fees", value: "Network fee")
        }
        switch feeState {
        case .loading:
            return .init(label: "Fees", value: "", isPending: true)
        case .free:
            return .init(label: "Fees", value: "No fee")
        case .amount(let fee):
            return .init(
                label: "Fees",
                value: AmountFormatter.sats(fee, useBitcoinSymbol: settings.useBitcoinSymbol)
            )
        case .idle, .unavailable:
            return .init(label: "Fees", value: "—")
        }
    }
}

struct LegacyQRScannerView: UIViewControllerRepresentable {
    var onResult: (String) -> Void
    var onFailure: (String) -> Void
    /// Fires every time the camera surface (re)appears — including the cases
    /// SwiftUI can't see: cancelled interactive dismissals and stacked covers
    /// closing. Callers use it to re-arm scan intake.
    var onAppear: () -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {
        context.coordinator.onResult = onResult
        context.coordinator.onFailure = onFailure
        context.coordinator.onAppear = onAppear
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult, onFailure: onFailure, onAppear: onAppear)
    }

    class Coordinator: NSObject, QRScannerViewControllerDelegate {
        var onResult: (String) -> Void
        var onFailure: (String) -> Void
        var onAppear: () -> Void

        init(onResult: @escaping (String) -> Void, onFailure: @escaping (String) -> Void, onAppear: @escaping () -> Void) {
            self.onResult = onResult
            self.onFailure = onFailure
            self.onAppear = onAppear
        }

        func didFound(code: String) {
            onResult(code)
        }

        func didFail(error: String) {
            onFailure(error)
        }

        func scannerDidAppear() {
            onAppear()
        }
    }
}

protocol QRScannerViewControllerDelegate: AnyObject {
    func didFound(code: String)
    func didFail(error: String)
    func scannerDidAppear()
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: QRScannerViewControllerDelegate?
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var qrCodeFrameView: UIView?
    private let sessionQueue = DispatchQueue(label: "com.cashu.me.qr-scanner-session", qos: .userInitiated)
    private var isSessionConfigured = false
    
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
            isSessionConfigured = true
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
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Re-arm intake on every (re)appearance: a consumed scan sets
        // `isScanning = false`, and appearances that don't rebuild the view
        // (cancelled interactive dismissal, a stacked cover closing, a reused
        // sheet) would otherwise leave a live camera that silently drops scans.
        delegate?.scannerDidAppear()

        // A cancelled interactive sheet dismissal fires viewWillDisappear (which
        // stops the session) and then viewWillAppear without reloading the view,
        // so the session must be restarted here or the preview stays frozen.
        setCaptureSessionRunning(true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        setCaptureSessionRunning(false)
    }

    private func setCaptureSessionRunning(_ shouldRun: Bool) {
        guard isSessionConfigured else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if shouldRun, !captureSession.isRunning {
                captureSession.startRunning()
            } else if !shouldRun, captureSession.isRunning {
                captureSession.stopRunning()
            }
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

/// Context for the Lightning top-up sheet: fund a freshly-added mint by paying
/// its invoice, then mint proofs and pay the pending Cashu request.
struct TopUpContext: Identifiable {
    let id = UUID()
    let summary: CashuPaymentRequestSummary
    let amount: UInt64
    let targetMintURL: String
    let quote: MintQuoteInfo
}

/// Presents the target mint's bolt11 as a QR so the user can top up over
/// Lightning from an external wallet. Polls the quote; once paid, mints the
/// proofs and pays the Cashu request, then calls `onComplete`. Used when no held
/// mint can bankroll the transfer (the `NeedsExternalTopUp` fallback).
struct CashuTopUpInvoiceSheet: View {
    let context: TopUpContext
    var onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared

    @State private var phase: Phase = .awaitingPayment
    @State private var monitorTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var errorSeverity: ErrorSeverity = .error
    /// VoiceOver Share action for the QR: ShareLink can't be invoked
    /// imperatively, so the accessibility action presents the share sheet.
    @State private var showShareSheet = false

    private enum Phase: Equatable {
        case awaitingPayment   // showing the QR, polling the quote
        case paying            // payment detected — minting + paying the request
        case done
    }

    private var host: String { URL(string: context.targetMintURL)?.host ?? context.targetMintURL }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        header

                        QRCodeView(
                            content: context.quote.request,
                            showControls: false,
                            staticOnly: true,
                            onCopy: copyInvoice,
                            onShare: { showShareSheet = true }
                        )
                            .frame(width: 280, height: 280)
                            .padding(16)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                            .padding(.top, 8)
                            .contextMenu {
                                Button(action: copyInvoice) {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                ShareLink(item: context.quote.request) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                            }
                            .sheet(isPresented: $showShareSheet) {
                                ShareSheet(items: [context.quote.request])
                            }

                        CurrencyAmountDisplay(sats: context.amount, primary: $settings.amountDisplayPrimary)

                        if let explanation = CashuRequestRouteExplanation(
                            state: .topUpTargetMint(targetMintURL: context.targetMintURL)
                        ) {
                            CashuRequestRouteExplanationRow(explanation: explanation)
                                .padding(.horizontal)
                        }

                        statusRow
                            .animation(.smooth(duration: 0.3), value: phase)

                        if let errorMessage {
                            InlineNotice(message: errorMessage, severity: errorSeverity)
                                .padding(.horizontal)
                                .transition(.opacity)
                        }
                    }
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity)
                }

                Button("Copy Invoice", action: copyInvoice)
                .glassButton()
                .disabled(phase != .awaitingPayment)
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .navigationTitle("Top up to pay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton()
                }
            }
            .onAppear { startMonitoring() }
            .onDisappear { monitorTask?.cancel() }
        }
        .flatBottomSheetSurface()
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(host)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("Pay this invoice to fund the mint and complete the request.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var statusRow: some View {
        // Phase swaps fade through (the app-wide .smooth(0.3) payment
        // choreography) instead of popping per poll beat.
        switch phase {
        case .awaitingPayment:
            Label("Waiting for payment…", systemImage: "clock")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .transition(.opacity)
        case .paying:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Payment received — paying request…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        case .done:
            // Monochrome, not green — green is reserved for the 64pt hero success
            // checks (DESIGN.md retired the small worded green ✓ badge).
            Label("Sent", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .transition(.opacity)
        }
    }

    private func copyInvoice() {
        UIPasteboard.general.string = context.quote.request
        HapticFeedback.notification(.success)
        ConfirmationToast.show("Copied payment request")
    }

    /// Poll the target mint quote until it's paid, then mint + pay the request.
    private func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { @MainActor in
            let delaysSec: [UInt64] = [3, 3, 4, 5, 5, 6, 8]   // backoff, then steady 10s
            var index = 0
            while !Task.isCancelled {
                let sleepSec = index < delaysSec.count ? delaysSec[index] : 10
                try? await Task.sleep(nanoseconds: sleepSec * 1_000_000_000)
                if Task.isCancelled { return }
                index += 1

                let state: MintQuoteState
                do {
                    state = try await walletManager.checkMintQuote(quoteId: context.quote.id).state
                } catch {
                    continue   // transient — keep polling
                }
                guard state == .paid || state == .issued else { continue }

                withAnimation(.smooth(duration: 0.3)) { phase = .paying }
                do {
                    try await walletManager.finishTopUpAndPayCashuRequest(
                        context.summary,
                        amount: context.amount,
                        targetMintURL: context.targetMintURL,
                        targetQuoteId: context.quote.id
                    )
                    withAnimation(.smooth(duration: 0.3)) { phase = .done }
                    HapticFeedback.notification(.success)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    onComplete()
                } catch {
                    let walletMessage = error.walletMessage
                    withAnimation(.smooth(duration: 0.3)) {
                        errorMessage = walletMessage.text
                        errorSeverity = walletMessage.severity
                        phase = .awaitingPayment   // let the retries/History backstop settle it
                    }
                }
                return
            }
        }
    }
}
