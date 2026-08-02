import SwiftUI
import UIKit

/// URL entry for connecting a mint, without a `NavigationStack` of its own — the
/// host supplies one. Used standalone by `AddMintSheet` (Mints list) and as the
/// pushed step of `ConnectMintPicker`.
struct AddMintFormView: View {
    /// Called after the mint is connected. Standalone hosts dismiss; the
    /// connect-a-mint picker pops back or closes depending on where it was opened.
    var onAdded: () -> Void
    /// Reports the form's intrinsic height so a host can hug it with a
    /// content-fit detent.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @EnvironmentObject private var walletManager: WalletManager

    @State private var mintUrl = ""
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var showingScanner = false
    @FocusState private var urlFieldFocused: Bool

    init(
        initialUrl: String = "",
        onAdded: @escaping () -> Void,
        onHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.onAdded = onAdded
        self.onHeightChange = onHeightChange
        _mintUrl = State(initialValue: initialUrl)
    }

    var body: some View {
        // Intrinsic height, matching Android's `AddMintFormBody` column and the
        // flat-canvas picker it is pushed from — a grouped `List` here would be a
        // second visual system inside one sheet, and its greedy height forces the
        // host to `.large`, stranding the buttons under a band of dead space.
        VStack(alignment: .leading, spacing: 0) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

            Text("Enter the URL of a Cashu mint to connect to it. This wallet is not affiliated with any mint.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            if let errorMessage {
                InlineNotice(message: errorMessage, severity: .error)
                    .padding(.top, 12)
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
            .padding(.top, 24)

            Button("Paste URL from Clipboard", action: pasteFromClipboard)
                .textLinkButton()
                .frame(maxWidth: .infinity)
                .disabled(isAdding)
                .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            onHeightChange(newHeight)
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

    @State private var contentHeight: CGFloat = 260

    /// Matches the connect-a-mint sheet's chrome allowance.
    private let sheetChrome: CGFloat = 108

    var body: some View {
        NavigationStack {
            AddMintFormView(
                onAdded: { dismiss() },
                onHeightChange: { contentHeight = $0 }
            )
        }
        // Hugs the form, like every other content-fit sheet in the app.
        .presentationDetents([.height(contentHeight + sheetChrome)])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    AddMintSheet()
        .environmentObject(WalletManager())
}
