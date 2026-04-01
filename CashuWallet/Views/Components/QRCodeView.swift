import SwiftUI
import CoreImage.CIFilterBuiltins
#if canImport(URKit)
import URKit
#endif

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

/// QR Code display view with animation support for large data
/// Includes per-QR speed and size controls like cashu.me
struct QRCodeView: View {
    private static let ciContext = CIContext()
    let content: String
    var showControls: Bool = true
    
    // Local settings per QR instance
    @State private var speed: QRSpeed = .fast
    @State private var size: QRSize = .large
    
    @State private var currentQRCodeString: String = ""
    @State private var currentPartIndex: Int = 0
    @State private var totalParts: Int = 0
    @State private var timer: Timer?
    
    #if canImport(URKit)
    @State private var encoder: UREncoder?
    #endif
    
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
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "qrcode")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
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
        .onChange(of: content) { _ in
            prepareEncoder()
        }
        .onChange(of: speed) { _ in
            restartTimer()
        }
        .onChange(of: size) { _ in
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
                .foregroundColor(.gray)
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
                .foregroundColor(.gray)
            }
            .accessibilityLabel("QR chunk size: \(size.rawValue)")
            .accessibilityHint("Cycles through small, medium, and large QR code chunk sizes")
        }
        .padding(.top, 4)
    }
    
    // MARK: - Encoder Logic
    
    private func prepareEncoder() {
        stopTimer()
        
        #if canImport(URKit)
        let chunkSize = size.chunkSize
        
        if content.count > chunkSize {
            // Encode as UR for animated QR
            let data = Data(content.utf8)
            
            do {
                let cbor = CBOR.bytes(data)
                let ur = try UR(type: "bytes", cbor: cbor)
                encoder = UREncoder(ur, maxFragmentLen: chunkSize)
                
                // Set initial part
                if let part = encoder?.nextPart() {
                    currentQRCodeString = part
                    // Parse "ur:bytes/1-X/..." to get total parts
                    if let parts = part.components(separatedBy: "/").dropFirst().first?.components(separatedBy: "-"),
                       parts.count == 2,
                       let total = Int(parts[1]) {
                        totalParts = total
                        currentPartIndex = 1
                    }
                }
                
                startTimer()
            } catch {
                print("UR Encoding failed: \(error)")
                // Fallback to static
                encoder = nil
                currentQRCodeString = content
                totalParts = 1
            }
        } else {
            encoder = nil
            currentQRCodeString = content
            totalParts = 1
        }
        #else
        // Fallback if URKit missing
        currentQRCodeString = content
        totalParts = 1
        #endif
    }
    
    private func startTimer() {
        #if canImport(URKit)
        guard encoder != nil else { return }
        
        timer = Timer.scheduledTimer(withTimeInterval: speed.interval, repeats: true) { _ in
            if let part = encoder?.nextPart() {
                currentQRCodeString = part
                // Parse seq num for UI (1-based index)
                if let seqStr = part.components(separatedBy: "/").dropFirst().first?.components(separatedBy: "-").first,
                   let seq = Int(seqStr) {
                    currentPartIndex = seq
                } else {
                    currentPartIndex = (currentPartIndex % totalParts) + 1
                }
            }
        }
        #endif
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
            .cornerRadius(12)
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
            .cornerRadius(12)
    }
}
