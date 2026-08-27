import SwiftUI

/// Settings screen for Nostr Wallet Connect (NIP-47), pushed from the Nostr hub
/// (Settings → Nostr → Wallet Connect).
///
/// Built on the shared single-canvas settings recipe (`SettingsSectionGroup` +
/// `SettingsSectionFooter`) so it reads as one family with the Nostr and Locked
/// Ecash hubs: an enable toggle, a Lightning-address-style connection row
/// (status dot + monospaced URI + QR sheet), inspector rows for the backing
/// mint and per-payment limit, and a destructive reset row.
struct NWCSettingsView: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var nwc = NWCManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    @State private var showMintPicker = false
    @State private var showBudgetSheet = false
    @State private var showConnectionQR = false
    @State private var showRegenerateConfirm = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Text("Connect a Nostr app to this wallet. Paired apps can check your balance, create invoices, and pay Lightning invoices with your ecash.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                    .padding(.bottom, 28)

                SettingsSectionGroup(nil) {
                    Toggle(isOn: enableBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Wallet Connect")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 14)
                    .disabled(nwc.isBusy || walletManager.mints.isEmpty)
                }

                statusFooter

                if nwc.isEnabled, let uri = nwc.connectionUri {
                    SettingsSectionGroup("Connection") {
                        connectionRow(uri)
                    }
                    SettingsSectionFooter {
                        Text("Scan or paste this code in a Nostr app to pair it. Keep it private — anyone with the code can spend within your payment limit.")
                    }

                    SettingsSectionGroup("Spending") {
                        mintRow
                        budgetRow
                    }
                    SettingsSectionFooter {
                        Text("Payments are sent as ecash from this mint over your Nostr relays.")
                    }

                    SettingsSectionGroup(nil) {
                        Button(action: { HapticFeedback.selection(); showRegenerateConfirm = true }) {
                            HStack(spacing: 14) {
                                SettingsRowIcon(systemName: "arrow.counterclockwise", tint: .red)
                                Text("Reset connection")
                                    .font(.body)
                                    .foregroundStyle(.red)
                                Spacer(minLength: 8)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(nwc.isBusy)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("Wallet Connect")
        .toolbarBackground(.hidden, for: .navigationBar)
        .animation(.easeInOut(duration: 0.2), value: nwc.isEnabled)
        .animation(.easeInOut(duration: 0.2), value: nwc.connectionUri)
        .animation(.easeInOut(duration: 0.2), value: nwc.errorMessage)
        .sheet(isPresented: $showMintPicker) {
            MintPickerSheet(
                mints: walletManager.mints,
                selectedMintUrl: Binding(
                    get: { nwc.selectedMintUrl },
                    set: { nwc.selectedMintUrl = $0 }
                ),
                onSelect: { nwc.selectedMintUrl = $0 }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showBudgetSheet) {
            NWCBudgetSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showConnectionQR) {
            QRCodeDetailSheet(title: "Wallet Connect", content: nwc.connectionUri ?? "")
                .presentationDetents([.medium, .large])
        }
        .alert("Reset Connection", isPresented: $showRegenerateConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task { await nwc.regenerateConnection() }
            }
        } message: {
            Text("This creates a new connection code. Any app paired with the current one will stop working until you share the new code.")
        }
    }

    // MARK: - Rows

    /// The pairing code row, mirroring the Lightning address row: a status dot,
    /// the monospaced middle-truncated URI, and a QR glyph. Tap opens the QR
    /// sheet; long-press exposes Copy + Share.
    private func connectionRow(_ uri: String) -> some View {
        Button { HapticFeedback.selection(); showConnectionQR = true } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(nwc.isRunning ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                Text(uri)
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
        .accessibilityLabel("Connection code. \(nwc.isRunning ? "Connected" : "Connecting").")
        .accessibilityHint("Shows QR code. Long-press for copy and share.")
        .contextMenu {
            Button {
                UIPasteboard.general.string = uri
                HapticFeedback.selection()
                ConfirmationToast.show("Copied connection code")
            } label: {
                Label("Copy code", systemImage: "doc.on.doc")
            }
            ShareLink(item: uri) {
                Label("Share code", systemImage: "square.and.arrow.up")
            }
        }
    }

    private var mintRow: some View {
        Button {
            HapticFeedback.selection()
            showMintPicker = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mint")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(selectedMintName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
        .disabled(walletManager.mints.isEmpty)
        .accessibilityLabel("Mint: \(selectedMintName)")
        .accessibilityHint("Choose which mint pays Wallet Connect requests")
    }

    private var budgetRow: some View {
        Button {
            HapticFeedback.selection()
            showBudgetSheet = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Payment limit")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(budgetLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
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
        .accessibilityLabel("Payment limit: \(budgetLabel)")
        .accessibilityHint("Caps how much a single payment can spend")
    }

    // MARK: - Footers

    @ViewBuilder
    private var statusFooter: some View {
        if walletManager.mints.isEmpty {
            SettingsSectionFooter {
                Text("Add a mint first to use Wallet Connect.")
            }
        } else if let error = nwc.errorMessage {
            SettingsSectionFooter {
                InlineNotice(message: error, severity: .error, showsIcon: false)
            }
        } else if !nwc.isEnabled {
            SettingsSectionFooter {
                Text("Enabling creates a private connection code you can scan or paste into a Nostr app.")
            }
        }
    }

    // MARK: - Derived

    /// Enabling with no mint chosen defaults to the active mint so the service
    /// can start without a detour through the picker.
    private var enableBinding: Binding<Bool> {
        Binding(
            get: { nwc.isEnabled },
            set: { newValue in
                if newValue, nwc.selectedMintUrl == nil {
                    nwc.selectedMintUrl = walletManager.activeMint?.url ?? walletManager.mints.first?.url
                }
                nwc.isEnabled = newValue
            }
        )
    }

    private var statusText: String {
        if nwc.isBusy { return "Working…" }
        if nwc.isRunning { return "Connected" }
        if nwc.isEnabled { return "Starting…" }
        return "Off"
    }

    private var selectedMintName: String {
        guard let url = nwc.selectedMintUrl else { return "Select a mint" }
        if let mint = walletManager.mints.first(where: { $0.url == url }) {
            return mint.name
        }
        return url
    }

    private var budgetLabel: String {
        guard let budget = nwc.budgetSats else { return "No limit" }
        return "\(AmountFormatter.sats(budget, useBitcoinSymbol: settings.useBitcoinSymbol)) per payment"
    }
}

// MARK: - Payment limit editor

/// Medium-detent editor for the per-payment budget: a glass numeric field on
/// the house input recipe. An empty (or zero) value means no limit.
private struct NWCBudgetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var nwc = NWCManager.shared

    @State private var budgetText: String
    @FocusState private var fieldFocused: Bool

    init() {
        _budgetText = State(initialValue: NWCManager.shared.budgetSats.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Caps how much a single payment can spend. Leave empty for no limit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)

                HStack(spacing: 10) {
                    TextField("No limit", text: $budgetText)
                        .font(.system(.body, design: .monospaced))
                        .keyboardType(.numberPad)
                        .focused($fieldFocused)

                    Text("sats")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 14))

                Spacer(minLength: 0)

                Button(action: save) {
                    Text("Save")
                }
                .glassButton()
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
            .navigationTitle("Payment Limit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { fieldFocused = true }
            .onChange(of: budgetText) { _, newValue in
                // Digits only, capped well below UInt64.max so parsing can't fail.
                let digits = String(newValue.filter(\.isNumber).prefix(12))
                if digits != newValue { budgetText = digits }
            }
        }
        .flatBottomSheetSurface()
    }

    private func save() {
        HapticFeedback.selection()
        let value = UInt64(budgetText.trimmingCharacters(in: .whitespaces))
        nwc.budgetSats = (value == 0) ? nil : value
        dismiss()
    }
}

#Preview {
    NavigationStack {
        NWCSettingsView()
            .environmentObject(WalletManager())
    }
}
