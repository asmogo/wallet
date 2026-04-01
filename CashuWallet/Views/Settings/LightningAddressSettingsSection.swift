import SwiftUI

struct LightningAddressSettingsSection: View {
    @EnvironmentObject var walletManager: WalletManager
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

                Text("Receive Lightning payments to your wallet using a Lightning address.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $npcService.isEnabled) {
                    Text("Enable Lightning Address")
                        .font(.subheadline)
                    }
                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                .padding(.top, 8)
            }

            if npcService.isEnabled {
                // Lightning Address Display
                if npcService.isInitialized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Lightning Address")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(action: copyLightningAddress) {
                        GroupBox {
                            HStack {
                                Text(npcService.lightningAddress)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(Color.accentColor)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                Image(systemName: copiedLightningAddress ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(copiedLightningAddress ? .green : Color.accentColor)
                            }
                        }
                    }
                    }
                    .padding(.top, 8)

                    // Auto-claim toggle
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $npcService.automaticClaim) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-claim payments")
                                    .font(.subheadline)
                                                Text("Automatically mint received payments")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                    }
                    .padding(.top, 8)

                    // Mint selection
                    if !walletManager.mints.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Receiving Mint")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button(action: { showMintPicker = true }) {
                            GroupBox {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(selectedMintName())
                                            .font(.subheadline)
                                        Text(npcService.selectedMintUrl ?? "Select a mint")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                            }
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
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color.accentColor))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Check for Payments")
                            }
                            .font(.subheadline)
        .foregroundStyle(Color.accentColor)
                        }
                        .disabled(isCheckingPayments)

                        Spacer()

                        if let lastCheck = npcService.lastCheck {
                            Text("Last: \(formatRelativeTime(lastCheck))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    // Error message
                    if let error = npcService.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.top, 4)
                    }
                } else {
                    // Nostr not initialized
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Wallet not fully initialized. Please restart the app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
