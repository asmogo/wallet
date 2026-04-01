import SwiftUI

struct LightningAddressSettingsSection: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var npcService = NPCService.shared

    @Binding var copiedLightningAddress: Bool
    @Binding var isCheckingPayments: Bool
    @Binding var showMintPicker: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Enable/Disable toggle
            VStack(alignment: .leading, spacing: 8) {
                Text("npub.cash Integration")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)

                Text("Receive Lightning payments to your wallet using a Lightning address.")
                    .font(.caption)
                    .foregroundColor(.cashuMutedText)

                Toggle(isOn: $npcService.isEnabled) {
                    Text("Enable Lightning Address")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))
                .padding(.top, 8)
            }

            if npcService.isEnabled {
                // Lightning Address Display
                if npcService.isInitialized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Lightning Address")
                            .font(.caption)
                            .foregroundColor(.cashuMutedText)

                        Button(action: copyLightningAddress) {
                            HStack {
                                Text(npcService.lightningAddress)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundColor(settings.accentColor)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                Image(systemName: copiedLightningAddress ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(copiedLightningAddress ? .green : settings.accentColor)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.cashuCardBackground)
                            )
                        }
                    }
                    .padding(.top, 8)

                    // Auto-claim toggle
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $npcService.automaticClaim) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-claim payments")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                Text("Automatically mint received payments")
                                    .font(.caption)
                                    .foregroundColor(.cashuMutedText)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: settings.accentColor))
                    }
                    .padding(.top, 8)

                    // Mint selection
                    if !walletManager.mints.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Receiving Mint")
                                .font(.caption)
                                .foregroundColor(.cashuMutedText)

                            Button(action: { showMintPicker = true }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(selectedMintName())
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                        Text(npcService.selectedMintUrl ?? "Select a mint")
                                            .font(.caption)
                                            .foregroundColor(.cashuMutedText)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.cashuMutedText)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.cashuCardBackground)
                                )
                            }
                        }
                        .padding(.top, 8)
                    }

                    // Manual check button
                    HStack {
                        Button(action: checkForPayments) {
                            HStack {
                                if isCheckingPayments {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: settings.accentColor))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Check for Payments")
                            }
                            .font(.subheadline)
                            .foregroundColor(settings.accentColor)
                        }
                        .disabled(isCheckingPayments)

                        Spacer()

                        if let lastCheck = npcService.lastCheck {
                            Text("Last: \(formatRelativeTime(lastCheck))")
                                .font(.caption2)
                                .foregroundColor(.cashuMutedText)
                        }
                    }
                    .padding(.top, 12)

                    // Connection status
                    HStack {
                        Circle()
                            .fill(npcService.isConnected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)

                        Text(npcService.isConnected ? "Connected to npubx.cash" : "Connecting...")
                            .font(.caption)
                            .foregroundColor(.cashuMutedText)
                    }
                    .padding(.top, 8)

                    // Error message
                    if let error = npcService.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.cashuError)
                            .padding(.top, 4)
                    }
                } else {
                    // Nostr not initialized
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.cashuWarning)
                        Text("Wallet not fully initialized. Please restart the app.")
                            .font(.caption)
                            .foregroundColor(.cashuMutedText)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showMintPicker) {
            MintPickerSheet(
                mints: walletManager.mints,
                selectedMintUrl: $npcService.selectedMintUrl,
                onSelect: { mintUrl in
                    Task {
                        try? await npcService.changeMint(to: mintUrl)
                    }
                }
            )
        }
    }

    // MARK: - Helpers

    private func copyLightningAddress() {
        let address = npcService.lightningAddress
        UIPasteboard.general.string = address
        copiedLightningAddress = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedLightningAddress = false
        }
    }

    private func checkForPayments() {
        isCheckingPayments = true
        Task {
            await npcService.checkAndClaimPayments()
            await MainActor.run {
                isCheckingPayments = false
            }
        }
    }

    private func selectedMintName() -> String {
        if let selectedUrl = npcService.selectedMintUrl,
           let mint = walletManager.mints.first(where: { $0.url == selectedUrl }) {
            return mint.name
        }
        return "Select Mint"
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
