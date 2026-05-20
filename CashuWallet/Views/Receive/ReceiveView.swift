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
                                Text("Scan a token, payment request, or address")
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
                                Text("Payment Request")
                                Text("Create an invoice, offer, or address")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .accessibilityLabel("Payment Request")
                    .accessibilityHint("Creates a lightning invoice, BOLT12 offer, or bitcoin address to receive sats")
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
            if TokenParser.isCashuToken(code) {
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

    var sheetDetent: Binding<PresentationDetent>? = nil

    @State private var tokenInput = ""
    @State private var errorMessage: String?
    @State private var navigateToDetail = false
    @State private var validatedToken: String?
    @State private var navigateToRequest = false
    @State private var currentRequest: CashuRequest?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack(alignment: .bottomTrailing) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $tokenInput)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .accessibilityLabel("Ecash token input")
                            .accessibilityHint("Enter or paste a cashu ecash token")

                        if tokenInput.isEmpty {
                            Text("cashuB…")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 17)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }
                    }
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.55),
                                .init(color: .black.opacity(0.85), location: 0.72),
                                .init(color: .black.opacity(0.35), location: 0.88),
                                .init(color: .clear, location: 1.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Smart corner icon: paste when empty, clear when full.
                    // Plain SF Symbol (no circle bg) so we don't stack a
                    // gray dot on the gray text field.
                    Button(action: tokenInput.isEmpty ? pasteFromClipboard : clearInput) {
                        Image(systemName: tokenInput.isEmpty ? "doc.on.clipboard" : "xmark.circle.fill")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tokenInput.isEmpty ? "Paste from clipboard" : "Clear")
                }
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .frame(maxHeight: .infinity)
                .padding(.horizontal)
                .padding(.top, 12)

                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .scale))
                }

                VStack(spacing: 10) {
                    Button(action: validateAndContinue) {
                        Text("Continue")
                    }
                    .glassButton()
                    .disabled(tokenInput.isEmpty)
                    .animation(.easeOut(duration: 0.2), value: tokenInput.isEmpty)
                    .accessibilityHint("Validates the token and proceeds to details")

                    Button(action: createNewRequest) {
                        Text("New Request")
                    }
                    .glassButton()
                    .accessibilityHint("Generate a Cashu Request to receive ecash")
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .animation(.easeInOut(duration: 0.2), value: errorMessage)
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
            .navigationDestination(isPresented: $navigateToRequest) {
                if let request = currentRequest {
                    CashuRequestDetailView(request: request, onClose: { dismiss() })
                        .environmentObject(walletManager)
                }
            }
            .onAppear {
                guard settings.autoPasteEcashReceive else { return }
                guard tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                guard let clipboardContent = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                      TokenParser.isCashuToken(clipboardContent) else { return }
                tokenInput = clipboardContent
            }
        }
    }

    private func pasteFromClipboard() {
        if let clipboardContent = UIPasteboard.general.string {
            HapticFeedback.selection()
            tokenInput = clipboardContent
        }
    }

    private func clearInput() {
        HapticFeedback.selection()
        tokenInput = ""
        errorMessage = nil
    }

    private func createNewRequest() {
        HapticFeedback.selection()
        let nostr = NostrService.shared
        guard nostr.isInitialized, !nostr.publicKeyHex.isEmpty else {
            errorMessage = "Nostr identity not initialized"
            return
        }
        let id = CashuRequest.newId()
        do {
            let encoded = try PaymentRequestBuilder.build(
                id: id,
                amount: nil,
                unit: "sat",
                mints: [],
                description: nil,
                nostrPubkeyHex: nostr.publicKeyHex,
                relays: SettingsManager.shared.nostrRelays
            )
            let request = CashuRequestStore.shared.createNew(
                amount: nil,
                unit: "sat",
                mints: [],
                memo: nil,
                encoded: encoded
            )
            currentRequest = request
            if let sheetDetent {
                withAnimation(.snappy) {
                    sheetDetent.wrappedValue = .large
                }
            }
            navigateToRequest = true
        } catch {
            errorMessage = "Could not build request: \(error)"
        }
    }

    private func validateAndContinue() {
        guard !tokenInput.isEmpty else { return }

        errorMessage = nil

        let trimmedToken = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if let token = TokenParser.normalizedToken(from: trimmedToken) {
            validatedToken = token
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
