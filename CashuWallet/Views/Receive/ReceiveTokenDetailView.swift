import SwiftUI
import CashuDevKit

struct ReceiveTokenDetailView: View {
    let tokenString: String
    var onComplete: (() -> Void)? = nil
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // Amount
                        CurrencyAmountDisplay(
                            sats: tokenAmount,
                            primary: $settings.amountDisplayPrimary
                        )
                        .padding(.top, 24)

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

                        if let error = errorMessage {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
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
        .onAppear {
            parseToken()
        }
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

    func parseToken() {
        do {
            let token = try walletManager.decodeToken(tokenString: tokenString)
            self.decodedToken = token
            // Token.value() is the canonical "total value of the token" API;
            // proofsSimple() is documented as "simplified - no keyset filtering"
            // and returns 0 / empty for some token formats.
            self.tokenAmount = try token.value().value
            let mint = try token.mintUrl()
            self.mintUrl = mint.url

            let tokenP2PKPubkeys = token.p2pkPubkeys()
            self.p2pkPubkeys = tokenP2PKPubkeys
            let knownKeys = Set(settings.p2pkKeys.map { normalizeP2PKForComparison($0.publicKey) })
            let hasMatch = tokenP2PKPubkeys.contains { knownKeys.contains(normalizeP2PKForComparison($0)) }
            self.tokenLockedToKnownKey = tokenP2PKPubkeys.isEmpty || hasMatch
            if !self.tokenLockedToKnownKey {
                errorMessage = "This token is P2PK locked and requires a matching key from Settings > P2PK."
            }

            Task { await calculateFee() }
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
                self.receiveFee = 0
                self.isLoadingFee = false
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
                    errorMessage = error.localizedDescription
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
