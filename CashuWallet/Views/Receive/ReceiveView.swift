import SwiftUI

struct ReceiveView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    
    @State private var selectedOption: ReceiveOption?
    
    enum ReceiveOption: String, Identifiable {
        case paste, scan, lightning
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Spacer()
                    
                    // Icon
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.cashuAccent)
                    
                    Text("Receive")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Choose how you want to receive")
                        .font(.subheadline)
                        .foregroundColor(.cashuMutedText)
                    
                    Spacer()
                    
                    // Options
                    VStack(spacing: 12) {
                        // Paste option
                        Button(action: { selectedOption = .paste }) {
                            receiveOptionRow(
                                icon: "doc.on.clipboard",
                                title: "Paste Ecash Token",
                                subtitle: "Paste a token from clipboard"
                            )
                        }
                        
                        // Scan option
                        Button(action: { selectedOption = .scan }) {
                            receiveOptionRow(
                                icon: "qrcode.viewfinder",
                                title: "Scan QR Code",
                                subtitle: "Scan token or invoice"
                            )
                        }
                        
                        // Lightning option
                        Button(action: { selectedOption = .lightning }) {
                            receiveOptionRow(
                                icon: "bolt.fill",
                                title: "Lightning Invoice",
                                subtitle: "Create invoice to receive sats"
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Cancel button
                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .foregroundColor(.cashuMutedText)
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(item: $selectedOption) { option in
                switch option {
                case .paste:
                    ReceiveEcashView()
                        .environmentObject(walletManager)
                case .scan:
                    ScannerWrapperView()
                        .environmentObject(walletManager)
                case .lightning:
                    ReceiveLightningView()
                        .environmentObject(walletManager)
                }
            }
        }
    }
    
    private func receiveOptionRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.cashuAccent)
                .frame(width: 50, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.cashuCardBackground)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.cashuMutedText)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cashuCardBackground)
        )
    }
    
    private func handleScannedCode(_ code: String) {
        Task { @MainActor in
            if code.lowercased().hasPrefix("cashu") {
                do {
                    let _ = try await walletManager.receiveTokens(tokenString: code)
                    dismiss()
                } catch {
                    print("Error receiving token: \(error)")
                }
            }
        }
    }
}

struct ReceiveEcashView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared
    
    @State private var tokenInput = ""
    @State private var errorMessage: String?
    @State private var navigateToDetail = false
    @State private var validatedToken: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.cashuBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Spacer()
                    
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 48))
                        .foregroundColor(.cashuAccent)
                    
                    Text("Paste Token")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    // Token input
                    TextEditor(text: $tokenInput)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .frame(height: 120)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.cashuCardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.cashuBorder, lineWidth: 1)
                                )
                        )
                        .padding(.horizontal)
                    
                    // Paste from clipboard
                    Button(action: pasteFromClipboard) {
                        HStack {
                            Image(systemName: "doc.on.clipboard")
                            Text("Paste from Clipboard")
                        }
                    }
                    .buttonStyle(CashuSecondaryButtonStyle())
                    .padding(.horizontal)
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.cashuError)
                    }
                    
                    Spacer()
                    
                    // Continue button - validates token and navigates to detail view
                    Button(action: validateAndContinue) {
                        Text("CONTINUE")
                    }
                    .buttonStyle(CashuPrimaryButtonStyle(isDisabled: tokenInput.isEmpty))
                    .disabled(tokenInput.isEmpty)
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Receive Ecash")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .navigationDestination(isPresented: $navigateToDetail) {
                if let token = validatedToken {
                    ReceiveTokenDetailView(tokenString: token, onComplete: {
                        dismiss()
                    })
                    .environmentObject(walletManager)
                    .navigationBarBackButtonHidden(true)
                }
            }
            .onAppear {
                guard settings.autoPasteEcashReceive else { return }
                guard tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                guard let clipboardContent = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                      clipboardContent.lowercased().hasPrefix("cashu") else { return }
                tokenInput = clipboardContent
            }
        }
    }
    
    private func pasteFromClipboard() {
        if let clipboardContent = UIPasteboard.general.string {
            tokenInput = clipboardContent
        }
    }
    
    private func validateAndContinue() {
        guard !tokenInput.isEmpty else { return }
        
        errorMessage = nil
        
        // Validate that it's a valid cashu token before navigating
        let trimmedToken = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Basic validation - check if it looks like a cashu token
        if trimmedToken.lowercased().hasPrefix("cashu") {
            validatedToken = trimmedToken
            navigateToDetail = true
        } else {
            errorMessage = "Invalid token format. Token should start with 'cashu'"
        }
    }
}

#Preview {
    ReceiveView()
        .environmentObject(WalletManager())
}
