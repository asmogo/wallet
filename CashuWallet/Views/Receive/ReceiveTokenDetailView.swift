import SwiftUI
import CashuDevKit

struct ReceiveTokenDetailView: View {
    let tokenString: String
    var onComplete: (() -> Void)? = nil  // Callback to dismiss entire flow
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var settings = SettingsManager.shared
    
    @State private var decodedToken: Token?
    @State private var tokenAmount: UInt64 = 0
    @State private var receiveFee: UInt64 = 0
    @State private var mintUrl: String = ""
    @State private var isReceiving = false
    @State private var errorMessage: String?
    @State private var isLoadingFee = true
    @State private var p2pkPubkeys: [String] = []
    @State private var tokenLockedToKnownKey = true
    
    // Animation
    @State private var displayedToken: String = ""
    @State private var tokenAnimationTimer: Timer?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                        .font(.system(size: 20, weight: .bold))
                }
                Spacer()
                Text("Receive Ecash")
                    .foregroundColor(.white)
                    .font(.headline)
                Spacer()
                // Placeholder for alignment
                Color.clear.frame(width: 20, height: 20)
            }
            .padding()
            .padding(.top, 20)
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    // Token Card
                    ZStack {
                        // Background gradient
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.2, green: 0.2, blue: 0.3), // Approx primary dark
                                Color.black.opacity(0.5)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        
                        // Scrambled Token Text Background
                        GeometryReader { geo in
                            Text(displayedToken)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.gray.opacity(0.5))
                                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                                .multilineTextAlignment(.leading)
                                .padding()
                                .mask(
                                    LinearGradient(gradient: Gradient(stops: [
                                        .init(color: .black, location: 0),
                                        .init(color: .black, location: 0.5),
                                        .init(color: .clear, location: 0.9)
                                    ]), startPoint: .top, endPoint: .bottom)
                                )
                        }
                        
                        // Overlay Content
                        VStack {
                            Spacer()
                            HStack(alignment: .bottom) {
                                Text(shortMintUrl(mintUrl))
                                    .foregroundColor(.white)
                                    .font(.subheadline)
                                
                                Spacer()
                                
                                Text("\(tokenAmount) sat")
                                    .foregroundColor(.white)
                                    .font(.system(size: 32, weight: .bold))
                            }
                            .padding()
                        }
                    }
                    .frame(height: 200)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
                    
                    // Details List
                    VStack(spacing: 20) {
                        if isLoadingFee {
                            HStack {
                                Image(systemName: "arrow.left.arrow.right")
                                    .foregroundColor(.gray)
                                    .frame(width: 24)
                                Text("Fee")
                                    .foregroundColor(.gray)
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        } else {
                            DetailRow(label: "Fee", value: "\(receiveFee) sat", icon: "arrow.left.arrow.right")
                        }
                        DetailRow(label: "Fiat", value: "$0.00", icon: "banknote")
                        DetailRow(label: "Mint", value: shortMintUrl(mintUrl), icon: "building.columns")
                        if !p2pkPubkeys.isEmpty {
                            DetailRow(
                                label: "P2PK",
                                value: tokenLockedToKnownKey ? "Locked to your key" : "Locked to unknown key",
                                icon: "lock.fill"
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            
            Spacer()
            
            // Buttons
            VStack(spacing: 16) {
                Button(action: receiveLater) {
                    Text("RECEIVE LATER")
                        .font(.headline)
                        .foregroundColor(.cashuMutedText)
                        .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 8)
                
                Button(action: receiveToken) {
                    ZStack {
                        if isReceiving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        } else {
                            Text("RECEIVE")
                                .font(.headline)
                                .foregroundColor(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.cashuAccent)
                    .cornerRadius(28)
                }
                .disabled(isReceiving || !tokenLockedToKnownKey)
            }
            .padding()
            .padding(.bottom, 20)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            parseToken()
            animateToken()
        }
        .onDisappear {
            tokenAnimationTimer?.invalidate()
            tokenAnimationTimer = nil
        }
    }
    
    func parseToken() {
        do {
            let token = try walletManager.decodeToken(tokenString: tokenString)
            self.decodedToken = token
            
            // Token structure in cdk-swift:
            // public let token: [TokenProof]
            // public struct TokenProof: Codable { public let mint: String, public let proofs: [Proof] }

            let proofs = try token.proofsSimple()
            self.tokenAmount = proofs.reduce(0) { $0 + $1.amount.value }
            let mint = try token.mintUrl()
            self.mintUrl = mint.url

            let tokenP2PKPubkeys = token.p2pkPubkeys()
            self.p2pkPubkeys = tokenP2PKPubkeys
            let knownKeys = Set(settings.p2pkKeys.map { normalizeP2PKForComparison($0.publicKey) })
            let hasMatch = tokenP2PKPubkeys.contains { knownKeys.contains(normalizeP2PKForComparison($0)) }
            self.tokenLockedToKnownKey = tokenP2PKPubkeys.isEmpty || hasMatch
            if !self.tokenLockedToKnownKey {
                errorMessage = "This token is P2PK locked and requires a matching key from Settings > P2PK Features."
            }
            
            // Calculate receive fee asynchronously
            Task {
                await calculateFee()
            }

        } catch {
            errorMessage = "Invalid Token: \(error.localizedDescription)"
            isLoadingFee = false
        }
    }
    
    func calculateFee() async {
        do {
            let fee = try await walletManager.calculateReceiveFee(tokenString: tokenString)
            await MainActor.run {
                self.receiveFee = fee
                self.isLoadingFee = false
            }
        } catch {
            await MainActor.run {
                // If we can't calculate fee, show 0
                self.receiveFee = 0
                self.isLoadingFee = false
                print("Failed to calculate receive fee: \(error)")
            }
        }
    }
    
    func receiveToken() {
        guard tokenLockedToKnownKey else {
            errorMessage = "Missing matching P2PK key for this token."
            return
        }

        isReceiving = true
        Task {
            do {
                let receivedAmount = try await walletManager.receiveTokens(tokenString: tokenString)
                await MainActor.run {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    
                    // Post notification to show badge on main screen
                    NotificationCenter.default.post(
                        name: .cashuTokenReceived,
                        object: nil,
                        userInfo: ["amount": receivedAmount, "fee": UInt64(0)] // TODO: Calculate fee
                    )
                    
                    // Dismiss entire scanner flow (not just this view)
                    if let onComplete = onComplete {
                        onComplete()
                    } else {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isReceiving = false
                }
            }
        }
    }
    
    func shortMintUrl(_ url: String) -> String {
        guard let urlObj = URL(string: url) else { return url }
        return urlObj.host ?? url
    }

    private func normalizeP2PKForComparison(_ pubkey: String) -> String {
        let normalized = pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.count == 66, normalized.hasPrefix("02") || normalized.hasPrefix("03") {
            return String(normalized.dropFirst(2))
        }
        return normalized
    }
    
    func receiveLater() {
        // Save token for later claiming
        let pendingReceive = PendingReceiveToken(
            tokenId: UUID().uuidString,
            token: tokenString,
            amount: tokenAmount,
            date: Date(),
            mintUrl: mintUrl
        )
        
        walletManager.savePendingReceiveToken(pendingReceive)
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Dismiss
        if let onComplete = onComplete {
            onComplete()
        } else {
            dismiss()
        }
    }
    
    func animateToken() {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()-_=+[]{}<>?/\\|~"
        let targetText = tokenString
        var currentLength = 0
        
        tokenAnimationTimer?.invalidate()
        tokenAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            currentLength += 6
            
            if currentLength >= targetText.count {
                displayedToken = targetText
                timer.invalidate()
                tokenAnimationTimer = nil
                return
            }
            
            let endIndex = targetText.index(targetText.startIndex, offsetBy: currentLength)
            var text = String(targetText[..<endIndex])
            
            // Add some random chars at the end
            for _ in 0..<5 {
                if let randomChar = chars.randomElement() {
                    text.append(randomChar)
                }
            }
            displayedToken = text
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.gray)
                .frame(width: 24)
            Text(label)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .fontWeight(.medium)
        }
    }
}
