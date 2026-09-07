import SwiftUI

struct LightningAddressSettingsSection: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var npcService = NPCService.shared
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var isCheckingPayments: Bool
    @Binding var showMintPicker: Bool

    @State private var showAddressQR = false
    @State private var retryingSetup = false
    @State private var setupError: String?

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

                if !settings.checkIncomingInvoices {
                    SettingsSectionFooter {
                        Text("To check for payments, allow incoming invoice checks in Privacy settings.")
                    }
                }
            } else if npcService.isEnabled && !npcService.isInitialized {
                SettingsSectionGroup(nil) {
                    VStack(spacing: 12) {
                        InlineNotice(
                            message: setupError ?? "Wallet not fully initialized. Try setup again to finish your Lightning address.",
                            severity: .error
                        )
                        Button {
                            guard !retryingSetup else { return }
                            retryingSetup = true
                            setupError = nil
                            Task { @MainActor in
                                defer { retryingSetup = false }
                                do {
                                    try await walletManager.retryLightningAddressSetup()
                                } catch {
                                    setupError = "Lightning address setup couldn't finish. Try again or restart the app."
                                }
                            }
                        } label: {
                            HStack {
                                if retryingSetup { ProgressView() }
                                Text("Try setup again")
                            }
                        }
                        .glassButton(prominent: true)
                        .disabled(retryingSetup)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 14)
                }
            }
        }
        .task { await npcService.initializeIfEnabled() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: npcService.isEnabled)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: npcService.errorMessage)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: settings.checkIncomingInvoices)
        .backdropSheet(isPresented: $showMintPicker) {
            // Titled after the row that opened it, so the sheet reads as a
            // continuation of the tap rather than a new context.
            MintPickerSheet(
                title: "Receiving mint",
                mints: walletManager.mints,
                selectedMintUrl: $npcService.selectedMintUrl,
                onSelect: { mintUrl in
                    Task {
                        do {
                            try await npcService.changeMint(to: mintUrl)
                        } catch is CancellationError {
                            // The address was disabled or the wallet changed.
                        } catch {
                            npcService.errorMessage = ActionErrorMessages.message(for: error, context: .lightningMint)
                        }
                    }
                }
            )
        }
        .backdropSheet(isPresented: $showAddressQR) {
            QRCodeDetailSheet(
                title: "Lightning Address",
                content: npcService.lightningAddress
            )
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
                InlineNotice(message: error, severity: .error)
            }
        } else if !npcService.isInitialized && retryingSetup {
            SettingsSectionFooter {
                Text("Setting up Lightning address…")
            }
        }
    }

    // MARK: - Address row

    private var addressRow: some View {
        Button { HapticFeedback.selection(); showAddressQR = true } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(npcService.lightningAddress)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
        if npcService.errorMessage != nil { return npcService.isConnected ? "Needs attention" : "Not connected" }
        if npcService.isConnected { return "Connected" }
        return npcService.isLoading ? "Connecting" : "Not connected"
    }

    // MARK: - Receiving Mint row

    private var receivingMintRow: some View {
        Button {
            HapticFeedback.selection()
            showMintPicker = true
        } label: {
            HStack(spacing: 12) {
                Text("Receiving mint")
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(selectedMintDisplayName)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

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
                    Text(lastCheckedCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCheckingPayments || !settings.checkIncomingInvoices)
        .opacity(settings.checkIncomingInvoices ? 1.0 : 0.5)
        .accessibilityLabel("Check for new payments. \(lastCheckedCaption).")
    }

    private var lastCheckedCaption: String {
        if let lastCheck = npcService.lastCheck {
            return "Last checked \(formatRelativeTime(lastCheck))"
        }
        return "Not checked yet"
    }

    // MARK: - Actions

    private func copyLightningAddress() {
        UIPasteboard.general.string = npcService.lightningAddress
        HapticFeedback.selection()
        ConfirmationToast.show("Copied Lightning address")
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
