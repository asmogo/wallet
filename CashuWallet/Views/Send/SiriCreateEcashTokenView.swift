import SwiftUI

struct SiriCreateEcashTokenView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager
    @ObservedObject private var settings = SettingsManager.shared

    let request: SiriCreateTokenRequest
    let onComplete: () -> Void

    @State private var phase: Phase = .creating
    @State private var token: String?
    @State private var tokenFee: UInt64 = 0
    @State private var tokenMintURL: String?
    @State private var hasStarted = false
    @State private var copyButtonText = "Copy"
    @State private var showShareSheet = false

    private enum Phase: Equatable {
        case creating
        case ready
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .creating:
                    creatingView
                case .ready:
                    if let token {
                        tokenView(token)
                    }
                case .failed(let message):
                    failureView(message)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: close) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }

                ToolbarItem(placement: .principal) {
                    Text("Siri Ecash")
                        .font(.headline)
                }

                if token != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showShareSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share token")
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let token {
                    CashuTokenShareSheet(token: token)
                }
            }
            .task {
                await createTokenIfNeeded()
            }
        }
    }

    private var creatingView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .scaleEffect(1.3)
            Text("Creating ecash token...")
                .font(.headline)
            Text("\(request.amountSats) sat")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func tokenView(_ token: String) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    QRCodeView(content: token, showControls: false)
                        .frame(width: 280, height: 280)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                        .padding(.top, 8)

                    VStack(spacing: 6) {
                        Text("\(request.amountSats) sat")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))

                        if let tokenMintURL {
                            Text(extractMintHost(tokenMintURL))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: 0) {
                        detailRow(icon: "arrow.up.arrow.down", label: "Fee", value: "\(tokenFee) sat")
                        canvasDivider
                        detailRow(icon: "banknote", label: "Unit", value: settings.unitLabel.uppercased())
                        if let tokenMintURL {
                            canvasDivider
                            detailRow(
                                icon: "bitcoinsign.bank.building",
                                label: "Mint",
                                value: extractMintHost(tokenMintURL)
                            )
                        }
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal)
            }

            Button(action: { copyToken(token) }) {
                Text(copyButtonText)
            }
            .glassButton()
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.orange)

            Text("Could not create token")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Close", action: close)
                .glassButton()
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func createTokenIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true

        var initializationAttempts = 0
        while !walletManager.isInitialized && !Task.isCancelled && initializationAttempts < 120 {
            try? await Task.sleep(nanoseconds: 150_000_000)
            initializationAttempts += 1
        }

        guard walletManager.isInitialized, !walletManager.needsOnboarding else {
            phase = .failed("Set up or unlock the wallet before using Siri to create ecash.")
            return
        }

        guard let mintURL = resolvedMintURL() else {
            phase = .failed("I could not find the requested mint in your wallet.")
            return
        }

        do {
            let result = try await walletManager.sendTokens(
                amount: request.amountSats,
                memo: request.memo,
                mintUrl: mintURL
            )
            token = result.token
            tokenFee = result.fee
            tokenMintURL = mintURL
            phase = .ready
            HapticFeedback.notification(.success)
        } catch {
            phase = .failed(error.userFacingWalletMessage)
            HapticFeedback.notification(.error)
        }
    }

    private func resolvedMintURL() -> String? {
        let requestedMint = request.mint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedMint.isEmpty else {
            return walletManager.activeMint?.url
        }

        var candidates = walletManager.mints
        if let activeMint = walletManager.activeMint,
           !candidates.contains(where: { $0.id == activeMint.id }) {
            candidates.append(activeMint)
        }
        let normalizedRequest = Self.normalizedMintLookupKey(requestedMint)

        return candidates.first { mint in
            let urlKey = Self.normalizedMintLookupKey(mint.url)
            let nameKey = Self.normalizedMintLookupKey(mint.name)
            return urlKey == normalizedRequest
                || nameKey == normalizedRequest
                || urlKey.contains(normalizedRequest)
                || nameKey.contains(normalizedRequest)
        }?.url
    }

    private static func normalizedMintLookupKey(_ value: String) -> String {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let host = URL(string: trimmed)?.host {
            return host
                .removingPrefix("www.")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        return trimmed
            .removingPrefix("https://")
            .removingPrefix("http://")
            .removingPrefix("www.")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
    }

    private var canvasDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 0.5)
            .padding(.leading, 28)
    }

    private func extractMintHost(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }

    private func copyToken(_ token: String) {
        UIPasteboard.general.string = token
        HapticFeedback.notification(.success)
        copyButtonText = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            copyButtonText = "Copy"
        }
    }

    private func close() {
        onComplete()
        dismiss()
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
