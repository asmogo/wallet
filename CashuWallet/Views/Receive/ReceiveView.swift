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
            List {
                Section {
                    Button(action: { selectedOption = .paste }) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Paste Ecash Token")
                                Text("Paste a token from clipboard")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "doc.on.clipboard")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .accessibilityLabel("Paste Ecash Token")
                    .accessibilityHint("Paste a cashu token from clipboard to receive ecash")
                    .accessibilityAddTraits(.isButton)

                    Button(action: { selectedOption = .scan }) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scan QR Code")
                                Text("Scan token or invoice")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "qrcode.viewfinder")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .accessibilityLabel("Scan QR Code")
                    .accessibilityHint("Opens camera to scan a token or invoice QR code")
                    .accessibilityAddTraits(.isButton)

                    Button(action: { selectedOption = .lightning }) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Lightning Invoice")
                                Text("Create invoice to receive sats")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .accessibilityLabel("Lightning Invoice")
                    .accessibilityHint("Creates a lightning invoice to receive sats")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Receive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedOption) { option in
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
            Form {
                Section {
                    TextEditor(text: $tokenInput)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 120)
                        .accessibilityLabel("Ecash token input")
                        .accessibilityHint("Enter or paste a cashu ecash token")
                }

                Section {
                    Button(action: pasteFromClipboard) {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    }
                    .accessibilityHint("Pastes ecash token from clipboard")
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: validateAndContinue) {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(tokenInput.isEmpty)
                    .accessibilityHint("Validates the token and proceeds to details")
                }
            }
            .navigationTitle("Receive Ecash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
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

        let trimmedToken = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)

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
