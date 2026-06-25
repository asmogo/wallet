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

    @StateObject private var scannerModel = ScannerViewModel()
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
                        Text("Scan Cashu Token, Payment Request, or Bitcoin Address")
                            .foregroundStyle(.primary)
                            .font(.caption)
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .clipShape(.rect(cornerRadius: 20))
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
                }
            }
            .fullScreenCover(isPresented: $navigateToCashuPaymentRequest) {
                if let request = scannedCashuPaymentRequest {
                    CashuPaymentRequestPayView(request: request, onComplete: {
                        dismiss()
                    })
                    .environmentObject(walletManager)
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

private struct CashuPaymentRequestPayView: View {
    let request: CashuPaymentRequestSummary
    var onComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var priceService = PriceService.shared

    @State private var customAmountString = ""
    @State private var isPaying = false
    @State private var errorMessage: String?
    @State private var showAuthorizingOverlay = false
    @State private var authorizingState: AuthorizingOverlay.FlowState = .authorizing
    @State private var showingMintPicker = false
    @State private var selectedMint: MintInfo?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        amountSection
                            .padding(.top, 24)

                        if request.isSatUnit {
                            if let mint = selectedPaymentMint {
                                cashuMintSelector(mint: mint)
                                    .padding(.horizontal)
                            } else {
                                Text("No matching mint for this request.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }

                        detailsSection

                        if !request.isSatUnit {
                            Text("This wallet can only pay sat-denominated Cashu requests.")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                }

                if request.amount == nil {
                    NumberPadAmountInput(amountString: $customAmountString, unit: entryUnit)
                        .padding(.horizontal, 24)
                }

                Button(action: payRequest) {
                    if isPaying {
                        ProgressView()
                    } else {
                        Label("Pay", systemImage: "checkmark.circle.fill")
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
            }
            .onChange(of: customAmountString) {
                syncSelectedMint()
            }
            .onChange(of: walletManager.activeMint?.id) {
                syncSelectedMint()
            }
            .onChange(of: entryUnit) { oldUnit, newUnit in
                customAmountString = AmountFormatter.entryConverted(raw: customAmountString, from: oldUnit, to: newUnit)
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

    private var detailsSection: some View {
        VStack(spacing: 0) {
            detailRow(
                icon: "text.quote",
                label: "Description",
                value: request.description?.isEmpty == false ? request.description! : "Cashu payment"
            )
            Divider().padding(.leading)
            detailRow(icon: "banknote", label: "Unit", value: request.unit ?? "sat")
            Divider().padding(.leading)
            detailRow(icon: "bitcoinsign.bank.building", label: "Mint", value: selectedMintLabel)
        }
        .padding(.vertical, 4)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    private func cashuMintSelector(mint: MintInfo) -> some View {
        Button(action: {
            HapticFeedback.selection()
            showingMintPicker = true
        }) {
            HStack(spacing: 12) {
                if let iconUrl = mint.iconUrl, let url = URL(string: iconUrl) {
                    AsyncImage(url: url) { image in
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
        .accessibilityLabel("Payment mint: \(mint.name), \(mint.balance) sats")
        .accessibilityHint("Double-tap to choose the mint to pay from")
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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

    private var selectedMintLabel: String {
        if let mint = selectedPaymentMint {
            return mint.name
        }

        guard let firstMint = request.mints.first else { return "Any mint" }
        return URL(string: firstMint)?.host ?? firstMint
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
                let message = error.userFacingWalletMessage
                errorMessage = message
                authorizingState = .error(message)
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
