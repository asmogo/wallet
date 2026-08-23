import SwiftUI
import UIKit

/// URL entry for connecting a mint, without a `NavigationStack` of its own — the
/// host supplies one. Used standalone by `AddMintSheet` (Mints list) and as the
/// pushed step of `ConnectMintPicker`.
struct AddMintFormView: View {
    /// Inline title for the host's navigation bar. The connect-a-mint picker
    /// pushes this as "Add by URL" — the link that opened it — while the
    /// standalone Mints-tab sheet keeps the plain name.
    var navigationTitle: String
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
    @FocusState private var urlFieldFocused: Bool

    init(
        initialUrl: String = "",
        navigationTitle: String = "Add mint",
        onAdded: @escaping () -> Void,
        onHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.navigationTitle = navigationTitle
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
            // A persistent label, not a placeholder doing double duty: the old
            // "Mint URL (https://…)" vanished the moment they typed, taking the
            // VoiceOver label with it. Android's floating label already does this.
            Text("Mint URL")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            HStack(spacing: 10) {
                TextField("https://…", text: $mintUrl)
                    .accessibilityLabel("Mint URL")
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

                if !mintUrl.isEmpty {
                    Button {
                        mintUrl = ""
                        errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isAdding)
                    .accessibilityLabel("Clear")
                    .accessibilityIdentifier("mints-add-clear-button")
                }
            }
            .animation(.smooth(duration: 0.2), value: mintUrl.isEmpty)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

            // The label and placeholder already say "enter a mint URL"; the only
            // load-bearing sentence here is the trust one.
            Text("Mints are run by third parties; this wallet isn't affiliated with any of them. Only add a mint you trust.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            if let errorMessage {
                InlineNotice(message: errorMessage, severity: .error)
                    .padding(.top, 12)
            }

            HStack(spacing: 12) {
                Button("Paste", action: pasteFromClipboard)
                    .flatSheetSecondaryButton()
                    .disabled(isAdding)
                    .accessibilityHint("Pastes a mint URL from the clipboard")
                    .accessibilityIdentifier("mints-add-paste-button")

                Button(action: addMint) {
                    Group {
                        if isAdding {
                            ProgressView().tint(.primary)
                        } else {
                            Text("Add mint")
                        }
                    }
                }
                .glassButton()
                .disabled(!canSubmit)
                .accessibilityIdentifier("mints-add-submit-button")
            }
            .padding(.top, 24)

        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .contentFitMeasured { onHeightChange($0) }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canSubmit: Bool {
        !mintUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAdding
    }

    /// Empty and "held something, but not a mint URL" are different mistakes
    /// with different fixes, so they read as different messages.
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
            errorMessage = "No mint URL in your clipboard. Copy the mint's address, then paste."
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

    /// Pulls the first plausible mint URL from free-form pasted text.
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

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        NavigationStack {
            AddMintFormView(
                onAdded: { dismiss() },
                onHeightChange: { contentHeight = $0 }
            )
        }
        // Hugs the form, like every other content-fit sheet in the app.
        .contentFitDetent(contentHeight, estimate: 260)
        .presentationDragIndicator(.visible)
        .compactBottomSheetSurface()
    }
}

#Preview {
    AddMintSheet()
        .environmentObject(WalletManager())
}
