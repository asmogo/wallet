import SwiftUI
import CoreImage.CIFilterBuiltins
import Cdk

// MARK: - QR Speed/Size Settings

enum QRSpeed: String, CaseIterable {
    case fast = "F"
    case medium = "M"
    case slow = "S"
    
    var interval: Double {
        switch self {
        case .fast: return 0.1
        case .medium: return 0.3
        case .slow: return 0.5
        }
    }
    
    var next: QRSpeed {
        switch self {
        case .fast: return .medium
        case .medium: return .slow
        case .slow: return .fast
        }
    }
}

enum QRSize: String, CaseIterable {
    case small = "S"
    case medium = "M"
    case large = "L"
    
    var chunkSize: Int {
        switch self {
        case .small: return 50
        case .medium: return 100
        case .large: return 200
        }
    }
    
    var next: QRSize {
        switch self {
        case .small: return .medium
        case .medium: return .large
        case .large: return .small
        }
    }
}

// MARK: - QR Code View with Controls

/// VoiceOver action names exposed on actionable QR codes. They mirror the
/// Copy / Share entries of the long-press context menu the call site attaches —
/// the same options Android's shared QrCard announces to TalkBack.
enum QRContextAccessibility {
    static let copyActionName = "Copy"
    static let shareActionName = "Share"
}

/// QR Code display view with animation support for large data
/// Includes per-QR speed and size controls like cashu.me
struct QRCodeView: View {
    private static let ciContext = CIContext()
    let content: String
    var showControls: Bool = true
    /// When true, never UR-encode the content. Use for standardized payloads
    /// (BOLT11 invoices, BOLT12 offers, Bitcoin addresses) that other wallets
    /// expect to scan as a single static frame. UR-animated QRs only make
    /// sense for our own long Cashu tokens.
    var staticOnly: Bool = false
    /// VoiceOver Copy action, mirroring the long-press context menu's Copy.
    /// Leave nil on non-actionable QRs so assistive tech never promises an
    /// unavailable action.
    var onCopy: (() -> Void)? = nil
    /// VoiceOver Share action, mirroring the long-press context menu's Share.
    var onShare: (() -> Void)? = nil

    // Local settings per QR instance
    @State private var speed: QRSpeed = .fast
    @State private var size: QRSize = .large

    @State private var currentQRCodeString: String = ""
    @State private var currentPartIndex: Int = 0
    @State private var totalParts: Int = 0
    @State private var timer: Timer?

    @State private var encoder: TokenUrEncoder?
    
    var body: some View {
        VStack(spacing: 8) {
            // QR Code
            Group {
                if let image = generateQRCode(from: currentQRCodeString) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("QR code")
                        .accessibilityHint("Contains scannable payment data")
                        .accessibilityActions {
                            if let onCopy {
                                Button(QRContextAccessibility.copyActionName, action: onCopy)
                            }
                            if let onShare {
                                Button(QRContextAccessibility.shareActionName, action: onShare)
                            }
                        }
                } else {
                    Rectangle()
                        .fill(.tertiary)
                        .overlay(
                            Image(systemName: "qrcode")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        )
                        .accessibilityLabel("QR code loading")
                }
            }
            
            // Controls row (Speed & Size toggles)
            if showControls && totalParts > 1 {
                controlsRow
            }
        }
        .onAppear {
            prepareEncoder()
        }
        .onChange(of: content) {
            prepareEncoder()
        }
        .onChange(of: speed) {
            restartTimer()
        }
        .onChange(of: size) {
            prepareEncoder()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    // MARK: - Controls Row
    
    private var controlsRow: some View {
        HStack(spacing: 24) {
            // Speed toggle
            Button(action: {
                speed = speed.next
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .accessibilityHidden(true)
                    Text("SPEED: \(speed.rawValue)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.secondary)
            }
            .accessibilityLabel("QR animation speed: \(speed.rawValue)")
            .accessibilityHint("Cycles through fast, medium, and slow animation speeds")

            // Size toggle
            Button(action: {
                size = size.next
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .accessibilityHidden(true)
                    Text("SIZE: \(size.rawValue)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.secondary)
            }
            .accessibilityLabel("QR chunk size: \(size.rawValue)")
            .accessibilityHint("Cycles through small, medium, and large QR code chunk sizes")
        }
        .padding(.top, 4)
    }
    
    // MARK: - Encoder Logic

    private func prepareEncoder() {
        stopTimer()

        // Static-only mode short-circuits UR encoding entirely so scanners
        // receive a single standard QR frame.
        if staticOnly {
            encoder = nil
            currentQRCodeString = content
            totalParts = 1
            return
        }

        let chunkSize = size.chunkSize

        // NUT-16 animated frames come from CDK's own fountain encoder. Only
        // Cashu tokens animate: anything else (invoices, addresses, request
        // strings) is a standardized static payload, and non-token content
        // simply doesn't fit the NUT-16 envelope.
        if content.count > chunkSize,
           let token = try? Token.decode(encodedToken: content),
           let urEncoder = try? token.urEncoder(maxFragmentLength: UInt32(chunkSize)),
           !urEncoder.isSingleFragment() {
            encoder = urEncoder
            totalParts = Int(urEncoder.fragmentCount())
            currentPartIndex = 1
            currentQRCodeString = (try? urEncoder.nextPart()) ?? content
            startTimer()
        } else {
            encoder = nil
            currentQRCodeString = content
            totalParts = 1
        }
    }

    private func startTimer() {
        guard encoder != nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: speed.interval, repeats: true) { _ in
            if let part = try? encoder?.nextPart() {
                currentQRCodeString = part
                currentPartIndex = Int(encoder?.currentIndex() ?? 0)
            }
        }
    }
    
    private func restartTimer() {
        stopTimer()
        startTimer()
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        guard !string.isEmpty else { return nil }
        
        let filter = CIFilter.qrCodeGenerator()
        
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        guard let outputImage = filter.outputImage else { return nil }
        
        // Scale up the image
        let scale = UIScreen.main.scale * 3
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = outputImage.transformed(by: transform)
        
        guard let cgImage = Self.ciContext.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Previews

#Preview("Static QR") {
    ZStack {
        Color.black
            .ignoresSafeArea()
        
        QRCodeView(content: "cashuAeyJwcm9vZnMiOlt7InByb29mIjoiIn1d")
            .frame(width: 250, height: 280)
            .padding()
            .background(Color.white)
            .clipShape(.rect(cornerRadius: 12))
    }
}

#Preview("Animated QR") {
    ZStack {
        Color.black
            .ignoresSafeArea()
        
        // Long content to trigger animation
        QRCodeView(content: String(repeating: "cashuAeyJwcm9vZnMiOlt7InByb29mIjoiIn1d", count: 10))
            .frame(width: 250, height: 300)
            .padding()
            .background(Color.white)
            .clipShape(.rect(cornerRadius: 12))
    }
}
