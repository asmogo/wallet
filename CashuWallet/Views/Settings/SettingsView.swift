import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var npcService = NPCService.shared

    @State private var showBackup = false
    @State private var showDeleteConfirm = false
    @State private var copiedLightningAddress = false
    @State private var isCheckingPayments = false
    @State private var showMintPicker = false

    // Nostr Key Management
    @State private var showNsec = false
    @State private var copiedNsec = false
    @State private var showImportNsec = false
    @State private var importNsecText = ""
    @State private var showGenerateKeyConfirm = false
    @State private var showResetKeyConfirm = false
    @State private var nostrKeyError: String?
    @State private var relayInput = ""
    @State private var relayError: String?
    @State private var copiedRelay: String?
    @State private var showRestoreFlowAlert = false
    @State private var p2pkImportText = ""
    @State private var showImportP2PK = false
    @State private var p2pkError: String?
    @State private var nwcError: String?
    @State private var expandedP2PKKeys = false
    @State private var activeQRPayload: QRPayload?
    @State private var copiedNWCConnectionId: UUID?
    @State private var copiedP2PKPublicKey: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    NavigationLink { backupDetailView } label: {
                        settingsRow("Backup & Restore", icon: "key.fill")
                    }
                    NavigationLink { lightningDetailView } label: {
                        settingsRow("Lightning", icon: "bolt.fill")
                    }
                    NavigationLink { nostrDetailView } label: {
                        settingsRow("Nostr", icon: "person.circle")
                    }
                    NavigationLink { paymentRequestsDetailView } label: {
                        settingsRow("Payment Requests", icon: "arrow.left.arrow.right")
                    }
                    NavigationLink { nwcDetailView } label: {
                        settingsRow("Nostr Wallet Connect", icon: "link")
                    }
                    NavigationLink { p2pkDetailView } label: {
                        settingsRow("P2PK", icon: "lock.fill")
                    }
                    NavigationLink { privacyDetailView } label: {
                        settingsRow("Privacy", icon: "eye.slash")
                    }
                    NavigationLink { appearanceDetailView } label: {
                        settingsRow("Appearance", icon: "paintbrush")
                    }

                    Divider()
                        .padding(.vertical, 12)

                    VStack(spacing: 4) {
                        LabeledContent("Balance", value: settings.formatAmount(walletManager.balance))
                        LabeledContent("Mints", value: "\(walletManager.mints.count)")
                        LabeledContent("Unit", value: settings.unitLabel)
                        LabeledContent("Version", value: "1.0.0")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                    Divider()
                        .padding(.vertical, 12)

                    Link(destination: URL(string: "https://cashu.space")!) {
                        settingsRow("Learn about Cashu", icon: "globe")
                    }
                    Link(destination: URL(string: "https://github.com/cashubtc/nuts")!) {
                        settingsRow("Protocol Specs (NUTs)", icon: "doc.text")
                    }

                    Divider()
                        .padding(.vertical, 12)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Wallet")
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showBackup) {
                BackupView()
                    .environmentObject(walletManager)
            }
            .sheet(isPresented: $showImportP2PK) {
                ImportP2PKSheet(
                    nsecText: $p2pkImportText,
                    onImport: importP2PKNsec
                )
            }
            .sheet(item: $activeQRPayload) { payload in
                QRCodeDetailSheet(title: payload.title, content: payload.content)
            }
            .alert("Open Restore Wizard", isPresented: $showRestoreFlowAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Open") {
                    walletManager.needsOnboarding = true
                }
            } message: {
                Text("This will open the restore flow used during onboarding.")
            }
            .alert("Delete Wallet", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteWallet()
                }
            } message: {
                Text("Are you sure you want to delete your wallet? This action cannot be undone. Make sure you have backed up your seed phrase!")
            }
        }
    }

    // MARK: - Detail Views

    private var backupDetailView: some View {
        List {
            Section {
                BackupSettingsSection(
                    showBackup: $showBackup,
                    showRestoreFlowAlert: $showRestoreFlowAlert
                )
            }
        }
        .listStyle(.plain)
        .navigationTitle("Backup & Restore")
    }

    private var lightningDetailView: some View {
        List {
            Section {
                LightningAddressSettingsSection(
                    copiedLightningAddress: $copiedLightningAddress,
                    isCheckingPayments: $isCheckingPayments,
                    showMintPicker: $showMintPicker
                )
            }
        }
        .listStyle(.plain)
        .navigationTitle("Lightning")
    }

    private var nostrDetailView: some View {
        List {
            Section("Keys") {
                NostrKeysSettingsSection(
                    showNsec: $showNsec,
                    copiedNsec: $copiedNsec,
                    showImportNsec: $showImportNsec,
                    importNsecText: $importNsecText,
                    showGenerateKeyConfirm: $showGenerateKeyConfirm,
                    showResetKeyConfirm: $showResetKeyConfirm,
                    nostrKeyError: $nostrKeyError
                )
            }
            Section("Relays") {
                NostrRelaysSettingsSection(
                    relayInput: $relayInput,
                    relayError: $relayError,
                    copiedRelay: $copiedRelay
                )
            }
        }
        .listStyle(.plain)
        .navigationTitle("Nostr")
    }

    private var paymentRequestsDetailView: some View {
        List {
            Section {
                PaymentRequestsSettingsSection()
            }
        }
        .listStyle(.plain)
        .navigationTitle("Payment Requests")
    }

    private var nwcDetailView: some View {
        List {
            Section {
                NWCSettingsSection(
                    nwcError: $nwcError,
                    copiedNWCConnectionId: $copiedNWCConnectionId,
                    activeQRPayload: $activeQRPayload
                )
            }
        }
        .listStyle(.plain)
        .navigationTitle("Nostr Wallet Connect")
    }

    private var p2pkDetailView: some View {
        List {
            Section {
                P2PKSettingsSection(
                    expandedP2PKKeys: $expandedP2PKKeys,
                    activeQRPayload: $activeQRPayload,
                    copiedP2PKPublicKey: $copiedP2PKPublicKey,
                    p2pkImportText: $p2pkImportText,
                    showImportP2PK: $showImportP2PK,
                    p2pkError: $p2pkError
                )
            }
        }
        .listStyle(.plain)
        .navigationTitle("P2PK")
    }

    private var privacyDetailView: some View {
        List {
            Section {
                PrivacySettingsSection()
            }
        }
        .listStyle(.plain)
        .navigationTitle("Privacy")
    }

    private var appearanceDetailView: some View {
        List {
            Section {
                ThemeSettingsSection()
            }
        }
        .listStyle(.plain)
        .navigationTitle("Appearance")
    }

    // MARK: - Helpers

    private func settingsRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 24)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 12), interactive: true)
        .contentShape(Rectangle())
    }

    private func deleteWallet() {
        try? KeychainService().deleteMnemonic()
        walletManager.needsOnboarding = true
    }

    private func importP2PKNsec() {
        p2pkError = nil
        do {
            try settings.importP2PKNsec(p2pkImportText)
            p2pkImportText = ""
            showImportP2PK = false
        } catch {
            p2pkError = error.localizedDescription
        }
    }
}

// MARK: - Shared Types

struct QRPayload: Identifiable {
    let id = UUID()
    let title: String
    let content: String
}

// MARK: - QR Code Detail Sheet

struct QRCodeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let content: String

    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                QRCodeView(content: content, showControls: false)
                    .padding()
                    .frame(width: 280, height: 280)
                    .background(Color.white)
                    .cornerRadius(12)

                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.horizontal)

                Button(action: copyToClipboard) {
                    HStack {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy")
                    }
                }
                .glassButton().controlSize(.large)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = content
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

// MARK: - Import P2PK Sheet

struct ImportP2PKSheet: View {
    @Binding var nsecText: String
    let onImport: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("nsec1...", text: $nsecText)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Import an nsec key to add a P2PK locking key.")
                }

                if let validationError {
                    Section {
                        Text(validationError)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Import nsec") {
                        if validate() { onImport() }
                    }
                    .disabled(nsecText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Import P2PK")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func validate() -> Bool {
        validationError = nil
        let value = nsecText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.hasPrefix("nsec1") else {
            validationError = "Invalid nsec format"
            return false
        }
        return true
    }
}

// MARK: - Backup View

struct BackupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager

    @State private var showWords = false
    @State private var copiedToClipboard = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundStyle(.orange)

                        Text("Keep Your Seed Phrase Safe")
                            .font(.headline)

                        Text("Anyone with these words can access your funds. Never share them with anyone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()

                    let words = walletManager.getMnemonicWords()
                    let mnemonic = words.joined(separator: " ")
                    let hiddenMnemonic = words.map { String(repeating: "\u{2022}", count: max(3, $0.count)) }.joined(separator: " ")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Seed phrase")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        HStack(spacing: 10) {
                            Text(showWords ? mnemonic : hiddenMnemonic)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(showWords ? .primary : .secondary)
                                .lineLimit(4)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 0)

                            VStack(spacing: 8) {
                                Button(action: { showWords.toggle() }) {
                                    Image(systemName: showWords ? "eye.slash" : "eye")
                                }

                                Button(action: copyToClipboard) {
                                    Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                                        .foregroundColor(copiedToClipboard ? .green : .accentColor)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)

                    Spacer(minLength: 50)

                    Button("Done") { dismiss() }
                        .glassButton().controlSize(.large)
                        .padding(.horizontal)
                        .padding(.bottom, 30)
                }
            }
            .navigationTitle("Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func copyToClipboard() {
        let words = walletManager.getMnemonicWords().joined(separator: " ")
        UIPasteboard.general.string = words
        copiedToClipboard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            copiedToClipboard = false
        }
    }
}

// MARK: - Mint Picker Sheet

struct MintPickerSheet: View {
    let mints: [MintInfo]
    @Binding var selectedMintUrl: String?
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(mints, id: \.url) { mint in
                Button {
                    selectedMintUrl = mint.url
                    onSelect(mint.url)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mint.name)
                            Text(mint.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if selectedMintUrl == mint.url {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Select Mint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Import Nsec Sheet

struct ImportNsecSheet: View {
    @Binding var nsecText: String
    let onImport: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("nsec1...", text: $nsecText)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Enter your nsec (Nostr private key) to use it for your Lightning address.")
                }

                Section {
                    Button("Paste from Clipboard") {
                        if let text = UIPasteboard.general.string {
                            nsecText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Import Key") {
                        if validateNsec() { onImport() }
                    }
                    .disabled(nsecText.isEmpty)
                }
            }
            .navigationTitle("Import Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func validateNsec() -> Bool {
        errorMessage = nil
        let trimmed = nsecText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("nsec1") else {
            errorMessage = "Invalid format. nsec must start with 'nsec1'"
            return false
        }
        guard trimmed.count >= 59 else {
            errorMessage = "nsec is too short"
            return false
        }
        return true
    }
}

#Preview {
    SettingsView()
        .environmentObject(WalletManager())
}
