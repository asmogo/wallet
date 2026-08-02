import SwiftUI
import UIKit

/// URL entry for connecting a mint, without a `NavigationStack` of its own — the
/// host supplies one. Used standalone by `AddMintSheet` (Mints list) and as the
/// pushed step of `ConnectMintPicker`.
struct AddMintFormView: View {
    /// Called after the mint is connected. Standalone hosts dismiss; the
    /// connect-a-mint picker pops back or closes depending on where it was opened.
    var onAdded: () -> Void

    @EnvironmentObject private var walletManager: WalletManager

    @State private var mintUrl = ""
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var showingScanner = false
    @FocusState private var urlFieldFocused: Bool

    init(initialUrl: String = "", onAdded: @escaping () -> Void) {
        self.onAdded = onAdded
        _mintUrl = State(initialValue: initialUrl)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    TextField("Mint URL (https://…)", text: $mintUrl)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .focused($urlFieldFocused)
                        .submitLabel(.go)
                        .onSubmit(addMint)
                        .onChange(of: mintUrl) {
                            if errorMessage != nil { errorMessage = nil }
                        }
                        .accessibilityIdentifier("mints-add-url-field")

                    Button(action: openScanner) {
                        Image(systemName: "viewfinder")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isAdding)
                    .accessibilityLabel("Scan QR Code")
                    .accessibilityHint("Opens the camera to scan a mint URL")
                    .accessibilityIdentifier("mints-add-scan-button")
                }
            } footer: {
                Text("Enter the URL of a Cashu mint to connect to it. This wallet is not affiliated with any mint.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if let errorMessage {
                    InlineNotice(message: errorMessage, severity: .error)
                }

                Button(action: addMint) {
                    Group {
                        if isAdding {
                            ProgressView().tint(.primary)
                        } else {
                            Text("Add Mint")
                        }
                    }
                }
                .glassButton()
                .disabled(!canSubmit)
                .accessibilityIdentifier("mints-add-submit-button")

                Button("Paste URL from Clipboard", action: pasteFromClipboard)
                    .textLinkButton()
                    .frame(maxWidth: .infinity)
                    .disabled(isAdding)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .navigationTitle("Add Mint")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingScanner) {
            ScannerWrapperView(
                onScanned: handleScannedMintUrl,
                promptText: "Scan a mint URL"
            )
            .environmentObject(walletManager)
            .canvasSheetBackground()
        }
    }

    private var canSubmit: Bool {
        !mintUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAdding
    }

    private func openScanner() {
        urlFieldFocused = false
        HapticFeedback.selection()
        showingScanner = true
    }

    private func handleScannedMintUrl(_ raw: String) {
        if let normalized = Self.normalizedMintUrl(from: raw) {
            mintUrl = normalized
            errorMessage = nil
        } else {
            errorMessage = "No valid mint URL found in QR code."
        }
    }

    private func addMint() {
        let urlToAdd = mintUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlToAdd.isEmpty, !isAdding else { return }

        isAdding = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await walletManager.addMint(url: urlToAdd)
                HapticFeedback.selection()
                mintUrl = ""
                onAdded()
            } catch {
                errorMessage = error.userFacingWalletMessage
            }
            isAdding = false
        }
    }

    private func pasteFromClipboard() {
        guard let clipboardContent = UIPasteboard.general.string,
              !clipboardContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Clipboard is empty."
            return
        }
        if let normalized = Self.normalizedMintUrl(from: clipboardContent) {
            mintUrl = normalized
            errorMessage = nil
        } else {
            errorMessage = "No valid mint URL found in clipboard."
        }
    }

    /// Pulls the first plausible mint URL from free-form paste/scan text.
    private static func normalizedMintUrl(from raw: String) -> String? {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))
        let candidates = raw.components(separatedBy: separators).filter { !$0.isEmpty }
        for rawCandidate in candidates {
            var candidate = rawCandidate.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !candidate.hasPrefix("http://") && !candidate.hasPrefix("https://") {
                candidate = "https://" + candidate
            }
            if candidate.hasSuffix("/") {
                candidate = String(candidate.dropLast())
            }
            if let url = URL(string: candidate), url.host != nil {
                return candidate
            }
        }
        return nil
    }
}

/// The Mints-list entry point. The wallet-home and Send entry points go through
/// `ConnectMintSheet` / `ConnectMintPicker` instead.
struct AddMintSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AddMintFormView(onAdded: { dismiss() })
        }
    }
}

#Preview {
    AddMintSheet()
        .environmentObject(WalletManager())
}
