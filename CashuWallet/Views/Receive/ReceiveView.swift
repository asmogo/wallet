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
                        .accessibilityHidden(true)
                    
                    Text("Receive")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
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
                        .accessibilityLabel("Paste Ecash Token")
                        .accessibilityHint("Paste a cashu token from clipboard to receive ecash")

                        // Scan option
                        Button(action: { selectedOption = .scan }) {
                            receiveOptionRow(
                                icon: "qrcode.viewfinder",
                                title: "Scan QR Code",
                                subtitle: "Scan token or invoice"
                            )
                        }
                        .accessibilityLabel("Scan QR Code")
                        .accessibilityHint("Opens camera to scan a token or invoice QR code")

                        // Lightning option
                        Button(action: { selectedOption = .lightning }) {
                            receiveOptionRow(
                                icon: "bolt.fill",
                                title: "Lightning Invoice",
                                subtitle: "Create invoice to receive sats"
                            )
                        }
                        .accessibilityLabel("Lightning Invoice")
                        .accessibilityHint("Creates a lightning invoice to receive sats")
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Cancel button
                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .foregroundColor(.cashuMutedText)
                    }
                    .accessibilityLabel("Cancel")
                    .accessibilityHint("Closes the receive screen")
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
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.cashuMutedText)
                .accessibilityHidden(true)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cashuCardBackground)
        )
        .accessibilityElement(children: .combine)
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
                        .accessibilityHidden(true)
                    
                    Text("Paste Token")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
                    // Token input
                    TextEditor(text: $tokenInput)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
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
                        .accessibilityLabel("Ecash token input")
                        .accessibilityHint("Enter or paste a cashu ecash token")
                    
                    // Paste from clipboard
                    Button(action: pasteFromClipboard) {
                        HStack {
                            Image(systemName: "doc.on.clipboard")
                                .accessibilityHidden(true)
                            Text("Paste from Clipboard")
                        }
                    }
                    .buttonStyle(CashuSecondaryButtonStyle())
                    .accessibilityLabel("Paste from Clipboard")
                    .accessibilityHint("Pastes ecash token from clipboard")
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
                    .accessibilityLabel("Continue")
                    .accessibilityHint("Validates the token and proceeds to details")
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Close")
                }

                ToolbarItem(placement: .principal) {
                    Text("Receive Ecash")
                        .font(.headline)
                        .foregroundStyle(.primary)
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
