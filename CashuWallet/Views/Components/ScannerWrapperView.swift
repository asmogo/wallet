import SwiftUI
import AVFoundation
import CashuDevKit
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
    
    @StateObject private var scannerModel = ScannerViewModel()
    @State private var scannedToken: String?
    @State private var scannedMeltRequest: String?
    @State private var scannedMeltMode: MeltView.MeltMode = .lightning
    @State private var scannedMeltAutoQuote = false
    @State private var navigateToDetail = false
    @State private var navigateToMelt = false
    
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
            .navigationDestination(isPresented: $navigateToDetail) {
                if let token = scannedToken {
                    ReceiveTokenDetailView(tokenString: token, onComplete: {
                        // Dismiss the entire scanner sheet
                        dismiss()
                    })
                    .environmentObject(walletManager)
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
        
        // Determine content type: Token (Receive) or Invoice (Pay/Melt)
        if TokenParser.isCashuToken(content) {
            // Handle Ecash Token -> Show Detail View
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            scannedToken = content
            navigateToDetail = true
            
        } else if let paymentMethod = PaymentRequestParser.paymentMethod(for: content) {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            scannedMeltRequest = paymentMethod == .onchain
                ? PaymentRequestParser.normalizeBitcoinRequest(content)
                : PaymentRequestParser.normalizeLightningRequest(content)
            scannedMeltMode = paymentMethod == .onchain ? .onchain : .lightning
            scannedMeltAutoQuote = paymentMethod != .onchain
            navigateToMelt = true
            
        } else if PaymentRequestParser.isHumanReadableLightningAddress(content) {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            scannedMeltRequest = content
            scannedMeltMode = .lightning
            scannedMeltAutoQuote = false
            navigateToMelt = true

        } else if content.lowercased().hasPrefix("https://") && content.contains("mint") {
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
