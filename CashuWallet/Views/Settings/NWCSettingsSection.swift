import SwiftUI

/// Settings UI for Nostr Wallet Connect (NIP-47).
///
/// Lets the user enable the wallet service, pick the backing mint, set an
/// optional per-payment budget, and share the `nostr+walletconnect://`
/// connection URI (QR + copy) with a Nostr app.
struct NWCSettingsSection: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var nwc = NWCManager.shared

    @State private var showMintPicker = false
    @State private var budgetText = ""
    @State private var copiedUri = false
    @State private var showRegenerateConfirm = false

    var body: some View {
        Group {
            Text("Connect a Nostr app to this wallet. The app can request invoices and make payments over Nostr (NIP-47), backed by the mint you choose below.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Enable toggle
            Toggle(isOn: enableBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Nostr Wallet Connect")
                        .font(.subheadline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(nwc.isRunning ? .green : .secondary)
                }
            }
            .disabled(nwc.isBusy || walletManager.mints.isEmpty)

            if walletManager.mints.isEmpty {
                Text("Add a mint first to use Nostr Wallet Connect.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            // Mint selection
            Button(action: { showMintPicker = true }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selectedMintName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .disabled(walletManager.mints.isEmpty)

            // Budget
            VStack(alignment: .leading, spacing: 4) {
                Text("Per-payment budget (sats)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    TextField("No limit", text: $budgetText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit(applyBudget)

                    Button("Set", action: applyBudget)
                        .disabled(budgetText == currentBudgetText)
                }
                Text("Caps how much a single pay_invoice request can spend. Leave empty for no limit.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Connection URI (QR + copy + share)
            if let uri = nwc.connectionUri {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connection")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    QRCodeView(content: uri, showControls: false)
                        .frame(width: 220, height: 220)
                        .padding(12)
                        .background(Color.white)
                        .clipShape(.rect(cornerRadius: 12))
                        .frame(maxWidth: .infinity)

                    Text(uri)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button(action: { copyUri(uri) }) {
                            Label(copiedUri ? "Copied" : "Copy", systemImage: copiedUri ? "checkmark" : "doc.on.doc")
                        }
                        ShareLink(item: uri) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    .font(.subheadline)

                    Button(role: .destructive, action: { showRegenerateConfirm = true }) {
                        Label("Reset connection", systemImage: "arrow.counterclockwise")
                    }
                    .font(.subheadline)
                    .disabled(nwc.isBusy)

                    Text("Keep this URI private. Anyone with it can request payments within the budget.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            if let error = nwc.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("Relays are managed under Integrations → Nostr.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .onAppear { syncBudgetText() }
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
        .alert("Reset connection", isPresented: $showRegenerateConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task { await nwc.regenerateConnection() }
            }
        } message: {
            Text("This creates a new connection URI. Any app paired with the current URI will stop working until you share the new one.")
        }
    }

    // MARK: - Derived

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
        if nwc.isRunning { return "Connected and listening" }
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

    private var currentBudgetText: String {
        nwc.budgetSats.map(String.init) ?? ""
    }

    // MARK: - Actions

    private func syncBudgetText() {
        budgetText = currentBudgetText
    }

    private func applyBudget() {
        let trimmed = budgetText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            nwc.budgetSats = nil
        } else if let value = UInt64(trimmed) {
            nwc.budgetSats = value
        }
        budgetText = currentBudgetText
    }

    private func copyUri(_ uri: String) {
        UIPasteboard.general.string = uri
        copiedUri = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedUri = false
        }
    }
}
