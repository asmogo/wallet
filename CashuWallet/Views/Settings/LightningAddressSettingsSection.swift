import SwiftUI

struct LightningAddressSettingsSection: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var npcService = NPCService.shared

    @Binding var copiedLightningAddress: Bool
    @Binding var isCheckingPayments: Bool
    @Binding var showMintPicker: Bool

    @State private var showAddressQR = false

    var body: some View {
        LazyVStack(spacing: 0) {
            SettingsSectionGroup("Lightning Address") {
                Toggle("Enable Lightning Address", isOn: $npcService.isEnabled)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 14)

                if npcService.isEnabled && npcService.isInitialized {
                    addressRow
                }
            }

            statusFooter

            if npcService.isEnabled && npcService.isInitialized {
                SettingsSectionGroup("Preferences") {
                    Toggle("Auto-claim payments", isOn: $npcService.automaticClaim)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 14)

                    if !walletManager.mints.isEmpty {
                        receivingMintRow
                    }
                }

                SettingsSectionFooter {
                    Text("Incoming payments are minted as ecash at your chosen mint.")
                }

                SettingsSectionGroup(nil) {
                    checkForPaymentsRow
                }
            } else if npcService.isEnabled && !npcService.isInitialized {
                SettingsSectionGroup(nil) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Wallet not fully initialized. Please restart the app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 14)
                }
            }
        }
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
        .sheet(isPresented: $showAddressQR) {
            QRCodeDetailSheet(
                title: "Lightning Address",
                content: npcService.lightningAddress
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Status footer + helpers

    @ViewBuilder
    private var statusFooter: some View {
        if !npcService.isEnabled {
            SettingsSectionFooter {
                Text("Receive Lightning payments to your wallet using a Lightning address.")
            }
        } else if let error = npcService.errorMessage {
            SettingsSectionFooter {
                Text(error)
                    .foregroundStyle(.red)
            }
        } else if !npcService.isInitialized {
            SettingsSectionFooter {
                Text("Setting up Lightning address…")
            }
        }
    }

    // MARK: - Address row

    private var addressRow: some View {
        Button { showAddressQR = true } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                Text(npcService.lightningAddress)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                Image(systemName: "qrcode")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Lightning address: \(npcService.lightningAddress). \(statusLabel).")
        .accessibilityHint("Shows QR code. Long-press for copy and share.")
        .contextMenu {
            Button {
                copyLightningAddress()
            } label: {
                Label("Copy address", systemImage: "doc.on.doc")
            }
            ShareLink(item: npcService.lightningAddress) {
                Label("Share address", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var statusColor: Color {
        if npcService.errorMessage != nil { return .red }
        return npcService.isConnected ? .green : .orange
    }

    private var statusLabel: String {
        if let error = npcService.errorMessage { return error }
        return npcService.isConnected ? "Connected" : "Connecting"
    }

    // MARK: - Receiving Mint row

    private var receivingMintRow: some View {
        Button {
            HapticFeedback.selection()
            showMintPicker = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receiving mint")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(selectedMintDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Receiving mint: \(selectedMintDisplayName)")
        .accessibilityHint("Choose which mint claims incoming Lightning payments")
    }

    private var selectedMintDisplayName: String {
        if let url = npcService.selectedMintUrl,
           let mint = walletManager.mints.first(where: { $0.url == url }) {
            return mint.name
        }
        return "Select a mint"
    }

    // MARK: - Check for Payments row

    private var checkForPaymentsRow: some View {
        Button(action: checkForPayments) {
            HStack(spacing: 14) {
                Group {
                    if isCheckingPayments {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Check for payments")
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let lastCheck = npcService.lastCheck {
                        Text("Last checked \(formatRelativeTime(lastCheck))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCheckingPayments)
        .accessibilityLabel("Check for new payments")
    }

    // MARK: - Actions

    private func copyLightningAddress() {
        UIPasteboard.general.string = npcService.lightningAddress
        HapticFeedback.selection()
        withAnimation(.snappy(duration: 0.18)) { copiedLightningAddress = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.snappy(duration: 0.18)) { copiedLightningAddress = false }
        }
    }

    private func checkForPayments() {
        isCheckingPayments = true
        HapticFeedback.selection()
        Task {
            await npcService.checkAndClaimPayments()
            await MainActor.run {
                isCheckingPayments = false
            }
        }
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

