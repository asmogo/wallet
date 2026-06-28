import SwiftUI

struct ReceiveTokenDetailView: View {
    let tokenString: String
    let onComplete: (() -> Void)?
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var settings = SettingsManager.shared

    @State private var tokenAmount: UInt64 = 0
    @State private var receiveFee: UInt64 = 0
    @State private var mintUrl: String = ""
    @State private var isReceiving = false
    @State private var errorMessage: String?
    @State private var isLoadingFee = true
    @State private var p2pkPubkeys: [String] = []
    @State private var tokenLockedToKnownKey = true
    @State private var mintIsKnown = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        // Amount
                        CurrencyAmountDisplay(
                            sats: tokenAmount,
                            primary: $settings.amountDisplayPrimary
                        )
                        .padding(.top, 12)

                        // Details
                        VStack(spacing: 0) {
                            if isLoadingFee {
                                HStack {
                                    Label("Fee", systemImage: "arrow.up.arrow.down")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    ProgressView().scaleEffect(0.8)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            } else {
                                detailRow(icon: "arrow.up.arrow.down", label: "Fee", value: "\(receiveFee) sat")
                            }
                            Divider().padding(.leading)
                            detailRow(icon: "bitcoinsign.bank.building", label: "Mint", value: shortMintUrl(mintUrl))
                            if !p2pkPubkeys.isEmpty {
                                Divider().padding(.leading)
                                detailRow(icon: "lock.fill", label: "P2PK",
                                          value: tokenLockedToKnownKey ? "Your key" : "Unknown key")
                            }
                        }
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)

                        if !mintIsKnown && !mintUrl.isEmpty {
                            newMintBadge
                        }

                        if let error = errorMessage {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 16)
                }

                // Buttons
                VStack(spacing: 12) {
                    Button(action: receiveToken) {
                        if isReceiving {
                            ProgressView()
                        } else {
                            Text("Receive")
                        }
                    }
                    .glassButton()
                    .disabled(isReceiving || !tokenLockedToKnownKey)

                    Button(action: receiveLater) {
                        Text("Receive Later")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Receive Ecash")
                        .font(.headline)
                }
            }
        }
        .task(id: tokenString) {
            await loadTokenPreview()
        }
    }

    init(tokenString: String, onComplete: (() -> Void)? = nil) {
        self.tokenString = tokenString
        self.onComplete = onComplete
    }

    private var newMintBadge: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("New mint")
                    .font(.caption.weight(.semibold))
                Text("You haven't used \(shortMintUrl(mintUrl)) before. Receiving adds it to your wallet — only continue if you trust it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Helpers

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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    func shortMintUrl(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }

    // MARK: - Actions

    @MainActor
    private func loadTokenPreview() async {
        isLoadingFee = true
        errorMessage = nil

        do {
            let preview = try await CdkRuntime.shared.tokenPreview(from: tokenString)
            guard !Task.isCancelled else { return }

            self.tokenAmount = preview.amount
            self.mintUrl = preview.mintUrl
            self.mintIsKnown = walletManager.isMintKnown(url: preview.mintUrl)

            let tokenP2PKPubkeys = preview.p2pkPubkeys
            self.p2pkPubkeys = tokenP2PKPubkeys
            let knownKeys = Set(settings.p2pkKeys.map { normalizeP2PKForComparison($0.publicKey) })
            let hasMatch = tokenP2PKPubkeys.contains { knownKeys.contains(normalizeP2PKForComparison($0)) }
            self.tokenLockedToKnownKey = tokenP2PKPubkeys.isEmpty || hasMatch
            if !self.tokenLockedToKnownKey {
                errorMessage = "This token is P2PK locked and requires a matching key from Settings > P2PK."
            }

            await calculateFee()
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Invalid token. \(error.userFacingWalletMessage)"
            isLoadingFee = false
        }
    }

    @MainActor
    private func calculateFee() async {
        do {
            let fee = try await walletManager.calculateReceiveFee(tokenString: tokenString)
            guard !Task.isCancelled else { return }
            self.receiveFee = fee
            self.isLoadingFee = false
        } catch {
            guard !Task.isCancelled else { return }
            self.receiveFee = 0
            self.isLoadingFee = false
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
                    HapticFeedback.notification(.success)
                    NotificationCenter.default.post(
                        name: .cashuTokenReceived,
                        object: nil,
                        userInfo: ["amount": receivedAmount, "fee": UInt64(0)]
                    )
                    if let onComplete = onComplete {
                        onComplete()
                    } else {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.userFacingWalletMessage
                    isReceiving = false
                    HapticFeedback.notification(.error)
                }
            }
        }
    }

    func receiveLater() {
        let pendingReceive = PendingReceiveToken(
            tokenId: UUID().uuidString,
            token: tokenString,
            amount: tokenAmount,
            date: Date(),
            mintUrl: mintUrl
        )
        walletManager.savePendingReceiveToken(pendingReceive)
        if let onComplete = onComplete {
            onComplete()
        } else {
            dismiss()
        }
    }

    private func normalizeP2PKForComparison(_ pubkey: String) -> String {
        let normalized = pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.count == 66, normalized.hasPrefix("02") || normalized.hasPrefix("03") {
            return String(normalized.dropFirst(2))
        }
        return normalized
    }
}
